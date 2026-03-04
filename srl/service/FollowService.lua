local mq = require 'mq'
local FollowService = {}
local State = require 'srl.core.State'
local TargetService = require 'srl.service.TargetService'
local Logging = require 'srl.core.Write'
FollowService.__index = FollowService

function FollowService:new()
    local self = setmetatable({}, FollowService)

    return self
end

--Actual Follow Functionality
function FollowService:follow(followId)

    if ((mq.TLO.Me.ID() == tonumber(followId))) then
        --Don't follow the person who called for it
        return
    end
    --Use Switch or AdvFollow make a service?
    Logging.Debug("Movement.follow Start")
    mq.cmd("/stick off")
    mq.cmd("/afollow off")
    TargetService:getTargetById(followId)
    mq.cmd('/face')
    mq.delay(100)
    mq.cmd("/stick 5")
    Logging.Debug("Movement.follow End")
end

--Handles the Events based off chat
function FollowService:followEvent(line, chatSender, args)
    Logging.Debug("Movement.follow_event Start")
    local me = mq.TLO.Me
    local spawnId = "pc " .. chatSender
    local followId = mq.TLO.Spawn(spawnId).ID()
    Logging.Debug("Follow Id -> " .. tostring(followId))
    if (me.ID() == followId) then
        --Don't follow the person who called for it
        return
    else
        --Check Zone|Distance
        self:follow(followId)
        --Set follow on ? Stop casting? Check for invis?
    end
    Logging.Debug("Movement.follow_event End")
end

function FollowService:stopFollow()
    local spawnName = "pc " .. tostring(chatSender)
    local stopId = mq.TLO.Spawn(spawnName).ID()
    local me = mq.TLO.Me
    if (me.ID() == stopId) then
        --Person who called for it doesn't need to stop
        return
    else
        self:callStop()
    end
end

function FollowService:stop()
    mq.cmd("/stick off");
    mq.cmd("/afollow off")
end

function FollowService:checkFollow()
    Logging.Debug("Movement.check_follow Start")

    --TODO More checks?
    if(State.assist.targetID) then return end

    --ASSISTING always true here
    if (State.follow.active) then
        if(mq.TLO.Me.ID() ~= State.follow.followId) then
            self:follow(State.follow.followId)
        end
    end
    Logging.Debug("Movement.check_follow End")
end

return FollowService