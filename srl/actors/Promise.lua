local mq = require('mq')

local Promise = {}
Promise.__index = Promise

function Promise:new(timeoutMs)
    local self = setmetatable({}, Promise)
    self.resolved = false
    self.rejected = false
    self.value = nil
    self.callbacks = {}
    self.errbacks = {}
    self.start = mq.gettime()
    self.timeout = timeoutMs or 3000
    return self
end

function Promise:resolve(value)
    if self.resolved or self.rejected then return end
    self.resolved = true
    self.value = value
    for _,cb in ipairs(self.callbacks) do
        cb(value)
    end
end

function Promise:reject(reason)
    if self.resolved or self.rejected then return end
    self.rejected = true
    for _,cb in ipairs(self.errbacks) do
        cb(reason)
    end
end

function Promise:next(cb)
    if self.resolved then
        cb(self.value)
    else
        table.insert(self.callbacks, cb)
    end
    return self
end

function Promise:catch(cb)
    if self.rejected then
        cb()
    else
        table.insert(self.errbacks, cb)
    end
    return self
end

function Promise:isExpired()
    return not self.resolved and not self.rejected
            and (mq.gettime() - self.start) > self.timeout
end

return Promise