--Macro Created to be full bot scenario for all classes in EQ
local mq = require "mq";
local init = require 'Setup'
local Logging = require 'core.Write'
local Bus = require 'core.Bus'
local BufferController = require 'controller.BufferController'
local Scheduler = require 'core.Scheduler'
local BuffService = require 'service.BuffService'
local CombatService = require 'service.CombatService'
local CastService = require 'service.CastService'
local BindService = require 'service.BindService'
local CombatController = require 'controller.CombatController'
local CommandBus = require 'core.CommandBus'
local PackageMan = require 'mq.PackageMan'
local TableUtil = require 'util.TableUtil'
local FollowController = require 'controller.FollowController'
local FollowService = require 'service.FollowService'
local ImGui = require 'ImGui'
local DEBUG = false
local debugState = { visible = false }
local GroupStatusWindow  = require 'window.GroupStatusWindow'
local ConfigEditorWindow = require 'window.ConfigEditorWindow'
local StatusService      = require 'service.StatusService'
local State = require 'core.State'
local HealService = require 'service.HealService'
local TradeService = require 'service.TradeService'
local TrustService = require 'service.TrustService'
local RoleService = require 'service.RoleService'
local DebuffService = require 'service.DebuffService'
local Context = require 'perception.CombatContext'
local DecisionEngine = require 'decision.DecisionEngine'
local ResourceDecision = require 'decision.actions.Resource'
local NukeDecision = require 'decision.actions.Nuke'
local AssistDecision = require 'decision.actions.Assist'
local HealDecision = require 'decision.actions.Heal'
local DebuffDecision = require 'decision.actions.Debuff'
local AbilityDecision = require 'decision.actions.Abilities'
local CCDecision = require 'decision.actions.CrowdControl'
local ClericDecision = require 'decision.actions.Cleric'
local GiftOfMana = require 'decision.actions.GiftOfMana'
local WizardDecision = require 'decision.actions.Wizard'
local ShrinkDecision = require 'decision.actions.Shrink'
local AuraDecision = require 'decision.actions.Aura'
local RezDecision  = require 'decision.actions.Rez'
local HoTDecision      = require 'decision.actions.HoT'
local MovementDecision = require 'decision.actions.Movement'
local TauntDecision    = require 'decision.actions.Taunt'
local AEDecision            = require 'decision.actions.AE'
local MedDecision           = require 'decision.actions.Med'
local BerzerkerAxeDecision  = require 'decision.actions.BerzerkerAxe'
local DotDecision           = require 'decision.actions.Dot'
local MemSwapDecision       = require 'decision.actions.MemSwap'
PackageMan.Require('lyaml')
PackageMan.Require('luafilesystem', 'lfs')
--needs to be after lyaml by packageman
local Config = require 'config.Config'
local EventRegistry = require 'core.EventRegistry'
local InviteService = require 'service.InviteService'
local BurnService = require 'service.BurnService'
local WeaponSwapService = require 'service.WeaponSwapService'
local CureService = require 'service.CureService'
local CureDecision = require 'decision.actions.Cure'
local MelodyService = require 'service.MelodyService'
local CommandRegistry = require 'core.CommandRegistry'
local ConfigValidator = require 'util.ConfigValidator'

-- Seed RNG uniquely per character so staggered delays differ across bots
do
    local name = mq.TLO.Me.Name() or ''
    local seed = os.time()
    for i = 1, #name do seed = seed + string.byte(name, i) * (i * 31) end
    math.randomseed(seed)
    math.random() math.random() -- discard first two (LCG warm-up)
end

RunTime = {}

