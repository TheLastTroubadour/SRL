local mq    = require 'mq'
local State = require 'core.State'

local AssistUtil = {}

-- Broadcasts a new Assist target to the raid and applies it locally immediately,
-- since /dgze delivery back to the sender's own client is not guaranteed.
function AssistUtil.broadcastAssist(targetId, extra)
    local me = mq.TLO.Me.Name()
    local generation = State.assist.generation + 1
    mq.cmdf('/dgze /srlevent Assist id=%s generation=%s sender=%s%s',
        targetId, generation, me, extra or '')
    local name = mq.TLO.Spawn('id ' .. tostring(targetId)).CleanName()
    State:updateAssistState({ id = targetId, name = name, sender = me })
end

return AssistUtil
