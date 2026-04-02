local mq = require 'mq'
local Target = require 'service.TargetService'

local RezDecision = {}
RezDecision.__index = RezDecision

local CLAIM_DURATION_MS = 20000  -- 20s: long enough to cover cast + settle

local MANUAL_REZ_EXPIRY_MS = 30000  -- drop manual request if unclaimed after 30s

function RezDecision:new(config)
    local self = setmetatable({}, RezDecision)
    self.name           = "RezDecision"
    self.config         = config
    self.pendingCorpse  = nil
    self.pendingSpell   = nil
    self.lastRezTime    = 0
    self.claimedCorpses = {}   -- corpseId -> expiry timestamp
    self.manualRezQueue = nil  -- { id, name, expiry } set by /srl rez
    return self
end

function RezDecision:claimCorpse(corpseId)
    self.claimedCorpses[tonumber(corpseId)] = mq.gettime() + CLAIM_DURATION_MS
    -- Also clear any matching manual request so we don't re-queue it
    if self.manualRezQueue and self.manualRezQueue.id == tonumber(corpseId) then
        self.manualRezQueue = nil
    end
end

function RezDecision:queueManualRez(corpseId, corpseName)
    self.manualRezQueue = {
        id     = tonumber(corpseId),
        name   = corpseName,
        expiry = mq.gettime() + MANUAL_REZ_EXPIRY_MS,
    }
end

function RezDecision:score(ctx)
    self.pendingCorpse = nil
    self.pendingSpell  = nil

    if ctx.casting then return 0 end
    if mq.gettime() - self.lastRezTime < 12000 then return 0 end

    local spells = self.config:get('AutoRez.Spells') or {}
    if #spells == 0 then return 0 end

    -- Expire stale corpse claims
    local now = mq.gettime()
    for id, expiry in pairs(self.claimedCorpses) do
        if now >= expiry then self.claimedCorpses[id] = nil end
    end

    -- ── Manual rez request (/srl rez) takes priority over auto-rez ──
    local manual = self.manualRezQueue
    if manual then
        if now > manual.expiry or self.claimedCorpses[manual.id] then
            self.manualRezQueue = nil  -- expired or already claimed
        else
            local spell = self:findReadySpell(spells)
            if spell then
                self.pendingCorpse = { id = manual.id, name = manual.name }
                self.pendingSpell  = spell
                return 76  -- just above auto-rez; bypasses Enabled flag and MinGroupHpPct
            end
            return 0  -- have a manual request but spell not ready yet; wait
        end
    end

    -- ── Auto-rez ─────────────────────────────────────────────────────
    if not self.config:get('AutoRez.Enabled') then return 0 end

    local corpse = self:findRezTarget()
    if not corpse then return 0 end

    if self.claimedCorpses[corpse.id] then return 0 end

    local spell = self:findReadySpell(spells)
    if not spell then return 0 end

    -- Don't rez while live group members need healing
    local minHp = self.config:get('AutoRez.MinGroupHpPct') or 90
    local members = ctx.groupMembers or {}
    for _, m in ipairs(members) do
        if m.hp < minHp then return 0 end
    end

    self.pendingCorpse = corpse
    self.pendingSpell  = spell

    return 75
end

function RezDecision:execute(ctx)
    if not self.pendingCorpse or not self.pendingSpell then return end

    Target:getTargetById(self.pendingCorpse.id)

    local corpseSpawn = mq.TLO.Spawn('id ' .. self.pendingCorpse.id)
    if corpseSpawn() and (corpseSpawn.Distance() or 999) > 10 then
        mq.cmd('/corpse')
        mq.delay(500)
    end

    local spell = self.pendingSpell

    if spell.type == 'spell' then
        local gem = mq.TLO.Me.Gem(spell.name)() or spell.gem
        if not gem then return end
        local castTime = (mq.TLO.Spell(spell.name).CastTime.TotalSeconds() or 3) * 1000 + 1500
        mq.cmdf('/cast %s', gem)
        mq.delay(1000, function() return mq.TLO.Me.Casting() ~= nil end)
        mq.delay(castTime, function() return not mq.TLO.Me.Casting() end)
    elseif spell.type == 'aa' then
        mq.cmdf('/alt activate "%s"', spell.name)
    elseif spell.type == 'item' then
        mq.cmdf('/useitem "%s"', spell.name)
    end

    self.lastRezTime = mq.gettime()

    -- Claim this corpse so other rez-capable bots stand down
    self:claimCorpse(self.pendingCorpse.id)
    mq.cmdf('/dgae /srlevent ClaimRez id=%s', self.pendingCorpse.id)

    local me = mq.TLO.Me.Name()
    local msg = string.format('%s rezzing %s', me, self.pendingCorpse.name)
    if (mq.TLO.Raid.Members() or 0) > 0 then
        mq.cmdf('/rsay %s', msg)
    else
        mq.cmdf('/gsay %s', msg)
    end
end

function RezDecision:findRezTarget()
    local peers = self:getPeers()
    local count = mq.TLO.SpawnCount('pccorpse radius 100')()

    for i = 1, count do
        local corpse = mq.TLO.NearestSpawn(i, 'pccorpse radius 100')
        if corpse() then
            local corpseName = corpse.CleanName():match("^(.+)'s [Cc]orpse$") or corpse.CleanName()
            if peers[corpseName:lower()] then
                return { id = corpse.ID(), name = corpseName }
            end
        end
    end

    return nil
end

function RezDecision:getPeers()
    local peers = {}

    -- DanNet peers (format: "server_charname" — extract charname after "_")
    local peerString = mq.TLO.DanNet.Peers() or ''
    for name in peerString:gmatch('[^|]+') do
        local charName = name:lower():match('_(.+)') or name:lower()
        peers[charName] = true
    end

    -- Group members
    local groupSize = mq.TLO.Group.Members() or 0
    for i = 1, groupSize do
        local m = mq.TLO.Group.Member(i)
        if m() then
            local name = m.CleanName()
            if name then peers[name:lower()] = true end
        end
    end

    -- Raid members
    local raidSize = mq.TLO.Raid.Members() or 0
    for i = 1, raidSize do
        local r = mq.TLO.Raid.Member(i)
        if r() then
            local name = r.CleanName()
            if name then peers[name:lower()] = true end
        end
    end

    return peers
end

function RezDecision:findReadySpell(spells)
    for _, spell in ipairs(spells) do
        if self:isReady(spell) then
            return spell
        end
    end
    return nil
end

function RezDecision:isReady(spell)
    if spell.type == 'spell' then
        return mq.TLO.Me.SpellReady(spell.name)() == true
    elseif spell.type == 'aa' then
        return mq.TLO.Me.AltAbilityReady(spell.name)() == true
    elseif spell.type == 'item' then
        local item = mq.TLO.FindItem('=' .. spell.name)
        return item() and (item.TimerReady() or 1) == 0
    end
    return false
end

return RezDecision
