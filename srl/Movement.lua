local mq = require 'mq'
local TargetService = require 'srl/service/TargetService'
local Logging = require 'srl/core/Write'
--All Movements related functionality
local movement_export = {}

--Actual Follow Functionality
local function follow(followId)
    --Use Switch or AdvFollow make a service?
    Logging.Debug("Movement.follow Start")
    FOLLOWING = true;
    FOLLOW_TARGET_ID = followId;
    mq.cmd("/stick off")
    mq.cmd("/afollow off")
    TargetService:getTargetById(followId)
    mq.cmd("/afollow on")
    Logging.Debug("Movement.follow End")
end

--Handles the Events based off chat
local function follow_event(line, chatSender, args)
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
        follow(followId)
        --Set follow on ? Stop casting? Check for invis?
    end
    Logging.Debug("Movement.follow_event End")
end

local function stop_event(line, chatSender)
    local spawnName = "pc " .. tostring(chatSender)
    local stopId = mq.TLO.Spawn(spawnName).ID()
    local me = mq.TLO.Me
    if (me.ID() == stopId) then
        --Person who called for it doesn't need to stop
        return
    else
        movement_export.call_stop()
    end
end

function movement_export.call_stop()
    FOLLOWING = false
    FOLLOW_TARGET_ID = nil
    mq.cmd("/stick off");
    mq.cmd("/afollow off")
end

function movement_export.check_follow()
    Logging.Debug("Movement.check_follow Start")

    if(ASSISTING == true) then return end

    --ASSISTING always true here
    if (FOLLOWING == true) then
        if(mq.TLO.Me.ID() ~= FOLLOW_TARGET_ID) then
            follow(FOLLOW_TARGET_ID)
        end
    end
    Logging.Debug("Movement.check_follow End")
end

function movement_export.registerEvents()
    mq.event('follow1', 'Follow Me #1#', follow_event);
    mq.event('follow2', '#*# Follow Me #1#', follow_event);
    --mq.event('follow3', '<#*#> Follow Me #1#', follow_event);
    mq.event('stop1', '[#1#] Stop', stop_event)
    mq.event('stop2', 'Stop', stop_event)
end

return movement_export

