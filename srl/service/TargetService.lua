local mq = require 'mq'
local TargetService = {}

function TargetService:getTargetById(targetId)
    mq.cmdf("/target id %s", tostring(targetId));
    mq.delay(150)
end

return TargetService