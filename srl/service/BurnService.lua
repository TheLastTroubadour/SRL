 local mq = require 'mq'

-- 2.0 first, 1.5 second. 1.0 epics not included. CLR intentionally omitted.
local CLASS_EPICS = {
    WAR = { "Kreljnok's Sword of Eternal Power",     "Champion's Sword of Eternal Power" },
    PAL = { "Nightbane, Sword of the Valiant",       "Redemption" },
    SHD = { "Innoruuk's Dark Blessing",              "Innoruuk's Voice" },
    BRD = { "Blade of Vesagran",                     "Prismatic Dragon Blade" },
    RNG = { "Aurora, the Heartwood Blade",           "Heartwood Blade" },
    ROG = { "Nightshade, Blade of Entropy",          "Fatestealer" },
    MNK = { "Transcended Fistwraps of Immortality",  "Fistwraps of Celestial Discipline" },
    BER = { "Vengeful Taelosian Blood Axe",          "Raging Taelosian Alloy Axe" },
    BST = { "Spiritcaller Totem of the Feral",             "Savage Lord's Totem" },
    MAG = { "Focus of Primal Elements",            "Staff of Elemental Essence" },
    WIZ = { "Staff of Phenomenal Power",               "Staff of Prismatic Power" },
    NEC = { "Deathwhisper",                    "Soulwhisper" },
    ENC = { "Staff of Eternal Eloquence",            "Transcendent Rod of Prismatic Wonders" },
    DRU = { "Staff of Everliving Brambles",              "Staff of Living Brambles" },
    SHM = { "Blessed Spiritstaff of the Heyokah",             "Crafted Talisman of Fates" },
}

local BurnService = {}
BurnService.__index = BurnService

function BurnService:new(config)
    local self = setmetatable({}, BurnService)
    self.config = config
    return self
end

-- Reads a burn section from YAML and activates each ability.
-- YAML format:
--   Burn:
--     QuickBurn:
--       - name: Intensity of the Resolute
--         type: aa
--       - name: Frenzied Devastation
--         type: disc
--       - name: Some Item Clicky
--         type: item
function BurnService:activate(sectionKey)
    self:clickEpic()
    local abilities = self.config:get(sectionKey) or {}
    for _, v in ipairs(abilities) do
        if v.type == 'aa' then
            mq.cmdf('/alt activate "%s"', v.name)
        elseif v.type == 'disc' then
            mq.cmdf('/disc "%s"', v.name)
        elseif v.type == 'ability' then
            mq.cmdf('/doability "%s"', v.name)
        elseif v.type == 'item' then
            mq.cmdf('/useitem "%s"', v.name)
        end
    end
end

-- Clicks the character's epic. Checks YAML Epic.name override first,
-- then falls back to the hardcoded class table (2.0 preferred over 1.5).
function BurnService:clickEpic()
    -- YAML override takes priority
    local override = self.config:get('Epic.name')
    if override then
        if mq.TLO.FindItem('=' .. override)() then
            mq.cmdf('/useitem "%s"', override)
        end
        return
    end

    -- Hardcoded fallback: try 2.0 then 1.5
    local class = mq.TLO.Me.Class.ShortName()
    local epics = CLASS_EPICS[class]
    if not epics then return end
    for _, name in ipairs(epics) do
        if mq.TLO.FindItem('=' .. name)() then
            mq.cmdf('/useitem "%s"', name)
            return
        end
    end
end

return BurnService
