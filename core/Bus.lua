local actors = require 'core.ActorWrapper'
local promise = require 'core.Promise'
local TableUtil = require 'util.TableUtil'

local Bus = {}
Bus.__index = Bus

local nextId = 0

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

    self.actor:on('buff_reply', function(sender, data)
        local id = data.data and data.data.id
        if id and self.pending[id] then
            self.pending[id]:resolve(data)
            self.pending[id] = nil
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
    nextId = nextId + 1
    local id = tostring(nextId)
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
    for id, prom in pairs(self.pending) do
        if prom:isExpired() then
            prom:reject("timeout")
            self.pending[id] = nil
        end
    end
end

return Bus