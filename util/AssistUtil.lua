local mq            = require 'mq'
local State         = require 'core.State'
local BroadcastUtil = require 'util.BroadcastUtil'

local AssistUtil = {}

function AssistUtil.setConfig(config)
    AssistUtil.config = config
end

-- Broadcasts a new Assist target to the raid and applies it locally immediately,
-- since delivery back to the sender's own client is not guaranteed.
function AssistUtil.broadcastAssist(targetId, extra)
    local me = mq.TLO.Me.Name()
    local generation = State.assist.generation + 1
    local prefix = BroadcastUtil.prefix(AssistUtil.config)
    mq.cmdf('%s /srlevent Assist id=%s generation=%s sender=%s%s',
        prefix, targetId, generation, me, extra or '')
    local name = mq.TLO.Spawn('id ' .. tostring(targetId)).CleanName()
    State:updateAssistState({ id = targetId, name = name, sender = me })
end

return AssistUtil
