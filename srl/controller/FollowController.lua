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

    State:setFollow(payload)

    self.followService:follow(payload.id)
end

function FollowController:stop()
    State:stopFollow()
    self.followService:stop()
end


return FollowController
