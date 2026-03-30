local mq = require 'mq'

local ConfigValidator = {}

local function warn(section, name, msg)
    mq.cmdf('/dgt all [SRL Validate] %s: "%s" - %s', mq.TLO.Me.Name(), tostring(name), msg)
end

-- Per-type TLO checks
local function checkDisc(name)
    return mq.TLO.Me.CombatAbility(name)() ~= nil
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

local function checkEntry(section, name, entryType)
    if not name or name == '' then
        warn(section, name, 'empty name')
        return
    end
    if type(name) ~= 'string' then
        warn(section, tostring(name), 'expected string name, got ' .. type(name))
        return
    end
    local t = (entryType or 'spell'):lower()
    if t == 'disc' then
        if not checkDisc(name) then
            warn(section, name, 'disc not found - not trained or name mismatch')
        end
    elseif t == 'aa' then
        if not checkAA(name) then
            warn(section, name, 'AA not found - not trained or name mismatch')
        end
    elseif t == 'item' then
        if not checkItem(name) then
            warn(section, name, 'item not in inventory')
        end
    elseif t == 'spell' or t == 'buff' or t == 'nuke' or t == 'heal' then
        if not checkSpell(name) then
            warn(section, name, 'spell not found in database')
        end
    -- 'ability' skipped - no reliable TLO check
    end
end

-- Validate a list of entries with a spell/name field and a type field
local function checkList(section, entries, nameField, typeField)
    if not entries then return end
    for _, entry in ipairs(entries) do
        local name = entry[nameField]
        local t    = entry[typeField]
        checkEntry(section, name, t)
    end
end

function ConfigValidator.run(config)
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
                checkEntry(key, entry.spell, 'spell')
            end
        end
    end

    -- Abilities (Ability field, type field)
    checkList('Abilities', config:get('Abilities'), 'Ability', 'type')

    -- Burn sections (name field, type field)
    for _, section in ipairs({ 'Burn.QuickBurn', 'Burn.FullBurn', 'Burn.LongBurn' }) do
        checkList(section, config:get(section), 'name', 'type')
    end

    -- Aura
    local aura = config:get('Aura.Aura')
    if aura and aura.spell then
        checkEntry('Aura.Aura', aura.spell, aura.type)
    end

    -- Epic
    local epic = config:get('Epic.name')
    if epic and epic ~= '' then
        checkEntry('Epic', epic, 'item')
    end

    -- Mount
    local mount = config:get('Mount')
    if mount and mount ~= '' then
        checkEntry('Mount', mount, 'item')
    end

    mq.cmdf('/dgt all [SRL Validate] Done for %s.', me)
end

return ConfigValidator
