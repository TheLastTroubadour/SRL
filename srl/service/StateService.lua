local mq = require 'mq'
local TableUtil = require 'srl.util.TableUtil'
local StateService = {}

function StateService:update(state)
    print("In State Service")
    print(TableUtil.table_print(state.assist))

    if not state.combatState then
        state.assist.targetId = nil
    end

    print("After State Service")
    print(TableUtil.table_print(state.assist))

end

return StateService