local mq = require 'mq'
local Logging = require 'srl/core/Write'
local TableUtil = require 'srl/util/TableUtil'

--Swap Item
local SWAP_ITEM_SECTION_KEY = 'Swap_Items'
local MAIN_KEY = 'Main'
--Use Item
local USE_ITEM_SECTION_KEY = 'USE_ITEMS'

local inihelper_export = {}

--General
inihelper_export.SPELL_GENERAL_KEY = "Main"
--Buffs
inihelper_export.BUFF_SECTION_KEY = 'Buffs';
inihelper_export.INSTANT_BUFF_KEY = 'Instant_Buff';
inihelper_export.SELF_BUFF_KEY = 'Self_Buff';
inihelper_export.BOT_BUFF_KEY = 'Bot_Buff';
inihelper_export.COMBAT_BUFF_KEY = 'Combat_Buff';
--Assist Settings
inihelper_export.ASSIST_SECTION_KEY = "Assist Settings"
inihelper_export.ASSIST_TYPE_KEY = "Assist Type (Melee/Ranged/Off)"
inihelper_export.MELEE_STICK_POINT_KEY= "Melee Stick Point"
inihelper_export.DEFAULT_MELEE_STICK_POINT_VALUE = "Behind"
inihelper_export.MELEE_DISTANCE_KEY= "Melee Distance"
inihelper_export.DEFAULT_MELEE_DISTANCE_VALUE = "MaxMelee"
inihelper_export.ASSIST_TYPE_KEY = "Assist Type (Melee/Ranged/Off)"
inihelper_export.DEFAULT_ASSIST_TYPE = "Melee"
inihelper_export.RANGED_DISTANCE_KEY = "Ranged Distance"
inihelper_export.DEFAULT_RANGED_DISTANCE_VALUE = "100"
inihelper_export.AUTO_ASSIST_KEY = "Auto Assist Enrage Percent"
inihelper_export.DEFAULT_AUTO_ASSIST_VALUE = "98"
--Melee Ability
inihelper_export.MELEE_ABILITIES_SECTION = 'Melee_Abilities'
inihelper_export.MELEE_ABILITY_KEY = 'Ability'
--Nukes
inihelper_export.NUKES_SECTION = "Nukes"
--Buffs
--Healing
inihelper_export.HEALING_SECTION ='Heals'
inihelper_export.TANK_KEY = 'Tank'
inihelper_export.IMPORTANT_BOT_KEY='Important Bot'
inihelper_export.TANK_HEAL_KEY='Tank Heal'
inihelper_export.IMPORTANT_HEAL_KEY = 'Important Heal'


local function writeToIni(location, section, key, keyvalue)
    mq.cmdf("/ini \"%s\" \"%s\" \"%s\" \"%s\"", location, section, key, keyvalue)
end


function inihelper_export.createBotIni()
    local doesIniExist = mq.TLO.Ini.File(botIniLocation).Exists();
    if (doesIniExist == false) then
        --fileNumber, keyname, valuename, value
        --Item swap
        writeToIni(botIniLocation, SWAP_ITEM_SECTION_KEY, MAIN_KEY, "")
        --Items
        writeToIni(botIniLocation, USE_ITEM_SECTION_KEY, ';Shrink', "Bracelet of the Shadow Hive")

        --Buffs
        writeToIni(botIniLocation, inihelper_export.BUFF_SECTION_KEY, inihelper_export.INSTANT_BUFF_KEY, "")
        writeToIni(botIniLocation, inihelper_export.BUFF_SECTION_KEY, inihelper_export.SELF_BUFF_KEY, "")
        writeToIni(botIniLocation, inihelper_export.BUFF_SECTION_KEY, inihelper_export.BOT_BUFF_KEY, "")
        writeToIni(botIniLocation, inihelper_export.BUFF_SECTION_KEY, inihelper_export.COMBAT_BUFF_KEY, "")
        --Cures
        --Pets
        --Life Support
        --Heals
        --Assist Settings
        --Depending on class we can change the assist type
        writeToIni(botIniLocation, inihelper_export.ASSIST_SECTION_KEY, inihelper_export.ASSIST_TYPE_KEY, inihelper_export.DEFAULT_ASSIST_TYPE)
        writeToIni(botIniLocation, inihelper_export.ASSIST_SECTION_KEY, inihelper_export.MELEE_STICK_POINT_KEY, inihelper_export.DEFAULT_MELEE_STICK_POINT_VALUE)
        writeToIni(botIniLocation, inihelper_export.ASSIST_SECTION_KEY, inihelper_export.MELEE_DISTANCE_KEY, inihelper_export.DEFAULT_MELEE_STICK_POINT_VALUE)
        writeToIni(botIniLocation, inihelper_export.ASSIST_SECTION_KEY, inihelper_export.RANGED_DISTANCE_KEY, inihelper_export.DEFAULT_RANGED_DISTANCE_VALUE)
        writeToIni(botIniLocation, inihelper_export.ASSIST_SECTION_KEY, inihelper_export.AUTO_ASSIST_KEY, inihelper_export.DEFAULT_AUTO_ASSIST_VALUE)
        --Melee Abilities
        writeToIni(botIniLocation, inihelper_export.MELEE_ABILITIES_SECTION, inihelper_export.MELEE_ABILITY_KEY, "")
        --Nukes
        writeToIni(botIniLocation, inihelper_export.NUKES_SECTION, inihelper_export.SPELL_GENERAL_KEY, "")
        --Dots on Assist
        --Dots on Command
        --Debuff on Assist
        --Debuff on Command
        --TargetAE
        --PB
        --BURN
        --Class
        --Misc
    end
end

function inihelper_export.readSection(section)
    Logging.Debug("BaseIni.readSection Start")
    local keys = {}
    local keyCount = mq.TLO.Ini.File(botIniLocation).Section(section).Key.Count()
    for i=1, keyCount do
        local spellSet = mq.TLO.Ini.File(botIniLocation).Section(section).Key.KeyAtIndex(i)()
        --add them to data structure but do not dup keys
        Logging.Debug(" Key ---" .. spellSet)
        local values = inihelper_export.readKey(section, spellSet);
        Logging.Debug("Values from " .. spellSet)
        Logging.Debug(TableUtil.table_print(values))

        keys[spellSet] = values
    end
    return keys
end

function inihelper_export.readKey(section, key)
    Logging.Debug("BaseIni.readKey Start")
    local keysToArray = {}
    local count = mq.TLO.Ini.File(botIniLocation).Section(section).Key(key).Count()
    --Make sure they have it before loading it?
    for i=1,count do
        local abilityName = mq.TLO.Ini.File(botIniLocation).Section(section).Key(key).ValueAtIndex(i)();
        if(abilityName ~= '' and abilityName~= nil) then
            Logging.Debug("Inserting -------" .. abilityName.. "------ At position " .. i)
            table.insert(keysToArray, abilityName)
        end
    end
    Logging.Debug("BaseIni.readKey End")
    return keysToArray
end

--Will always return the latest value if there are duplicates should only be used for unique section/keys
function inihelper_export.returnValueFromSectionAndKey(section, key)
    Logging.Debug("BaseIni.returnValueFromSectionAndKey Start")
    local ret = ""
    local count = mq.TLO.Ini.File(botIniLocation).Section(section).Key(key).Count()
    for i=1,count do
        local keyValue = mq.TLO.Ini.File(botIniLocation).Section(section).Key(key).ValueAtIndex(i);
        ret = tostring(keyValue)
    end
    Logging.Debug("BaseIni.returnValueFromSectionAndKey End")
    return ret
end

return inihelper_export