local mq = require 'mq'
local SpellUtil = require 'util.SpellUtil'

local TANK_CLASSES = { WAR = true, SHD = true, PAL = true }

local TauntDecision = {}
TauntDecision.__index = TauntDecision

function TauntDecision:new(config)
    local self = setmetatable({}, TauntDecision)
    self.name    = "TauntDecision"
    self.config  = config
    self.pending = nil
    return self
end

function TauntDecision:score(ctx)
    self.pending = nil

    if ctx.casting then return 0 end

    local myClass = mq.TLO.Me.Class.ShortName()
    if not TANK_CLASSES[myClass] then return 0 end

    if not self.config:get('Taunt.Enabled') then return 0 end

    if not ctx.assist.Id then return 0 end

    -- Must have the assist target currently targeted to get valid TargetOfTarget data
    if tonumber(ctx.myCurrentTargetId) ~= tonumber(ctx.assist.Id) then return 0 end

    local totId = ctx.myCurrentTargetsTargetId
    if not totId or totId == 0 then return 0 end

    if totId == mq.TLO.Me.ID() then
        -- Still holding it -- proactive top-off if aggro is slipping
        local ability = self:findReady(true)
        if not ability then return 0 end

        self.pending = ability
        return 97
    end

    -- If targeting another tank, don't taunt -- Me.TargetOfTarget (not
    -- Target.TargetOfTarget) is the TLO that actually populates; it returns a
    -- name string, so resolve through Spawn to get the class.
    local totName = mq.TLO.Me.TargetOfTarget()
    local totClass = totName and mq.TLO.Spawn('=' .. totName).Class.ShortName()
    if totClass and TANK_CLASSES[totClass] then return 0 end

    local ability = self:findReady(false)
    if not ability then return 0 end

    self.pending = ability
    return 98
end

function TauntDecision:execute(ctx)
    if not self.pending then return end

    local name = self.pending._resolvedName or self.pending.name
    if self.pending.type == 'ability' then
        mq.cmdf('/doability %s', name)
    elseif self.pending.type == 'aa' then
        mq.cmdf('/alt activate "%s"', name)
    elseif self.pending.type == 'disc' then
        mq.cmdf('/disc %s', name)
    end
end

-- Every entry is always reactive-eligible -- fires as soon as it's ready
-- whenever someone else already has aggro (stillHaveAggro=false), no
-- threshold involved since aggro's already lost. Entries that also declare
-- an aggroThreshold are ADDITIONALLY proactive-eligible -- while you still
-- hold aggro (stillHaveAggro=true), they fire once Me.PctAggro drops below
-- their own threshold, topping it off before it's actually lost. An entry
-- with no aggroThreshold is reactive-only. List order is priority order --
-- the first ready+qualifying entry wins, so put your preferred ability
-- first and reserve a lower aggroThreshold on a later entry as backup for
-- when the first one is on cooldown.
function TauntDecision:findReady(stillHaveAggro)
    local abilities = self.config:get('Taunt.Abilities') or {}
    local pctAggro = mq.TLO.Me.PctAggro()

    for _, entry in ipairs(abilities) do
        if not stillHaveAggro then
            if self:isReady(entry) then return entry end
        elseif entry.aggroThreshold then
            if (pctAggro or 100) < entry.aggroThreshold and self:isReady(entry) then
                return entry
            end
        end
    end
    return nil
end

function TauntDecision:isReady(entry)
    if entry.type == 'ability' then
        return mq.TLO.Me.AbilityReady(entry.name)() == true
    elseif entry.type == 'aa' then
        return mq.TLO.Me.AltAbilityReady(entry.name)() == true
    elseif entry.type == 'disc' then
        if not entry._resolvedName then
            entry._resolvedName = SpellUtil.resolveRank(entry.name, 'disc')
        end
        return mq.TLO.Me.CombatAbilityReady(entry._resolvedName)() == true
    end
    return false
end

return TauntDecision
