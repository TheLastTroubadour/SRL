local mq = require 'mq'
local Job = require 'srl.model.Job'
local TableUtil = require 'srl.util.TableUtil'
local HealDecision = {}

HealDecision.__index = HealDecision

local HEALER_ROLE = 'healer'

function HealDecision:new(config)
    local self = setmetatable({}, HealDecision)
    self.config = config
    self.name = "HealDecision"
    self.job = nil

    return self
end

function HealDecision:score(ctx)
    self.job = nil

    if ctx.casting then return 0 end

    if not ctx.roles[HEALER_ROLE] then
        return 0
    end

    local targets = ctx.self.heal.group.memberStatus

    if self:checkGroupHeal(targets) then
        return 110
    end

    -- Normal heal selection
    local bestTarget = self:selectBestTarget(targets)

    if bestTarget then
        local heal = self:selectHealSpell(bestTarget, ctx.self.heal.spells)
        if heal then
            local spell = mq.TLO.Spell(heal.spell)
            local spellManaCost = spell.Mana()
            if ctx.currentMana > spellManaCost and mq.TLO.Cast.Ready(heal.spell) then
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
        mq.cmdf('/target id %s', self.job.targetId)
        mq.delay(100)
    end

    mq.cmdf("/casting \"%s\"|%s", self.job.name, self.job.gem)
end

function HealDecision:checkGroupHeal(targets)

    if self.groupHealLock and mq.gettime() < self.groupHealLock then
        return false
    end

    local total = 0

    for _,t in ipairs(targets) do
        total = total + t.hp
    end

    local avg = total / #targets

    local threshold = self.config:get("Heals.GroupThreshold") or 65
    local spell = self.config:get("Heals.GroupSpell")

    if avg <= threshold and spell then

        self.job = Job:new(
                mq.TLO.Me.ID(),
                mq.TLO.Me.Name(),
                spell,
                "heal",
                480
        )

        self.groupHealLock = mq.gettime() + 5000

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

        if target.hp <= heal.threshold then

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
    end

    return best
end


return HealDecision