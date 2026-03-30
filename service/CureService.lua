local mq = require 'mq'

local CHECK_INTERVAL_MS     = 3000
local BROADCAST_COOLDOWN_MS = 8000
local CURABLE_TYPES         = { Poison = true, Disease = true, Curse = true, Corruption = true }

local CureService = {}
CureService.__index = CureService

function CureService:new(config)
    local self = setmetatable({}, CureService)
    self.config           = config
    self.nextCheck        = 0
    self.broadcastCooldown = 0
    return self
end

function CureService:isIgnored(buffName)
    local ignoreList = self.config:get('Cures.IgnoreList') or {}
    for _, name in ipairs(ignoreList) do
        if name:lower() == buffName:lower() then return true end
    end
    return false
end

-- Called every main loop tick. Detects own affliction counters and broadcasts
-- a NeedCure event via dgae so any configured curer on the network can respond.
function CureService:update()
    if mq.TLO.Me.Dead() then return end
    local now = mq.gettime()
    if now < self.nextCheck then return end
    self.nextCheck = now + CHECK_INTERVAL_MS

    local types     = {}
    local buffNames = {}
    local seenTypes = {}
    local seenNames = {}
    local slots     = mq.TLO.Me.MaxBuffSlots() or 42

    for i = 1, slots do
        local buff = mq.TLO.Me.Buff(i)
        if buff() and buff.SpellType() == 'Detrimental' then
            local ct   = buff.CounterType()
            local name = buff.Name()
            if ct and CURABLE_TYPES[ct] and not seenTypes[ct] then
                local counters = mq.TLO.Me['Counters' .. ct]()
                if counters and counters > 0 then
                    seenTypes[ct] = true
                    table.insert(types, ct)
                    if name and not seenNames[name] and not self:isIgnored(name) then
                        seenNames[name] = true
                        table.insert(buffNames, (name:gsub(' ', '_')))
                    end
                end
            end
        end
    end

    -- No detrimental buffs: reset cooldown so next affliction broadcasts immediately
    if #types == 0 then
        self.broadcastCooldown = 0
        return
    end

    if now < self.broadcastCooldown then return end

    mq.cmdf('/dgae /srlevent NeedCure id=%s name=%s types=%s buff=%s sender=%s',
        mq.TLO.Me.ID(), mq.TLO.Me.Name(),
        table.concat(types, ','), table.concat(buffNames, ','),
        mq.TLO.Me.Name())

    self.broadcastCooldown = now + BROADCAST_COOLDOWN_MS
end

function CureService:reset()
    self.nextCheck         = 0
    self.broadcastCooldown = 0
end

return CureService
