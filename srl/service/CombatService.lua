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

function CombatService:assist(targetId)

    if not targetId then return end

    if self.currentTarget ~= targetId then
        self.currentTarget = targetId
        self.generation = self.generation + 1

        print("New assist target:", targetId)

        -- Clear any queued combat jobs
        self.castService:clearCombatQueue()
    end

    mq.cmdf('/target id %s', targetId)
    mq.delay(150)
    mq.cmdf('/stick behind loose')
    mq.delay(50)
    mq.cmd('/attack on')
end

function CombatService:update()

    if not self.currentTarget then return end

    if not mq.TLO.Target() then return end
    if mq.TLO.Target.CleanName() ~= self.currentTarget then return end
    if mq.TLO.Target.Type() ~= "NPC" then return end
    if mq.TLO.Target.Dead() then return
        --If was following someone resume follow?
        --Next Target or Wait for Call
    end

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
    --restick?

end

function CombatService:canUse(job)
    --Don't Queue up till it's ready?
    if(job.type == 'spell') then
        local spell = mq.TLO.Spell(job.spell)
        if spell() then
            print(("Spell %s not Available removing from self.rotation.spellRotation"):format(spellName))
            local indexToRemove = nil
            for k, v in ipairs(self.rotation.spellRotation) do
            end
        end
    end

    if(type == 'ability') then
        if mq.TLO.Me.CombatAbility(job.spell)() then
            -- Is it ready?
        end
        if mq.TLO.Me.CombatAbilityReady(job.spell)() then
        end
    end

    self.castService:enqueue(job)
end

return CombatService