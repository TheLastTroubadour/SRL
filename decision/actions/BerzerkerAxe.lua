local mq = require 'mq'

local BerzerkerAxeDecision = {}
BerzerkerAxeDecision.__index = BerzerkerAxeDecision

local LOW_REAGENT_THRESHOLD = 10
local WARN_INTERVAL         = 300000  -- 5 minutes

local function countItem(itemName)
    local total = 0
    local lower = itemName:lower()
    for slot = 0, 31 do
        local inv = mq.TLO.Me.Inventory(slot)
        if inv() then
            if (inv.Name() or ''):lower() == lower then
                total = total + (inv.StackCount() or 1)
            end
            local containerSize = inv.Container() or 0
            for s = 1, containerSize do
                local sub = inv.Item(s)
                if sub() and (sub.Name() or ''):lower() == lower then
                    total = total + (sub.StackCount() or 1)
                end
            end
        end
    end
    return total
end

function BerzerkerAxeDecision:new(config)
    local self = setmetatable({}, BerzerkerAxeDecision)
    self.name        = "BerzerkerAxeDecision"
    self.config      = config
    self.pending     = nil
    self.lastWarn    = 0
    return self
end

function BerzerkerAxeDecision:score(ctx)
    self.pending = nil

    if ctx.inCombat then return 0 end
    if ctx.casting  then return 0 end
    if ctx.dead     then return 0 end

    local cfg = self.config:get('BerzerkerAxes')
    if not cfg or not cfg.item or not cfg.ability then return 0 end

    local minimum  = cfg.minimum or 20
    local axeCount = countItem(cfg.item)
    if axeCount >= minimum then return 0 end

    -- Check reagent if configured
    if cfg.reagent then
        local reagentCount = countItem(cfg.reagent)
        local now = mq.gettime()
        if reagentCount == 0 then
            if now - self.lastWarn >= WARN_INTERVAL then
                print(string.format('[SRL] WARNING: %s is out of %s — cannot forge axes!',
                    mq.TLO.Me.Name(), cfg.reagent))
                self.lastWarn = now
            end
            return 0
        elseif reagentCount < LOW_REAGENT_THRESHOLD then
            if now - self.lastWarn >= WARN_INTERVAL then
                print(string.format('[SRL] WARNING: %s has only %d %s remaining — restock soon!',
                    mq.TLO.Me.Name(), reagentCount, cfg.reagent))
                self.lastWarn = now
            end
        end
    end

    -- Check ability is ready
    if not self:isReady(cfg) then return 0 end

    self.pending = cfg
    return 65
end

function BerzerkerAxeDecision:execute(ctx)
    if not self.pending then return end
    local cfg = self.pending
    local entryType = cfg.type or 'disc'

    if entryType == 'disc' then
        mq.cmdf('/disc "%s"', cfg.ability)
        local castTime = (mq.TLO.Spell(cfg.ability).CastTime.TotalSeconds() or 0) * 1000 + 500
        if castTime > 500 then
            mq.delay(castTime, function() return not mq.TLO.Me.Casting() end)
        end
    elseif entryType == 'aa' then
        mq.cmdf('/alt activate "%s"', cfg.ability)
        local castTime = mq.TLO.Me.AltAbility(cfg.ability).Spell.CastTime() or 0
        if castTime > 0 then
            mq.delay(castTime + 500, function() return not mq.TLO.Me.Casting() end)
        end
    elseif entryType == 'ability' then
        mq.cmdf('/doability "%s"', cfg.ability)
        mq.delay(1000)
    end
end

function BerzerkerAxeDecision:isReady(cfg)
    local entryType = cfg.type or 'disc'
    if entryType == 'disc' then
        return mq.TLO.Me.CombatAbilityReady(cfg.ability)() == true
    elseif entryType == 'aa' then
        return mq.TLO.Me.AltAbilityReady(cfg.ability)() == true
    elseif entryType == 'ability' then
        return mq.TLO.Me.AbilityReady(cfg.ability)() == true
    end
    return false
end

return BerzerkerAxeDecision
