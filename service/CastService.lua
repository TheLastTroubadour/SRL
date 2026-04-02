local mq = require 'mq'
local TableUtil = require 'util.TableUtil'
local Logging = require 'core.Write'
local Target = require 'service.TargetService'
local State = require 'core.State'

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
    self.lockedGems = {}
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
            local ok, err = pcall(function()
            for i = #self.queue, 1, -1 do
                local job = self.queue[i]
                if not job then
                    table.remove(self.queue, i)
                    goto continue
                end

                -- Stale generation
                if job.generation and job.generation ~= State.assist.generation then
                    self.queuedKeys[job.key] = nil
                    table.remove(self.queue, i)
                    goto continue
                end

                -- Spawn gone (zoned, died, etc.)
                local spawn = mq.TLO.Spawn('id ' .. job.targetId)
                if not spawn() then
                    print("Removing from queue spawn not alive")
                    table.remove(self.queue, i)
                    goto continue
                end

                -- Dead target
                if spawn.Dead() then
                    table.remove(self.queue, i)
                    goto continue
                end

                -- Out of range
                if job.type ~= 'ability' and job.type ~= 'disc' and job.type ~= 'item' and job.type ~= 'aa' then
                    local range = mq.TLO.Spell(job.name).Range() or 0
                    local spellDistance = tonumber(range) == 0 and mq.TLO.Spell(job.name).AERange() or range
                    if spellDistance and tonumber(spellDistance) < tonumber(spawn.Distance()) then
                        print(string.format("Removing due to spell distance: %s | target: %s (id: %s) | dist: %.1f | range: %.1f",
                            job.name, job.targetName, job.targetId, tonumber(spawn.Distance()), tonumber(spellDistance)))
                        table.remove(self.queue, i)
                        goto continue
                    end
                end

                ::continue::
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
                        if not a then return false end
                        if not b then return true end
                        return a.priority > b.priority
                    end)
                end

                -- Find first job past its notBefore time
                local jobIdx = nil
                local nowMs = mq.gettime()
                for idx = 1, #self.queue do
                    local j = self.queue[idx]
                    if not j.notBefore or nowMs >= j.notBefore then
                        jobIdx = idx
                        break
                    end
                end

                if not jobIdx then
                    mq.delay(50)
                    goto workerNext
                end

                local job = table.remove(self.queue, jobIdx)

                self.currentlyInFlight = job
                local result = self:performCast(job)
                if result == "NOT_READY" and (job.type == 'disc' or job.type == 'aa') then
                    -- Burn job not ready yet — put it back so it fires when it comes off cooldown
                    self.queuedKeys[job.key] = nil
                    self:enqueue(job)
                else
                    if job.type == 'buff' and self:checkIfHasBuff(job) then
                        self.buffService:setTakeHoldCooldownOnJob(job)
                        -- Notify all bots so group members can confirm they
                        -- received it and suppress duplicate casts.
                        if self.bus then
                            self.bus.actor:broadcast('buff_cast', {
                                casterName = mq.TLO.Me.Name(),
                                spellName  = job.buffName or job.name,
                                sender     = mq.TLO.Me.Name(),
                            })
                        end
                    end
                    self.queuedKeys[job.key] = nil
                    self.queuedKeys[job.name] = nil
                end
                self.currentlyInFlight = nil
            end
            ::workerNext::
            end) -- end pcall
            if not ok then
                print("CastService worker error:", err)
                self.currentlyInFlight = nil
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

    local spellType = job.type == "spell" or job.type == "heal" or job.type == "buff" or job.type == "nuke" or job.type == "aa" or job.type == "item"
    if spellType and mq.TLO.Me.Silenced() then
        return "SILENCED"
    end

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

function CastService:lockGem(gemNum)
    self.lockedGems[tonumber(gemNum)] = true
end

function CastService:unlockGem(gemNum)
    self.lockedGems[tonumber(gemNum)] = nil
end

function CastService:isGemLocked(gemNum)
    return self.lockedGems[tonumber(gemNum)] == true
end

local function hasEnoughMana(spellName)
    local spell = mq.TLO.Spell(spellName)
    if not spell() then
        return true -- spell not in DB, let the cast attempt handle it
    end

    local manaCost = spell.Mana() or 0
    if manaCost == 0 then return true end

    local currentMana = mq.TLO.Me.CurrentMana() or 0

    return currentMana >= manaCost
