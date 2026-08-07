local mq         = require 'mq'
local State      = require 'core.State'
local AssistUtil = require 'util.AssistUtil'

-- When the current assist target dies but other aggressive mobs remain in
-- XTarget (chain-pull adds, etc.), the bot that owns the Assist broadcast
-- (puller hand-off, tank auto-assiston, or manual /srl assiston) re-broadcasts
-- at the next live threat so the raid doesn't stall waiting for a human.
local AssistAdvanceDecision = {}
AssistAdvanceDecision.__index = AssistAdvanceDecision

function AssistAdvanceDecision:new()
    local self = setmetatable({}, AssistAdvanceDecision)
    self.name = "AssistAdvanceDecision"
    self.safeWhileInvis = true  -- broadcasting an id doesn't break invis
    self.nextId = nil
    return self
end

function AssistAdvanceDecision:score(ctx)
    self.nextId = nil
    if State.assist.sender ~= mq.TLO.Me.Name() then return 0 end
    if not ctx.assist.dead then return 0 end

    local bestId, bestDist = nil, math.huge
    for _, xt in ipairs(ctx.xtargets) do
        if xt.type == 'NPC' and not xt.dead and xt.aggressive and xt.id ~= State.charm.petId then
            local spawn = mq.TLO.Spawn('id ' .. xt.id)
            local dist = spawn() and spawn.Distance() or math.huge
            if dist < bestDist then bestDist, bestId = dist, xt.id end
        end
    end
    if not bestId then return 0 end

    self.nextId = bestId
    return 91
end

function AssistAdvanceDecision:execute(ctx)
    if not self.nextId then return end
    AssistUtil.broadcastAssist(self.nextId)
end

return AssistAdvanceDecision
