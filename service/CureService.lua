local mq = require 'mq'

local CHECK_INTERVAL_MS     = 3000
local BROADCAST_COOLDOWN_MS = 8000

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

-- Called every main loop tick. Detects all detrimental buffs (not just ones
-- carrying a Poison/Disease/Curse/Corruption counter) and broadcasts a
-- NeedCure event via dgae so any configured curer on the network can respond.
-- Cure type sent per debuff is its CounterType when present, else the debuff's
-- own name (underscored) as a pseudo-type — lets Cures.Spells entries target
-- a specific uncountered debuff by name instead of only the four counter types.
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
            local name = buff.Name()
            if name and not seenNames[name] and not self:isIgnored(name) then
                seenNames[name] = true
                local underscored = name:gsub(' ', '_')
                table.insert(buffNames, underscored)

                -- CounterType() returns the literal string "None" for an
                -- uncountered debuff, not nil/empty -- without this check that
                -- passes straight through as a meaningless "None" cure type
                -- instead of falling back to the debuff's own name.
                local ct = buff.CounterType()
                local cureType = (ct and ct ~= '' and ct ~= 'None' and ct) or underscored
                if not seenTypes[cureType] then
                    seenTypes[cureType] = true
                    table.insert(types, cureType)
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
