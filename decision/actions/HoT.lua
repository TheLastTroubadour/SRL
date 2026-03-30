local mq = require 'mq'
local Target = require 'service.TargetService'

-- Handles HoT (Heal over Time) and Promised heal spells.
-- Fires on the lowest-HP group/raid/xtarget member that:
--   - is below the configured role threshold
--   - does not already have the buff on them
--   - has a ready spell available
--
-- Scores 92 — below Cure (95) but above Assist (90).
-- Config keys: Heals.HoTSpells and Heals.PromisedSpells (per-role, same shape).
--
-- Example YAML:
--   Heals:
--     HoTSpells:
--       tank:
--         - spell: Restoring Winds Rk. III
--           gem: 5
--           threshold: 95
--       normal:
--         - spell: Restoring Winds Rk. III
--           gem: 5
--           threshold: 90
--     PromisedSpells:
--       tank:
--         - spell: Promised Renewal Rk. III
--           gem: 6
--           threshold: 95
--           checkBuff: Promised Renewal

local HoTDecision = {}
HoTDecision.__index = HoTDecision

function HoTDecision:new(config)
    local self = setmetatable({}, HoTDecision)
    self.name             = "HoTDecision"
    self.config           = config
    self.pendingTarget    = nil
    self.pendingSpell     = nil
    self.promisedCastTime = {}   -- [targetId] = timestamp when promised heal was last cast
    return self
end

function HoTDecision:score(ctx)
    self.pendingTarget = nil
    self.pendingSpell  = nil

    if ctx.casting then return 0 end
    if not ctx.roles['healer'] then return 0 end
    if not ctx.self.heal or not ctx.self.heal.group then return 0 end
    if ctx.mana < 20 then return 0 end

    local targets = ctx.self.heal.group.memberStatus
    if not targets or #targets == 0 then return 0 end

    local best = self:findBest(targets)
    if not best then return 0 end

    self.pendingTarget = best.target
    self.pendingSpell  = best.spell
    return 92
end

-- Searches HoTSpells then PromisedSpells for the lowest HP target
-- that needs a cast (below threshold, buff not present, spell ready).
-- HoTSpells: skip if buff is already present.
-- PromisedSpells: the buff fires the heal when it expires, so we must let it fall off.
--   Skip if buff is present. After it falls off, wait `buffer` seconds (default 3) before
--   recasting to ensure the promised heal has landed before applying the next one.
function HoTDecision:findBest(targets)
    local best = nil
    local now  = mq.gettime()

    for _, configKey in ipairs({ 'Heals.HoTSpells', 'Heals.PromisedSpells' }) do
        local spellsByRole = self.config:get(configKey)
        if not spellsByRole then goto nextKey end

        local isPromised = (configKey == 'Heals.PromisedSpells')

        for _, target in ipairs(targets) do
            local spells = spellsByRole[target.role] or spellsByRole['normal']
            if not spells then goto nextTarget end

            for _, entry in ipairs(spells) do
                if (target.hp or 100) > (entry.threshold or 100) then goto nextEntry end
                if best and (target.hp or 100) >= (best.target.hp or 100) then goto nextEntry end

                local buffName = entry.checkBuff or (entry.spell:gsub('%s+Rk%.%s*%w+$', ''))
                local spawn = mq.TLO.Spawn('id ' .. target.id)
                if not spawn() then goto nextEntry end

                if spawn.Buff(buffName)() then goto nextEntry end  -- buff active, let it fire

                if isPromised then
                    -- Wait `buffer` seconds after the buff fell off before recasting
                    local buffer = (entry.buffer or 3) * 1000
                    local lastCast = self.promisedCastTime[target.id] or 0
                    if (now - lastCast) < buffer then goto nextEntry end
                end

                if self:isReady(entry) then
                    best = { target = target, spell = entry }
                end

                ::nextEntry::
            end

            ::nextTarget::
        end

        ::nextKey::
    end

    return best
end

function HoTDecision:isReady(entry)
    local t = entry.type or 'spell'
    if t == 'spell' then
        return mq.TLO.Me.SpellReady(entry.spell)() == true
    elseif t == 'aa' then
        return mq.TLO.Me.AltAbilityReady(entry.spell)() == true
    elseif t == 'item' then
        local item = mq.TLO.FindItem('=' .. entry.spell)
        return item() and (item.TimerReady() or 1) == 0
    end
    return false
end

function HoTDecision:execute(ctx)
    if not self.pendingTarget or not self.pendingSpell then return end

    if mq.TLO.Target.ID() ~= self.pendingTarget.id then
        Target:getTargetById(self.pendingTarget.id)
    end

    local entry    = self.pendingSpell
    local t        = entry.type or 'spell'
    local isPromised = false
    local spellsByRole = self.config:get('Heals.PromisedSpells')
    if spellsByRole then
        local roleSpells = spellsByRole[self.pendingTarget.role] or spellsByRole['normal'] or {}
        for _, s in ipairs(roleSpells) do
            if s.spell == entry.spell then isPromised = true; break end
        end
    end

    if t == 'spell' then
        local gem = mq.TLO.Me.Gem(entry.spell)() or entry.gem
        if not gem then return end
        mq.cmdf('/cast %s', gem)
    elseif t == 'aa' then
        mq.cmdf('/alt activate "%s"', entry.spell)
    elseif t == 'item' then
        mq.cmdf('/useitem "%s"', entry.spell)
    end

    if isPromised then
        self.promisedCastTime[self.pendingTarget.id] = mq.gettime()
    end
end

return HoTDecision
