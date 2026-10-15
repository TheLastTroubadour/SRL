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

-- Cast range for this character: MyRange (base range plus this character's
-- range-extending focus effects), falling back to the base Range when MyRange
-- is 0/nil. Returns nil when the spell can't be found, so callers keep their
-- own `or <default>` fallback.
function SpellUtil.castRange(name)
    if not name then return nil end
    local spell = mq.TLO.Spell(name)
    if not spell() then return nil end
    local myRange = tonumber(spell.MyRange()) or 0
    if myRange > 0 then return myRange end
    return tonumber(spell.Range())
end

return SpellUtil
