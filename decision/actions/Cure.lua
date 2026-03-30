local mq = require 'mq'
local Target = require 'service.TargetService'

local CureDecision = {}
CureDecision.__index = CureDecision

local CLAIM_DURATION_MS = 7000

function CureDecision:new(config)
    local self = setmetatable({}, CureDecision)
    self.name           = "CureDecision"
    self.config         = config
    self.spells         = self:loadSpells()
    self.queue          = {}
    self.claimedTargets = {}  -- targetId -> expiry timestamp
    self.pendingEntry   = nil
    self.pendingSpell   = nil
    return self
end

-- Loads Cures.Spells from YAML. Each entry must have name, type, and either
-- gem (spell) or leave gem nil for AA abilities (type='aa').
-- Example YAML:
--   Cures:
--     Spells:
--       - name: Purified Blood
--         type: Poison
--         gem: 4
--       - name: Radiant Cure
--         type: Poison,Disease,Curse
--         spelltype: aa
function CureDecision:loadSpells()
    local list = self.config:get('Cures.Spells') or {}
    local result = {}
    for _, v in ipairs(list) do
        if v.name and v.type then
            table.insert(result, {
                name       = v.name,
                type       = v.type,          -- comma-separated cure types this spell covers
                gem        = v.gem,           -- nil for AA
                spelltype  = v.spelltype or 'spell',  -- 'spell' or 'aa'
                minInjured = v.minInjured,    -- optional: minimum unclaimed targets before using this spell
                groupOnly  = v.groupOnly,     -- optional: only cure group members
            })
        end
    end
    return result
end

-- Called by the CommandBus NeedCure handler when another bot broadcasts a request.
-- Upserts by targetId so re-broadcasts refresh the types list.
function CureDecision:addRequest(targetId, targetName, types, buff)
    local id = tonumber(targetId)
    if not id then return end
    if not types or types == '' then return end

    for i, entry in ipairs(self.queue) do
        if entry.targetId == id then
            self.queue[i] = { targetId = id, targetName = targetName, types = types, buff = buff }
            return
        end
    end

    table.insert(self.queue, { targetId = id, targetName = targetName, types = types, buff = buff })
end

function CureDecision:reset()
    self.queue          = {}
    self.claimedTargets = {}
    self.pendingEntry   = nil
    self.pendingSpell   = nil
end

function CureDecision:claimTarget(targetId)
    self.claimedTargets[tonumber(targetId)] = mq.gettime() + CLAIM_DURATION_MS
end

function CureDecision:score(ctx)
    self.pendingEntry = nil
    self.pendingSpell = nil

    if ctx.casting then return 0 end
    if #self.spells == 0 then return 0 end
    if #self.queue == 0 then return 0 end

    -- Expire stale claims
    local now = mq.gettime()
    for id, expiry in pairs(self.claimedTargets) do
        if now >= expiry then self.claimedTargets[id] = nil end
    end

    for _, entry in ipairs(self.queue) do
        if self.claimedTargets[entry.targetId] then goto continue end
        local spell = self:findSpell(entry)
        if spell then
            self.pendingEntry = entry
            self.pendingSpell = spell
            return 95
        end
        ::continue::
    end

    return 0
end

function CureDecision:execute(ctx)
    if not self.pendingEntry or not self.pendingSpell then return end

    local entry = self.pendingEntry
    local spell = self.pendingSpell

    -- Remove immediately; if target is still afflicted they will re-broadcast
    for i, e in ipairs(self.queue) do
        if e.targetId == entry.targetId then
            table.remove(self.queue, i)
            break
        end
    end

    -- Verify debuff is still on target before casting.
    -- Only skip if the target is our current target (buff window visible) and confirmed gone.
    if entry.buff and entry.buff ~= '' then
        if mq.TLO.Target.ID() == entry.targetId then
            local stillAfflicted = false
            for buffName in entry.buff:gmatch('[^,]+') do
                if mq.TLO.Target.Buff(buffName:gsub('_', ' '))() then
                    stillAfflicted = true
                    break
                end
            end
            if not stillAfflicted then return end
        end
    end

    -- Claim this target so peers don't double-cure
    self:claimTarget(entry.targetId)
    mq.cmdf('/dgae /srlevent ClaimCure id=%s', entry.targetId)

    -- If this is a group/AE cure, pre-claim all other queued targets whose types
    -- overlap this spell so we don't cast again for each one in subsequent ticks.
    -- Only claim targets actually in our EQ group (AE cures don't reach outside it).
    if spell.groupOnly then
        for _, e in ipairs(self.queue) do
            if e.targetId ~= entry.targetId and mq.TLO.Group.Member(e.targetName)() then
                for coverType in spell.type:gmatch('[^,]+') do
                    coverType = coverType:match('^%s*(.-)%s*$')
                    if e.types and e.types:find(coverType, 1, true) then
                        self:claimTarget(e.targetId)
                        mq.cmdf('/dgae /srlevent ClaimCure id=%s', e.targetId)
                        break
                    end
                end
            end
        end
    end

    if mq.TLO.Target.ID() ~= entry.targetId then
        Target:getTargetById(entry.targetId)
    end

    if spell.spelltype == 'aa' then
        mq.cmdf('/alt activate "%s"', spell.name)
    else
        local gem = mq.TLO.Me.Gem(spell.name)() or spell.gem
        if not gem then return end
        mq.cmdf('/cast %s', gem)
    end
end

-- Count unclaimed entries in the queue that match a given cure type.
function CureDecision:countUnclaimed(coverType)
    local count = 0
    for _, entry in ipairs(self.queue) do
        if not self.claimedTargets[entry.targetId] then
            if entry.types and entry.types:find(coverType, 1, true) then
                count = count + 1
            end
        end
    end
    return count
end

-- Find the first configured spell that covers at least one of the requested types.
-- entry has targetId, targetName, types (comma-separated), buff.
-- Spells with minInjured are skipped unless enough unclaimed targets need that cure type.
-- Spells with groupOnly are skipped if the target is not in the group.
function CureDecision:findSpell(entry)
    local typesStr = entry.types
    if not typesStr or typesStr == '' then return nil end
    for _, spell in ipairs(self.spells) do
        if spell.groupOnly and not mq.TLO.Group.Member(entry.targetName)() then
            goto nextSpell
        end
        for coverType in spell.type:gmatch('[^,]+') do
            coverType = coverType:match('^%s*(.-)%s*$')
            if typesStr:find(coverType, 1, true) and self:isReady(spell) then
                if spell.minInjured and self:countUnclaimed(coverType) < spell.minInjured then
                    goto nextSpell
                end
                return spell
            end
        end
        ::nextSpell::
    end
    return nil
end

function CureDecision:isReady(spell)
    if spell.spelltype == 'aa' then
        return mq.TLO.Me.AltAbilityReady(spell.name)() == true
    end
    return mq.TLO.Me.SpellReady(spell.name)() == true
end

return CureDecision
