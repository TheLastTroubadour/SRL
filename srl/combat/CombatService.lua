local mq = require 'mq'
local CombatService = {}
CombatService.__index = CombatService

function CombatService:new(castService)
    local self = setmetatable({}, CombatService)

    self.castService = castService
    self.currentTarget = nil
    self.generation = 0
    self.rotation =
    {
        spellRotation = {},
        abilityRotation = {}
    }

    return self
end

function CombatService:isInCombat()
    return mq.TLO.Me.Combat()
end

function CombatService:assist(targetName)

    if not targetName then return end

    if self.currentTarget ~= targetName then
        self.currentTarget = targetName
        self.generation = self.generation + 1

        print("New assist target:", targetName)

        -- Clear any queued combat jobs
        self.castService:clearCombatQueue()
    end

    mq.cmdf('/target %s', targetName)
    mq.delay(150)
    mq.cmdf('/stick behind loose')
    mq.delay(150)
    mq.cmd('/attack on')
end

function CombatService:update()

    if not self.currentTarget then return end

    if not mq.TLO.Target() then return end
    if mq.TLO.Target.CleanName() ~= self.currentTarget then return end
    if mq.TLO.Target.Type() ~= "NPC" then return end
    if mq.TLO.Target.Dead() then return end

    for _, entry in ipairs(self.rotation.spellRotation) do
        if self:canUse(entry) then
            self.castService:enqueue(entry)
        end
    end
     for _, entry in ipairs(self.rotation.abilityRotation) do
            if self:canUse(entry) then
                self.castService:enqueue(entry)
            end
    end

end

function CombatService:canUse(spellName, spellOrAbility)
    if(type == 'spell') then
        local spell = mq.TLO.Spell(spellName)
        if spell() then
            print(("Spell %s not Available removing from self.rotation.spellRotation"):format(spellName))
            local indexToRemove = nil
            for k, v in ipairs(self.rotation.spellRotation) do
            end
        end
    end
end

return CombatService