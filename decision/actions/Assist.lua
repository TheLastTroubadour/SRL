local mq = require 'mq'
local Target = require 'service.TargetService'
local State  = require 'core.State'
local AssistDecision = {}
AssistDecision.__index = AssistDecision


function AssistDecision:new()
    local self = setmetatable({}, AssistDecision)
    self.name = "AssistDecision"
    return self
end

function AssistDecision:score(ctx)

    if not ctx.assist.Id then
        return 0
    end

    -- Never assist (attack/stick) while FD — would cause puller to stand up
    if State.flags.isPuller and mq.TLO.Me.Feigning() then
        return 0
    end

    if ctx.assist.assistType:lower() == 'off' then
        return 0
    end

    if ctx.isForeground then
        return 0
    end

    if not ctx.myCurrentTargetId then
        return 90
    end

    if tonumber(ctx.assist.Id) ~= tonumber(ctx.myCurrentTargetId) then
        return 90
    end

    if ctx.assist.dead then
        mq.cmd('/attack off')
        return 0
    end

    if not ctx.inCombat then
        return 90
    end

    if not mq.TLO.Stick.Active() then
        return 90
    end

    return 0
end

function AssistDecision:execute(ctx)

    Target:getTargetById(ctx.assist.Id)

    mq.cmdf('/stick %s %s moveback uw', ctx.assist.stickPoint, ctx.assist.stickDistance)
    mq.delay(50)
    mq.cmd('/attack on')
end

return AssistDecision
