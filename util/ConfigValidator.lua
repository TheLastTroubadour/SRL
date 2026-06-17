local mq = require 'mq'
local SpellUtil = require 'util.SpellUtil'

local ConfigValidator = {}

local badSet = {}  -- populated by run(); keyed "name|type"

local function badKey(name, entryType)
    return tostring(name) .. '|' .. tostring(entryType or 'spell'):lower()
end

local function warn(section, name, msg)
    mq.cmdf('/dgt all [SRL Validate] %s: "%s" - %s', mq.TLO.Me.Name(), tostring(name), msg)
end

-- Per-type TLO checks
local function checkDisc(name)
    local resolved = SpellUtil.resolveRank(name, 'disc')
    return mq.TLO.Me.CombatAbility(resolved)() ~= nil
end

local function checkAA(name)
    return mq.TLO.Me.AltAbility(name)() ~= nil
end

local function checkSpell(name)
    return mq.TLO.Spell(name)() ~= nil
end

local function checkItem(name)
    return mq.TLO.FindItem('=' .. name)() ~= nil
end

-- Returns true if the entry is valid (castable/usable).
local function checkEntry(section, name, entryType)
    if not name or name == '' then
        warn(section, name, 'empty name')
        return false
    end
    if type(name) ~= 'string' then
        warn(section, tostring(name), 'expected string name, got ' .. type(name))
        return false
    end
    local t = (entryType or 'spell'):lower()
    if t == 'disc' then
        if not checkDisc(name) then
            warn(section, name, 'disc not found - not trained or name mismatch')
            return false
        end
    elseif t == 'aa' then
        if not checkAA(name) then
            warn(section, name, 'AA not found - not trained or name mismatch')
            return false
        end
    elseif t == 'item' then
        if not checkItem(name) then
            warn(section, name, 'item not in inventory')
            return false
        end
    elseif t == 'spell' or t == 'buff' or t == 'nuke' or t == 'heal' then
        if not checkSpell(name) then
            warn(section, name, 'spell not found in database')
            return false
        end
    -- 'ability' skipped - no reliable TLO check
    end
    return true
end

-- Returns false if this name+type was flagged invalid during run().
function ConfigValidator.isValid(name, entryType)
    return not badSet[badKey(name, entryType)]
end

local function recordIfBad(name, entryType, valid)
    if not valid then
        badSet[badKey(name, entryType)] = true
    end
end

-- Validate a list of entries with a spell/name field and a type field
local function checkList(section, entries, nameField, typeField)
    if not entries then return end
    for _, entry in ipairs(entries) do
        local name = entry[nameField]
        local t    = entry[typeField]
        local ok   = checkEntry(section, name, t)
        recordIfBad(name, t, ok)
    end
end

function ConfigValidator.run(config)
    badSet = {}  -- reset for this character's validation pass
    local me = mq.TLO.Me.Name()
    mq.cmdf('/dgt all [SRL Validate] Running config validation for %s...', me)

    -- Buffs (spell field, type field)
    for _, section in ipairs({ 'Buffs.SelfBuff', 'Buffs.BotBuff', 'Buffs.CombatBuff', 'Buffs.GroupBuff' }) do
        checkList(section, config:get(section), 'spell', 'type')
    end

    -- Nukes (always spells)
    local nukeKeys = { 'Nukes.Main', 'Nukes.QuickBurn', 'Nukes.LongBurn', 'Nukes.FullBurn' }
    for _, key in ipairs(nukeKeys) do
        local entries = config:get(key)
        if entries then
            for _, entry in ipairs(entries) do
                local ok = checkEntry(key, entry.spell, 'spell')
                recordIfBad(entry.spell, 'spell', ok)
            end
        end
    end

    -- Abilities (Ability field, type field)
    checkList('Abilities', config:get('Abilities'), 'Ability', 'type')

    -- Burn sections (name field, type field)
    for _, section in ipairs({ 'Burn.QuickBurn', 'Burn.FullBurn', 'Burn.LongBurn', 'Burn.ExpMode' }) do
        checkList(section, config:get(section), 'name', 'type')
    end

    -- Aura
    local aura = config:get('Aura.Aura')
    if aura and aura.spell then
        local ok = checkEntry('Aura.Aura', aura.spell, aura.type)
        recordIfBad(aura.spell, aura.type, ok)
    end

    -- Epic
    local epic = config:get('Epic.name')
    if epic and epic ~= '' then
        local ok = checkEntry('Epic', epic, 'item')
        recordIfBad(epic, 'item', ok)
    end

    -- Mount
    local mount = config:get('Mount')
    if mount and mount ~= '' then
        local ok = checkEntry('Mount', mount, 'item')
        recordIfBad(mount, 'item', ok)
    end

    mq.cmdf('/dgt all [SRL Validate] Done for %s.', me)
end

return ConfigValidator
