local mq = require('mq')

local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler:new()
    local self = setmetatable({}, Scheduler)
    self.ready = {}
    self.waiting = {}
    return self
end

function Scheduler:spawn(fn)
    local co = coroutine.create(fn)
    table.insert(self.ready, co)
end

function Scheduler:resume(co, ...)
    if coroutine.status(co) == "dead" then
        return
    end

    local ok, yielded = coroutine.resume(co, ...)

    if not ok then
        print("Coroutine error:", yielded)
        return
    end

    if coroutine.status(co) == "dead" then
        return
    end

    -- If coroutine yielded a function,
    -- we treat it as a resume hook
    if type(yielded) == "function" then

        -- Store coroutine as waiting
        self.waiting[co] = true

        -- Provide resume callback
        yielded(function(...)
            self.waiting[co] = nil
            table.insert(self.ready, co)
            self:resume(co, ...)
        end)

    else
        -- If yielded something else,
        -- requeue coroutine next tick
        table.insert(self.ready, co)
    end
end

function Scheduler:run()
    local current = self.ready
    self.ready = {}

    for _,co in ipairs(current) do
        self:resume(co)
    end
end

return Scheduler