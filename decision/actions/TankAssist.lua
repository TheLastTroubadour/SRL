local mq         = require 'mq'
local State      = require 'core.State'
local AssistUtil = require 'util.AssistUtil'
local MoveUtil   = require 'util.MoveUtil'

-- Automates what a human MA does by hand: target a mob, run /srl assiston.
-- Fires whenever this bot's own target is a live hostile NPC the raid isn't
-- already fighting -- covers the first pull of a session and any time this
-- bot's own target changes to something new.
local TankAssistDecision = {}
TankAssistDecision.__index = TankAssistDecision

local REPULSE_MS = 30000 -- re-announce assist on the same target periodically, cheap safety net

function TankAssistDecision:new(config)
    local self = setmetatable({}, TankAssistDecision)
    self.name = "TankAssistDecision"
    self.config = config
    self.safeWhileInvis = true
    self.pendingId = nil
    self.lastBroadcastAt = 0
    return self
end

-- Ground-truth check, independent of Pull.lua's own internal state tracking:
-- is this candidate actually near camp with LoS on us? Pull's state can get
-- out of sync with reality (aborts back to 'idle' on a mid-cycle safety net
-- without the mob having gone anywhere -- see the mid-drag abort in Pull.lua),
-- so gating solely on "Pull thinks it's still working on it" isn't reliable.
-- No camp set at all means there's no camp concept in play -- don't gate.
function TankAssistDecision:nearCampWithLoS(spawnId)
    local camp = State.pull.camp
    if not camp then return true end

    local spawn = mq.TLO.Spawn('id ' .. tostring(spawnId))
    if not spawn() then return false end
    if not spawn.LineOfSight() then return false end

    local returnDist = (self.config and self.config:get('Pull.ReturnDist')) or 15
    local dist = MoveUtil.pathLengthToLoc(camp.x, camp.y, camp.z)
    return dist ~= nil and dist <= returnDist
end

function TankAssistDecision:score(ctx)
    self.pendingId = nil
    if State.flags.automode ~= 'tank' and State.flags.automode ~= 'tankpuller' then return 0 end

    local target = mq.TLO.Target
    local targetId = target.ID()
    -- Camp/LoS check is part of what makes a target "usable" here, not a
    -- separate early-out -- otherwise a stale/irrelevant current target that
    -- fails it short-circuits before ever falling through to check whether
    -- something else nearby (e.g. an already-mezzed add sitting at camp) is
    -- actually ready to engage.
    local hasLiveTarget = targetId and targetId ~= 0
        and target.Type() == 'NPC' and not target.Dead() and target.Aggressive()
        and self:nearCampWithLoS(targetId)

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
-- target (that one's already being handled by AssistDecision) and is
-- actually near camp with LoS -- see nearCampWithLoS.
function TankAssistDecision:findUnclaimedAggressive(ctx)
    for _, xt in ipairs(ctx.xtargets or {}) do
        if xt.type == 'NPC' and not xt.dead and xt.aggressive
                and tostring(xt.id) ~= tostring(State.assist.targetId)
                and self:nearCampWithLoS(xt.id) then
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
