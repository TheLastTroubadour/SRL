local mq         = require 'mq'
local State      = require 'core.State'
local AssistUtil = require 'util.AssistUtil'

-- Automates what a human MA does by hand: target a mob, run /srl assiston.
-- Fires whenever this bot's own target is a live hostile NPC the raid isn't
-- already fighting -- covers the first pull of a session and any time this
-- bot's own target changes to something new.
local TankAssistDecision = {}
TankAssistDecision.__index = TankAssistDecision

function TankAssistDecision:new()
    local self = setmetatable({}, TankAssistDecision)
    self.name = "TankAssistDecision"
    self.safeWhileInvis = true
    self.pendingId = nil
    return self
end

function TankAssistDecision:score(ctx)
    self.pendingId = nil
    if State.flags.automode ~= 'tank' then return 0 end

    local target = mq.TLO.Target
    local targetId = target.ID()
    if not targetId or targetId == 0 then return 0 end
    if target.Type() ~= 'NPC' or target.Dead() then return 0 end
    if not target.Aggressive() then return 0 end
    if tostring(targetId) == tostring(State.assist.targetId) then return 0 end

    self.pendingId = targetId
    return 93
end

function TankAssistDecision:execute(ctx)
    if not self.pendingId then return end
    AssistUtil.broadcastAssist(self.pendingId)
end

return TankAssistDecision
