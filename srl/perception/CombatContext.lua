local mq = require 'mq'
local RoleService = require 'srl.service.RoleService'
local State = require 'srl.core.State'
local Context = {}
Context.__index = Context

function Context:new(config)
    local self = setmetatable({}, Context)
    self.config = config

    self.heal = {
        spells = config:get('Heals.Spells') or {},
        tanks = config:get('Heals.Tanks') or {},
        importantBots = config:get('Heals.ImportantBots') or {}
    }

    self.debuff = {
        onAssistSpells = config:get('Debuff.DebuffOnAssist.Main') or {},
        onCommandSpells = config:get('Debuff.DebuffOnCommand.Main') or {},
        enabledForXTar = config:get('Debuff.DebuffTargetsOnXTarEnabled') or false,
        onXTarSpells = config:get('Debuff.DebuffOnXTar.Main') or {},
        minXTarTargets = config:get('Debuff.MinimumAmountToStartDebuffOnXTar') or 2
    }

    self.assistType = config:get('AssistSettings.type') or 'off'
    return self
end

function Context:build(state)

    local ctx = {}
    ctx.assist = {}
    ctx.self = {}

    ctx.assist.assistType = self.assistType

    ctx.self.Id = mq.TLO.Me.ID()
    ctx.mana = mq.TLO.Me.PctMana()
    ctx.currentMana = mq.TLO.Me.CurrentMana()
    ctx.hp = mq.TLO.Me.PctHPs()
    ctx.endurance = mq.TLO.Me.PctEndurance()
    ctx.moving = mq.TLO.Me.Moving()
    ctx.casting = mq.TLO.Me.Casting()
    ctx.sitting = mq.TLO.Me.Sitting()

    ctx.isForeground = mq.TLO.EverQuest.Foreground()

    ctx.roles = RoleService:getRoles()
    ctx.addCount = nil

    ctx.myCurrentTargetId = mq.TLO.Target.ID()

    --Target of Current Target
    ctx.myCurrentTargetsTargetId = mq.TLO.Target.TargetOfTarget.ID()

    --target info
    ctx.assist.Id = State.assist.targetId

    if ctx.assist.Id then
        local spawn = mq.TLO.Spawn(ctx.assist.Id)
        if spawn() and not spawn.Dead() then
            ctx.assist.distance = spawn.Distance()
            ctx.assist.HP = spawn.PctHPs()
            ctx.assist.dead = false
        else
            State.assist.targetId = nil
            ctx.assist.HP = nil
            ctx.assist.distance = nil
            ctx.assist.id = nil
            ctx.assist.dead = true
        end
    end
    local numberOfAggressive = 0
    local slots = mq.TLO.Me.XTargetSlots()
    for i = 1, slots do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and xt.Type() == "NPC" and not xt.Dead() and xt.Aggressive() then
            numberOfAggressive = numberOfAggressive + 1
        end
    end

    ctx.numberOfAggresiveInXTar = numberOfAggressive

    ctx.inCombat = mq.TLO.Me.Combat()

    --healing
    if ctx.roles['healer'] then
        ctx.self.heal = {}
        ctx.self.heal.group = {}
        ctx.self.heal.group.memberStatus = {}
        if next(self.heal.spells) then
            for _,roleSpells in pairs(self.heal.spells) do
                table.sort(roleSpells,function(a,b)
                    return a.threshold < b.threshold
                end)
            end
            ctx.self.heal.spells = self.heal.spells
            ctx.self.heal.group.members = mq.TLO.Group.Members()

            for i = 1, ctx.self.heal.group.members do
                local m = mq.TLO.Group.Member(i)

                if m() and m.Spawn() then
                    local role = self:getHealerRole(m.CleanName())
                    table.insert(ctx.self.heal.group.memberStatus, {
                        id = m.ID(),
                        name = m.CleanName(),
                        hp = m.PctHPs(),
                        role = role
                    })
                end
            end
        end
    end

    if ctx.roles['debuff'] then
        ctx.self.debuff = {
            onAssistSpells =  self.debuff.onAssistSpells,
            onCommandSpells = self.debuff.onCommandSpells ,
            enabledForXTar =  self.debuff.enabledForXTar,
            minXTarTargets =  self.debuff.minXTarTargets,
            xTarSpells = self.debuff.onXTarSpells
        }

    end

    return ctx
end

function Context:getHealerRole(name)
    for _,t in ipairs(self.heal.tanks) do
        if t == name then
            return "tank"
        end
    end

    for _,b in ipairs(self.heal.importantBots) do
        if b == name then
            return "important"
        end
    end

    return "normal"
end

return Context