local mq = require 'mq'

local COUNTER_TYPES       = { 'Poison', 'Disease', 'Curse', 'Corruption' }
local CHECK_INTERVAL_MS   = 3000
local BROADCAST_COOLDOWN_MS = 8000

local CureService = {}
CureService.__index = CureService

function CureService:new()
    local self = setmetatable({}, CureService)
    self.nextCheck        = 0
    self.broadcastCooldown = 0
    return self
end

-- Called every main loop tick. Detects own affliction counters and broadcasts
-- a NeedCure event via dgae so any configured curer on the network can respond.
function CureService:update()
    local now = mq.gettime()
    if now < self.nextCheck then return end
    self.nextCheck = now + CHECK_INTERVAL_MS

    local needed = {}
    for _, t in ipairs(COUNTER_TYPES) do
        if mq.TLO.Me['Counters' .. t]() > 0 then
            table.insert(needed, t)
        end
    end

    -- No counters: reset cooldown so next affliction broadcasts immediately
    if #needed == 0 then
        self.broadcastCooldown = 0
        return
    end

    if now < self.broadcastCooldown then return end

    local types = table.concat(needed, ',')
    mq.cmdf('/dgae /srlevent NeedCure id=%s name=%s types=%s sender=%s',
        mq.TLO.Me.ID(), mq.TLO.Me.Name(), types, mq.TLO.Me.Name())

    self.broadcastCooldown = now + BROADCAST_COOLDOWN_MS
end

return CureService
