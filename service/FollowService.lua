local mq = require 'mq'
local FollowService = {}
local State = require 'core.State'
local TargetService = require 'service.TargetService'
local Logging = require 'core.Write'
FollowService.__index = FollowService

function FollowService:new()
    local self = setmetatable({}, FollowService)
    self.lastFollowCheck = nil
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
    mq.cmd('/nav stop')
    TargetService:getTargetById(followId)
    mq.cmd("/stick 5 uw")
    Logging.Debug("Movement.follow End")
    State:updateLastActivity()
end

function FollowService:resumeFollow()
    if State.follow.active and State.follow.followId then
        self:follow(State.follow.followId)
    end
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
    mq.cmd('/nav stop')
end

function FollowService:checkFollow()
    Logging.Debug("Movement.check_follow Start")
    if self.lastFollowCheck and mq.gettime() - self.lastFollowCheck > 500 then
        if not State.follow.enabled then
            return
        end

        -- don't follow during combat
        if State.combat.inCombat then
            return
        end

        --local dist = mq.TLO.Me.Distance(State.follow.followId)()

        --if not dist then
        --    return
        --end


        self:resumeFollow()
        --if dist > self.config.followDistance then
        --    mq.cmd("/stick hold " .. self.state.follow.target)
        --end
    end

    self.lastFollowCheck = mq.gettime()

    Logging.Debug("Movement.check_follow End")
end

return FollowService