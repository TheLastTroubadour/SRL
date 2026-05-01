local mq    = require 'mq'
local State = require 'core.State'

local ResourceDecision = {}
ResourceDecision.__index = ResourceDecision

function ResourceDecision:new(melodyService)
    local self = setmetatable({}, ResourceDecision)
    self.__index = self
    self.active = false
    self.startThreshold = 20
    self.stopThreshold = 100
    self.name = "ResourceDecision"
    self.melodyService = melodyService
    self.suppressUntil = 0

    return self
end

function ResourceDecision:suppressFor(seconds)
    self.suppressUntil = mq.gettime() + (seconds * 1000)
    self.active = false
end

function ResourceDecision:score(ctx)

    if State.flags.medDisabled then return 0 end

    if mq.gettime() < self.suppressUntil then
        return 0
    end

    if ctx.isForeground then
        return 0
    end

    if ctx.numberOfAggresiveInXTar and ctx.numberOfAggresiveInXTar > 0 then
        self.active = false
        return 0
    end

    if ctx.assist.Id and not State.flags.isPuller then
        self.active = false
        return 0
    end

    local needMana = (ctx.roles['caster'] or ctx.roles['healer'] or ctx.roles['hybrid'])
                     and ctx.mana ~= nil
    local needEndurance = (ctx.roles['melee'] or ctx.roles['hybrid'])
                          and ctx.endurance ~= nil

    local low = false
    local full = true

    if needMana then
        if ctx.mana < self.startThreshold then low = true end
        if ctx.mana < self.stopThreshold then full = false end
    end

    if needEndurance then
        if ctx.endurance < self.startThreshold then low = true end
        if ctx.endurance < self.stopThreshold then full = false end
    end

    if self.active and full then
        self.active = false
        return 0
    end

    if self.active then
        return 90
    end

    if low then
        self.active = true
        return 100
    end

    return 0
end

function ResourceDecision:execute(ctx)

    if ctx.myClass == 'BRD' and self.melodyService then
        mq.cmd('/stopsong')
    end

    if not mq.TLO.Me.Sitting() then
        mq.cmd("/sit")
    end

end

return ResourceDecision