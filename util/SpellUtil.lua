local mq = require 'mq'

local SpellUtil = {}

local RANKS = {'Rk. III', 'Rk. II'}

local function stripRank(name)
    return (name:gsub('%s+Rk%.%s*%a+$', ''))
end

-- Resolve a spell/ability base name to the highest available rank.
-- spellType governs how availability is checked:
--   'disc'              → Me.CombatAbility (disciplines)
--   'aa','item','ability' → returned unchanged (no ranked variants)
--   anything else       → Me.Book (scribd spells)
-- If no ranked variant is found, returns the base name (rank stripped).
function SpellUtil.resolveRank(name, spellType)
    if not name then return name end
    local t = (spellType or 'spell'):lower()

    if t == 'aa' or t == 'item' or t == 'ability' then
        return name
    end

    local base = stripRank(name)

    if t == 'disc' then
        for _, rank in ipairs(RANKS) do
            if mq.TLO.Me.CombatAbility(base .. ' ' .. rank)() then
                return base .. ' ' .. rank
            end
        end
        return base
    end

    -- spell, buff, nuke, heal, dot, or any unrecognised type
    for _, rank in ipairs(RANKS) do
        if mq.TLO.Me.Book(base .. ' ' .. rank)() then
            return base .. ' ' .. rank
        end
    end
    return base
end

return SpellUtil
