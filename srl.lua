--Macro Created to be full bot scenario for all classes in EQ
local mq = require "mq";
local init = require "srl/Setup"
local Logging = require 'srl/core/Write'
local Bus = require 'srl/core/Bus'
local BufferController = require 'srl/controller/BufferController'
local Scheduler = require 'srl/core/Scheduler'
local BuffService = require 'srl/service/BuffService'
local CombatService = require 'srl/service/CombatService'
local CastService = require 'srl/service/CastService'
local BindService = require 'srl/service/BindService'
local CombatController = require 'srl/controller/CombatController'
local CommandBus = require 'srl/core/CommandBus'
local Config = require 'srl.config.Config'
local PackageMan = require('mq/PackageMan')
local TableUtil = require 'srl.util.TableUtil'
local FollowController = require 'srl.controller.FollowController'
local FollowService = require 'srl.service.FollowService'
local ImGui = require 'ImGui'
local DEBUG = true
local State = require 'srl.core.State'
local HealService = require 'srl.service.HealService'
local TradeService = require 'srl.service.TradeService'
PackageMan.Require('lyaml')
PackageMan.Require('luafilesystem', 'lfs')

local function DrawDebugWindow(castService, buffService, healService, combatService)

    ImGui.SetNextWindowSize(400, 300, ImGuiCond_FirstUseEver)

    if ImGui.Begin("Combat Debug") then

        DEBUG = ImGui.Checkbox("Debug Enabled", DEBUG)

        ImGui.Separator()

        if DEBUG then

            if State and State.assist then
                ImGui.Text("Assist Generation: " .. tostring(State.assist.generation))
                ImGui.Text("Assist Target Id: " .. tostring(State.assist.targetID))
            else
                ImGui.Text("Assist Generation: nil")
            end

            if State and State.follow then
                ImGui.Text("Follow Id: " .. tostring(State.follow.followId))
                ImGui.Text("Follow State: " .. tostring(State.follow.active))
            end

            if castService and castService.currentlyInFlight then
                ImGui.Text("In Flight: " .. tostring(castService.currentlyInFlight.spell))
            else
                ImGui.Text("In Flight: None")
            end

            ImGui.Separator()
            ImGui.Text("Queue N: " .. #castService.queue)

            ImGui.BeginChild("QueueList", 0, 150, true)
            if castService and castService.queue then
                if #castService.queue == 0 then
                    ImGui.Text("Queue Empty")
                end

                for i, job in ipairs(castService.queue) do
                    ImGui.Text(string.format(
                            "%d) Spell: %s | T:%s | P:%s | G:%s",
                            i,
                            tostring(job.name),
                            tostring(job.targetId),
                            tostring(job.priority),
                            tostring(job.generation)
                    ))
                end

            end
            ImGui.EndChild()
            ImGui.Separator()
            ImGui.Text("Buff Service")

            if buffService then

                ImGui.Text("Requested Polls: " .. #buffService.requested)
                ImGui.Text("Cooldowns: " .. #buffService.cooldowns)
                ImGui.Text("Next Checks: " .. #buffService.nextCheck)

                ImGui.Separator()

                ImGui.BeginChild("BuffRequests", 0, 120, true)

                ImGui.Text("Buff Requests Outbound")
                if (buffService.requested) then
                    for k, v in pairs(buffService.requested) do
                        ImGui.Text("Polling: " .. tostring(k))
                    end
                end
                ImGui.EndChild()

                ImGui.Separator()

                ImGui.Text("Cooldown Display")

                ImGui.BeginChild("BuffCooldowns", 0, 120, true)

                if (buffService.cooldowns) then
                    local now = mq.gettime()

                    for k, v in pairs(buffService.cooldowns) do
                        local remaining = math.max(0, v - now)
                        ImGui.Text(string.format(
                                "%s | cooldown: %.2fs",
                                tostring(k),
                                remaining / 1000
                        ))
                    end
                end
                ImGui.EndChild()

                ImGui.Separator()

                ImGui.Text("NextChecks Display")
                ImGui.BeginChild("BuffNextChecks", 0, 120, true)

                local now = mq.gettime()

                if buffService.nextCheck then
                    for k, v in pairs(buffService.nextCheck) do
                        local remaining = math.max(0, v - now)

                        ImGui.Text(string.format(
                                "%s | next in %.2fs",
                                tostring(k),
                                remaining / 1000
                        ))
                    end
                else
                    ImGui.Text("No NextChecks")
                end

                ImGui.EndChild()
            end

            ImGui.Separator()
            ImGui.Text("Combat Service")

            if(combatService) then

                ImGui.Text("Abilities")
                ImGui.BeginChild("Ability Rotation")
                local abilityRotation = combatService:getAbilityRotation()
               for _, t in ipairs(abilityRotation) do


                    ImGui.Text(string.format(
                            "%s",
                            t.name
                    ))

                end

                ImGui.EndChild()

                ImGui.Separator()

                ImGui.Text("NukeRotation")
                ImGui.BeginChild("Nuke Rotation")
                    local nukeRotation = combatService:getSpellRotation()
               for _, t in ipairs(nukeRotation) do


                    ImGui.Text(string.format(
                            "%s | %s",
                            t.name,
                            t.gem
                    ))

                end

                ImGui.EndChild()

            end


            ImGui.Separator()
            ImGui.Text("Heal Service")

            if healService then

                local targets = healService:collectTargets()
                local total = 0

                for _, t in ipairs(targets) do
                    total = total + t.hp
                end

                local avg = 100
                if #targets > 0 then
                    avg = total / #targets
                end

                ImGui.Text(string.format("Group Average HP: %.1f", avg))

                ImGui.Separator()

                ImGui.Text("Targets")

                ImGui.BeginChild("HealTargets", 0, 150, true)

                for _, t in ipairs(targets) do

                    local locked = healService:healLocked(t.id)

                    ImGui.Text(string.format(
                            "%s | HP:%d | Role:%s | Locked:%s",
                            t.name,
                            t.hp,
                            t.role,
                            tostring(locked)
                    ))

                end

                ImGui.EndChild()

                ImGui.Separator()
                ImGui.Text("Heal Spell Selection")

                local targets = healService:collectTargets()

                ImGui.BeginChild("HealSpellEval", 0, 120, true)

                for _, t in ipairs(targets) do

                    local heal = healService:selectHealSpell(t)

                    if heal then
                        ImGui.Text(string.format(
                                "%s → %s (threshold %d)",
                                t.name,
                                heal.spell,
                                heal.threshold
                        ))
                    else
                        ImGui.Text(string.format(
                                "%s → no heal",
                                t.name
                        ))
                    end

                end

                ImGui.EndChild()

                ImGui.Separator()
                ImGui.Text("Heal Decision")

                local targets = healService:collectTargets()
                local best = healService:selectBestTarget(targets)

                if best then

                    local heal = healService:selectHealSpell(best)

                    ImGui.Text(string.format(
                            "Chosen Target: %s",
                            best.name
                    ))

                    ImGui.Text(string.format(
                            "HP: %d",
                            best.hp
                    ))

                    if heal then
                        ImGui.Text(string.format(
                                "Spell: %s",
                                heal.spell
                        ))
                    end

                else
                    ImGui.Text("No heal needed")
                end

            end
        else
            ImGui.Text("Debug Disabled")
        end

    end

    ImGui.End()
end

-- MAIN MACRO LOOP
local function mainLoop()
    Logging.Debug("Main Loop Start")
    init.setup();

    local config = Config:new(nil)

    config:generateCharacterYaml()
    config:loadCharacterYaml()

    local scheduler = Scheduler:new()
    local castService = CastService:new(scheduler)
    local busService = Bus:new("SRL")
    castService:setBus(busService)
    BufferController:new(busService)
    local combatService = CombatService:new(castService, config)
    BindService:new(combatService)
    castService.combatService = combatService
    local combatController = CombatController:new(combatService)
    local buffService = BuffService:new(busService, scheduler, combatService, castService, config)
    CommandBus:init()
    CommandBus:register('Assist', function(payload)
        combatController:assist(payload)
    end)

    combatService.commandBus = CommandBus

    local followService = FollowService:new()
    local followController = FollowController:new(followService)
    local healService = HealService:new(castService, config)

    CommandBus:register('Follow', function(payload)
        followController:follow(payload)
    end)

    CommandBus:register('Stop', function(payload)
        followController:stop()
    end)

    CommandBus:register("COMBAT_ENDED", function()
            State:clearCombatState()
            followService:resumeFollow()
    end)

    mq.imgui.init("CombatDebugUI", function()
        local ok, err = pcall(function()
            DrawDebugWindow(castService, buffService, healService, combatService)
        end)

        if not ok then
            print("UI Error:", err)
        end
    end)

    while true do
        Logging.Debug("Main While loop Start")
        mq.doevents()
        --order matters
        --Process network replies and resolve promises
        busService:update()
        --resume any coroutines waiting on await
        scheduler:run()

        healService:update()
        buffService:update()
        combatService:update()
        followService:checkFollow()
        TradeService:update()
        mq.delay(50)

        Logging.Debug("Main While loop End")
    end
end

mainLoop();
