local mq = require 'mq'

local AuraDecision = {}
AuraDecision.__index = AuraDecision

function AuraDecision:new(config)
    local self = setmetatable({}, AuraDecision)
    self.name = "AuraDecision"
    self.config = config
    self.pendingAura = nil
    return self
end

function AuraDecision:score(ctx)
    self.pendingAura = nil

    if ctx.casting then return 0 end
    if ctx.assist.Id then return 0 end

    if not self.config:get('Aura.CastAura') then return 0 end

    local aura = self.config:get('Aura.Aura')
    if not aura or not aura.spell or aura.spell == '' then return 0 end

    if self:isActive(aura.spell) then return 0 end

    local auraType = aura.type or 'spell'
    if auraType == 'aa' then
        if not mq.TLO.Me.AltAbilityReady(aura.spell)() then return 0 end
    else
        if not mq.TLO.Cast.Ready(aura.spell)() then return 0 end
    end

    self.pendingAura = aura
    return 85
end

function AuraDecision:execute(ctx)
    if not self.pendingAura then return end

    local aura = self.pendingAura
    local auraType = aura.type or 'spell'

    if auraType == 'aa' then
        mq.cmdf('/alt activate "%s"', aura.spell)
    else
        mq.cmdf('/casting "%s"|%s', aura.spell, aura.gem)
    end
end

function AuraDecision:isActive(spellName)
    for i = 1, 2 do
        if mq.TLO.Me.Aura(i)() == spellName then
            return true
        end
    end
    return false
end

return AuraDecision
