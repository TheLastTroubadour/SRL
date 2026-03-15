local MovementDecision = {}

function MovementDecision:score(ctx)

    if ctx.combat.inCombat then
        return 0
    end

    if ctx.followDistance and ctx.followDistance > 20 then
        return 0.5
    end

    return 0
end

function MovementDecision:execute(ctx)

    if ctx.followTarget then
        mq.cmd("/stick hold " .. ctx.followTarget)
    end

end

return MovementDecision