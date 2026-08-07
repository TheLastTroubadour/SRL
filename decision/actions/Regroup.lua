local mq       = require 'mq'
local State    = require 'core.State'
local MoveUtil = require 'util.MoveUtil'

-- Low-priority idle-time housekeeping: once a fight ends, non-puller bots that
-- have drifted too far from camp (knockbacks, chasing runners, etc.) nav back
-- so the group ends up in the same vicinity again. Pullers manage their own
-- return-to-camp via Pull.lua and are excluded here. Yields to an active
-- /srl follow, which is an explicit, more specific movement instruction.
local RegroupDecision = {}
RegroupDecision.__index = RegroupDecision

function RegroupDecision:new(config)
    local self = setmetatable({}, RegroupDecision)
    self.name   = "RegroupDecision"
    self.config = config
    return self
end

function RegroupDecision:score(ctx)
    if State.flags.automode == 'puller' then return 0 end
    if not State.pull.camp then return 0 end
    if State.follow.active then return 0 end

    local hasActiveCombat = ctx.inCombat and (
        (ctx.numberOfAggresiveInXTar and ctx.numberOfAggresiveInXTar > 0) or
        (State.assist.targetId ~= nil)
    )
    if hasActiveCombat then return 0 end
    if ctx.casting or State.flags.castInFlight then return 0 end
    if mq.TLO.Navigation.Active() then return 0 end

    local camp = State.pull.camp
    local threshold = self.config:get('Regroup.Distance') or 75
    if MoveUtil.distanceToLoc(camp.x, camp.y) <= threshold then return 0 end

    return 8
end

function RegroupDecision:execute(ctx)
    local camp = State.pull.camp
    if not camp then return end
    local returnDist = self.config:get('Regroup.ReturnDist') or 15
    MoveUtil.navToLoc(camp.x, camp.y, camp.z, returnDist)
end

return RegroupDecision
