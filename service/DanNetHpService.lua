local mq     = require 'mq'
local DanNet = require 'DanNet'

-- Sets up a persistent DanNet observer (${Me.PctHPs}) on every connected
-- DanNet peer's own client, not just configured tanks -- covers the whole
-- bot network automatically as people connect/disconnect. Unlike our own
-- char_status broadcast (gated behind each bot's main loop, which freezes
-- during mq.delay while that bot is mid-cast), DanNet's observer push is
-- driven by its own native plugin on the peer's end, so it isn't blocked by
-- whatever that peer's Lua script happens to be doing.
local DanNetHpService = {}
DanNetHpService.__index = DanNetHpService

local RESCAN_INTERVAL_MS = 30000
local HP_QUERY = '${Me.PctHPs}'

function DanNetHpService:new()
    local self = setmetatable({}, DanNetHpService)
    self.observed  = {} -- [charName] = true once an observer is set up
    self.lastScan  = 0
    return self
end

function DanNetHpService:getPeerNames()
    local names = {}
    local peerString = mq.TLO.DanNet.Peers() or ''
    for peer in peerString:gmatch('[^|]+') do
        local charName = peer:match('_(.+)') or peer
        if charName and charName ~= '' then
            table.insert(names, charName)
        end
    end
    return names
end

-- Rate-limited internally -- safe to call every tick.
function DanNetHpService:ensureObservers()
    local now = mq.gettime()
    if now - self.lastScan < RESCAN_INTERVAL_MS then return end
    self.lastScan = now

    for _, name in ipairs(self:getPeerNames()) do
        if not self.observed[name] then
            self.observed[name] = true
            DanNet.create_observer(name, HP_QUERY, 0) -- timeout=0: fire /dobserve, don't block waiting on it
        end
    end
end

-- Cheap local read of the last-pushed value -- no network round-trip.
function DanNetHpService:getHp(name)
    if not name or not self.observed[name] then return nil end
    local value = DanNet.read_observer(name, HP_QUERY)
    return tonumber(value)
end

return DanNetHpService
