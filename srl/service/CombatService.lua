local mq = require 'mq'
local CombatService = {}
local State = require 'srl.core.State'
local Job = require 'srl.model.Job'
local TableUtil = require 'srl.util.TableUtil'
local TargetService = require 'srl.service.TargetService'
CombatService.__index = CombatService

local IDLE_DELAY = 5000

function CombatService:new(castService, config, commandBus, roleService, debuffService)
    local self = setmetatable({}, CombatService)

    self.castService = castService
    self.debuffService = debuffService
    self.config = config
    self.commandBus = commandBus
    self.tryingToMed = false
    self.roleService = roleService
    self.rotation =
    {
        spellRotation = self:getNukesFromKey('Nukes.Main'),
        abilityRotation = self:getAbilitiesFromKey('Abilities')
    }

    return self
end

local function isIdle(lastActivity, idleDelay)
    return (mq.gettime() - lastActivity) > idleDelay
end

function CombatService:getSpellRotation()
    return self.rotation.spellRotation
end

function CombatService:getAbilityRotation()
    return self.rotation.abilityRotation
end

function CombatService:handleMed()

    if mq.TLO.Me.Casting() or mq.TLO.Me.Moving() then
        return
    end

    if mq.TLO.Me.Dead() then return end


    local roles = self.roleService:getRoles()
    if not roles.caster and not roles.healer then
        return
    end

    local mana = mq.TLO.Me.PctMana()
    local medStart = self.config:get('General.medStart') or 10
    local medEnd = self.config:get('General.medStop') or 100

    -- never med during combat
    if State.assist.targetID then
        if mq.TLO.Me.Sitting() then
            mq.cmd("/stand")
        end
        return
    end

    -- enter med mode
    if not State.caster.medMode and mana < medStart then
        State:setMedMode(true)
    end

    -- exit med mode
    if State.caster.medMode and mana >= medEnd then
        State:setMedMode(false)
        if mq.TLO.Me.Sitting() then
            mq.cmd("/stand")
        end
        return
    end

    -- if moving, pause med posture
    if mq.TLO.Me.Moving() then
        State:updateLastActivity()
        if mq.TLO.Me.Sitting() then
            mq.cmd("/stand")
        end
        return
    end

    -- stay sitting while medding
    if State.caster.medMode then
        if not mq.TLO.Me.Sitting() and not mq.TLO.Me.Casting() and not mq.TLO.Me.Moving() then
            if isIdle(State.lastActivity, IDLE_DELAY) then
                mq.cmd("/sit")
            end
        end
    end

    --if idle feel free to sit even if not medding
    if (isIdle(State.lastActivity, IDLE_DELAY) and mana < 100) then
        if not mq.TLO.Me.Sitting() then
            mq.cmd("/sit")
        end
    end
end

function CombatService:getAbilitiesFromKey(key)
    local values = self.config:get(key)
    local jobList = {}
    if values then
        for _, v in ipairs(values) do
            local abilityName = v.Ability
            local type = v.type or 'ability'
            local job = Job:new(nil, nil, tostring(abilityName), type, 50, nil)
            if v.debuff then
                job.abilityHasDebuff = true
            end
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
            local job = Job:new(nil, nil, spellName, 'nuke', 50, gem)
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

    local assistType = self.config:get('AssistSettings.type') or 'Off'

    if assistType and assistType:lower() == 'off' then
        return
    end

    if not State.assist.targetID then return end

    if not mq.TLO.Spawn('id ' .. State.assist.targetID)() then
        State:stopAssist()
        return
    end

    if State.assist.targetID ~= mq.TLO.Target.ID() then
        print("New assist target:", targetId)

        -- Clear any queued combat jobs
        self.castService:clearCombatQueue()
    end

    State:updateLastActivity()

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

    if not State.assist.targetID then
        self:handleMed()
        return
    end

    local hasAggro = self:hasHostileXTarget()
    if hasAggro then
        self.debuffService:update()
        for _, entry in ipairs(self.rotation.spellRotation) do
            entry:setTargetId(State.assist.targetID)
            if self:canUse(entry) then
                self.castService:enqueue(entry)
            end
        end
        for _, entry in ipairs(self.rotation.abilityRotation) do
            entry:setTargetId(State.assist.targetID)
            if self:canUse(entry) then
                self.castService:enqueue(entry)
            end
        end
        State:updateCombatState(true)
        return
    end

    if(State.combat.combatState) then
        self.commandBus:dispatch("COMBAT_ENDED")
    end
end

function CombatService:shouldEngage()
    local target = mq.TLO.Target
    if not target() then return false end

    if target.Type() ~= "NPC" then return false end
    if target.Dead() then
        if target.ID() == State.assist.targetID then
            State.assist.targetID = nil
        end
    return false end

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

    -- Prevent queue flooding
    if self.castService:isQueued(entry.key) then return false end

    if entry.type == "nuke" then
        local spell = mq.TLO.Spell(entry.name)
        if not spell() then return false end
        return true
    end

    if entry.abilityHasDebuff then
        if mq.TLO.Target.ID() ~= entry.targetId then
            TargetService:getTargetById(entry.targetId)
        end
        if not mq.TLO.Target.Buff(entry.name)() then
            return true
        end
        return false
    end

    if entry.type == 'ability' and mq.TLO.Me.AbilityReady(entry.name)() then
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