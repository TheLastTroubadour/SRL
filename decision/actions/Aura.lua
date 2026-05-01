local mq = require 'mq'

local AuraDecision = {}
AuraDecision.__index = AuraDecision

function AuraDecision:new(config, melodyService)
    local self = setmetatable({}, AuraDecision)
    self.name = "AuraDecision"
    self.config = config
    self.melodyService = melodyService
    self.pendingAura = nil
    return self
end

function AuraDecision:score(ctx)
    self.pendingAura = nil

    if ctx.casting then return 0 end
    if ctx.assist.Id then return 0 end

    local inCombat = (ctx.numberOfAggresiveInXTar and ctx.numberOfAggresiveInXTar > 0)
                  or ctx.inCombat
    if inCombat then return 0 end

    if not self.config:get('Aura.CastAura') then return 0 end

    local aura = self.config:get('Aura.Aura')
    if not aura or not aura.spell or aura.spell == '' then return 0 end

    if self:isActive(aura.spell) then return 0 end

    local auraType = aura.type or 'spell'
    if auraType == 'aa' then
        if not mq.TLO.Me.AltAbilityReady(aura.spell)() then return 0 end
    elseif auraType == 'disc' then
        if not mq.TLO.Me.CombatAbilityReady(aura.spell)() then return 0 end
    else
        if not mq.TLO.Me.SpellReady(aura.spell)() then return 0 end
    end

    self.pendingAura = aura
    return 85
end

function AuraDecision:execute(ctx)
    if not self.pendingAura then return end

    local aura = self.pendingAura
    local auraType = aura.type or 'spell'

    -- Bards must stop twisting before casting, then resume afterward
    local resumeMelody = nil
    if self.melodyService and mq.TLO.Me.Class.ShortName() == 'BRD' then
        resumeMelody = self.melodyService.active
        self.melodyService:stop()
        mq.delay(100)
    end

    if auraType == 'aa' then
        mq.cmdf('/alt activate "%s"', aura.spell)
        mq.delay(500)
    elseif auraType == 'disc' then
        mq.cmdf('/disc %s', aura.spell)
        mq.delay(500)
    else
        local gem = mq.TLO.Me.Gem(aura.spell)() or aura.gem
        if not gem then return end
        local isBard = mq.TLO.Me.Class.ShortName() == 'BRD'
        local castTime = isBard and 4000 or ((mq.TLO.Spell(aura.spell).CastTime() or 2000) + 1500)
        mq.cmdf('/cast %s', gem)
        mq.delay(1000, function() return mq.TLO.Me.Casting() ~= nil end)
        mq.delay(castTime, function() return not mq.TLO.Me.Casting() end)
    end

    if resumeMelody then
        self.melodyService:play(resumeMelody)
    end
end

function AuraDecision:isActive(spellName)
    local base = spellName:gsub('%s+Rk%.%s*%a+$', '')
    for i = 1, 2 do
        local active = mq.TLO.Me.Aura(i)()
        if active then
            local activeBase = active:gsub('%s+Rk%.%s*%a+$', '')
            if activeBase == base then return true end
        end
    end
    return false
end

return AuraDecision
