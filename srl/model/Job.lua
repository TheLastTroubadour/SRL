local Job = {}
local mq = require 'mq'
Job.__index = Job

-- Job.lua
local Job = {}
Job.__index = Job

function Job:new(targetId, targetName, name, type, priority, gem)
    local self = setmetatable({}, Job)

    self.targetId = targetId
    self.targetName = targetName
    self.name = name --name of spell/ability/aa
    self.type     = type
    self.priority = priority or 0
    self.gem      = gem -- optional
    self.generation = nil
    -- Unique identity for duplicate protection
    self.key = name .. ":" .. tostring(targetId)

    return self
end

return Job