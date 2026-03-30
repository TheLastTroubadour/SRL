local mq = require('mq')

local Promise = {}
Promise.__index = Promise

function Promise:new(timeout)
    local self = setmetatable({}, Promise)

    self.resolved = false
    self.rejected = false
    self.value = nil
    self.reason = nil
    self.onResolve = {}
    self.onReject = {}
    self.start = mq.gettime()
    self.timeout = timeout or 3000

    return self
end

function Promise:resolve(value)
    if self.resolved or self.rejected then return end

    self.resolved = true
    self.value = value

    for _,cb in ipairs(self.onResolve) do
        cb(value)
    end
end

function Promise:reject(reason)
    if self.resolved or self.rejected then return end

    self.rejected = true
    self.reason = reason

    for _,cb in ipairs(self.onReject) do
        cb(reason)
    end
end

function Promise:next(cb)
    assert(type(cb) == "function", "Promise:next requires a function")

    if self.resolved then
        cb(self.value)
    elseif not self.rejected then
        table.insert(self.onResolve, cb)
    end

    return self
end

function Promise:await()
    return coroutine.yield(function(resume)

        self:next(function(value)
            resume(value)
        end)

        self:catch(function(reason)
            resume(nil, reason)
        end)

    end)
end

function Promise:isExpired()
    return not self.resolved and not self.rejected
            and (mq.gettime() - self.start) > self.timeout
end

function Promise:catch(cb)
    assert(type(cb) == "function", "Promise:catch requires a function")

    if self.rejected then
        cb(self.reason)
    elseif not self.resolved then
        table.insert(self.onReject, cb)
    end

    return self
end

function Promise.all(promises)

    assert(type(promises) == "table", "Promise.all expects table")

    local combined = Promise:new()
    local total = #promises
    local remaining = total
    local results = {}

    -- Edge case: empty table
    if total == 0 then
        combined:resolve(results)
        return combined
    end

    for index, promise in ipairs(promises) do

        assert(getmetatable(promise) == Promise,
                "Promise.all expects Promise objects")

        promise:next(function(value)

            results[index] = value
            remaining = remaining - 1

            if remaining == 0 then
                combined:resolve(results)
            end
        end)

        promise:catch(function(reason)

            -- MMO-safe behavior:
            -- treat rejection as nil result
            results[index] = nil
            remaining = remaining - 1

            if remaining == 0 then
                combined:resolve(results)
            end
        end)

    end

    return combined
end

return Promise