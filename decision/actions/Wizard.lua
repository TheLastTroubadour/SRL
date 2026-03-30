local mq = require 'mq'

local WizardDecision = {}
WizardDecision.__index = WizardDecision

function WizardDecision:new(config)
    local self = setmetatable({}, WizardDecision)
    self.name    = "WizardDecision"
    self.config  = config
    self.pending = nil
    return self
end

function WizardDecision:score(ctx)
    self.pending = nil

    if ctx.casting then return 0 end
    if mq.TLO.Me.Class.ShortName() ~= 'WIZ' then return 0 end
    if not self.config:get('Wizard.AutoHarvest') then return 0 end

    local harvests = self.config:get('Wizard.Harvest') or {}
    for _, entry in ipairs(harvests) do
        local threshold = entry.manaThreshold or self.config:get('Wizard.HarvestThreshold') or 50
        if ctx.mana < threshold and self:isReady(entry) then
            self.pending = entry
            return 97
        end
    end

    return 0
end

function WizardDecision:execute(ctx)
    if not self.pending then return end

    if self.pending.type == 'aa' then
        mq.cmdf('/alt activate "%s"', self.pending.name)
    elseif self.pending.type == 'spell' then
        local gem = mq.TLO.Me.Gem(self.pending.name)() or self.pending.gem
        if not gem then return end
        mq.cmdf('/cast %s', gem)
    end
end

function WizardDecision:isReady(entry)
    if entry.type == 'aa' then
        return mq.TLO.Me.AltAbilityReady(entry.name)() == true
    elseif entry.type == 'spell' then
        return mq.TLO.Me.SpellReady(entry.name)() == true
    end
    return false
end

return WizardDecision
