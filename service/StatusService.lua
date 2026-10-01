local mq = require 'mq'

local StatusService = {}
StatusService.__index = StatusService

local EXPIRY_MS = 15000

local CLASS_ROLE_ORDER = {
    CLR = 1, DRU = 1, SHM = 1,                   -- healers
    WIZ = 2, MAG = 2, NEC = 2, ENC = 2,          -- caster dps
    WAR = 3, PAL = 3, SHD = 3,                   -- tanks
    BRD = 4, ROG = 4, MNK = 4, BER = 4,          -- melee dps
    RNG = 4, BST = 4,                             -- hybrid/melee dps
}

local function classOrder(class)
    return CLASS_ROLE_ORDER[class] or 99
end

function StatusService:new()
    local self = setmetatable({}, StatusService)
    self.peers = {}
    return self
end

function StatusService:update(data)
    if not data or not data.name then return end
    self.peers[data.name] = {
        name      = data.name,
        hp        = data.hp,
        mana      = data.mana,
        endurance = data.endurance,
        aggro     = data.aggro,
        target    = data.target,
        casting   = data.casting,
        dead      = data.dead,
        zone      = data.zone,
        class     = data.class or '',
        pctExp    = data.pctExp,
        pctAAExp  = data.pctAAExp,
        aaUnspent  = data.aaUnspent,
        aaAssigned = data.aaAssigned,
        aaTotal    = data.aaTotal,
        updatedAt = mq.gettime(),
    }
end

-- Every bot always knows its own HP with certainty and broadcasts it every
-- tick (see init.lua char_status broadcast) -- far more reliable than reading
-- a raid member's spawn HP, which is only fresh if this client is actively
-- tracking that entity (see CombatContext.lua raid-member scan).
function StatusService:getHp(name)
    local entry = self.peers[name]
    if not entry or entry.hp == nil then return nil end
    if (mq.gettime() - entry.updatedAt) >= EXPIRY_MS then return nil end
    return entry.hp
end

-- Self-reported aggro % on this peer's own current target -- the only cheap
-- way to know who a mob is actually attacking, since MQ2SpawnType has no
-- field for a mob's current target at all. Used to tell "configured tank"
-- apart from "tank currently getting hit" (see Context:isPeerTanking).
function StatusService:getAggro(name)
    local entry = self.peers[name]
    if not entry or entry.aggro == nil then return nil end
    if (mq.gettime() - entry.updatedAt) >= EXPIRY_MS then return nil end
    return entry.aggro
end

-- Self-reported dead flag (Me.Dead() is always accurate for whoever's
-- broadcasting it -- no null-spawn edge case like reading a group/raid
-- member's Dead() off their possibly-gone spawn pointer). Returns nil
-- (unknown, not confirmed alive) if we haven't heard from this peer recently.
function StatusService:isDead(name)
    local entry = self.peers[name]
    if not entry then return nil end
    if (mq.gettime() - entry.updatedAt) >= EXPIRY_MS then return nil end
    return entry.dead == true
end

function StatusService:getAll()
    local now      = mq.gettime()
    local myZone   = mq.TLO.Zone.ShortName() or ''
    local result   = {}
    for _, entry in pairs(self.peers) do
        if (now - entry.updatedAt) < EXPIRY_MS and entry.zone == myZone then
            table.insert(result, entry)
        end
    end
    table.sort(result, function(a, b)
        local ra = classOrder(a.class)
        local rb = classOrder(b.class)
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return result
end

return StatusService
