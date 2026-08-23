local mq         = require 'mq'
local State      = require 'core.State'
local AssistUtil = require 'util.AssistUtil'

-- Automates what a human MA does by hand: target a mob, run /srl assiston.
-- Fires whenever this bot's own target is a live hostile NPC the raid isn't
-- already fighting -- covers the first pull of a session and any time this
-- bot's own target changes to something new.
local TankAssistDecision = {}
TankAssistDecision.__index = TankAssistDecision

local REPULSE_MS = 30000 -- re-announce assist on the same target periodically, cheap safety net

function TankAssistDecision:new()
    local self = setmetatable({}, TankAssistDecision)
    self.name = "TankAssistDecision"
    self.safeWhileInvis = true
    self.pendingId = nil
    self.lastBroadcastAt = 0
    return self
end

function TankAssistDecision:setPullDecision(pullDecision)
    self.pullDecision = pullDecision
end

function TankAssistDecision:score(ctx)
    self.pendingId = nil
    if State.flags.automode ~= 'tank' and State.flags.automode ~= 'tankpuller' then return 0 end

    local target = mq.TLO.Target
    local targetId = target.ID()
    local hasLiveTarget = targetId and targetId ~= 0
        and target.Type() == 'NPC' and not target.Dead() and target.Aggressive()

    -- Pull.lua drags its candidate back to camp before handing off (tickReturn/
    -- tickHandoff) -- but it aggroes and fights back out in the field well
    -- before that (tickConfirmAggro). Without this check, this fires the
    -- instant it's aggressive and broadcasts assist on a mob that's nowhere
    -- near camp yet, pulling everyone else out to chase it there. Defer to
    -- Pull's own handoff, which already waits for arrival + LoS.
    if hasLiveTarget and self.pullDecision
            and self.pullDecision.state ~= 'idle'
            and self.pullDecision.candidateId == targetId then
        return 0
    end

    if not hasLiveTarget then
        -- Nothing useful targeted -- if something's already aggressive (an
        -- add, a mob that got pulled indirectly, a pull we just abandoned)
        -- and nobody's called assist on it, pick it up directly rather than
        -- just sitting there with a stale/no target waiting for a human to
        -- manually retarget.
        local pick = self:findUnclaimedAggressive(ctx)
        if not pick then return 0 end
        self.pendingId = pick
        return 93
    end

    -- Same id AND name as our last broadcast -- genuinely the same ongoing
    -- engagement (id alone isn't a safe match: EQ recycles spawn ids, so a
    -- later mob could reuse an old target's id). Still re-pulse periodically
    -- as a cheap safety net in case a broadcast ever got missed.
    local sameEngagement = tostring(targetId) == tostring(State.assist.targetId)
        and target.CleanName() == State.assist.targetName
    if sameEngagement and mq.gettime() - self.lastBroadcastAt < REPULSE_MS then
        return 0
    end

    self.pendingId = targetId
    return 93
end

-- First aggressive NPC on xtarget that isn't already the active raid assist
-- target (that one's already being handled by AssistDecision) and isn't
-- Pull's own in-progress candidate (not at camp yet -- same reasoning as
-- the check in score()).
function TankAssistDecision:findUnclaimedAggressive(ctx)
    local pullCandidateId = self.pullDecision and self.pullDecision.state ~= 'idle'
        and self.pullDecision.candidateId or nil
    for _, xt in ipairs(ctx.xtargets or {}) do
        if xt.type == 'NPC' and not xt.dead and xt.aggressive
                and tostring(xt.id) ~= tostring(State.assist.targetId)
                and (not pullCandidateId or tostring(xt.id) ~= tostring(pullCandidateId)) then
            return xt.id
        end
    end
    return nil
end

function TankAssistDecision:execute(ctx)
    if not self.pendingId then return end
    AssistUtil.broadcastAssist(self.pendingId)
    self.lastBroadcastAt = mq.gettime()
end

return TankAssistDecision
