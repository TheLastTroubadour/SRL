local mq = require 'mq'
local BindService = {}
BindService.__index = BindService

function BindService:new(combatService)
    local self = setmetatable({}, BindService)
    self.combatService = combatService
    self:register()

    return self
end

function BindService:register()
    self:bindAssist()
end

function BindService:bindAssist()
  mq.bind('/assistme', function(...)
        local args = {...}
        local targetId = args[1]
        print(self)
        print(targetId)
        self.combatService:assist(targetId)
    end)
end

return BindService