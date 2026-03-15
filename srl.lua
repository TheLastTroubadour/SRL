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
local PackageMan = require('mq/PackageMan')
local TableUtil = require 'srl.util.TableUtil'
local FollowController = require 'srl.controller.FollowController'
local FollowService = require 'srl.service.FollowService'
local ImGui = require 'ImGui'
local DEBUG = true
local State = require 'srl.core.State'
local HealService = require 'srl.service.HealService'
local TradeService = require 'srl.service.TradeService'
local RoleService = require 'srl.service.RoleService'
local DebuffService = require 'srl.service.DebuffService'
local Context = require 'srl.perception.CombatContext'
local DecisionEngine = require 'srl.decision.DecisionEngine'
local ResourceDecision = require 'srl.decision.actions.Resource'
local NukeDecision = require 'srl.decision.actions.Nuke'
local AssistDecision = require 'srl.decision.actions.Assist'
local HealDecision = require 'srl.decision.actions.Heal'
local DebuffDecision = require 'srl.decision.actions.Debuff'
local AbilityDecision = require 'srl.decision.actions.Abilities'
PackageMan.Require('lyaml')
PackageMan.Require('luafilesystem', 'lfs')
--needs to be after lyaml by packageman
local Config = require 'srl.config.Config'
local StateService = require 'srl.service.StateService'

RunTime = {}

