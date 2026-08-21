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
    if not TANK_CLASSES[mq.TLO.Me.Class.ShortName()] then return 0 end
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

    -- If targeting another tank, don't taunt
    local totSpawn = mq.TLO.Spawn('id ' .. totId)
    if totSpawn() then
        local totClass = totSpawn.Class.ShortName()
        if totClass and TANK_CLASSES[totClass] then return 0 end
    end

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
        mq.cmdf('/disc "%s"', name)
    end
end

-- Reactive entries (proactiveOnly=false) fire as soon as they're ready.
-- Proactive entries (proactiveOnly=true) additionally require Me.PctAggro to
-- have dropped below the entry's own aggroThreshold (falls back to
-- Taunt.AggroThreshold, default 95). List order is priority order -- the
-- first ready+qualifying entry wins, so put your preferred top-off ability
-- first and reserve a lower aggroThreshold on a later entry as backup for
-- when the first one is on cooldown.
function TauntDecision:findReady(proactiveOnly)
    local abilities = self.config:get('Taunt.Abilities') or {}
    local defaultThreshold = self.config:get('Taunt.AggroThreshold') or 95
    local pctAggro = mq.TLO.Me.PctAggro()

    for _, entry in ipairs(abilities) do
        if (entry.proactive == true) == proactiveOnly then
            if not proactiveOnly then
                if self:isReady(entry) then return entry end
            else
                local threshold = entry.aggroThreshold or defaultThreshold
                if (pctAggro or 100) < threshold and self:isReady(entry) then
                    return entry
                end
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
