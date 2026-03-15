local CCDecision = {}

function CCDecision:score(ctx)

    if ctx.combat.addCount == 0 then
        return 0
    end

    local adds = ctx.combat.addCount

    local score = math.min(adds * 0.4, 1)

    return score
end

function CCDecision:execute(ctx)
    mq.cast("Mesmerize")
end

return CCDecision