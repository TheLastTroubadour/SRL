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
    self.subtype = nil
    self.priority = priority or 0
    self.gem      = gem -- optional
    self.generation = nil
    -- Unique identity for duplicate protection
    self.key = name .. ":" .. tostring(targetId)
    self.abilityHasDebuff = false
    self.notBefore = 0  -- epoch ms; job stays in queue until this time passes

    return self
end

function Job:setTargetId(targetId)
    self.targetId = targetId
    self.key = self.name .. ":" .. tostring(targetId)
end

return Job