local function DrawDebugWindow()

    if not debugState.visible then return end

    ImGui.SetNextWindowSize(400, 600, 8) -- ImGuiCond_FirstUseEver = 8

    local open = true
    if ImGui.Begin("Combat Debug", open) then

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
                    tostring(mq.TLO.Me.SpellReady(s.spell)())
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

    -- Wait until fully in-game before registering actors and initializing services
    while mq.TLO.EverQuest.GameState() ~= 'INGAME' do
        mq.delay(500)
    end
    -- Extra settle time for the actors system to be ready
    mq.delay(2000)

    local config = Config:new(nil)

    config:generateCharacterYaml()
    config:loadCharacterYaml()
    ConfigValidator.run(config)

    -- Apply YAML overrides to State flags
    if config:get('AE.Enabled') ~= nil then
        State.flags.aeEnabled = config:get('AE.Enabled') == true
    end

    local scheduler = Scheduler:new()
    local castService = CastService:new(scheduler)
    local busService = Bus:new("SRL")
    local statusService = StatusService:new()
    GroupStatusWindow:setStatusService(statusService)
    ConfigEditorWindow:setConfig(config)
    busService.actor:on('char_status', function(sender, data)
        if data and data.data then statusService:update(data.data) end
    end)
    castService:setBus(busService)
    local bufferController = BufferController:new(busService)
    local combatService = CombatService:new(castService, config)
    BindService:new(combatService)
    castService.combatService = combatService
    local combatController = CombatController:new(combatService, config)
    local buffService = BuffService:new(busService, scheduler, combatService, castService, config)
    castService.buffService = buffService
    buffService:startWatcher()

    busService.actor:on('reset_buffs_for_me', function(sender, data)
        local name = data and data.data and data.data.sender
        if name and name ~= '' then
            buffService:resetForTarget(name)
        end
    end)

    busService.actor:on('buff_received', function(sender, data)
        local d = data and data.data
        if d and d.targetName and d.spellName and d.duration then
            buffService:onBuffReceived(d.targetName, d.spellName, d.duration)
        end
    end)

    busService.actor:on('buff_removed', function(sender, data)
        local d = data and data.data
        if d and d.targetName and d.spellName then
            buffService:onBuffRemoved(d.targetName, d.spellName)
        end
    end)

    local trustService = TrustService:new(config)
    local inviteService = InviteService
    inviteService:setup(trustService)
    EventRegistry:new():init({
        buffService   = buffService,
        inviteService = inviteService,
        config        = config,
        trustService  = trustService,
    })

    CommandBus:init()
    combatService.commandBus = CommandBus
    combatService.roleService = RoleService

    local followService = FollowService:new()
    local followController = FollowController:new(followService, config)
    local healService = HealService:new(castService, config)
    local debuffService = DebuffService:new(castService, config)
    combatService.debuffService = debuffService

    local tradeService = TradeService:new(config, trustService)
    local weaponSwapService = WeaponSwapService:new(config)
    combatController:setWeaponSwapService(weaponSwapService)

    local burnService = BurnService:new(config)
    burnService:setCombatService(combatService)
    local cureService = CureService:new(config)
    local cureDecision = CureDecision:new(config)
    local melodyService = MelodyService:new(config)
    castService:setMelodyService(melodyService)

    local resourceDecision = ResourceDecision:new(melodyService)
    local nukeDecision = NukeDecision:new(config)
    local assistDecision = AssistDecision:new()
    local healDecision = HealDecision:new(config)
    healDecision:setBus(busService)
    busService.actor:on('group_heal_cast', function(sender, data)
        local d = data and data.data
        if d and d.suppressMs then
            healDecision:suppressGroupHeal(tonumber(d.suppressMs) or 8000)
        end
    end)
    local debuffDecision = DebuffDecision:new(config)
    local abilityDecision = AbilityDecision:new(config)
    burnService:setAbilityDecision(abilityDecision)
    local ccDecision = CCDecision:new(config)
    local clericDecision  = ClericDecision:new(config)
    local giftOfMana      = GiftOfMana:new(config)
    local wizardDecision  = WizardDecision:new(config)
    local shrinkDecision  = ShrinkDecision:new(config)
    local auraDecision    = AuraDecision:new(config, melodyService)
    local rezDecision     = RezDecision:new(config)
    local hotDecision      = HoTDecision:new(config)
    local tauntDecision    = TauntDecision:new(config)
    local aeDecision           = AEDecision:new(config)
    local movementDecision     = MovementDecision:new()
    local medDecision          = MedDecision:new()
    local berzerkerAxeDecision = BerzerkerAxeDecision:new(config)
    local dotDecision          = DotDecision:new(config)
    local memSwapDecision      = MemSwapDecision:new(config, castService)
    local context = Context:new(config)

    CommandRegistry:setup(CommandBus, {
        combatController = combatController,
        followController = followController,
        followService    = followService,
        castService      = castService,
        combatService    = combatService,
        burnService       = burnService,
        weaponSwapService = weaponSwapService,
        buffService      = buffService,
        melodyService    = melodyService,
        cureDecision     = cureDecision,
        abilityDecision  = abilityDecision,
        nukeDecision     = nukeDecision,
        context          = context,
        ccDecision       = ccDecision,
        memSwapDecision  = memSwapDecision,
        debugState          = debugState,
        groupStatusWindow   = GroupStatusWindow,
        configEditorWindow  = ConfigEditorWindow,
        resourceDecision    = resourceDecision,
        rezDecision         = rezDecision,
    }, config)

    local engine = DecisionEngine:new({
        movementDecision,
        tauntDecision,
        resourceDecision,
        ccDecision,
        nukeDecision,
        assistDecision,
        healDecision,
        clericDecision,
        giftOfMana,
        wizardDecision,
        cureDecision,
        hotDecision,
        debuffDecision,
        abilityDecision,
        shrinkDecision,
        auraDecision,
        rezDecision,
        aeDecision,
        berzerkerAxeDecision,
        dotDecision,
        medDecision,
        memSwapDecision
    })

    RunTime.engine = engine
    RunTime.castService = castService
    RunTime.buffService = buffService
    RunTime.nukeDecision = nukeDecision
    RunTime.memSwapDecision = memSwapDecision
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

    mq.imgui.init("GroupStatusUI", function()
        local ok, err = pcall(function() GroupStatusWindow:draw() end)
        if not ok then print("GroupStatus UI Error:", err) end
    end)

    mq.imgui.init("ConfigEditorUI", function()
        local ok, err = pcall(function() ConfigEditorWindow:draw() end)
        if not ok then print("ConfigEditor UI Error:", err) end
    end)

    local lastZoneId  = mq.TLO.Zone.ID()
    local wasDead     = false

    while true do
        Logging.Debug("Main While loop Start")
        mq.doevents()

        -- Detect zone change and clear all combat state
        local currentZoneId = mq.TLO.Zone.ID()
        if currentZoneId ~= lastZoneId then
            lastZoneId = currentZoneId
            State:stopAssist()
            State:stopFollow()
            castService:clearQueue()
            cureService:reset()
            cureDecision:reset()
            context.raidSpawnIdCache = {}
            busService.actor:broadcast('reset_buffs_for_me', { sender = mq.TLO.Me.Name() })
        end

        -- Detect death and notify peers to reset their buff cooldowns for us
        local isDead = mq.TLO.Me.Dead() == true
        if isDead and not wasDead then
            busService.actor:broadcast('reset_buffs_for_me', { sender = mq.TLO.Me.Name() })
            State:clearCombatState()
            castService:clearQueue()
        end
        wasDead = isDead

        -- Stand up if force-feigned by a mob, unless this bot is the designated puller
        if mq.TLO.Me.Feigning() and not State.flags.isPuller then
            mq.cmd('/stand')
        end

        --order matters
        --Process network replies and resolve promises
        local ctx = context:build(State)
        RunTime.ctx = ctx
        if not ctx.dead then
            local action = engine:evaluate(ctx)
            if action then
                action:execute(ctx)
            end
        end
        busService:update()
        --resume any coroutines waiting on await
        scheduler:run()

        buffService:update(ctx)
        bufferController:update()
        tradeService:update()
        cureService:update()
        melodyService:tick(ctx)
        burnService:tick()

        -- Broadcast own status for the group status window
        local myStatus = {
            name       = ctx.myName,
            hp         = ctx.hp,
            mana       = ctx.mana,
            endurance  = ctx.endurance,
            target     = mq.TLO.Target.CleanName() or '',
            casting    = ctx.casting or '',
            dead       = ctx.dead == true,
            zone       = mq.TLO.Zone.ShortName() or '',
            class      = ctx.myClass or '',
        }
        statusService:update(myStatus)
        busService.actor:broadcast('char_status', myStatus)

        mq.delay(50)

        Logging.Debug("Main While loop End")
    end
end



mainLoop();
