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
local CCDecision = require 'srl.decision.actions.CrowdControl'
local ClericDecision = require 'srl.decision.actions.Cleric'
local RezDecision = require 'srl.decision.actions.Rez'
local GiftOfMana = require 'srl.decision.actions.GiftOfMana'
local MovementDecision = require 'srl.decision.actions.Movement'
PackageMan.Require('lyaml')
PackageMan.Require('luafilesystem', 'lfs')
--needs to be after lyaml by packageman
local Config = require 'srl.config.Config'
local EventRegistry = require 'srl.core.EventRegistry'
local InviteService = require 'srl.service.InviteService'
local BurnService = require 'srl.service.BurnService'
local CureService = require 'srl.service.CureService'
local CureDecision = require 'srl.decision.actions.Cure'
local MelodyService = require 'srl.service.MelodyService'

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

        ImGui.Separator()

        -- CC Decision
        ImGui.Text("CC Decision")
        local ccDecision = RunTime.ccDecision
        if ccDecision then
            local ctx2 = RunTime.ctx
            ImGui.Text(string.format("Role: %s  Enabled: %s  Casting: %s",
                tostring(ctx2 and ctx2.roles and ctx2.roles['cc']),
                tostring(ccDecision.config:get('CrowdControl.Enabled')),
                tostring(ctx2 and ctx2.casting)
            ))
            ImGui.Text(string.format("Spells loaded: %d  WaitingResult: %s",
                #ccDecision.spells,
                tostring(ccDecision.waitingForResult)
            ))
            if ccDecision.spells[1] then
                local s = ccDecision.spells[1]
                ImGui.Text(string.format("Spell[1]: %s gem:%s ready:%s",
                    tostring(s.spell),
                    tostring(s.gem),
                    tostring(mq.TLO.Cast.Ready(s.spell)())
                ))
            end
            -- XTarget scan
            local xtTotal, xtNPC, xtAggro = 0, 0, 0
            local slots = mq.TLO.Me.XTargetSlots()
            for i = 1, slots do
                local xt = mq.TLO.Me.XTarget(i)
                if xt() then
                    xtTotal = xtTotal + 1
                    if xt.Type() == "NPC" and not xt.Dead() then
                        xtNPC = xtNPC + 1
                        if xt.Aggressive() then xtAggro = xtAggro + 1 end
                    end
                end
            end
            ImGui.Text(string.format("XTar slots:%d  NPCs:%d  Aggressive:%d", xtTotal, xtNPC, xtAggro))
            ImGui.Text(string.format("Pending: %s  Spell: %s",
                tostring(ccDecision.pendingTarget),
                tostring(ccDecision.pendingSpell and ccDecision.pendingSpell.spell)
            ))
            local now = mq.gettime()
            ImGui.BeginChild("MezzedList", 0, 80, true)
            local any = false
            for id, recastAt in pairs(ccDecision.mezzed) do
                any = true
                ImGui.Text(string.format("id:%s | recast in %.1fs", tostring(id), math.max(0, recastAt - now) / 1000))
            end
            if not any then ImGui.Text("No mezzed targets") end
            ImGui.EndChild()
        end

    end

    ImGui.End()
end


-- MAIN MACRO LOOP
local function mainLoop()
    Logging.Debug("Main Loop Start")
    --init.setup();

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

    local inviteService = InviteService
    EventRegistry:new():init({
        buffService   = buffService,
        inviteService = inviteService,
    })

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

    CommandBus:register('Move', function(payload)
        State:setMove(payload)
    end)

    CommandBus:register('CCMaxMobs', function(payload)
        ccDecision:setMaxTankedMobs(payload.n)
    end)

    CommandBus:register('ReloadConfig', function()
        config:reload()
    end)

    CommandBus:register('BackOff', function()
        State:clearCombatState()
        mq.cmd('/attack off')
        mq.cmd('/stick off')
        mq.cmd('/afollow off')
        mq.cmd('/stopcast')
        mq.cmd('/cleartarget')
    end)

    local burnService = BurnService:new(config)
    local cureService = CureService:new()
    local cureDecision = CureDecision:new(config)
    local melodyService = MelodyService:new(config)

    CommandBus:register('QuickBurn', function()
        burnService:activate('Burn.QuickBurn')
    end)

    CommandBus:register('LongBurn', function()
        burnService:activate('Burn.LongBurn')
    end)

    CommandBus:register('FullBurn', function()
        burnService:activate('Burn.FullBurn')
    end)

    CommandBus:register('EpicBurn', function()
        burnService:clickEpic()
    end)

    CommandBus:register('Lesson', function()
        mq.cmd('/alt activate "Lesson of the Devoted"')
    end)

    CommandBus:register('Armor', function()
        mq.cmd('/alt activate "Armor of Experience"')
    end)

    CommandBus:register('Staunch', function()
        mq.cmd('/alt activate "Staunch Recovery"')
    end)

    CommandBus:register('Intensity', function()
        mq.cmd('/alt activate "Intensity of the Resolute"')
    end)

    CommandBus:register('Expedient', function()
        mq.cmd('/alt activate "Expedient Recovery"')
    end)

    CommandBus:register('Throne', function()
        mq.cmd('/alt activate "Throne of Heroes"')
    end)

    CommandBus:register('PlayMelody', function(payload)
        if payload.name then melodyService:play(payload.name) end
    end)

    CommandBus:register('StopMelody', function()
        melodyService:stop()
    end)

    CommandBus:register("COMBAT_ENDED", function()
            State:clearCombatState()
            castService:interruptCasting()
            followService:resumeFollow()
            mq.cmd('/attack off')
    end)

    local resourceDecision = ResourceDecision:new()
    local nukeDecision = NukeDecision:new(config)
    local assistDecision = AssistDecision:new()
    local healDecision = HealDecision:new(config)
    local debuffDecision = DebuffDecision:new(config)
    local abilityDecision = AbilityDecision:new(config)
    local ccDecision = CCDecision:new(config)
    local clericDecision  = ClericDecision:new(config)
    local rezDecision     = RezDecision:new(config)
    local giftOfMana      = GiftOfMana:new(config)
    local movementDecision = MovementDecision:new()
    local context = Context:new(config)

    CommandBus:register('NeedCure', function(payload)
        cureDecision:addRequest(payload.id, payload.name, payload.types)
    end)

    local engine = DecisionEngine:new({
        movementDecision,
        resourceDecision,
        ccDecision,
        nukeDecision,
        assistDecision,
        healDecision,
        clericDecision,
        rezDecision,
        giftOfMana,
        cureDecision,
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
    RunTime.ccDecision = ccDecision

    mq.imgui.init("CombatDebugUI", function()
        local ok, err = pcall(DrawDebugWindow)
        if not ok then
            print("UI Error:", err)
        end
    end)

    while true do
        Logging.Debug("Main While loop Start")
        mq.doevents()

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
        --followService:checkFollow(ctx)  -- replaced by MovementDecision
        TradeService:update(ctx)
        cureService:update()
        mq.delay(50)

        Logging.Debug("Main While loop End")
    end
end



mainLoop();
