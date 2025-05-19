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
    --ini driven
    ASSIST_TYPE = IniHelper.returnValueFromSectionAndKey(IniHelper.ASSIST_SECTION_KEY, IniHelper.ASSIST_TYPE_KEY)
    MELEE_STICK_POINT = IniHelper.DEFAULT_MELEE_STICK_POINT_VALUE
    MELEE_DISTANCE = IniHelper.returnValueFromSectionAndKey(IniHelper.ASSIST_SECTION_KEY, IniHelper.MELEE_DISTANCE_KEY)
    RANGED_DISTANCE = IniHelper.returnValueFromSectionAndKey(IniHelper.ASSIST_SECTION_KEY, IniHelper.RANGED_DISTANCE_KEY)
end

local function getHealingFromIni()
    Logging.Debug("Setup.getHealingFromIni Start")
    --tanks
    local importantBotValues = IniHelper.readKey(IniHelper.HEALING_SECTION, IniHelper.IMPORTANT_BOT_KEY)
    local tankList = IniHelper.readKey(IniHelper.HEALING_SECTION, IniHelper.TANK_KEY)
    local tankHeal = IniHelper.readKey(IniHelper.HEALING_SECTION, IniHelper.TANK_HEAL_KEY)
    local importantBotHealValues = IniHelper.readKey(IniHelper.HEALING_SECTION, IniHelper.IMPORTANT_HEAL_KEY)

    HEALING_2D[IniHelper.TANK_KEY] = tankList
    HEALING_2D[IniHelper.IMPORTANT_BOT_KEY] = importantBotValues
    HEALING_2D[IniHelper.TANK_HEAL_KEY] = tankHeal
    HEALING_2D[IniHelper.IMPORTANT_HEAL_KEY] = importantBotHealValues

    Logging.Debug("Setup.getHealingFromIni End")
end

local function getMeleeAbilitiesFromIni()
    Logging.Debug("Setup.getMeleeAbilitiesFromIni Start")
    --Check if melee section exists first?
    MELEE_ABILITIES_2D = IniHelper.readKey(IniHelper.MELEE_ABILITIES_SECTION, IniHelper.MELEE_ABILITY_KEY)
    Logging.Debug('----------------Melee Abilities Table -------------')
    Logging.Debug(TableUtil.table_print(MELEE_ABILITIES_2D))
    Logging.Debug("Setup.getMeleeAbilitiesFromIni End")
end

local function getNukeSetsFromIni()
    Logging.Debug("Setup.getNukeSetsFromIni Start")

    NUKES_2D = IniHelper.readSection(IniHelper.NUKES_SECTION)

    Logging.Debug("----------------spell table --------------")
    Logging.Debug(TableUtil.table_print(NUKES_2D))
    Logging.Debug("Setup.getNukeSetsFromIni End")
end

function setup_export.setup()
    Logging.Debug("Setup.setup Start")
    local charName = mq.TLO.Me.CleanName() .. ".ini";
    local iniLocation = ("\\srl\\config\\bot_ini\\%s"):format(charName);
    botIniLocation = mq.TLO.Lua.Dir() .. iniLocation

    --ALWAYS FIRST
    IniHelper.createBotIni()
    initializeGlobalVars()

    getHealingFromIni()
    getMeleeAbilitiesFromIni()
    getNukeSetsFromIni()
    Movement.registerEvents()
    Attack.registerEvents()
    Logging.Debug("Setup.setup End")
end

return setup_export