local mq    = require 'mq'
local State = require 'srl.core.State'

local FOLLOW_DIST_THRESHOLD = 15   -- yards before we re-issue stick
local FOLLOW_RECHECK_MS     = 2000 -- don't re-issue stick more than once per 2s

local MovementDecision = {}
MovementDecision.__index = MovementDecision

function MovementDecision:new()
    local self = setmetatable({}, MovementDecision)
    self.name            = "MovementDecision"
    self.lastStickIssued = 0
    return self
end

function MovementDecision:score(ctx)
    -- Emergency: a move was commanded (works in and out of combat)
    if State.move.active then
        return 200
    end

    -- Normal out-of-combat follow
    if ctx.inCombat then return 0 end
    if not State.follow.active or not State.follow.followId then return 0 end

    local now = mq.gettime()
    if now - self.lastStickIssued < FOLLOW_RECHECK_MS then return 0 end

    local spawn = mq.TLO.Spawn('id ' .. State.follow.followId)
    if not spawn() or spawn.Dead() then return 0 end

    local dist = spawn.Distance() or 0
    if dist > FOLLOW_DIST_THRESHOLD then
        return 0.5
    end

    return 0
end

function MovementDecision:execute(ctx)
    if State.move.active then
        -- Cancel all current actions and move to target
        mq.cmd('/stopcast')
        mq.cmd('/attack off')
        mq.cmd('/stick off')
        mq.cmd('/afollow off')

        if State.move.targetId then
            mq.cmdf('/target id %s', State.move.targetId)
            mq.delay(100)
            mq.cmd('/stick 5')
        end

        State:clearMove()
        return
    end

    -- Normal follow: re-issue stick on follow target
    if State.follow.active and State.follow.followId then
        mq.cmdf('/target id %s', State.follow.followId)
        mq.delay(100)
        mq.cmd('/stick 5')
        self.lastStickIssued = mq.gettime()
    end
end

return MovementDecision
