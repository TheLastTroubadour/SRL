local mq = require 'mq'
local Job = require 'model.Job'
local State = require 'core.State'
local SpellUtil = require 'util.SpellUtil'

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
    self.config          = config
    self.myClass         = mq.TLO.Me.Class.ShortName()
    self.combatService   = nil
    self.abilityDecision = nil
    return self
end

function BurnService:setCombatService(cs)
    self.combatService = cs
end

function BurnService:setAbilityDecision(ad)
    self.abilityDecision = ad
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
    local myId   = mq.TLO.Me.ID()
    local myName = mq.TLO.Me.Name()
    local castService = self.combatService and self.combatService.castService
    local assistTargetId = State.assist.targetId or mq.TLO.Target.ID() or 0

    for _, v in ipairs(abilities) do
        if v.soloBot and v.soloBot:lower() ~= myName:lower() then goto continue end
        local resolvedName = SpellUtil.resolveRank(v.name, v.type)
        local job = Job:new(myId, myName, resolvedName, v.type, v.priority or 60, nil)
        job.burn = true

        if v.debuff and self.abilityDecision and assistTargetId ~= 0 then
            local expiry = self.abilityDecision:getClaimExpiry(v.name, assistTargetId)
            local now = mq.gettime()
            if expiry and now < expiry then
                -- Another bard claimed it — defer until their application wears off
                job.notBefore = expiry
            else
                -- We're first — claim it and cast immediately
                local duration = (mq.TLO.Me.AltAbility(v.name).Spell.Duration.TotalSeconds() or 0)
                if duration > 0 then
                    local durationMs = (duration + 2) * 1000
                    self.abilityDecision:addClaim(v.name, assistTargetId, durationMs)
                    mq.cmdf('/dgae /srlevent ClaimAbility name=%s targetId=%s duration=%s',
                        (v.name:gsub(' ', '_')), tostring(assistTargetId), tostring(math.floor(durationMs)))
                end
            end
        end

        if castService then
            castService:enqueue(job)
        end
        ::continue::
    end
end

function BurnService:tick()
    if not State.flags.expMode then return end
    if not State.assist.targetId then return end

    local now = mq.gettime()
    if self._lastExpActivation and now - self._lastExpActivation < 2000 then return end
    self._lastExpActivation = now

    self:activate('Burn.ExpMode')
end

-- Clicks the character's epic. Checks YAML Epic.name override first,
-- then falls back to the hardcoded class table (2.0 preferred over 1.5).
function BurnService:clickEpic()
    if self.myClass == 'CLR' then return end

    -- YAML override takes priority
    local override = self.config:get('Epic.name')
    if override and override ~= '' then
        if mq.TLO.FindItem('=' .. override)() then
            mq.cmdf('/useitem "%s"', override)
        end
        return
    end

    -- Hardcoded fallback: try 2.0 then 1.5
    local epics = CLASS_EPICS[self.myClass]
    if not epics then return end
    for _, name in ipairs(epics) do
        if mq.TLO.FindItem('=' .. name)() then
            mq.cmdf('/useitem "%s"', name)
            return
        end
    end
end

return BurnService