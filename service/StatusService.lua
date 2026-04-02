local mq = require 'mq'

local StatusService = {}
StatusService.__index = StatusService

local EXPIRY_MS = 15000

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
        target    = data.target,
        casting   = data.casting,
        dead      = data.dead,
        zone      = data.zone,
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
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

return StatusService
