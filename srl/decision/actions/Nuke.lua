local Job = require 'srl.model.Job'
local mq = require 'mq'
local NukeDecision = {}
NukeDecision.__index = NukeDecision

local NUKE_KEY = 'Nukes.Main'
local JOLT_KEY = 'Jolts.Main'

function NukeDecision:new(config)
    local self = setmetatable({}, NukeDecision)
    self.config = config
    self.name = "NukeDecision"
    self.nukeList = self:getJobsFromKey(NUKE_KEY, 'nuke')
    self.joltList = self:getJobsFromKey(JOLT_KEY, 'nuke')
    self.joltThreshold  = config:get('Jolts.JoltThreshold')  or 80
    self.lockoutThreshold = config:get('Jolts.LockoutThreshold') or 100
    self.nuke = nil
    return self
end

function NukeDecision:getNukeList()
    return self.nukeList
end

function NukeDecision:score(ctx)
    self.nuke = nil

    if ctx.casting then return 0 end
    if not ctx.assist.Id then return 0 end
    if ctx.assist.distance and ctx.assist.distance > 200 then return 0 end
    if ctx.mana < 20 then return 0 end

    local aggro = mq.TLO.Me.PctAggro() or 0

    -- At or above lockout: jolts only, nothing if no jolt is ready
    if aggro >= self.lockoutThreshold then
        local jolt = self:findReadyJolt(aggro, ctx.assist.Id)
        if jolt then
            self.nuke = jolt
            return ctx.mana / 100
        end
        return 0
    end

    -- Above jolt threshold: prefer jolt, fall back to nuke if no jolt ready
    if aggro > self.joltThreshold then
        local jolt = self:findReadyJolt(aggro, ctx.assist.Id)
        if jolt then
            self.nuke = jolt
            return ctx.mana / 100
        end
    end

    -- Normal nuke (also fallback when aggro > joltThreshold but no jolt ready)
    local nuke = self:findReady(self.nukeList, ctx.assist.Id)
    if nuke then
        self.nuke = nuke
        return ctx.mana / 100
    end

    return 0
end

function NukeDecision:execute(ctx)
    if not self.nuke then return end

    if self.nuke.type == 'ability' then
        mq.cmdf('/doability %s', self.nuke.name)
        return
    end

    if self.nuke.type == 'disc' then
        mq.cmdf('/disc %s', self.nuke.name)
        return
    end

    if mq.TLO.Target.ID() ~= self.nuke.targetId then
        mq.cmdf('/target id %s', self.nuke.targetId)
        mq.delay(100)
    end

    mq.cmd("/stick off")
    mq.cmd("/afollow off")
    mq.cmdf("/casting \"%s\"|%s", self.nuke.name, self.nuke.gem)
end

-- Find the highest-threshold jolt that applies to current aggro and is ready.
-- Falls back to any ready jolt if the best one is on cooldown.
function NukeDecision:findReadyJolt(aggro, targetId)
    local best = nil
    for _, entry in ipairs(self.joltList) do
        local threshold = entry.aggroThreshold or self.joltThreshold
        if aggro >= threshold then
            if not best or threshold > (best.aggroThreshold or self.joltThreshold) then
                best = entry
            end
        end
    end

    if best then
        best:setTargetId(targetId)
        if self:canUse(best) then return best end
    end

    -- Best jolt on cooldown — fall back to any ready jolt
    return self:findReady(self.joltList, targetId)
end

function NukeDecision:findReady(list, targetId)
    for _, entry in ipairs(list) do
        entry:setTargetId(targetId)
        if self:canUse(entry) then
            return entry
        end
    end
    return nil
end

function NukeDecision:canUse(entry)
    if entry.type == 'ability' then
        return mq.TLO.Me.AbilityReady(entry.name)() == true
    end

    if entry.type == 'disc' then
        return mq.TLO.Me.CombatAbilityReady(entry.name)() == true
    end

    local spell = mq.TLO.Spell(entry.name)
    if not spell() then return false end
    if not mq.TLO.Cast.Ready(entry.name) then return false end
    return true
end

function NukeDecision:getJobsFromKey(key, jobType)
    local values = self.config:get(key)
    local jobList = {}
    if values then
        for _, v in ipairs(values) do
            local entryType = v.type or jobType
            local job = Job:new(nil, nil, v.spell, entryType, 50, v.gem or 8)
            job.aggroThreshold = v.aggroThreshold
            table.insert(jobList, job)
        end
    end
    return jobList
end

return NukeDecision
