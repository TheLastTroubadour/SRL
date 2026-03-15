local mq = require 'mq'

local ResourceDecision = {}
ResourceDecision.__index = ResourceDecision

function ResourceDecision:new()
    local self = setmetatable({}, ResourceDecision)
    self.__index = self
    self.active = false
    self.startThreshold = 20
    self.stopThreshold = 100
    self.name = "ResourceDecision"

    return self
end

function ResourceDecision:score(ctx)

    local mana = ctx.mana

    if ctx.isForeground then
        return 0
    end

    if ctx.numberOfAggresiveInXTar and ctx.numberOfAggresiveInXTar > 0 then
        self.active = false
        return 0
    end

    if ctx.roles['caster'] or ctx.roles['healer'] or ctx.roles['hybrid'] then

        if self.active and ctx.assist.Id then
            self.active = false
            return 0
        end

        if self.active and mana >= self.stopThreshold then
            self.active = false
            return 0
        end

        if self.active then
            return 90
        end

        if mana < self.startThreshold then
            self.active = true
            return 100
        end
    end

    return 0
end

function ResourceDecision:execute(ctx)

    if not mq.TLO.Me.Sitting() then
        mq.cmd("/sit")
    end

end

return ResourceDecision