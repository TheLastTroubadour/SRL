local mq = require 'mq'
local TargetService = {}

function TargetService:get_target_by_id(targetId)
    mq.cmdf("/target id %s", tostring(targetId));
    mq.delay(150)
end

return TargetService