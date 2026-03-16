local mq = require 'mq'
local FollowController = {}
local State = require 'srl.core.State'
local TableUtil = require 'srl.util.TableUtil'
FollowController.__index = FollowController

function FollowController:new(followService)
    local self = setmetatable({}, FollowController)

    self.followService = followService

    return self
end

function FollowController:follow(payload)
    local sender = mq.TLO.Spawn('pc ' .. tostring(payload.sender))
    if not sender() then return end
    if sender.Distance() > 250 then return end

    State:setFollow(payload)
    self.followService:follow(payload.id)
end

function FollowController:stop()
    State:stopFollow()
    self.followService:stop()
end


return FollowController
