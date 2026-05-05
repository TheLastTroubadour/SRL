local mq = require 'mq'

local WizardDecision = {}
WizardDecision.__index = WizardDecision

function WizardDecision:new(config)
    local self = setmetatable({}, WizardDecision)
    self.name           = "WizardDecision"
    self.config         = config
    self.pending        = nil
    self.castTimestamps = {}   -- [spellName] = ms timestamp of last cast
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
        self.castTimestamps[self.pending.name] = mq.gettime()
    end
end

function WizardDecision:isReady(entry)
    if entry.type == 'aa' then
        return mq.TLO.Me.AltAbilityReady(entry.name)() == true
    elseif entry.type == 'spell' then
        if not mq.TLO.Me.SpellReady(entry.name)() then return false end
        -- SpellReady only checks the short gem refresh timer, not the spell's long reuse
        -- timer. Track our own cast time and compare against the spell's recast time.
        local lastCast = self.castTimestamps[entry.name] or 0
        if lastCast > 0 then
            local recastMs = mq.TLO.Spell(entry.name).RecastTime() or 0
            if recastMs > 0 and (mq.gettime() - lastCast) < recastMs then
                return false
            end
        end
        return true
    end
    return false
end

return WizardDecision
