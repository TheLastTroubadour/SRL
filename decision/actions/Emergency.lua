local EmergencyDecision = {}

function EmergencyDecision:score(ctx)

    local hp = ctx.group.lowestHP or 100

    if hp > 50 then
        return 0
    end

    local missing = 100 - hp

    return (missing / 100)^2
end

function EmergencyDecision:execute(ctx)
    mq.cast("Remedy")
end

return EmergencyDecision