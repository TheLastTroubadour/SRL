local mq = require 'mq'

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
    if totId == mq.TLO.Me.ID() then return 0 end  -- mob already on us

    -- If targeting another tank, don't taunt
    local totSpawn = mq.TLO.Spawn('id ' .. totId)
    if totSpawn() then
        local totClass = totSpawn.Class.ShortName()
        if totClass and TANK_CLASSES[totClass] then return 0 end
    end

    local ability = self:findReady()
    if not ability then return 0 end

    self.pending = ability
    return 98
end

function TauntDecision:execute(ctx)
    if not self.pending then return end

    if self.pending.type == 'ability' then
        mq.cmdf('/doability %s', self.pending.name)
    elseif self.pending.type == 'aa' then
        mq.cmdf('/alt activate "%s"', self.pending.name)
    elseif self.pending.type == 'disc' then
        mq.cmdf('/disc "%s"', self.pending.name)
    end
end

function TauntDecision:findReady()
    local abilities = self.config:get('Taunt.Abilities') or {}
    for _, entry in ipairs(abilities) do
        if self:isReady(entry) then
            return entry
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
        return mq.TLO.Me.CombatAbilityReady(entry.name)() == true
    end
    return false
end

return TauntDecision
