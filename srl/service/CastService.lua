local mq = require 'mq'
local TableUtil = require 'srl/util/TableUtil'
local Logging = require 'srl/core/Write'
local Target = require 'srl/service/TargetService'
local State = require 'srl.core.State'

local CastService = {}
CastService.__index = CastService

function CastService:new(scheduler, combatService)
    local self = setmetatable({}, CastService)

    self.scheduler = scheduler
    self.combatService = combatService
    self.buffService = {}
    self.queue = {}
    self.queuedKeys = {}
    self.currentlyInFlight = nil
    self:startWorker()

    return self
end

function CastService:setBus(bus)
    self.bus = bus
end

function CastService:enqueue(job)
    if self.queuedKeys[job.key] then return end

    table.insert(self.queue, job)
    self.queuedKeys[job.key] = true
end

function CastService:startWorker()

    self.scheduler:spawn(function()

        while true do
            for i = #self.queue, 1, -1 do
                local job = self.queue[i]
                if job.generation then
                    if job.generation ~= State.assist.generation then
                        self.queuedKeys[job.key] = nil
                        table.remove(self.queue, i)
                    end
                end

                --remove anything that doesn't have a spawn also since might have zoned and new id
                local spawn = mq.TLO.Spawn('id ' .. job.targetId)
                if not spawn() then
                    print("Removing from queue spawn not alive")
                    table.remove(self.queue, i)
                end

                --Don't queue anything not in range need to do something for AE spells
                if(job.type ~= 'ability') then
                    local spellDistance = mq.TLO.Spell(job.name).Range()
                    if spellDistance and spawn() and tonumber(spellDistance) < tonumber(spawn.Distance()) then
                        print("Removing due to spell distance " .. job.name .. job.targetId)
                        table.remove(self.queue, i)
                    end
                end
                --Don't cast on dead targets
                if spawn() and spawn.Dead() then
                    table.remove(self.queue, i)
                end

            end

            if self.currentlyInFlight
                    and self.currentlyInFlight.generation
                    and self.currentlyInFlight.generation ~= State.assist.generation then
                -- Let cast finish naturally
                self.currentlyInFlight = nil
            end

            if self.currentlyInFlight then
                mq.delay(25)
                return
            end

            if #self.queue == 0 then
                mq.delay(50)
            else
                if #self.queue > 1 then
                    table.sort(self.queue, function(a, b)
                        return a.priority > b.priority
                    end)
                end

                local job = table.remove(self.queue, 1)

                self.currentlyInFlight = job
                local result = self:performCast(job)
                if result == 'CAST_TAKEHOLD' then
                    if(job.type == 'buff') then
                        self.buffService:setTakeHoldCooldownOnJob(job)
                    end
                end
                self.currentlyInFlight = nil
                self.queuedKeys[job.key] = nil
                self.queuedKeys[job.name] = nil
            end
        end
    end)
end

function CastService:performCast(job)
    --[[
    self.bus:broadcast("cast_started " .. mq.TLO.Me.Name() .. " spell: " .. job.name .. " targetId: " .. job.targetId, {
        caster = mq.TLO.Me.Name(),
        spell = job.name,
        targetId = job.targetId,
        type = job.type
    })
    --]]

    local result

    if job.type == "spell" or job.type == "heal" or job.type == "buff" or job.type == "nuke" then
        result = self:castSpell(job)
    elseif job.type == "aa" then
        result = self:castAA(job)
    elseif job.type == "item" then
        result = self:castItem(job)
    elseif job.type == "disc" then
        result = self:castDisc(job)
    elseif job.type == 'ability' then
        result = self:castAbility(job)
    end

    --[[
    -- announce completion
    self.bus:broadcast("cast_finished " .. mq.TLO.Me.Name() .. "spell" .. job.name .. " targetId: " .. job.targetId, {
        caster = mq.TLO.Me.Name(),
        spell = job.name,
        targetId = job.targetId,
        success = result
    })
    --]]

    return result
end

function CastService:isQueued(job)
    return self.queuedKeys[job.key] == true
end

local function hasEnoughMana(spellName)
    local spell = mq.TLO.Spell(spellName)
    if not spell() then
        return false
    end

    local manaCost = spell.Mana() or 0
    local currentMana = mq.TLO.Me.CurrentMana() or 0

    return currentMana >= manaCost
end

function CastService:castAbility(job)
    mq.cmdf('/doability %s', job.name)
end

function CastService:castDisc(job)
    if mq.TLO.Me.CombatAbilityReady(job.name)() then
        mq.cmdf('/disc %s', job.name)
    end
end


function CastService:castSpell(job)
    if not hasEnoughMana(job.name) then
        print("Not enough mana for: " .. job.name)
        return
    end
    if job.type == 'buff' then
        local alreadyHasBuff = self:checkIfHasBuff(job)
        if alreadyHasBuff then
            return
        end
    end
    return self:srlCast(job)
end

function CastService:checkIfHasBuff(job)
    if(mq.TLO.Target.ID() ~= job.targetId) then
        Target:getTargetById(job.targetId)
    end

    if mq.TLO.Target.Buff(job.name)() then
        return true
    end
    return false
end


function CastService:memSpellIfNeeded(job)
    if job then
        if mq.TLO.Me.Spell(job.name)() then
            if not mq.TLO.Me.Gem(job.name)() then
                mq.cmdf("/memorize \"%s\" %s", job.name, job.gem)
                mq.delay(5000, function()
                    return mq.TLO.Me.Gem(job.name)() ~= nil
                end)
            end
        end
    end
end


function CastService:srlCast(job)
    Logging.Debug("Cast Util Export SRL Cast Start")
    local isSpellReady = mq.TLO.Cast.Ready(job.name)
    Logging.Debug(("Is spell ready %s --- %s "):format(job.name, isSpellReady))
    if(isSpellReady) then
        if not job.targetId then
            return "BAD_TARGET_ID"
        end

        if mq.TLO.Target.ID() ~= job.targetId then
            Target:getTargetById(job.targetId)
        end
        --param gems
        --need to stop moving as well
        mq.cmd("/stick off");
        mq.cmd("/afollow off")
        local castTime = mq.TLO.Spell(job.name).CastTime.TotalSeconds() * 1000 + 1500
        mq.cmdf("/casting \"%s\"|%s", job.name, job.gem)
        mq.delay(castTime)
        local result = mq.TLO.Cast.Result()
        return result
    end
    Logging.Debug("Cast Util Export SRL Cast End")
    return "CAST_NOTREADY"
end

function CastService:clearCombatQueue()
    for i = #self.queue, 1, -1 do
        local job = self.queue[i]
        if job.type == "ability" or job.type == "nuke" then
            self.queuedKeys[job.key] = nil
            table.remove(self.queue, i)
        end
    end
end

function CastService:interruptCasting()
    if mq.TLO.Me.Casting() and mq.TLO.Target.ID() == State.assist.targetId then
        mq.cmd('/interrupt')
    end
end

return CastService