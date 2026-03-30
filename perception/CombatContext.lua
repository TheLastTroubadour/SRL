local mq = require 'mq'
local RoleService = require 'service.RoleService'
local State = require 'core.State'
local Context = {}
Context.__index = Context

function Context:new(config)
    local self = setmetatable({}, Context)
    self.config = config

    -- Static per-session fields — queried once, reused every tick
    self.myName  = mq.TLO.Me.Name()
    self.myId    = mq.TLO.Me.ID()
    self.myClass = mq.TLO.Me.Class.ShortName()

    self.heal = {
        spells = config:get('Heals.Spells') or {},
        tanks = config:get('Heals.Tanks') or {},
        importantBots = config:get('Heals.ImportantBots') or {}
    }

    self.assistType       = config:get('AssistSettings.type') or 'off'
    self.stickPoint       = config:get('AssistSettings.meleeStickPoint') or 'behind'
    self.stickDistance    = config:get('AssistSettings.meleeStickDistance') or 10
    self:reloadSet('Main')
    return self
end

function Context:setStickPoint(point)
    self.stickPoint = point
end

function Context:setStickDist(dist)
    self.stickDistance = tonumber(dist) or self.stickDistance
end

function Context:reloadSet(set)
    local onAssist  = self.config:get('Debuff.DebuffOnAssist.' .. set) or {}
    local onCommand = self.config:get('Debuff.DebuffOnCommand.' .. set) or {}
    local onXTar    = self.config:get('Debuff.DebuffOnXTar.' .. set) or {}

    self.debuff = {
        onAssistSpells  = self:sortByPriority(#onAssist  > 0 and onAssist  or (self.config:get('Debuff.DebuffOnAssist.Main')  or {})),
        onCommandSpells = self:sortByPriority(#onCommand > 0 and onCommand or (self.config:get('Debuff.DebuffOnCommand.Main') or {})),
        enabledForXTar  = self.config:get('Debuff.DebuffTargetsOnXTarEnabled') or false,
        onXTarSpells    = self:sortByPriority(#onXTar    > 0 and onXTar    or (self.config:get('Debuff.DebuffOnXTar.Main')    or {})),
        minXTarTargets  = self.config:get('Debuff.MinimumAmountToStartDebuffOnXTar') or 2
    }

    local dotsOnAssist  = self.config:get('Dots.DotsOnAssist.' .. set) or {}
    local dotsOnCommand = self.config:get('Dots.DotsOnCommand.' .. set) or {}

    self.dot = {
        onAssistSpells  = self:sortByPriority(#dotsOnAssist  > 0 and dotsOnAssist  or (self.config:get('Dots.DotsOnAssist.Main')  or {})),
        onCommandSpells = self:sortByPriority(#dotsOnCommand > 0 and dotsOnCommand or (self.config:get('Dots.DotsOnCommand.Main') or {})),
    }
end

function Context:build(state)

    local ctx = {}
    ctx.assist = {}
    ctx.self = {}

    ctx.assist.assistType    = self.assistType
    ctx.assist.stickPoint    = self.stickPoint
    ctx.assist.stickDistance = self.stickDistance

    -- Static fields (never change per session)
    ctx.myName      = self.myName
    ctx.myId        = self.myId
    ctx.myClass     = self.myClass
    ctx.myCleanName = mq.TLO.Me.CleanName()

    ctx.self.Id = ctx.myId
    ctx.mana = mq.TLO.Me.PctMana()
    ctx.currentMana = mq.TLO.Me.CurrentMana()
    ctx.hp = mq.TLO.Me.PctHPs()
    ctx.endurance = mq.TLO.Me.PctEndurance()
    ctx.moving = mq.TLO.Me.Moving()
    ctx.casting  = mq.TLO.Me.Casting()
    ctx.sitting  = mq.TLO.Me.Sitting()
    ctx.stunned  = mq.TLO.Me.Stunned()
    ctx.silenced = mq.TLO.Me.Silenced()
    ctx.feared   = mq.TLO.Me.Feared()
    ctx.dead     = mq.TLO.Me.Dead()
    ctx.invis    = mq.TLO.Me.Invis()

    -- Per-tick fields computed once and shared
    ctx.aggro      = mq.TLO.Me.PctAggro() or 0
    ctx.activeDisc = mq.TLO.Me.ActiveDisc()

    ctx.isForeground = mq.TLO.EverQuest.Foreground()

    ctx.roles = RoleService:getRoles()
    ctx.addCount = nil

    ctx.myCurrentTargetId = mq.TLO.Target.ID()

    --Target of Current Target
    ctx.myCurrentTargetsTargetId = mq.TLO.Target.TargetOfTarget.ID()

    --target info
    ctx.assist.Id = State.assist.targetId

    if ctx.assist.Id then
        local spawn = mq.TLO.Spawn('id ' .. tostring(ctx.assist.Id))
        if spawn() and not spawn.Dead() then
            ctx.assist.distance = spawn.Distance()
            ctx.assist.HP = spawn.PctHPs()
            ctx.assist.lineOfSight = spawn.LineOfSight()
            ctx.assist.dead = false
        else
            State.assist.targetId = nil
            ctx.assist.HP = nil
            ctx.assist.distance = nil
            ctx.assist.Id = nil
            ctx.assist.dead = true
        end
    end

    -- Build XTarget list once; derive numberOfAggressive from it
    ctx.xtargets = {}
    local numberOfAggressive = 0
    local slots = mq.TLO.Me.XTargetSlots()
    for i = 1, slots do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() then
            local entry = {
                id         = xt.ID(),
                name       = xt.CleanName(),
                type       = xt.Type(),
                aggressive = xt.Aggressive(),
                dead       = xt.Dead(),
                hp         = xt.PctHPs(),
            }
            table.insert(ctx.xtargets, entry)
            if entry.type == 'NPC' and not entry.dead and entry.aggressive then
                numberOfAggressive = numberOfAggressive + 1
            end
        end
    end

    ctx.numberOfAggresiveInXTar = numberOfAggressive

    -- Group member list (self + live group members); used by Rez/Heal/Shrink/etc.
    ctx.groupMembers = {}
    table.insert(ctx.groupMembers, { id = ctx.myId, name = ctx.myName, hp = ctx.hp, dead = false })
    local gCount = mq.TLO.Group.Members()
    for i = 1, gCount do
        local m = mq.TLO.Group.Member(i)
        if m() and m.Spawn() and not m.Dead() then
            table.insert(ctx.groupMembers, { id = m.ID(), name = m.CleanName(), hp = m.PctHPs(), dead = false })
        end
    end

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

            local seen = {}

            -- Always include self as a heal target
            local myName = mq.TLO.Me.Name()
            seen[myName] = true
            table.insert(ctx.self.heal.group.memberStatus, {
                id   = mq.TLO.Me.ID(),
                name = myName,
                hp   = mq.TLO.Me.PctHPs(),
                role = self:getHealerRole(myName)
            })

            for i = 1, ctx.self.heal.group.members do
                local m = mq.TLO.Group.Member(i)

                if m() and m.Spawn() and not m.Dead() then
                    local name = m.CleanName()
                    if not seen[name] then
                        seen[name] = true
                        local role = self:getHealerRole(name)
                        table.insert(ctx.self.heal.group.memberStatus, {
                            id = m.ID(),
                            name = name,
                            hp = m.PctHPs(),
                            role = role
                        })
                    end
                end
            end

            -- Raid members
            local raidMembers = mq.TLO.Raid.Members() or 0
            for i = 1, raidMembers do
                local r = mq.TLO.Raid.Member(i)
                if r() and not r.Dead() then
                    local name = r.CleanName()
                    if name and not seen[name] then
                        local spawn = mq.TLO.Spawn('pc =' .. name)
                        if spawn() then
                            seen[name] = true
                            local role = self:getHealerRole(name)
                            table.insert(ctx.self.heal.group.memberStatus, {
                                id = spawn.ID(),
                                name = name,
                                hp = r.PctHPs(),
                                role = role
                            })
                        end
                    end
                end
            end

            -- XTarget friendly slots
            local xtSlots = mq.TLO.Me.XTargetSlots() or 0
            for i = 1, xtSlots do
                local xt = mq.TLO.Me.XTarget(i)
                if xt() and not xt.Dead() and xt.Type() ~= 'NPC' and not xt.Aggressive() then
                    local name = xt.CleanName()
                    if name and not seen[name] then
                        seen[name] = true
                        local role = self:getHealerRole(name)
                        table.insert(ctx.self.heal.group.memberStatus, {
                            id = xt.ID(),
                            name = name,
                            hp = xt.PctHPs(),
                            role = role
                        })
                    end
                end
            end
        end
    end

    if ctx.roles['debuff'] then
        ctx.self.debuff = {
            onAssistSpells  = self.debuff.onAssistSpells,
            onCommandSpells = self.debuff.onCommandSpells,
            enabledForXTar  = self.debuff.enabledForXTar,
            minXTarTargets  = self.debuff.minXTarTargets,
            xTarSpells      = self.debuff.onXTarSpells
        }
    end

    if ctx.roles['dot'] then
        ctx.self.dot = {
            onAssistSpells  = self.dot.onAssistSpells,
            onCommandSpells = self.dot.onCommandSpells,
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

function Context:sortByPriority(list)
    -- Preserve original order for ungrouped entries; sort by priority only within the same group
    for i, v in ipairs(list) do v._idx = i end
    table.sort(list, function(a, b)
        if a.group and b.group and a.group == b.group then
            return (a.priority or 99) < (b.priority or 99)
        end
        return a._idx < b._idx
    end)
    for _, v in ipairs(list) do v._idx = nil end
    return list
end

return Context