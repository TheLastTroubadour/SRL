local mq = require('mq')
local Job = require('srl.model.Job')

local HealService = {}
HealService.__index = HealService

function HealService:new(castService, config)

    local self = setmetatable({}, HealService)

    self.castService = castService
    self.config = config

    self.healLocks = {}
    self.groupHealLock = 0

    self.healSpells = config:get("Heals.Spells") or {}

    self.tanks = config:get("Heals.Tanks") or {}
    self.importantBots = config:get("Heals.ImportantBots") or {}

    if(#self.healSpells > 0) then
        for _,roleSpells in pairs(self.healSpells) do
            table.sort(roleSpells,function(a,b)
                return a.threshold < b.threshold
            end)
        end
    end

    return self
end

function HealService:collectTargets()

    local targets = {}

    for i = 1, mq.TLO.Group.Members() do

        local m = mq.TLO.Group.Member(i)

        if m() then
            local role = self:getRole(m.CleanName())

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

function HealService:update()

    local now = mq.gettime()

    local targets = self:collectTargets()

    if #targets == 0 then return end

    -- Emergency heal
    local emergency = self:checkEmergency(targets)
    if emergency then
        self:enqueueHeal(emergency, 500)
        return
    end

    -- Group heal
    if self:checkGroupHeal(targets, now) then
        return
    end

    -- Normal heal selection
    local best = self:selectBestTarget(targets)

    if best then
        self:enqueueHeal(best, best.priority)
    end

end

function HealService:enqueueHeal(target)

    local heal = self:selectHealSpell(target)

    if not heal then return end

    local job = Job:new(
            target.id,
            target.name,
            heal.spell,
            "heal",
            heal.priority,
            heal.gem
    )

    if not self.castService:isQueued(job) then
        self.castService:enqueue(job)
        self.healLocks[target.id] = mq.gettime() + 2500
    end

end



function HealService:getRole(name)

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

function HealService:checkEmergency(targets)

    for _,t in ipairs(targets) do

        if t.hp <= 15 and not self:healLocked(t.id) then
            return t
        end

    end

end

function HealService:checkGroupHeal(targets, now)

    if now < self.groupHealLock then
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

        local job = Job:new(
                mq.TLO.Me.ID(),
                mq.TLO.Me.Name(),
                spell,
                "heal",
                480
        )

        self.castService:enqueue(job)

        self.groupHealLock = now + 5000

        return true
    end

end

function HealService:selectHealSpell(target)

    local spells = self.healSpells[target.role]

    if not spells then
        spells = self.healSpells["normal"]
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

function HealService:selectBestTarget(targets)

    local best = nil
    local bestScore = 0

    for _,t in ipairs(targets) do

        if not self:healLocked(t.id) then

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

    end

    return best
end

function HealService:healLocked(targetId)

    local now = mq.gettime()

    if self.healLocks[targetId] and now < self.healLocks[targetId] then
        return true
    end

    return false
end

function HealService:selectHealSpell(target)

    local spells = self.healSpells[target.role]

    if not spells then
        spells = self.healSpells["normal"]
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

return HealService