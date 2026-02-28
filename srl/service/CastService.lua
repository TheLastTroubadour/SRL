local mq = require 'mq'
local TableUtil = require 'srl/util/TableUtil'
local Logging = require 'Write'
local Target = require 'TargetService'

local CastService = {}
CastService.__index = CastService

function CastService:new(scheduler, combatService)
    local self = setmetatable({}, CastService)

    self.scheduler = scheduler
    self.combatService = combatService
    self.queue = {}
    self.currentJob = nil
    self.isCasting = false

    self:startWorker()

    return self
end

function CastService:setBus(bus)
    self.bus = bus
end

function CastService:enqueue(job)
    -- prevent duplicates
    for _,existing in ipairs(self.queue) do
        if existing.target == job.target
                and existing.spell == job.spell
                and existing.category == job.category
        then
            return
        end
    end

    table.insert(self.queue, job)
end

function CastService:startWorker()

    self.scheduler:spawn(function()

        while true do

            if #self.queue == 0 then
                mq.delay(50)
            else
                local job = table.remove(self.queue, 1)

                -- Skip outdated combat jobs
                if job.generation
                        and job.generation ~= self.combatService.generation
                then
                    print("Skipping outdated job")
                else
                    self:performCast(job)
                end
            end

        end

    end)
end

function CastService:performCast(job)
    if self.isCasting then
        return { success = false, reason = "Already casting" }
    end

    self.isCasting = true

    -- announce cast start
    self.bus:broadcast("cast_started", {
        caster = mq.TLO.Me.Name(),
        spell = job.spell,
        targetId = job.Id,
        type = job.type
    })

    local result

    if job.type == "spell" then
        result = self:castSpell(job)
    elseif job.type == "aa" then
        result = self:castAA(job)
    elseif job.type == "item" then
        result = self:castItem(job)
    elseif job.type == "disc" then
        result = self:castDisc(job)
    end

    -- announce completion
    self.bus:broadcast("cast_finished", {
        caster = mq.TLO.Me.Name(),
        spell = job.spell,
        targetId = job.targetId,
        success = result
    })

    self.isCasting = false

    return result
end

function CastService:castSpell(job)
    self:srlCast(job)
end


function CastService:srlCast(job)
    Logging.Debug("Cast Util Export SRL Cast Start")
    print("Srl Cast ")
    print(TableUtil.table_print(job))
    local isSpellReady = self.isCasting and mq.TLO.Cast.Ready(job.spell)
    Logging.Debug(("Is spell ready %s --- %s "):format(job.spell, isSpellReady))
    if(isSpellReady) then
        Target:get_target_by_id(job.targetId)
        --param gems
        --need to stop moving as well
        local castTime = mq.TLO.Spell(job.spell).CastTime.TotalSeconds() * 1000 + 1500
        mq.cmdf("/casting \"%s\"|%s", job.spell, job.gem)
        mq.delay(castTime)
        local result = mq.TLO.Cast.Result()
        return result
    end
    Logging.Debug("Cast Util Export SRL Cast End")
    return "CAST_NOTREADY"
end

function CastService:clearCombatQueue()

    local newQueue = {}

    for _,job in ipairs(self.queue) do
        if job.type ~= "spell" or not job.generation then
            table.insert(newQueue, job)
        end
    end

    self.queue = newQueue
end

return CastService