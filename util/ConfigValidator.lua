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

    -- Jolts
    checkList('Jolts.Main', config:get('Jolts.Main'), 'spell', 'type')

    -- Debuffs (Main sets)
    for _, section in ipairs({ 'Debuff.DebuffOnAssist.Main', 'Debuff.DebuffOnCommand.Main', 'Debuff.DebuffOnXTar.Main' }) do
        checkList(section, config:get(section), 'spell', 'type')
    end

    -- DoTs (Main sets)
    for _, section in ipairs({ 'Dots.DotsOnAssist.Main', 'Dots.DotsOnCommand.Main' }) do
        checkList(section, config:get(section), 'spell', 'type')
    end

    -- Crowd Control
    checkList('CrowdControl.Spells', config:get('CrowdControl.Spells'), 'spell', 'type')

    -- AE spells
    checkList('AE.Spells', config:get('AE.Spells'), 'name', 'type')

    -- Taunt
    checkList('Taunt.Abilities', config:get('Taunt.Abilities'), 'name', 'type')

    -- Pull
    checkList('Pull.Spells', config:get('Pull.Spells'), 'spell', 'type')

    -- Heals
    local function checkHealRoles(section)
        local roles = config:get(section)
        if not roles then return end
        for role, spells in pairs(roles) do
            if type(spells) == 'table' then
                for _, entry in ipairs(spells) do
                    if entry.spell then
                        local ok = checkEntry(section .. '.' .. role, entry.spell, 'spell')
                        recordIfBad(entry.spell, 'spell', ok)
                    end
                end
            end
        end
    end
    checkHealRoles('Heals.Spells')
    checkHealRoles('Heals.HoTSpells')
    checkHealRoles('Heals.PromisedSpells')
    local groupSpell = config:get('Heals.GroupSpell')
    if groupSpell and groupSpell.spell then
        local ok = checkEntry('Heals.GroupSpell', groupSpell.spell, 'spell')
        recordIfBad(groupSpell.spell, 'spell', ok)
    end

    -- Cures
    local cures = config:get('Cures.Spells')
    if cures then
        for _, entry in ipairs(cures) do
            local t = entry.spelltype or 'spell'
            local ok = checkEntry('Cures.Spells', entry.name, t)
            recordIfBad(entry.name, t, ok)
        end
    end

    -- GiftOfMana
    local gom = config:get('GiftOfMana')
    if gom and gom.spell then
        local ok = checkEntry('GiftOfMana', gom.spell, 'spell')
        recordIfBad(gom.spell, 'spell', ok)
    end

    -- Shrink
    local shrink = config:get('UseItems.Shrink')
    if shrink and shrink.spell then
        local ok = checkEntry('UseItems.Shrink', shrink.spell, shrink.type or 'spell')
        recordIfBad(shrink.spell, shrink.type or 'spell', ok)
    end

    -- Shaman Canni
    local canniSpell = config:get('Shaman.CanniSpells.CanniSpell')
    local canniType  = config:get('Shaman.CanniSpells.CanniType') or 'spell'
    if canniSpell and canniSpell ~= '' then
        local ok = checkEntry('Shaman.CanniSpells', canniSpell, canniType)
        recordIfBad(canniSpell, canniType, ok)
    end

    mq.cmdf('/dgt all [SRL Validate] Done for %s.', me)
end

return ConfigValidator
