local actors = require 'srl/actors/ActorWrapper'
local promise = require 'srl/actors/Promise'
local mq = require 'mq'
local TableUtil = require 'srl/util/TableUtil'

local Bus = {}
Bus.__index = Bus

function Bus:new(name)
    local self = setmetatable({}, Bus)

    self.actor = actors:new(name)
    self.handlers = {}
    self.pending = {}
    self:registerCore()

    return self
end

function Bus:registerCore()
    self.actor:on('bus_event', function(sender, data)
        if self.handlers[data.type] then
            self.handlers[data.type](sender, data.payload)
        end
    end)


    self.actor:on('bus_reply', function(sender, data)
        if self.pending[data.id] then
            self.pending[data.id](sender, data.payload)
            self.pending[data.id] = nil
        end
    end)
end

function Bus:send(target, event, data)
    self.actor:send(target, {
        event = event,
        data = data
    })
end

function Bus:on(eventType, callback)
    self.handlers[eventType] = callback
end

function Bus:broadcast(eventType, payload)
    self.actor:broadcast(eventType, payload)
end

function Bus:request(target, eventType, payload, timeout)
    local id = tostring(math.random(100000,999999))
    local prom = promise:new(timeout)

    self.pending[id] = prom
    payload.id = id

    self.actor:send(target, eventType, payload)

    return prom
end

function Bus:reply(target, payload)
    self.actor:send(target, 'buff_reply', payload)
end

function Bus:update()
    for id, promise in pairs(self.pending) do
        if promise:isExpired() then
            promise:reject("timeout")
            self.pending[id] = nil
        end
    end
end

return Bus