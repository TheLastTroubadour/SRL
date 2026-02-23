local mq = require 'mq'
local actors = require('actors')

local Wrapper = {}
Wrapper.__index = Wrapper

function Wrapper:new(name)
    local self = setmetatable({}, Wrapper)

    local ok, actor = pcall(function()
        return actors.register(name)
    end)

    if ok and actor then
        -- NEW API
        self.actor = actor
        self.newAPI = true
    else
        -- OLD API fallback
        self.handlers = {}

        local function dispatcher(message)
            print("RAW MESSAGE RECEIVED:", message)
            local data = message()
            local event = data.event
            local eventName = data.event.event
            local payload = data.event.payload
            print("Payload: ", payload)

            if self.handlers[eventName] then
                self.handlers[eventName](data.sender, payload)
            end
        end

        self.actor = actors.register(name, dispatcher)
        self.newAPI = false
    end

    return self
end

function Wrapper:on(event, callback)
    if self.newAPI then
        self.actor:on(event, callback)
    else
        self.handlers[event] = callback
    end
end

function Wrapper:send(target, event, data)
    local name = mq.TLO.Me.Name()
    print("Event -> ", event)
    self.actor:send({mailbox=target, script='srl'}, {
        event = event,
        data = data,
        sender = name
    })
end

return Wrapper