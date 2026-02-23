local actors = require 'srl/actors/ActorWrapper'
local promise = require 'srl/actors/Promise'
local mq = require 'mq'

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
            print("Bus event type")
            print(data.type)
            self.handlers[data.type](sender, data.payload)
        end
    end)

    self.actor:on("reply", function(sender, data)
        local id = data.id
        print("In Bus Reply")
        if self.pending[id] then
            self.pending[id]:resolve(data.payload)
            self.pending[id] = nil
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
    self.actor:send(nil, 'bus_event', {
        type = eventType,
        payload = payload
    })
end

function Bus:request(target, eventType, payload, timeout)
    local id = tostring(math.random(100000,999999))
    local prom = promise:new(timeout)

    self.pending[id] = prom

    self.actor:send({mailbox=target, script='srl'},
        {
        id = id,
        event = eventType,
        payload = payload,
        sender = mq.TLO.Me.Name(),
    })

    return prom
end

function Bus:reply(target, id, payload)
    self.actor:send({mailbox=target, script="srl"}, 'bus_reply', {
        id = id,
        payload = payload
    })
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