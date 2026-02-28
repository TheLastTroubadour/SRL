local CombatController = {}
CombatController.__index = CombatController

function CombatController:new(bus, combatService)
    local self = setmetatable({}, CombatController)

    self.bus = bus
    self.combatService = combatService
    self:register()
    return self
end

function CombatController:register()
    self.bus.actor:on("assist", function(sender, data)
        print("Assist Actor")
        print(data)
        -- Don't react to your own broadcast
        if data.sender == mq.TLO.Me.Name() then
            return
        end

        self.combatService:assist(data.targetName)
    end)
end

return CombatController
