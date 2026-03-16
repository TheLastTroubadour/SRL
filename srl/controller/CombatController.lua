local mq = require 'mq'
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
    local sender = mq.TLO.Spawn('pc ' .. tostring(payload.sender))
    if not sender() then return end
    if sender.Distance() > 250 then return end

    State:updateAssistState(payload)
    --self.combatService:assist(payload.id)
end

return CombatController
