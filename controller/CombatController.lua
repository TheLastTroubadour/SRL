local mq = require 'mq'
local CombatController = {}
local State = require 'core.State'
local TableUtil = require 'util.TableUtil'
CombatController.__index = CombatController

function CombatController:new(combatService, config)
    local self = setmetatable({}, CombatController)

    self.combatService     = combatService
    self.config            = config
    self.weaponSwapService = nil

    return self
end

function CombatController:setWeaponSwapService(ws)
    self.weaponSwapService = ws
end

function CombatController:assist(payload)
    local sender = mq.TLO.Spawn('pc ' .. tostring(payload.sender))
    if not sender() then return end
    local maxDist = self.config:get('General.DistanceSetting') or 250
    if sender.Distance() > maxDist then return end

    local target = mq.TLO.Spawn('id ' .. tostring(payload.id))
    if not target() then return end
    local targetType = target.Type()
    if targetType == 'PC' or targetType == 'Mercenary' then return end
    if targetType == 'NPC' then
        local requireAggressive = self.config:get('AssistSettings.requireAggressive')
        if requireAggressive == nil then requireAggressive = true end
        if requireAggressive and not target.Aggressive() then return end
    end

    State:updateAssistState(payload)

    if payload.weaponset and self.weaponSwapService then
        self.weaponSwapService:swap(payload.weaponset)
    end
end

return CombatController
