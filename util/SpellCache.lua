-- SpellCache.lua
-- Lazily enumerates the character's spellbook and known combat abilities.
-- Call reset() to force a rebuild (e.g. after memming new spells).

local mq = require 'mq'

local SpellCache = {}

-- EQ combat abilities (doability-type skills). Includes all classes;
-- only ones the character actually has will appear via AbilityReady.
local ABILITY_NAMES = {
    'Backstab', 'Bash', 'Begging', 'Bind Wound', 'Disarm',
    'Double Attack', 'Dragon Punch', 'Dual Wield', 'Eagle Strike',
    'Feign Death', 'Flying Kick', 'Forage', 'Frenzy',
    'Hide', 'Intimidation', 'Kick', 'Mend',
    'Pick Lock', 'Riposte', 'Round Kick', 'Safe Fall',
    'Slam', 'Sneak', 'Spin Stun', 'Taunt',
    'Tiger Claw', 'Throw Stone', 'Track', 'Trick Stab',
    'Tumbling', 'Zan Fi Whistle',
}

local spellList   = nil
local abilityList = nil

function SpellCache.getSpells()
    if spellList then return spellList end
    spellList = {}
    local i = 1
    while true do
        local book = mq.TLO.Me.Book(i)
        if not book() then break end
        local name = book.Name()
        if name and name ~= '' then
            table.insert(spellList, name)
        end
        i = i + 1
    end
    table.sort(spellList)
    return spellList
end

function SpellCache.getAbilities()
    if abilityList then return abilityList end
    abilityList = {}
    for _, name in ipairs(ABILITY_NAMES) do
        -- Include if the character has the skill at all (ready or on cooldown)
        if mq.TLO.Me.Ability(name)() then
            table.insert(abilityList, name)
        end
    end
    return abilityList
end

-- Call after memming spells or changing character
function SpellCache.reset()
    spellList   = nil
    abilityList = nil
end

-- Search helpers — returns up to `limit` matches (default 10)
function SpellCache.searchSpells(query, limit)
    limit = limit or 10
    local results = {}
    local lower = query:lower()
    for _, name in ipairs(SpellCache.getSpells()) do
        if name:lower():find(lower, 1, true) then
            table.insert(results, name)
            if #results >= limit then break end
        end
    end
    return results
end

function SpellCache.searchAbilities(query, limit)
    limit = limit or 10
    local results = {}
    local lower = query:lower()
    for _, name in ipairs(SpellCache.getAbilities()) do
        if name:lower():find(lower, 1, true) then
            table.insert(results, name)
            if #results >= limit then break end
        end
    end
    return results
end

return SpellCache
