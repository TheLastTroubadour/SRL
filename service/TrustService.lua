local mq = require 'mq'

local TrustService = {}
TrustService.__index = TrustService

function TrustService:new(config)
    local self = setmetatable({}, TrustService)
    self.config = config
    return self
end

function TrustService:isTrusted(name)
    if not name or name == '' then return false end
    local lower = name:lower()

    -- DanNet peers (format: "server_charname" — strip prefix)
    local peerString = mq.TLO.DanNet.Peers() or ''
    for peer in peerString:gmatch('[^|]+') do
        local charName = peer:match('_(.+)') or peer
        if charName:lower() == lower then return true end
    end

    -- Whitelist from config
    local whitelist = self.config:get('Trusted.Whitelist') or {}
    for _, entry in ipairs(whitelist) do
        if tostring(entry):lower() == lower then return true end
    end

    -- Group members
    local groupSize = mq.TLO.Group.Members() or 0
    for i = 1, groupSize do
        local m = mq.TLO.Group.Member(i)
        if m() and (m.CleanName() or ''):lower() == lower then return true end
    end

    -- Raid members
    local raidSize = mq.TLO.Raid.Members() or 0
    for i = 1, raidSize do
        local r = mq.TLO.Raid.Member(i)
        if r() and (r.CleanName() or ''):lower() == lower then return true end
    end

    return false
end

return TrustService
