return {
    melee = {
        Abilities = {
            Ability = ''
        }
    },

    caster = {
        AssistSettings = {
            type = 'ranged'
        },
        Nukes = {
            Main = {}
        },
        Jolts = {
            Main = {}
        }
    },

    healer = {
        AssistSettings = {
            type = 'Off'
        },
        Heals = {
            Spells = {
                tank      = {},
                important = {},
                normal    = {}
            },
            Tanks        = {},
            ImportantBots = {}
        }
    },

    debuff = {
        Debuff = {
            DebuffTargetsOnXTarEnabled        = false,
            MinimumAmountToStartDebuffOnXTar  = 2,
            DebuffOnXTar    = { Main = {} },
            DebuffOnAssist  = { Main = {} },
            DebuffOnCommand = { Main = {} }
        }
    },

    doter = {
        DotsOnCommand = { Main = {} },
        DotsOnAssist  = { Main = {} }
    },

    cc = {
        CrowdControl = {
            Enabled        = false,
            RecastBuffer   = 10,
            MaxTankedMobs  = 1,
            Spells         = {}
        }
    },

    curer = {
        Cures = {
            Spells = {}
            -- Example entries:
            --   - name: Purified Blood      (spell)
            --     type: Poison
            --     gem: 4
            --   - name: Counteract Disease  (spell)
            --     type: Disease
            --     gem: 5
            --   - name: Radiant Cure        (AA - covers multiple types)
            --     type: Poison,Disease,Curse
            --     spelltype: aa
        }
    }
}
