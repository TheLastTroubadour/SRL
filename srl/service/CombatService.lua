local mq = require 'mq'
local CombatService = {}
local State = require 'srl.core.State'
local Job = require 'srl.model.Job'
CombatService.__index = CombatService

function CombatService:new(castService, config)
    local self = setmetatable({}, CombatService)

    self.castService = castService
    self.config = config
    self.rotation =
    {
        spellRotation = self:getNukesFromKey('Nukes.Main'),
        abilityRotation = self:getAbilitiesFromKey('Abilities')
    }

    return self
end

function CombatService:getAbilitiesFromKey(key)
    local values = self.config:Get(key)
    local jobList = {}
    if values then
        for _, v in ipairs(values) do
            local abilityName = v.ability
            local job = Job:new(nil, nil, abilityName, 'ability', 50, nil)
            table.insert(jobList, job)
        end

    end

    return jobList
end

function CombatService:getNukesFromKey(key)
    local values = self.config:Get(key)
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
    mq.cmd('/face')
    mq.delay(100)
    mq.cmdf('/stick behind loose')
    mq.delay(50)
    mq.cmd('/attack on')
end

function CombatService:update()

    if mq.TLO.Me.Casting() then return end
    if not mq.TLO.Target() then return end
    if mq.TLO.Target.Type() ~= "NPC" then return end
    if mq.TLO.Target.Dead() then return
        --If was following someone resume follow?
        --Next Target or Wait for Call
    end

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
    --restick?

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

return CombatService