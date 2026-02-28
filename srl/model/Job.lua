local Job = {}
local mq = require 'mq'
Job.__index = Job



function Job:new(target, spell, type, generation, iniLine, gem)
    local self = setmetatable({}, Job)

    self.target = target
    local spawnSearch = 'pc ' .. target
    self.targetId = mq.TLO.Spawn(spawnSearch).ID
    self.spell = spell
    self.type = type
    self.generation = generation
    self.iniLine = iniLine
    self.gem = gem or 8

    return self
end

return Job
