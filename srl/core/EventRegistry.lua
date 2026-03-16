local mq = require 'mq'

local EventRegistry = {}
EventRegistry.__index = EventRegistry

function EventRegistry:new()
    local self = setmetatable({}, EventRegistry)
    return self
end

function EventRegistry:init(services)
    local buffService   = services.buffService
    local inviteService = services.inviteService

    -- Death: clear all buff timers so everything repolls on rez
    mq.event('SRL_Death', 'You have been slain by#*#', function()
        if buffService then buffService:reset() end
    end)

    -- Resurrection offer
    mq.event('RezOffer', '#1# has offered you a resurrection.', function(resurrector)
        if inviteService then inviteService:handleRezOffer(resurrector) end
    end)

    -- Group / raid invites
    mq.event('GroupInvite', '#1# invites you to join a group.', function(inviter)
        if inviteService then inviteService:handleGroupInvite(inviter) end
    end)

    mq.event('RaidInvite', '#1# invites you to join a raid.', function(inviter)
        if inviteService then inviteService:handleRaidInvite(inviter) end
    end)
end

return EventRegistry
