local CombatController = {}
local State = require 'srl.core.State'
local TableUtil = require 'srl.util.TableUtil'
CombatController.__index = CombatController

function CombatController:new(combatService)
    local self = setmetatable({}, CombatController)

    self.combatService = combatService

    return self
end

function CombatController:assist(payload)

    State:updateAssistState(payload)

    self.combatService:assist(payload.id)
end

return CombatController