end

function CastService:castAA(job)
    if not mq.TLO.Me.AltAbilityReady(job.name)() then return "NOT_READY" end
    mq.cmdf('/alt activate "%s"', job.name)
    local castTime = (mq.TLO.Me.AltAbility(job.name).Spell.CastTime() or 0)
    if castTime > 0 then
        mq.delay(castTime + 500, function() return not mq.TLO.Me.Casting() end)
    end
end

function CastService:castAbility(job)
    mq.cmdf('/doability %s', job.name)
end

function CastService:castItem(job)
    local item = mq.TLO.FindItem('=' .. job.name)
    if not item() then return end
    mq.cmdf('/useitem "%s"', job.name)
    local castTime = item.Clicky.CastTime() or 0
    if castTime > 0 then
        mq.delay(castTime + 500, function() return not mq.TLO.Me.Casting() end)
    end
end

function CastService:castDisc(job)
    if mq.TLO.Me.CombatAbilityReady(job.name)() then
        mq.cmdf('/disc %s', job.name)
        local castTime = (mq.TLO.Spell(job.name).CastTime.TotalSeconds() or 0) * 1000 + 500
        if castTime > 500 then
            mq.delay(castTime, function() return not mq.TLO.Me.Casting() end)
        end
    else
        return "NOT_READY"
    end
end


function CastService:castSpell(job)
    if not hasEnoughMana(job.name) then
        print(string.format("Not enough mana for: %s (have %d, need %d)",
            job.name,
            mq.TLO.Me.CurrentMana() or 0,
            mq.TLO.Spell(job.name).Mana() or 0
        ))
        return
    end
    if job.type == 'buff' and not job.force then
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

    local checkName = job.buffName or job.name
    if mq.TLO.Target.Buff('=' .. checkName)() then
        return true
    end

    -- Also check base name without rank suffix (e.g. "Hand of Tenacity Rk. III" -> "Hand of Tenacity")
    local baseName = checkName:gsub('%s+Rk%.%s*%a+$', '')
    if baseName ~= checkName and mq.TLO.Target.Buff('=' .. baseName)() then
        return true
    end

    return false
end


function CastService:memSpellIfNeeded(job)
    if job then
        if mq.TLO.Me.Spell(job.name)() then
            if not mq.TLO.Me.Gem(job.name)() then
                local gemNum = tonumber(job.gem)
                -- Wait up to 20s for MemSwap to release the slot
                mq.delay(20000, function() return not self:isGemLocked(gemNum) end)
                self:lockGem(gemNum)
                mq.cmdf("/memspell %s \"%s\"", job.gem, job.name)
                mq.delay(12000, function()
                    return mq.TLO.Me.Gem(job.name)() ~= nil
                end)
                self:unlockGem(gemNum)
            end
        end
    end
end


function CastService:srlCast(job)
    Logging.Debug("Cast Util Export SRL Cast Start")
    self:memSpellIfNeeded(job)
    if not mq.TLO.Me.SpellReady(job.name)() then
        mq.delay(2000, function() return mq.TLO.Me.SpellReady(job.name)() end)
    end
    local isSpellReady = mq.TLO.Me.SpellReady(job.name)()
    Logging.Debug(("Is spell ready %s --- %s "):format(job.name, tostring(isSpellReady)))
    if isSpellReady then
        if not job.targetId then
            return "BAD_TARGET_ID"
        end

        if mq.TLO.Target.ID() ~= job.targetId then
            Target:getTargetById(job.targetId)
        end
        mq.cmd("/stick off")
        mq.cmd('/nav stop')
        local gem = mq.TLO.Me.Gem(job.name)() or job.gem
        if not gem then return end
        local castTime = mq.TLO.Spell(job.name).CastTime.TotalSeconds() * 1000 + 1500
        mq.cmdf('/cast %s', gem)
        mq.delay(1000, function() return mq.TLO.Me.Casting() ~= nil end)
        mq.delay(castTime, function() return not mq.TLO.Me.Casting() end)
    end
    Logging.Debug("Cast Util Export SRL Cast End")
end

function CastService:clearCombatQueue()
    for i = #self.queue, 1, -1 do
        local job = self.queue[i]
        if not job.burn and (job.type == "ability" or job.type == "nuke" or job.type == "disc" or job.type == "aa") then
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