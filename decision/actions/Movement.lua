local mq    = require 'mq'
local State = require 'core.State'
local Target = require 'service.TargetService'

local FOLLOW_DIST_THRESHOLD = 15   -- yards before we re-issue nav
local FOLLOW_RECHECK_MS     = 250  -- don't re-issue nav more than once per 250ms
local FOLLOW_MAX_DIST       = 550  -- yards before giving up on follow
local TOO_FAR_WARN_MS       = 10000 -- only warn once per 10s

local MovementDecision = {}
MovementDecision.__index = MovementDecision

function MovementDecision:new()
    local self = setmetatable({}, MovementDecision)
    self.name            = "MovementDecision"
    self.lastStickIssued = 0
    self.lastTooFarWarn  = 0
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

    -- Too far: stop following and announce
    if dist > FOLLOW_MAX_DIST then
        mq.cmd('/stick off')
        mq.cmd('/nav stop')
        State:stopFollow()
        if now - self.lastTooFarWarn > TOO_FAR_WARN_MS then
            mq.cmdf('/dgt all [%s] too far from follow target (%.0f yards) -- follow stopped',
                mq.TLO.Me.Name(), dist)
            self.lastTooFarWarn = now
        end
        return 0
    end

    if dist > FOLLOW_DIST_THRESHOLD then
        return 10
    end

    return 0
end

function MovementDecision:execute(ctx)
    if State.move.active then
        -- Cancel all current actions and move to target
        mq.cmd('/stopcast')
        mq.cmd('/attack off')
        mq.cmd('/stick off')
        mq.cmd('/nav stop')

        if State.move.targetId then
            Target:getTargetById(State.move.targetId)
            mq.cmd('/stick 5')
        end

        State:clearMove()
        return
    end

    -- Normal follow: re-issue movement on follow target
    if State.follow.active and State.follow.followId then
        if State.follow.mode == 'nav' then
            mq.cmdf('/nav id %s', State.follow.followId)
        else
            Target:getTargetById(State.follow.followId)
            mq.cmd('/stick 5')
        end
        self.lastStickIssued = mq.gettime()
    end
end

return MovementDecision
