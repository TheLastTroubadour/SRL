-- EditorSchema.lua
-- Describes how each config section should be rendered in the structured editor.
--
-- Section types:
--   'kv'          key-value pairs (scalar fields only)
--   'array'       flat list of items, each item is a table of fields
--   'named_sets'  table whose values are arrays (e.g. Nukes.Main, Nukes.Cold)
--   'mixed'       top-level kv fields + one named sub-array (e.g. AE)
--
-- Field types (ftype):
--   'string', 'number', 'bool', 'enum'

local SPELL_TYPES  = {'spell', 'aa', 'disc', 'item', 'ability'}
local BURN_TYPES   = {'aa', 'spell', 'disc', 'item'}
local ASSIST_TYPES = {'melee', 'ranged', 'off'}
local STICK_POINTS = {'Behind', 'Front', 'Left', 'Right'}
local CURE_TYPES   = {'Poison', 'Disease', 'Curse', 'Corruption',
                      'Poison,Disease', 'Poison,Disease,Curse',
                      'Poison,Disease,Curse,Corruption'}

-- Ordered list of top-level section keys to display (rest are shown generically)
local SECTION_ORDER = {
    'General', 'AssistSettings', 'Port',
    'Abilities',
    'Nukes', 'Jolts', 'Burn',
    'Buffs',
    'Debuff', 'DotsOnAssist', 'DotsOnCommand',
    'Cures',
    'AE',
    'GemSwap',
    'Heals',
    'Shrink', 'Aura', 'Epic', 'GiftOfMana',
}

