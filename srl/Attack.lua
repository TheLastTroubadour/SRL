-- All things attack related
local CastUtil = require 'srl/util/CastUtil'

local attack_export = {}

local function assist_event(line, chatSender, targetId)
    local spawnName = "pc =" .. tostring(chatSender)
    local chatSenderId = mq.TLO.Spawn(spawnName).ID()
    local me = mq.TLO.Me
    ASSISTING = true
    if(me.ID() == chatSenderId) then
        --don't do anything if person that issued it
        return
    else
        Movement.call_stop()
        Target.get_target_by_id(targetId)
        CURRENT_ASSIST_ID = targetId
        --need to export to ini var
        --only if melee setting is true
        if(ASSIST_TYPE == 'Melee') then
            local stickDistance = 10;
            if(MELEE_STICK_POINT == 'MaxMelee') then
                stickDistance = mq.TLO.Spawn(targetId).MaxRangeTo() * .75
            end
            mq.cmdf("/stick %s", stickDistance)
            mq.cmd("/attack on")
        end
        if(ASSIST_TYPE == 'Ranged') then
            --TODO
        end
    end
end

local function checkIfAbilityReady(abilityName)
    Logging.Debug("Checking if Ability Ready " .. abilityName .. ' for ' .. mq.TLO.Me.CleanName())
    if(mq.TLO.Me.AbilityReady(abilityName)) then
        return true
    end
    return false
end

local function check_abilities()
    Logging.Debug("Attack.check_abilities Start")

    if(MELEE_ABILITIES_2D == nil) then return end
    Logging.Debug("Current Count " .. tostring(#MELEE_ABILITIES_2D))
    for k, v in ipairs(MELEE_ABILITIES_2D) do
        Logging.Debug("Key is " .. tostring(k) .. " Value is " .. tostring(v))
        if(v == 'Bash' and v ~= mq.TLO.InvSlot('offhand').Item.Type()) then
            --go to next iteration
            Logging.Trace('Breaking out of Loop early for check_abilities')
            do break end
        end
        local isAbilityReady = checkIfAbilityReady(v)
        if(isAbilityReady) then
            mq.cmdf('/doability %s', v)
        end
    end
    Logging.Debug("Attack.check_abilities End")
end



local function check_nukes()

    Logging.Debug("Attack.check_nukes Start")

    if(NUKES_2D["Main"] == nil or #NUKES_2D["Main"] == 0) then return end

    --Put to var "Main spell set"
    --different nuke sets

    local currentSpellSet = NUKES_2D["Main"]
    for k,v in ipairs(currentSpellSet) do
        local splits = StringUtil.split(tostring(v), "/")
        local spellName = tostring(splits[1])
        local gem = tostring(splits[2]):gsub("|", "")
        CastUtil.srl_cast(spellName, gem, CURRENT_ASSIST_ID)
    end
    Logging.Debug("Attack.check_nukes End")
end

function attack_export.check_assist()
    Logging.Debug("Attack.check_assist Start")

    --check spawn if dead then reset global vars?
    if(mq.TLO.Spawn(CURRENT_ASSIST_ID).Type() == 'Corpse') then
        ASSISTING = false
    end

    if(ASSISTING == true) then
        check_abilities()
        --check abilities
        check_nukes()
        --check nukes
    end
    Logging.Debug("Attack.check_assist End")
end

function attack_export.registerEvents()
    mq.event('attack1', '[#1#] Assist on #2#', assist_event);
    mq.event('attack2', '<#1#> Assist on #2#', assist_event);
end

return attack_export