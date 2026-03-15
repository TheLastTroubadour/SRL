local CommandBus = {}
local mq = require 'mq'
local State = require 'srl.core.State'
local TableUtil = require 'srl.util.TableUtil'
CommandBus.handlers = {}

function CommandBus:init()
    mq.unbind('/srlevent')

    local commandBus = self

    mq.bind('/srlevent', function(...)
        local args = { ... }
        local command = table.remove(args, 1)

        if not command then
            return
        end

        local payload = {}

        for _, token in ipairs(args) do
            local k, v = token:match("([^=]+)=([^=]+)")
            if k and v then
                payload[k] = v
            end
        end

        commandBus:dispatch(command, payload)
    end)

    mq.unbind('/assiston')
    mq.bind('/assiston', function(...)
        local args = { ... }
        local command = table.remove(args, 1)
        if not command then
            return
        end

        local payload = {}

        for _, token in ipairs(args) do
            local k, v = token:match("([^=]+)=([^=]+)")
            if k and v then
                payload[k] = v
            end
        end
        mq.cmdf('/dgae /srlevent Assist id=%s generation=%s sender=%s', mq.TLO.Target.ID(), State.assist.generation + 1, mq.TLO.Me.Name())
    end)

    mq.unbind('/followme')
    mq.bind('/followme', function(...)
        local args = { ... }
        local command = table.remove(args, 1)
        if not command then
            return
        end

        local payload = {}

        for _, token in ipairs(args) do
            local k, v = token:match("([^=]+)=([^=]+)")
            if k and v then
                payload[k] = v
            end
        end
        mq.cmdf('/dgae /srlevent Follow id=%s sender=%s', mq.TLO.Target.ID(), mq.TLO.Me.Name())
    end)

    mq.unbind('/srlstop')
    mq.bind('/srlstop', function(...)
        local args = { ... }
        local command = table.remove(args, 1)
        if not command then
            return
        end

        local payload = {}

        for _, token in ipairs(args) do
            local k, v = token:match("([^=]+)=([^=]+)")
            if k and v then
                payload[k] = v
            end
        end
        mq.cmdf('/dgae /srlevent Stop sender=%s', mq.TLO.Me.Name())
    end)

end

function CommandBus:register(command, handler)
    self.handlers[command] = handler
end

function CommandBus:dispatch(command, payload)
    local handler = self.handlers[command]
    if not handler then
        print("No handler registered for:", command)
        return
    end
    if handler then
        handler(payload)
    end
end

function CommandBus:diedReset()
    mq.event('Died1', 'You have died', function()
        --reset all the buff timers to 3-5 minutes?
    end)
end

return CommandBus