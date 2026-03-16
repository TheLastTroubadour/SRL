local mq = require 'mq'

local RezDecision = {}
RezDecision.__index = RezDecision

function RezDecision:new(config)
    local self = setmetatable({}, RezDecision)
    self.name          = "RezDecision"
    self.config        = config
    self.pendingCorpse = nil
    self.pendingSpell  = nil
    return self
end

function RezDecision:score(ctx)
    self.pendingCorpse = nil
    self.pendingSpell  = nil

    if ctx.casting then return 0 end
    if not self.config:get('AutoRez.Enabled') then return 0 end

    local spells = self.config:get('AutoRez.Spells') or {}
    if #spells == 0 then return 0 end

    local corpse = self:findRezTarget()
    if not corpse then return 0 end

    local spell = self:findReadySpell(spells)
    if not spell then return 0 end

    self.pendingCorpse = corpse
    self.pendingSpell  = spell

    return 115
end

function RezDecision:execute(ctx)
    if not self.pendingCorpse or not self.pendingSpell then return end

    mq.cmdf('/target id %s', self.pendingCorpse.id)
    mq.delay(300, function() return mq.TLO.Target.ID() == self.pendingCorpse.id end)

    local spell = self.pendingSpell

    if spell.type == 'spell' then
        local castTime = (mq.TLO.Spell(spell.name).CastTime.TotalSeconds() or 3) * 1000 + 1500
        mq.cmdf('/casting "%s"|%s', spell.name, spell.gem)
        mq.delay(castTime)
    elseif spell.type == 'aa' then
        mq.cmdf('/alt activate "%s"', spell.name)
    elseif spell.type == 'item' then
        mq.cmdf('/useitem "%s"', spell.name)
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
    local peerString = mq.TLO.DanNet.Peers() or ''
    for name in peerString:gmatch('[^|]+') do
        peers[name:lower()] = true
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
        return mq.TLO.Cast.Ready(spell.name)() == true
    elseif spell.type == 'aa' then
        return mq.TLO.Me.AltAbilityReady(spell.name)() == true
    elseif spell.type == 'item' then
        return mq.TLO.FindItem('=' .. spell.name)() ~= nil
    end
    return false
end

return RezDecision