local function DrawDebugWindow()

    ImGui.SetNextWindowSize(400, 600, ImGuiCond_FirstUseEver)

    if ImGui.Begin("Combat Debug") then

        DEBUG = ImGui.Checkbox("Debug Enabled", DEBUG)
        ImGui.Separator()

        if not DEBUG then
            ImGui.Text("Debug Disabled")
            ImGui.End()
            return
        end

        -- Decision Engine
        ImGui.Text("Decision Engine")
        if RunTime.engine then
            for _, entry in ipairs(RunTime.engine.debug) do
                ImGui.Text(string.format("  %s | %.2f", entry.name, entry.score))
            end
        end

        ImGui.Separator()

        -- Assist / State
        local ctx = RunTime.ctx
        if ctx and ctx.assist then
            ImGui.Text(string.format("Assist Id: %s  Dead: %s  Dist: %s",
                tostring(ctx.assist.Id),
                tostring(ctx.assist.dead),
                tostring(ctx.assist.distance)
            ))
            ImGui.Text(string.format("My Target: %s  Casting: %s  Aggro: %s%%",
                tostring(ctx.myCurrentTargetId),
                tostring(ctx.casting),
                tostring(mq.TLO.Me.PctAggro())
            ))
        end
        if State and State.assist then
            ImGui.Text("Assist Gen: " .. tostring(State.assist.generation))
        end
        if State and State.follow then
            ImGui.Text(string.format("Follow Id: %s  Active: %s",
                tostring(State.follow.followId),
                tostring(State.follow.active)
            ))
        end

        ImGui.Separator()

        -- Buff Service queue (BuffService still uses CastService)
        local castService = RunTime.castService
        local buffService = RunTime.buffService
        if castService then
            ImGui.Text("Buff Queue: " .. #castService.queue)
            ImGui.BeginChild("QueueList", 0, 100, true)
            if #castService.queue == 0 then
                ImGui.Text("Empty")
            end
            for i, job in ipairs(castService.queue) do
                ImGui.Text(string.format("%d) %s | T:%s | P:%s",
                    i, tostring(job.name), tostring(job.targetId), tostring(job.priority)
                ))
            end
            ImGui.EndChild()
        end

        if buffService then
            ImGui.Separator()
            ImGui.Text("Buff Service")
            ImGui.BeginChild("BuffRequests", 0, 80, true)
            if buffService.requested then
                for k, _ in pairs(buffService.requested) do
                    ImGui.Text("Polling: " .. tostring(k))
                end
            end
            ImGui.EndChild()

            ImGui.BeginChild("BuffCooldowns", 0, 80, true)
            local now = mq.gettime()
            if buffService.cooldowns then
                for k, v in pairs(buffService.cooldowns) do
                    ImGui.Text(string.format("%s | cd: %.1fs", tostring(k), math.max(0, v - now) / 1000))
                end
            end
            ImGui.EndChild()
        end

        ImGui.Separator()

        -- Nuke Decision
        ImGui.Text("Nuke Decision")
        local nukeDecision = RunTime.nukeDecision
        if nukeDecision then
            ImGui.BeginChild("NukeList", 0, 80, true)
            for _, t in ipairs(nukeDecision.nukeList) do
                ImGui.Text(string.format("Nuke: %s | gem %s", t.name, tostring(t.gem)))
            end
            for _, t in ipairs(nukeDecision.joltList) do
                ImGui.Text(string.format("Jolt: %s | gem %s | aggro >%s%%",
                    t.name, tostring(t.gem), tostring(t.aggroThreshold or nukeDecision.joltThreshold)
                ))
            end
            ImGui.EndChild()
        end

        ImGui.Separator()

        -- Ability Decision
        ImGui.Text("Ability Decision")
        local abilityDecision = RunTime.abilityDecision
        if abilityDecision then
            ImGui.BeginChild("AbilityList", 0, 80, true)
            for _, t in ipairs(abilityDecision.abilityList) do
                ImGui.Text(string.format("%s | %s", t.name, t.type))
            end
            ImGui.EndChild()
        end

        ImGui.Separator()

        -- Heal Decision
        ImGui.Text("Heal Decision")
        local healDecision = RunTime.healDecision
        if healDecision and healDecision.job then
            ImGui.Text(string.format("Pending: %s → %s", tostring(healDecision.job.targetId), healDecision.job.name))
        else
            ImGui.Text("No heal pending")
        end
        if ctx and ctx.self and ctx.self.heal and ctx.self.heal.group then
            ImGui.BeginChild("HealTargets", 0, 100, true)
            for _, t in ipairs(ctx.self.heal.group.memberStatus or {}) do
                ImGui.Text(string.format("%s | HP:%d | Role:%s", t.name, t.hp, t.role))
            end
            ImGui.EndChild()
        end

        ImGui.Separator()

        -- Debuff Decision
        ImGui.Text("Debuff Decision")
        local debuffDecision = RunTime.debuffDecision
        if debuffDecision then
            local now = mq.gettime()
            ImGui.BeginChild("DebuffTimers", 0, 80, true)
            local any = false
            for k, v in pairs(debuffDecision.retryTimer) do
                any = true
                ImGui.Text(string.format("%s | %.1fs", k, math.max(0, v - now) / 1000))
            end
            if not any then ImGui.Text("No active timers") end
            ImGui.EndChild()
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
    castService.buffService = buffService
    CommandBus:init()
    CommandBus:register('Assist', function(payload)
        combatController:assist(payload)
    end)

    combatService.commandBus = CommandBus
    combatService.roleService = RoleService

    local followService = FollowService:new()
    local followController = FollowController:new(followService)
    local healService = HealService:new(castService, config)
    local debuffService = DebuffService:new(castService, config)
    combatService.debuffService = debuffService

    CommandBus:register('Follow', function(payload)
        followController:follow(payload)
    end)

    CommandBus:register('Stop', function(payload)
        followController:stop()
    end)

    CommandBus:register("COMBAT_ENDED", function()
            State:clearCombatState()
            castService:interruptCasting()
            followService:resumeFollow()
    end)

    local resourceDecision = ResourceDecision:new()
    local nukeDecision = NukeDecision:new(config)
    local assistDecision = AssistDecision:new()
    local healDecision = HealDecision:new(config)
    local debuffDecision = DebuffDecision:new(config)
    local abilityDecision = AbilityDecision:new(config)
    local context = Context:new(config)

    local engine = DecisionEngine:new({
        resourceDecision,
        nukeDecision,
        assistDecision,
        healDecision,
        debuffDecision,
        abilityDecision
    })

    RunTime.engine = engine
    RunTime.castService = castService
    RunTime.buffService = buffService
    RunTime.nukeDecision = nukeDecision
    RunTime.abilityDecision = abilityDecision
    RunTime.healDecision = healDecision
    RunTime.debuffDecision = debuffDecision

    mq.imgui.init("CombatDebugUI", function()
        local ok, err = pcall(DrawDebugWindow)
        if not ok then
            print("UI Error:", err)
        end
    end)

    while true do
        Logging.Debug("Main While loop Start")
        mq.doevents()

        --StateService:update(State)
        --order matters
        --Process network replies and resolve promises
        local ctx = context:build(State)
        RunTime.ctx = ctx
        local action = engine:evaluate(ctx)
        if action then
            action:execute(ctx)
        end
        busService:update()
        --resume any coroutines waiting on await
        scheduler:run()

        buffService:update(ctx)
        --combatService:update(ctx)
        followService:checkFollow(ctx)
        TradeService:update(ctx)
        mq.delay(50)

        Logging.Debug("Main While loop End")
    end
end



mainLoop();
