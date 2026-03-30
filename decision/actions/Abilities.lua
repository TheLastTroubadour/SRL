local mq = require 'mq'
local Job = require 'model.Job'

local AbilityDecision = {}
AbilityDecision.__index = AbilityDecision

local ABILITY_KEY = 'Abilities'

function AbilityDecision:new(config)
    local self = setmetatable({}, AbilityDecision)
    self.config = config
    self.name = "AbilityDecision"
    self.abilityList = self:loadAbilities()
    self.pendingJobs = {}
    self.recastTimers = {}
    self.claimedAbilities = {}  -- name:targetId -> expiry timestamp
    self.lastDiscTime    = 0
    self.lastAbilityTime = 0
    self.lastItemTime    = 0
    return self
end

function AbilityDecision:addClaim(name, targetId, durationMs)
    local k = name .. ':' .. tostring(targetId)
    self.claimedAbilities[k] = mq.gettime() + durationMs
end

function AbilityDecision:getClaimExpiry(name, targetId)
    local k = name .. ':' .. tostring(targetId)
    return self.claimedAbilities[k]
end

function AbilityDecision:score(ctx)
    self.pendingJobs = {}

    -- Expire stale claims
    local now = mq.gettime()
    for k, expiry in pairs(self.claimedAbilities) do
        if now >= expiry then self.claimedAbilities[k] = nil end
    end

    local isBard = ctx.myClass == 'BRD'

    if ctx.casting and not isBard then return 0 end

    if not ctx.assist.Id then return 0 end

    if ctx.assist.distance and ctx.assist.distance > 200 then return 0 end

    for _, entry in ipairs(self.abilityList) do
        -- While singing, bards can only use instant-cast entries
        if ctx.casting and isBard and not self:isInstant(entry) then
            goto continue
        end
        entry:setTargetId(ctx.assist.Id)
        if self:canUse(entry, ctx) then
            table.insert(self.pendingJobs, entry)
        end
        ::continue::
    end

    if #self.pendingJobs == 0 then return 0 end

    return 75
end

function AbilityDecision:execute(ctx)
    local now = mq.gettime()
    for _, job in ipairs(self.pendingJobs) do
        if job.type == 'ability' then
            if now - self.lastAbilityTime < 1500 then goto continueExec end
            mq.cmdf('/doability %s', job.name)
            self.lastAbilityTime = now
        elseif job.type == 'disc' then
            -- Only one disc per execute; gate against activation window
            if now - self.lastDiscTime < 3000 then goto continueExec end
            mq.cmdf('/disc %s', job.name)
            self.lastDiscTime = now
            if job.stacks and job.targetId then
                local duration = self:resolveBuffDuration(job)
                if duration and duration > 0 then
                    self.recastTimers[job.name .. ':' .. tostring(job.targetId)] = now + ((duration + 1) * 1000)
                end
            end
            -- Skip remaining discs this iteration
            goto doneExec
        elseif job.type == 'aa' then
            mq.cmdf('/alt activate %s', job.name)
        elseif job.type == 'item' then
            if now - self.lastItemTime < 1500 then goto continueExec end
            mq.cmdf('/useitem "%s"', job.name)
            self.lastItemTime = now
            local castTime = mq.TLO.FindItem('=' .. job.name).Clicky.CastTime() or 0
            if castTime > 0 then
                mq.delay(castTime + 500, function() return not mq.TLO.Me.Casting() end)
                goto doneExec
            end
        end

        if job.stacks and job.targetId then
            local duration = self:resolveBuffDuration(job)
            if duration and duration > 0 then
                local timerKey = job.name .. ':' .. tostring(job.targetId)
                self.recastTimers[timerKey] = now + ((duration + 1) * 1000)
            end
        end

        if job.abilityHasDebuff and job.targetId then
            local duration = self:resolveBuffDuration(job)
            if duration and duration > 0 then
                local durationMs = (duration + 2) * 1000
                local claimKey = job.name .. ':' .. tostring(job.targetId)
                self.claimedAbilities[claimKey] = now + durationMs
                mq.cmdf('/dgae /srlevent ClaimAbility name=%s targetId=%s duration=%s',
                    (job.name:gsub(' ', '_')), tostring(job.targetId), tostring(math.floor(durationMs)))
            end
        end
        ::continueExec::
    end
    ::doneExec::
end

function AbilityDecision:canUse(entry, ctx)
    if not entry or not entry.name then return false end

    -- reagent check: skip if required item not in inventory
    if entry.reagent then
        if not mq.TLO.FindItem('=' .. entry.reagent)() then
            return false
        end
    end

    -- aggro threshold gate
    if entry.aggroThreshold then
        if ctx.aggro < entry.aggroThreshold then return false end
    end

    -- stacks entries: timer is the only gate
    if entry.stacks then
        if not entry.targetId then return false end
        local timerKey = entry.name .. ':' .. tostring(entry.targetId)
        local expiry = self.recastTimers[timerKey]
        local now = mq.gettime()
        if expiry and now < expiry then
            return false
        end
        -- fall through to readiness check
    elseif entry.abilityHasDebuff and entry.targetId then
        -- Peer-claimed: another bot is handling this ability on this target
        local claimKey = entry.name .. ':' .. tostring(entry.targetId)
        local expiry = self.claimedAbilities[claimKey]
        if expiry and mq.gettime() < expiry then return false end

        -- debuff-type abilities: skip if target already has the effect
        local buffName = self:resolveBuffName(entry)
        local baseName = buffName:gsub('%s+Rk%.%s*%a+$', '')
        local spawn = mq.TLO.Spawn('id ' .. tostring(entry.targetId))
        if spawn() then
            if spawn.Buff(buffName)() or (baseName ~= buffName and spawn.Buff(baseName)()) then
                return false
            end
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

    if entry.type == 'item' then
        local item = mq.TLO.FindItem('=' .. entry.name)
        if not item() then return false end
        return (item.TimerReady() or 0) == 0
    end

    return false
end

function AbilityDecision:isInstant(entry)
    if entry.type == 'ability' then return true end
    if entry.type == 'aa' then
        return (mq.TLO.Me.AltAbility(entry.name).Spell.CastTime() or 0) == 0
    end
    if entry.type == 'disc' then
        return (mq.TLO.Spell(entry.name).CastTime() or 0) == 0
    end
    if entry.type == 'item' then
        local item = mq.TLO.FindItem('=' .. entry.name)
        return item() and (item.Clicky.CastTime() or 0) == 0
    end
    return false
end

function AbilityDecision:resolveBuffName(entry)
    if entry.type == 'aa' then
        local spellName = mq.TLO.Me.AltAbility(entry.name).Spell.Name()
        if spellName then return spellName end
    elseif entry.type == 'item' then
        local spellName = mq.TLO.FindItem('=' .. entry.name).Clicky.Spell.Name()
        if spellName then return spellName end
    end
    return entry.name
end

function AbilityDecision:resolveBuffDuration(entry)
    if entry.duration then return entry.duration end

    if entry.type == 'aa' then
        return mq.TLO.Me.AltAbility(entry.name).Spell.Duration.TotalSeconds()
    end
    local buffName = self:resolveBuffName(entry)
    return mq.TLO.Spell(buffName).Duration.TotalSeconds()
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
            if v.stacks then
                job.stacks = true
            end
            if v.reagent then
                job.reagent = v.reagent
            end
            if v.duration then
                job.duration = v.duration
            end
            if v.aggroThreshold then
                job.aggroThreshold = v.aggroThreshold
            end
            table.insert(jobList, job)
        end
    end
    return jobList
end

return AbilityDecision
