local mq = require('mq')

local Promise = {}
Promise.__index = Promise

function Promise:new(timeout)
    local self = setmetatable({}, Promise)
    self.resolved = false
    self.rejected = false
    self.value = nil
    self.waiting = nil
    self.start = mq.gettime()
    self.timeout = timeout or 3000
    return self
end

function Promise:resolve(value)
    if self.resolved or self.rejected then return end
    self.resolved = true
    self.value = value

    if self.waiting then
        self.waiting(self.value)
    end
end

function Promise:reject(reason)
    if self.resolved or self.rejected then return end
    self.rejected = true

    if self.waiting then
        self.waiting(nil, reason)
    end
end

function Promise:await()
    return coroutine.yield(function(resume)
        self.waiting = resume
    end)
end

function Promise:isExpired()
    return not self.resolved and not self.rejected
            and (mq.gettime() - self.start) > self.timeout
end

return Promise