local mq         = require 'mq'
local State      = require 'core.State'
local AssistUtil = require 'util.AssistUtil'

-- Automates what a human MA does by hand: target a mob, run /srl assiston.
-- Fires whenever this bot's own target is a live hostile NPC the raid isn't
-- already fighting -- covers the first pull of a session and any time this
-- bot's own target changes to something new.
local TankAssistDecision = {}
TankAssistDecision.__index = TankAssistDecision

local REPULSE_MS = 10000 -- re-announce assist on the same target periodically, cheap safety net

function TankAssistDecision:new()
    local self = setmetatable({}, TankAssistDecision)
    self.name = "TankAssistDecision"
    self.safeWhileInvis = true
    self.pendingId = nil
    self.lastBroadcastAt = 0
    return self
end

function TankAssistDecision:score(ctx)
    self.pendingId = nil
    if State.flags.automode ~= 'tank' and State.flags.automode ~= 'tankpuller' then return 0 end

    local target = mq.TLO.Target
    local targetId = target.ID()
    if not targetId or targetId == 0 then return 0 end
    if target.Type() ~= 'NPC' or target.Dead() then return 0 end
    if not target.Aggressive() then return 0 end

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

function TankAssistDecision:execute(ctx)
    if not self.pendingId then return end
    AssistUtil.broadcastAssist(self.pendingId)
    self.lastBroadcastAt = mq.gettime()
end

return TankAssistDecision
