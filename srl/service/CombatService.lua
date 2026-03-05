local mq = require 'mq'
local CombatService = {}
local State = require 'srl.core.State'
local Job = require 'srl.model.Job'
local TableUtil = require 'srl.util.TableUtil'
CombatService.__index = CombatService

function CombatService:new(castService, config, commandBus)
    local self = setmetatable({}, CombatService)

    self.castService = castService
    self.config = config
    self.commandBus = commandBus
    self.rotation =
    {
        spellRotation = self:getNukesFromKey('Nukes.Main'),
        abilityRotation = self:getAbilitiesFromKey('Abilities')
    }

    return self
end

function CombatService:getSpellRotation()
    return self.rotation.spellRotation
end

function CombatService:getAbilityRotation()
    return self.rotation.abilityRotation
end



function CombatService:getAbilitiesFromKey(key)
    local values = self.config:get(key)
    local jobList = {}
    if values then
        for _, v in ipairs(values) do
            local abilityName = v.Ability
            local job = Job:new(nil, nil, tostring(abilityName), 'ability', 50, nil)
            table.insert(jobList, job)
        end

    end

    return jobList
end

function CombatService:getNukesFromKey(key)
    local values = self.config:get(key)
    local jobList = {}
    if values then
        for _, v in ipairs(values) do
            local spellName = v.spell
            local gem = v.gem or 8

            local job = Job:new(nil, nil, spellName, 'spell', 50, gem)
            table.insert(jobList, job)
        end
    end

    return jobList
end

function CombatService:isInCombat()
    return mq.TLO.Me.Combat()
end

function CombatService:assist()

    local targetId = State.assist.targetID

    if not State.assist.targetID then return end

    if State.assist.targetID ~= mq.TLO.Target.ID() then

        print("New assist target:", targetId)

        -- Clear any queued combat jobs
        self.castService:clearCombatQueue()
    end

    if(State.assist.sender == mq.TLO.Me.Name()) then
        return
    end

    mq.cmdf('/target id %s', targetId)
    mq.delay(150)
    mq.cmdf('/stick behind 10 moveback uw')
    mq.delay(50)
    mq.cmd('/attack on')
end

function CombatService:update()

    local hasAggro = self:hasHostileXTarget()

    if hasAggro then
        for _, entry in ipairs(self.rotation.spellRotation) do
            if self:canUse(entry) then
                entry.targetId = mq.TLO.Target.ID()
                entry.generation = State.assist.generation
                self.castService:enqueue(entry)
                return
            end
        end
        for _, entry in ipairs(self.rotation.abilityRotation) do
            if self:canUse(entry) then
                entry.targetId = mq.TLO.Target.ID()
                entry.generation = State.assist.generation
                self.castService:enqueue(entry)
                return
            end
        end
        State:updateCombatState(true)
        return
    end

    if(State.combat.combatState) then
        State:updateCombatState(false)
        self.commandBus:dispatch("COMBAT_ENDED")
    end
end

function CombatService:shouldEngage()
    local target = mq.TLO.Target
    if not target() then return false end

    if target.Type() ~= "NPC" then return false end
    if target.Dead() then return false end

    -- already fighting
    if mq.TLO.Me.Combat() then
        return true
    end

    -- mob attacking us
    if target.Target.ID() == mq.TLO.Me.ID() then
        return true
    end

    -- mob attacking group member
    if mq.TLO.Me.GroupSize() > 0 then
        for i = 1, mq.TLO.Me.GroupSize() do
            local member = mq.TLO.Group.Member(i)
            if member() and target.Target.ID() == member.ID() then
                return true
            end
        end
    end

    if mq.TLO.Target.Distance() > 200 then
        return false
    end

    if mq.TLO.Target.PctAggro() > 0 then
        return true
    end

    return false
end

function CombatService:canUse(entry)
    if not entry or not entry.name then return false end

    -- Don't queue if already casting
    if mq.TLO.Me.Casting() then return false end

    -- Prevent queue flooding
    if self.castService:isQueued(entry.name) then return false end

    if entry.type == "spell" then
        local spell = mq.TLO.Spell(entry.name)
        if not spell() then return false end

        -- Mana check
        if mq.TLO.Me.CurrentMana() < spell.Mana() then return false end

        -- Spell ready
        if not mq.TLO.Me.SpellReady(entry.name)() then return false end

        -- Global cooldown safety
        if mq.TLO.Me.GemTimer(entry.gem)() > 0 then return false end

        return true
    end

    if entry.type == "ability" then
        if not mq.TLO.Me.AbilityReady(entry.name)() then return false end
        return true
    end

    return false
end

function CombatService:hasHostileXTarget()
    local slots = mq.TLO.Me.XTargetSlots()

    for i = 1, slots do
        local xt = mq.TLO.Me.XTarget(i)

        if xt() and xt.Type() == "NPC" and not xt.Dead() then
            return true
        end
    end
    return false
end

return CombatService