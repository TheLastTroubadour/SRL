local mq = require 'mq'
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
        return 90
    end

    return 0
end

function AssistDecision:execute(ctx)

    mq.cmdf('/target id %s', ctx.assist.Id)
    mq.delay(150)

    mq.cmdf('/stick behind 10 moveback uw')
    mq.delay(50)
    mq.cmd('/attack on')
end

return AssistDecision
