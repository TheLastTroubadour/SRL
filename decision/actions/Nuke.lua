local Job = require 'model.Job'
local mq = require 'mq'
local Target = require 'service.TargetService'
local NukeDecision = {}
NukeDecision.__index = NukeDecision

function NukeDecision:new(config)
    local self = setmetatable({}, NukeDecision)
    self.config = config
    self.name = "NukeDecision"
    self.joltThreshold    = config:get('Jolts.JoltThreshold')  or 80
    self.lockoutThreshold = config:get('Jolts.LockoutThreshold') or 100
    self.nuke             = nil
    self.nukeIndex        = 1
    self.joltList         = self:getJobsFromKey('Jolts', 'nuke')
    self:reloadSet('Main')
    return self
end

function NukeDecision:reloadSet(set)
    local nukes = self:getJobsFromKey('Nukes.' .. set, 'nuke')
    if #nukes > 0 then
        self.nukeList = nukes
        self.nukeIndex = 1
    end
end

function NukeDecision:getNukeList()
    return self.nukeList
end

function NukeDecision:score(ctx)
    self.nuke = nil

    if ctx.casting then return 0 end
    if not ctx.assist.Id then return 0 end

    -- Defer to GiftOfMana decision when the buff is active so the free cast
    -- lands on the configured spell rather than whatever is up next in rotation.
    local hasGoM = mq.TLO.Me.Buff('Gift of Mana')() ~= nil
             or mq.TLO.Me.Song('Gift of Mana')() ~= nil
    if hasGoM then return 0 end
    if ctx.assist.distance and ctx.assist.distance > 200 then return 0 end
    if ctx.mana < 20 then return 0 end

    if not ctx.assist.lineOfSight then return 0 end

    -- At or above lockout: jolts only, nothing if no jolt is ready
    if ctx.aggro >= self.lockoutThreshold then
        local jolt = self:findReadyJolt(ctx.aggro, ctx.assist.Id)
        if jolt then
            self.nuke = jolt
            return ctx.mana / 100
        end
        return 0
    end

    -- Above jolt threshold: prefer jolt, fall back to nuke if no jolt ready
    if ctx.aggro > self.joltThreshold then
        local jolt = self:findReadyJolt(ctx.aggro, ctx.assist.Id)
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
        Target:getTargetById(self.nuke.targetId)
    end

    mq.cmd("/stick off")
    mq.cmd('/nav stop')
    local gem = mq.TLO.Me.Gem(self.nuke.name)() or self.nuke.gem
    if not gem then return end
    mq.cmdf('/cast %s', gem)
    self.nukeIndex = self.nukeIndex % #self.nukeList + 1
end

-- Find the highest-threshold jolt that applies to current aggro and is ready.
-- Falls back to any ready jolt if the best one is on cooldown.
function NukeDecision:findReadyJolt(aggro, targetId)
    if not self.joltList or #self.joltList == 0 then return nil end
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
    if not list or #list == 0 then return nil end

    -- Check if any entry has explicit priority set
    local hasPriority = false
    for _, entry in ipairs(list) do
        if entry.priority and entry.priority ~= 0 then hasPriority = true; break end
    end

    if not hasPriority then
        -- Original round-robin
        for i = 0, #list - 1 do
            local idx = (self.nukeIndex - 1 + i) % #list + 1
            local entry = list[idx]
            entry:setTargetId(targetId)
            if self:canUse(entry) then return entry end
        end
        return nil
    end

    -- Priority mode: collect unique priorities sorted highest first
    local priorities = {}
    local seen = {}
    for _, entry in ipairs(list) do
        local p = entry.priority or 0
        if not seen[p] then seen[p] = true; table.insert(priorities, p) end
    end
    table.sort(priorities, function(a, b) return a > b end)

    for _, p in ipairs(priorities) do
        -- Build this priority group
        local group = {}
        for _, entry in ipairs(list) do
            if (entry.priority or 0) == p then table.insert(group, entry) end
        end
        -- Round-robin within the group
        for i = 0, #group - 1 do
            local idx = (self.nukeIndex - 1 + i) % #group + 1
            local entry = group[idx]
            entry:setTargetId(targetId)
            if self:canUse(entry) then return entry end
        end
        -- Nothing ready in this group, fall through to next lower priority
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
    return mq.TLO.Me.SpellReady(entry.name)() == true
end

function NukeDecision:getJobsFromKey(key, jobType)
    local values = self.config:get(key)
    local jobList = {}
    if values then
        for _, v in ipairs(values) do
            local entryType = v.type or jobType
            local job = Job:new(nil, nil, v.spell, entryType, 50, v.gem or 8)
            job.aggroThreshold = v.aggroThreshold
            job.priority       = v.priority or 0
            table.insert(jobList, job)
        end
    end
    return jobList
end

return NukeDecision
