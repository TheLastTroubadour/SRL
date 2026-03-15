local mq = require('mq')
local State = require 'srl.core.State'
local TargetService = require 'srl.service.TargetService'
local TableUtil = require 'srl.util.TableUtil'
local Job = require 'srl.model.Job'

local DebuffService = {}
DebuffService.__index = DebuffService

function DebuffService:new(castService, config)
    local self = setmetatable({}, DebuffService)

    self.config = config
    self.castService = castService
    self.debuffsOnAssist = self.config:get('Debuff.DebuffOnAssist.Main') or {}

    self.debuffsOnCommand = {}
    self.debuffEnabledForXTargets = self.config:get('Debuff.DebuffTargetsOnXTarEnabled') or false
    self.minNumberOfTargetsToStartXTargetDebuff = self.config:get('Debuff.MinimumAmountToStartDebuffOnXTar') or 2
    self.retryTimers = {}

    return self
end

function DebuffService:update()

    local targetId = State.assist.targetId

    if not targetId then return end

    --Spawn?
    --local hp = mq.TLO.Target.PctHPs()

    if not self.debuffsOnAssist then
        return
    end

    if self.debuffsOnAssist and #self.debuffsOnAssist == 0 then
        return
    end


    for _,debuff in ipairs(self.debuffsOnAssist) do
        debuff.priority = debuff.priority or 150
        print("Debuff loop" .. debuff.spell)
        self:addToCastServiceQueue(debuff.spell, targetId, debuff.priority, debuff.gem)
        if(self.debuffEnabledForXTargets) then
            local slots = mq.TLO.Me.XTargetSlots()
            local numberOfAggressive = 0

            local targets = {}
            for i = 1, slots do
                local xt = mq.TLO.Me.XTarget(i)
                if xt() and xt.Type() == "NPC" and not xt.Dead() and xt.Aggressive() then
                    numberOfAggressive = numberOfAggressive + 1
                    if xt.ID() ~= targetId then
                        table.insert(targets, xt)
                    end
                end
            end

            print("Number of XTargets")
            print(#targets)
            if(#targets > 0 and #targets <= self.minNumberOfTargetsToStartXTargetDebuff) then
                for i = 1, #targets do
                    local xt = targets[i]
                    self:addToCastServiceQueue(debuff.spell, xt.ID(), debuff.priority, debuff.gem)
                end
            end
        end
    end

end

function DebuffService:addToCastServiceQueue(spellName, targetId, priority, gem)
   local k = spellName.. ":" .. targetId

    --if debuff.minHP and hp < debuff.minHP then goto continue end
    local retry = self.retryTimers[k]
    if retry and retry > mq.gettime() then return end


    TargetService:getTargetById(targetId)

    local target = mq.TLO.Target.Name()
    local spell = mq.TLO.Target.Buff(spellName)
    if(target) then
        print("Checking duration on " .. target)
        print(spell())
        print(spell.Duration())
        print("Retry")
        print(retry)
    end
    --Check Duration left?
    if spell() then
        local duration = spell.Duration.TotalSeconds() or 0
        self.retryTimers[k] = mq.gettime() + (duration * 1000 - 18000)
        return
    else
        --max tries?
        self.retryTimers[k] = mq.gettime() + (2000)
    end


    local job = Job:new(targetId, nil, spellName, 'spell', priority, gem)

    if self.castService:isQueued(job) then
        return
    end
    print("Adding spell to queue")
    print(job.key)
    self.castService:enqueue(job)
    return job
end

function DebuffService:getDebuffInformationFromKey(key)
    local values = self.config:get(key)
    local jobList = {}
    if values then
        for _, v in ipairs(values) do
            local spellName = v.spell
            local gem = v.gem or 8
            local job = Job:new(nil, nil, spellName, 'spell', 150, gem)
            table.insert(jobList, job)
        end
    end
    return jobList
end


return DebuffService
