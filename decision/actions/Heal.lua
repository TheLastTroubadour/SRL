local mq = require 'mq'
local Job = require 'model.Job'
local TableUtil = require 'util.TableUtil'
local Target = require 'service.TargetService'
local HealDecision = {}

HealDecision.__index = HealDecision

local HEALER_ROLE = 'healer'

function HealDecision:new(config)
    local self = setmetatable({}, HealDecision)
    self.config = config
    self.name = "HealDecision"
    self.job = nil
    self.groupHealPending = false
    self.bus = nil

    return self
end

function HealDecision:setBus(bus)
    self.bus = bus
end

function HealDecision:suppressGroupHeal(ms)
    self.groupHealLock = mq.gettime() + ms
end

function HealDecision:score(ctx)
    self.job = nil
    self.groupHealPending = false

    if ctx.casting then return 0 end

    if not ctx.roles[HEALER_ROLE] then
        return 0
    end

    local targets = ctx.self.heal.group.memberStatus

    if self:checkGroupHeal(targets) then
        self.groupHealPending = true
        return 110
    end

    -- Normal heal selection
    local bestTarget = self:selectBestTarget(targets)

    if bestTarget then
        local heal = self:selectHealSpell(bestTarget, ctx.self.heal.spells)
        if heal then
            local spell = mq.TLO.Spell(heal.spell)
            local spellManaCost = spell.Mana() or 0
            if ctx.currentMana > spellManaCost and mq.TLO.Me.SpellReady(heal.spell)() then
                self.job = Job:new(
                        bestTarget.id,
                        bestTarget.name,
                        heal.spell,
                        "heal",
                        heal.priority,
                        heal.gem
                )
                return 105
            end
        end
    end

    return 0
end

function HealDecision:execute(ctx)
    if not self.job then return end

    if mq.TLO.Target.ID() ~= self.job.targetId then
        Target:getTargetById(self.job.targetId)
    end

    local gem = mq.TLO.Me.Gem(self.job.name)() or self.job.gem
    if not gem then return end
    mq.cmdf('/cast %s', gem)
    local suppressMs = 8000
    self.groupHealLock = mq.gettime() + suppressMs
    if self.groupHealPending and self.bus then
        self.bus.actor:broadcast('group_heal_cast', {
            casterName = mq.TLO.Me.Name(),
            suppressMs = tostring(suppressMs),
        })
    end
end

function HealDecision:checkGroupHeal(targets)

    if self.groupHealLock and mq.gettime() < self.groupHealLock then
        return false
    end

    local groupSpell   = self.config:get("Heals.GroupSpell")
    local threshold    = (groupSpell and groupSpell.threshold) or self.config:get("Heals.GroupThreshold")    or 65
    local minInjured   = (groupSpell and groupSpell.minInjured) or self.config:get("Heals.GroupHealMinInjured") or 4
    local groupOnlyCfg = self.config:get("Heals.GroupHealGroupOnly")
    local groupOnly    = groupOnlyCfg == nil or groupOnlyCfg == true

    if not (groupSpell and groupSpell.spell) then return false end

    local aeRange        = mq.TLO.Spell(groupSpell.spell).AERange() or 100
    local injuredInRange = 0

    if groupOnly then
        -- Only count EQ group members + self as injured
        if (mq.TLO.Me.PctHPs() or 100) <= threshold then
            injuredInRange = injuredInRange + 1
        end
        local gCount = mq.TLO.Group.Members() or 0
        for i = 1, gCount do
            local m = mq.TLO.Group.Member(i)
            if m() then
                local hp  = m.PctHPs()
                local dist = m.Distance() or 999
                if hp and hp <= threshold and dist <= aeRange then
                    injuredInRange = injuredInRange + 1
                end
            end
        end
    else
        for _, t in ipairs(targets) do
            if t.hp and t.hp <= threshold then
                local spawn = mq.TLO.Spawn('id ' .. tostring(t.id))
                if spawn() and (spawn.Distance() or 999) <= aeRange then
                    injuredInRange = injuredInRange + 1
                end
            end
        end
    end

    if injuredInRange >= minInjured then
        self.job = Job:new(
                mq.TLO.Me.ID(),
                mq.TLO.Me.Name(),
                groupSpell.spell,
                "heal",
                480,
                groupSpell.gem
        )
        return true
    end

end

function HealDecision:collectTargets(ctx)

    local targets = {}

    for i = 1, mq.TLO.Group.Members() do

        local m = mq.TLO.Group.Member(i)

        if m() and m.Spawn() then
            local role = ctx:getHealerRole(m.CleanName())
            table.insert(targets,{
                id = m.ID(),
                name = m.CleanName(),
                hp = m.PctHPs(),
                role = role
            })
        end

    end

    return targets
end

function HealDecision:getRole(name)
    for _,t in ipairs(self.tanks) do
        if t == name then
            return "tank"
        end
    end

    for _,b in ipairs(self.importantBots) do
        if b == name then
            return "important"
        end
    end
    return "normal"
end

function HealDecision:selectHealSpell(target, healSpells)

    local spells = healSpells[target.role]

    if not spells then
        spells = healSpells["normal"]
    end

    if not spells then return nil end

    local chosen = nil

    for _,heal in ipairs(spells) do

        if target.hp and target.hp <= heal.threshold then

            if not chosen or heal.threshold < chosen.threshold then
                chosen = heal
            end

        end

    end

    return chosen
end

function HealDecision:selectBestTarget(targets)

    local best = nil
    local bestScore = 0

    for _,t in ipairs(targets) do

            if not t.hp then goto continue end

            local weight = 1

            if t.role == "tank" then
                weight = 2
            elseif t.role == "important" then
                weight = 1.5
            end

            local score = (100 - t.hp) * weight

            if score > bestScore then
                bestScore = score
                best = t
                best.priority = 450
            end
            ::continue::
    end

    return best
end


return HealDecision