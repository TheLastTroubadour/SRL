local mq = require 'mq'
local Job = require 'srl.model.Job'

local AbilityDecision = {}
AbilityDecision.__index = AbilityDecision

local ABILITY_KEY = 'Abilities'

function AbilityDecision:new(config)
    local self = setmetatable({}, AbilityDecision)
    self.config = config
    self.name = "AbilityDecision"
    self.abilityList = self:loadAbilities()
    self.pendingJobs = {}
    return self
end

function AbilityDecision:score(ctx)
    self.pendingJobs = {}

    if ctx.casting then return 0 end

    if not ctx.assist.Id then return 0 end

    if ctx.assist.distance and ctx.assist.distance > 200 then return 0 end

    for _, entry in ipairs(self.abilityList) do
        entry:setTargetId(ctx.assist.Id)
        if self:canUse(entry, ctx) then
            table.insert(self.pendingJobs, entry)
        end
    end

    if #self.pendingJobs == 0 then return 0 end

    return 75
end

function AbilityDecision:execute(ctx)
    for _, job in ipairs(self.pendingJobs) do
        if job.type == 'ability' then
            mq.cmdf('/doability %s', job.name)
        elseif job.type == 'disc' then
            mq.cmdf('/disc %s', job.name)
        elseif job.type == 'aa' then
            mq.cmdf('/alt activate %s', job.name)
        end
    end
end

function AbilityDecision:canUse(entry, ctx)
    if not entry or not entry.name then return false end

    -- reagent check: skip if required item not in inventory
    if entry.reagent then
        if not mq.TLO.FindItem('=' .. entry.reagent)() then
            return false
        end
    end

    -- debuff-type abilities: skip if target already has the effect
    if entry.abilityHasDebuff then
        if ctx.myCurrentTargetId == entry.targetId and mq.TLO.Target.Buff(entry.name)() then
            return false
        end
    end

    if entry.type == 'ability' then
        return mq.TLO.Me.AbilityReady(entry.name)() == true
    end

    if entry.type == 'disc' then
        return mq.TLO.Me.CombatAbilityReady(entry.name)() == true
    end

    if entry.type == 'aa' then
        return mq.TLO.Me.AltAbilityReady(entry.name)() == true
    end

    return false
end

function AbilityDecision:loadAbilities()
    local values = self.config:get(ABILITY_KEY)
    local jobList = {}
    if values then
        for _, v in ipairs(values) do
            local name = v.Ability
            local jobType = v.type or 'ability'
            local priority = v.priority or 50
            local job = Job:new(nil, nil, tostring(name), jobType, priority, nil)
            if v.debuff then
                job.abilityHasDebuff = true
            end
            if v.reagent then
                job.reagent = v.reagent
            end
            table.insert(jobList, job)
        end
    end
    return jobList
end

return AbilityDecision
