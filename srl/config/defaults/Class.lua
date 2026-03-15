return {
    WIZ = {
        Wizard = {
            EvacSpell    = '',
            AutoHarvest  = false,
            Harvest = {
                spells = { spell = '' }
            }
        },
        Epic = { name = 'Staff of Phenomenal Power' }
    },
    SHD = {
        ShadowKnight = {
            LifeTap = ''
        },
        Epic = { name = "Innoruuk's Dark Blessing" }
    },
    CLR = {
        Cleric = {
            DivineArbitrationPct      = 35,
            EpicPct                   = 35,
            CelestialRegenarationPct  = 0,
            AutoYaulp                 = false,
            YaulpSpell                = '',
        }
        -- No Epic entry: CLR epic is intentionally excluded from epicburn
    },
    SHM = {
        Shaman = {
            AutoCanni    = false,
            CanniSpells  = { CanniSpell = '' }
        },
        Epic = { name = 'Blessed Spiritstaff of the Heyokah' }
    },
    BRD = {
        Bard = {
            AutoMez     = false,
            MezSpell    = '',
            MezLevel    = '',
            CharmSpell  = '',
            CharmLevel  = '',
            -- Named melodies: each key is a melody name, value is a list of gem slot numbers.
            -- /playmelody <name> activates the corresponding /twist sequence.
            -- Example:
            --   Melodies:
            --     dps:
            --       - 1
            --       - 2
            --       - 3
            --       - 4
            --     invis:
            --       - 5
            --       - 6
            Melodies    = {}
        },
        CrowdControl = {
            Enabled       = false,
            RecastBuffer  = 10,
            MaxTankedMobs = 1,
            Spells        = {}
        },
        Epic = { name = 'Blade of Vesagran' }
    },
    WAR = {
        Epic = { name = "Kreljnok's Sword of Eternal Power" }
    },
    PAL = {
        Epic = { name = 'Nightbane, Sword of the Valiant' }
    },
    RNG = {
        Epic = { name = 'Aurora, the Heartwood Blade' }
    },
    ROG = {
        Epic = { name = 'Nightshade, Blade of Entropy' }
    },
    MNK = {
        Epic = { name = 'Transcended Fistwraps of Immortality' }
    },
    BER = {
        Epic = { name = 'Vengeful Taelosian Blood Axe' }
    },
    BST = {
        Epic = { name = 'Spiritcaller Totem of the Feral' }
    },
    MAG = {
        Epic = { name = 'Focus of Primal Elements' }
    },
    NEC = {
        Epic = { name = 'Deathwhisper' }
    },
    ENC = {
        CrowdControl = {
            Enabled       = false,
            RecastBuffer  = 10,
            MaxTankedMobs = 1,
            Spells        = {}
        },
        Epic = { name = 'Staff of Eternal Eloquence' }
    },
    DRU = {
        Epic = { name = 'Staff of Everliving Brambles' }
    }
}
