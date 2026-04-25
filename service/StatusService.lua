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
        target    = data.target,
        casting   = data.casting,
        dead      = data.dead,
        zone      = data.zone,
        class     = data.class or '',
        updatedAt = mq.gettime(),
    }
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
