local mq = require 'mq'
local heal = require 'srl/Heal'
local attack = require 'srl/Attack'
local iBasic = require 'srl/Basic'
local Logging = require 'Write'
local iniHelper = require 'srl/ini/BaseIni'
local tableUtil = require 'srl/util/tableUtil'
local movement = require 'srl/Movement'
local bus = require 'srl/actors/Bus'
local bufferController = require 'srl/actors/BufferController'
local responder = require 'srl/actors/BufferResponder'

local setup_export = {}

local function initializeGlobalVars()
    ASSISTING = false
    FOLLOWING = false
    FOLLOW_TARGET_ID = nil
    CURRENT_ASSIST_ID = nil
    --Anything Ini driven needs to move to database eventually
    MELEE_ABILITIES_2D = {}
    NUKES_2D = {}
    HEALING_2D = {}
    BUFFS_2D = {}
    --ini driven
    ASSIST_TYPE = iniHelper.returnValueFromSectionAndKey(iniHelper.ASSIST_SECTION_KEY, iniHelper.ASSIST_TYPE_KEY)
    MELEE_STICK_POINT = iniHelper.DEFAULT_MELEE_STICK_POINT_VALUE
    MELEE_DISTANCE = iniHelper.returnValueFromSectionAndKey(iniHelper.ASSIST_SECTION_KEY, iniHelper.MELEE_DISTANCE_KEY)
    RANGED_DISTANCE = iniHelper.returnValueFromSectionAndKey(iniHelper.ASSIST_SECTION_KEY, iniHelper.RANGED_DISTANCE_KEY)


    BUS = bus:new(mq.TLO.Me.Name())
    CONTROLLER = bufferController:new(BUS)
end

local function getBuffInformationFromIni()
    Logging.Debug("Setup.getBuffInformationFromIni Start")

    local instantBuffValues = iniHelper.readKey(iniHelper.BUFF_SECTION_KEY, iniHelper.INSTANT_BUFF_KEY)
    local selfBuffValues = iniHelper.readKey(iniHelper.BUFF_SECTION_KEY, iniHelper.SELF_BUFF_KEY)
    local botBuffValues = iniHelper.readKey(iniHelper.BUFF_SECTION_KEY, iniHelper.BOT_BUFF_KEY)
    local combatBuffValues = iniHelper.readKey(iniHelper.BUFF_SECTION_KEY, iniHelper.COMBAT_BUFF_KEY)

    BUFFS_2D[iniHelper.INSTANT_BUFF_KEY] = instantBuffValues;
    BUFFS_2D[iniHelper.SELF_BUFF_KEY] = selfBuffValues;
    BUFFS_2D[iniHelper.BOT_BUFF_KEY] = botBuffValues;
    BUFFS_2D[iniHelper.COMBAT_BUFF_KEY] = combatBuffValues;

    Logging.Debug("Setup.getBuffInformationFromIni End")
end

local function getHealingFromIni()
    Logging.Debug("Setup.getHealingFromIni Start")
    --tanks
    local importantBotValues = iniHelper.readKey(iniHelper.HEALING_SECTION, iniHelper.IMPORTANT_BOT_KEY)
    local tankList = iniHelper.readKey(iniHelper.HEALING_SECTION, iniHelper.TANK_KEY)
    local tankHeal = iniHelper.readKey(iniHelper.HEALING_SECTION, iniHelper.TANK_HEAL_KEY)
    local importantBotHealValues = iniHelper.readKey(iniHelper.HEALING_SECTION, iniHelper.IMPORTANT_HEAL_KEY)

    HEALING_2D[iniHelper.TANK_KEY] = tankList
    HEALING_2D[iniHelper.IMPORTANT_BOT_KEY] = importantBotValues
    HEALING_2D[iniHelper.TANK_HEAL_KEY] = tankHeal
    HEALING_2D[iniHelper.IMPORTANT_HEAL_KEY] = importantBotHealValues

    Logging.Debug("Setup.getHealingFromIni End")
end

local function getMeleeAbilitiesFromIni()
    Logging.Debug("Setup.getMeleeAbilitiesFromIni Start")
    --Check if melee section exists first?
    MELEE_ABILITIES_2D = iniHelper.readKey(iniHelper.MELEE_ABILITIES_SECTION, iniHelper.MELEE_ABILITY_KEY)
    Logging.Debug('----------------Melee Abilities Table -------------')
    Logging.Debug(tableUtil.table_print(MELEE_ABILITIES_2D))
    Logging.Debug("Setup.getMeleeAbilitiesFromIni End")
end

local function getNukeSetsFromIni()
    Logging.Debug("Setup.getNukeSetsFromIni Start")

    NUKES_2D = iniHelper.readSection(iniHelper.NUKES_SECTION)

    Logging.Debug("----------------spell table --------------")
    Logging.Debug(tableUtil.table_print(NUKES_2D))
    Logging.Debug("Setup.getNukeSetsFromIni End")
end

function setup_export.setup()
    Logging.Debug("Setup.setup Start")
    local charName = mq.TLO.Me.CleanName() .. ".ini";
    local iniLocation = ("\\srl\\config\\bot_ini\\%s"):format(charName);
    botIniLocation = mq.TLO.Lua.Dir() .. iniLocation

    --ALWAYS FIRST
    iniHelper.createBotIni()
    initializeGlobalVars()

    heal.createObservables()

    getBuffInformationFromIni()
    getHealingFromIni()
    getMeleeAbilitiesFromIni()
    getNukeSetsFromIni()
    movement.registerEvents()
    attack.registerEvents()
    iBasic.registerEvents()

    Logging.Debug("Setup.setup End")
end

return setup_export