local SECTIONS = {

    General = {
        label = 'General',
        type  = 'kv',
        fields = {
            { key = 'debugLevel', label = 'Debug Level', ftype = 'enum', options = {'off', 'on'} },
            { key = 'medStart',   label = 'Med Start %', ftype = 'number' },
            { key = 'medStop',    label = 'Med Stop %',  ftype = 'number' },
        },
    },

    AssistSettings = {
        label = 'Assist Settings',
        type  = 'kv',
        fields = {
            { key = 'enabled',                label = 'Enabled',            ftype = 'bool' },
            { key = 'type',                   label = 'Assist Type',        ftype = 'enum',   options = ASSIST_TYPES },
            { key = 'meleeStickDistance',      label = 'Stick Distance',     ftype = 'number' },
            { key = 'meleeStickPoint',         label = 'Stick Point',        ftype = 'enum',   options = STICK_POINTS },
            { key = 'rangedDistance',          label = 'Ranged Distance',    ftype = 'number' },
            { key = 'AutoAssistEngagePercent', label = 'Auto Assist %',      ftype = 'number' },
            { key = 'requireAggressive',       label = 'Require Aggressive', ftype = 'bool' },
        },
    },

    Port = {
        label = 'Port',
        type  = 'kv',
        fields = {
            { key = 'Enabled', label = 'Enabled', ftype = 'bool' },
            { key = 'Gem',     label = 'Gem',     ftype = 'number' },
        },
    },

    -- ── Spell/ability arrays ──────────────────────────────────────────

    Abilities = {
        label    = 'Abilities',
        type     = 'array',
        labelKey = 'Ability',
        fields   = {
            { key = 'Ability',        label = 'Name',            ftype = 'ability_name', required = true },
            { key = 'type',           label = 'Type',            ftype = 'enum',   options = {'ability','disc','aa','item'}, required = true },
            { key = 'reagent',        label = 'Reagent',         ftype = 'string' },
            { key = 'debuff',         label = 'Has Debuff',      ftype = 'bool' },
            { key = 'stacks',         label = 'Stacks',          ftype = 'bool' },
            { key = 'duration',       label = 'Duration (s)',    ftype = 'number' },
            { key = 'priority',       label = 'Priority',        ftype = 'number' },
            { key = 'aggroThreshold', label = 'Aggro Threshold', ftype = 'number' },
        },
        default  = { Ability = '', type = 'ability' },
    },

    Nukes = {
        label    = 'Nukes',
        type     = 'named_sets',
        labelKey = 'spell',
        fields   = {
            { key = 'spell',    label = 'Spell',    ftype = 'spell_name', required = true },
            { key = 'gem',      label = 'Gem',      ftype = 'number',     required = true },
            { key = 'priority', label = 'Priority', ftype = 'number' },
        },
        default  = { spell = '', gem = 1 },
    },

    Jolts = {
        label    = 'Jolts',
        type     = 'named_sets',
        labelKey = 'spell',
        fields   = {
            { key = 'spell',    label = 'Spell',    ftype = 'spell_name', required = true },
            { key = 'gem',      label = 'Gem',      ftype = 'number',     required = true },
            { key = 'priority', label = 'Priority', ftype = 'number' },
        },
        default  = { spell = '', gem = 1 },
    },

    Burn = {
        label    = 'Burn',
        type     = 'named_sets',
        labelKey = 'name',
        setNames = {'LongBurn', 'QuickBurn', 'FullBurn'},
        fields   = {
            { key = 'name', label = 'Name', ftype = 'string', required = true },
            { key = 'type', label = 'Type', ftype = 'enum',   options = BURN_TYPES, required = true },
        },
        default  = { name = '', type = 'aa' },
    },

    Buffs = {
        label    = 'Buffs',
        type     = 'named_sets',
        labelKey = 'spell',
        setNames = {'SelfBuff', 'GroupBuff', 'CombatBuff', 'InstantBuff', 'BotBuff'},
        fields   = {
            { key = 'spell',           label = 'Spell',            ftype = 'spell_name', required = true },
            { key = 'type',            label = 'Type',             ftype = 'enum',       options = SPELL_TYPES },
            { key = 'gem',             label = 'Gem',              ftype = 'number' },
            { key = 'buffName',        label = 'Buff Name',        ftype = 'spell_name' },
            { key = 'alwaysCheck',     label = 'Always Check',     ftype = 'bool' },
            { key = 'charactersToBuff', label = 'Characters to Buff', ftype = 'string_list' },
        },
        default  = { spell = '', type = 'spell' },
    },

    Debuff = {
        label    = 'Debuff',
        type     = 'named_sets',
        labelKey = 'spell',
        setNames = {'DebuffOnAssist', 'DebuffOnCommand', 'DebuffOnXTar'},
        nestedSets = true,  -- sets contain another level: Main, Seru, etc.
        fields   = {
            { key = 'spell',      label = 'Spell',       ftype = 'spell_name', required = true },
            { key = 'gem',        label = 'Gem',         ftype = 'number' },
            { key = 'type',       label = 'Type',        ftype = 'enum',       options = SPELL_TYPES },
            { key = 'checkBuff',  label = 'Check Buff',  ftype = 'spell_name' },
            { key = 'priority',   label = 'Priority',    ftype = 'bool' },
        },
        kvFields = {
            { key = 'DebuffTargetsOnXTarEnabled',        label = 'XTar Debuff Enabled', ftype = 'bool' },
            { key = 'MinimumAmountToStartDebuffOnXTar',  label = 'XTar Min Count',      ftype = 'number' },
        },
        default  = { spell = '', gem = 1 },
    },

    DotsOnAssist = {
        label    = 'DoTs on Assist',
        type     = 'named_sets',
        labelKey = 'spell',
        fields   = {
            { key = 'spell',     label = 'Spell',      ftype = 'spell_name', required = true },
            { key = 'gem',       label = 'Gem',        ftype = 'number',     required = true },
            { key = 'checkBuff', label = 'Check Buff', ftype = 'spell_name' },
        },
        default  = { spell = '', gem = 1 },
    },

    DotsOnCommand = {
        label    = 'DoTs on Command',
        type     = 'named_sets',
        labelKey = 'spell',
        fields   = {
            { key = 'spell',     label = 'Spell',      ftype = 'spell_name', required = true },
            { key = 'gem',       label = 'Gem',        ftype = 'number',     required = true },
            { key = 'checkBuff', label = 'Check Buff', ftype = 'spell_name' },
        },
        default  = { spell = '', gem = 1 },
    },

    Cures = {
        label    = 'Cures',
        type     = 'named_sets',
        labelKey = 'name',
        setNames = {'Spells'},
        fields   = {
            { key = 'name',       label = 'Name',        ftype = 'spell_name', required = true },
            { key = 'type',       label = 'Cure Types',  ftype = 'string', required = true },
            { key = 'spelltype',  label = 'Spell Type',  ftype = 'enum',   options = SPELL_TYPES },
            { key = 'gem',        label = 'Gem',         ftype = 'number' },
            { key = 'groupOnly',  label = 'Group Only',  ftype = 'bool' },
            { key = 'minInjured', label = 'Min Injured', ftype = 'number' },
        },
        default  = { name = '', type = 'Poison,Disease', spelltype = 'spell' },
    },

    AE = {
        label    = 'AE',
        type     = 'mixed',
        kvFields = {
            { key = 'Enabled', label = 'Enabled', ftype = 'bool' },
        },
        arrayKey = 'Spells',
        labelKey = 'name',
        fields   = {
            { key = 'name',      label = 'Name',      ftype = 'string', required = true },
            { key = 'type',      label = 'Type',      ftype = 'enum',   options = SPELL_TYPES, required = true },
            { key = 'gem',       label = 'Gem',       ftype = 'number' },
            { key = 'threshold', label = 'Threshold', ftype = 'number' },
            { key = 'targeted',  label = 'Targeted',  ftype = 'bool' },
            { key = 'debuff',    label = 'Debuff',    ftype = 'bool' },
        },
        default  = { name = '', type = 'spell', threshold = 3 },
    },

    GemSwap = {
        label    = 'Gem Swap',
        type     = 'named_sets',
        labelKey = 'name',
        fields   = {
            { key = 'name', label = 'Spell', ftype = 'string', required = true },
            { key = 'gem',  label = 'Gem',   ftype = 'number', required = true },
        },
        default  = { name = '', gem = 1 },
    },

    Shrink = {
        label = 'Shrink',
        type  = 'kv',
        fields = {
            { key = 'Enabled',       label = 'Enabled',         ftype = 'bool' },
            { key = 'name',          label = 'Item Name',       ftype = 'string' },
            { key = 'type',          label = 'Type',            ftype = 'enum', options = {'item', 'aa', 'spell'} },
            { key = 'sizeThreshold', label = 'Size Threshold',  ftype = 'number' },
        },
    },

    Aura = {
        label = 'Aura',
        type  = 'kv',
        fields = {
            { key = 'CastAura', label = 'Cast Aura', ftype = 'bool' },
            { key = 'Aura',     label = 'Aura Spell', ftype = 'subobject', fields = {
                { key = 'spell', label = 'Spell', ftype = 'spell_name' },
                { key = 'type',  label = 'Type',  ftype = 'enum', options = SPELL_TYPES },
                { key = 'gem',   label = 'Gem',   ftype = 'number' },
            }},
        },
    },

    Epic = {
        label = 'Epic',
        type  = 'kv',
        fields = {
            { key = 'name', label = 'Item Name', ftype = 'string' },
        },
    },

    GiftOfMana = {
        label = 'Gift of Mana',
        type  = 'kv',
        fields = {
            { key = 'spell',  label = 'Spell',  ftype = 'spell_name' },
            { key = 'gem',    label = 'Gem',    ftype = 'number' },
            { key = 'target', label = 'Target', ftype = 'enum', options = {'assist', 'self'} },
        },
    },

}

return {
    sections = SECTIONS,
    order    = SECTION_ORDER,
}
