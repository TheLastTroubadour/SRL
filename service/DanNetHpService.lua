local mq     = require 'mq'
local DanNet = require 'DanNet'

-- Sets up persistent DanNet observers (${Me.PctHPs}/${Me.PctMana}/${Me.PctEndurance})
-- on every connected DanNet peer's own client, not just configured tanks --
-- covers the whole bot network automatically as people connect/disconnect.
-- Unlike our own char_status broadcast (gated behind each bot's main loop,
-- which freezes during mq.delay while that bot is mid-cast), DanNet's observer
-- push is driven by its own native plugin on the peer's end, so it isn't
-- blocked by whatever that peer's Lua script happens to be doing. And unlike
-- Spawn.MaxMana/PctMana (unreliable for anyone but yourself -- not a real
-- GroupMember field, falls through to spawn data), this is the peer
-- self-reporting its own value, no reliability question at all.
local DanNetHpService = {}
DanNetHpService.__index = DanNetHpService

local RESCAN_INTERVAL_MS = 30000

local QUERIES = {
    hp        = 'Me.PctHPs',
    mana      = 'Me.PctMana',
    endurance = 'Me.PctEndurance',
}

function DanNetHpService:new()
    local self = setmetatable({}, DanNetHpService)
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

-- Rate-limited internally -- safe to call every tick. Re-issues (drop +
-- recreate, see DanNet.create_observer) for every known peer on every scan,
-- rather than latching "confirmed" after one successful read and stopping --
-- a read succeeding only proves SOME value exists, never that it's still
-- being actively refreshed (plugin-side observer entries can go stale/dead
-- silently with no expiry of their own, confirmed live). Re-doing the drop+
-- recreate periodically is what actually guards against that, since a plain
-- re-/dobserve on an already-registered entry is a no-op either way.
function DanNetHpService:ensureObservers()
    local now = mq.gettime()
    if now - self.lastScan < RESCAN_INTERVAL_MS then return end
    self.lastScan = now

    local myName = mq.TLO.Me.Name():lower()
    for _, name in ipairs(self:getPeerNames()) do
        if name:lower() ~= myName then
            for _, query in pairs(QUERIES) do
                DanNet.create_observer(name, query, 0) -- timeout=0: fire /dobserve, don't block waiting on it
            end
        end
    end
end

-- Cheap local reads of the last-pushed values -- no network round-trip.
function DanNetHpService:getHp(name)
    if not name then return nil end
    return tonumber(DanNet.read_observer(name, QUERIES.hp))
end

function DanNetHpService:getMana(name)
    if not name then return nil end
    return tonumber(DanNet.read_observer(name, QUERIES.mana))
end

function DanNetHpService:getEndurance(name)
    if not name then return nil end
    return tonumber(DanNet.read_observer(name, QUERIES.endurance))
end

return DanNetHpService
