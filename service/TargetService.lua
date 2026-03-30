local mq = require 'mq'
local TargetService = {}

function TargetService:getTargetById(targetId)
    local id = tonumber(targetId)
    mq.cmdf("/target id %s", tostring(id))
    mq.delay(150, function() return mq.TLO.Target.ID() == id end)
end

return TargetService