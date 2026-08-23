
return {
    _version = 1,
    General = {
        debugLevel = 'off',
        BackgroundAssist = true, -- when not in automode, still auto-follow the active assist target once this window loses foreground focus (stays hands-off while foregrounded either way)
    },
    Automode = {
        BroadcastScope = 'group', -- group | zone | raid | all -- how far automode's own broadcasts travel (assist calls, med break, camp)
    },
    SwapItems = {
        Main=''
    },
    UseItems ={
        Shrink=''
    },
    Aura = {
        CastAura = false,
        spell    = '',
        type     = 'spell',
        gem      = nil
    },
    Buffs = {
        InstantBuff = {
        },
        SelfBuff = {

        },
        BotBuff = {

        },
        CombatBuff = {

        },
        GroupBuff = {

        }
    },
    AssistSettings = {
        enabled = 'true',
        type = 'melee',
        meleeStickDistance = 'MaxMelee',
        meleeStickPoint= 'Behind',
        rangedDistance = 100,
        AutoAssistEngagePercent = 98,
        requireAggressive = true
    },
    LifeSupport = {

    },
    Burn = {
        QuickBurn = {},
        LongBurn  = {},
        FullBurn  = {}
    },
    Epic = {
        name = ''
    },
    Pull = {
        Radius     = 100,
        MaxZRange  = 70,   -- vertical band around camp's Z; keeps different-floor mobs out of a large horizontal Radius
        MaxActive  = 1,
        ReturnDist = 15,
        HealerMedThreshold = 30,        -- trigger a hold while any group healer's mana is below this
        HealerMedResumeThreshold = 90,  -- once holding, require this much before resuming (hysteresis)
        Spells = {},   -- ordered list: { spell=, type=, gem=, range= }; first ready+in-range wins, melee fallback if empty/none ready
        CampDragDistance = 80, -- tank/tankpuller drifted (knockback etc.) this far from camp mid-fight -- nav back to camp instead of standing put
    },
    Regroup = {
        Distance   = 75,  -- trigger nav-to-camp once this far from camp while idle
        ReturnDist = 15,  -- how close counts as "back"
    }
}