local mq = require 'mq'
local target_export = {}

function target_export.get_target_by_id(targetId)
    mq.cmdf("/target id %s", tostring(targetId));
    mq.delay(30)
end

return target_export