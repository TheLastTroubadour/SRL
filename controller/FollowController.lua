local mq = require 'mq'
local FollowController = {}
local State = require 'core.State'
local TableUtil = require 'util.TableUtil'
FollowController.__index = FollowController

function FollowController:new(followService, config)
    local self = setmetatable({}, FollowController)

    self.followService = followService
    self.config = config

    return self
end

function FollowController:follow(payload)
    local sender = mq.TLO.Spawn('pc ' .. tostring(payload.sender))
    if not sender() then return end
    local maxDist = self.config:get('General.DistanceSetting') or 250
    if sender.Distance() > maxDist then return end

    State:setFollow(payload)
    self.followService:follow(payload.id)
end

function FollowController:stop()
    State:stopFollow()
    self.followService:stop()
end


return FollowController
