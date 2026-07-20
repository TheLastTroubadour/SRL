local mq     = require 'mq'
local State  = require 'core.State'
local Target = require 'service.TargetService'

local CharmDecision = {}
CharmDecision.__index = CharmDecision

function CharmDecision:new(config)
    local self = setmetatable({}, CharmDecision)
    self.name         = 'CharmDecision'
    self.config       = config
    self.mode         = nil   -- 'recharm' | 'setup' | 'petbuff'
    self.pendingBuff  = nil
    self.prevPetId    = 0
    self.petBuffsDone = false
    return self
end

function CharmDecision:score(ctx)
    self.mode        = nil
    self.pendingBuff = nil

    if ctx.casting then return 0 end
    if ctx.myClass ~= 'ENC' then return 0 end

    local petId = State.charm.petId
    if not petId then return 0 end

    local spellName = self.config:get('Charm.Spell')
    local gem       = tonumber(self.config:get('Charm.Gem'))
    if not spellName or not gem then return 0 end

    local currentPetId = mq.TLO.Me.Pet.ID() or 0

    -- Detect charm landing: pet ID just transitioned to our target
    if currentPetId == petId and self.prevPetId ~= petId then
        self.petBuffsDone = false
    end
    self.prevPetId = currentPetId

    if currentPetId ~= petId then
        -- Charm not active — verify mob still alive
        local spawn = mq.TLO.Spawn('id ' .. petId)
        if not spawn() or spawn.Dead() then
            State.charm.petId = nil
            mq.cmdf('/dgae /srlevent CharmPetSet id=0 sender=%s', mq.TLO.Me.Name())
            return 0
        end

        -- Check max level gate
        local maxLevel = tonumber(self.config:get('Charm.MaxLevel'))
        if maxLevel and (spawn.Level() or 0) > maxLevel then return 0 end

        -- Spell not ready — recast timer or global cooldown; let CC mez it
        if not mq.TLO.Me.SpellReady(spellName)() then return 0 end

        self.mode = 'recharm'
        return 120
    end

    -- Pet buffs — cast each configured buff once per charm
    if not self.petBuffsDone then
        local petBuffs = self.config:get('Charm.PetBuffs') or {}
        for _, buff in ipairs(petBuffs) do
            if buff.spell and not mq.TLO.Me.Pet.Buff(buff.spell)() then
                self.mode        = 'petbuff'
                self.pendingBuff = buff
                return 45
            end
        end
        self.petBuffsDone = true
    end

    return 0
end

function CharmDecision:execute(ctx)
    if self.mode == 'recharm' then
        local petId = State.charm.petId
        if not petId then return end
        if mq.TLO.Target.ID() ~= petId then
            Target:getTargetById(petId)
            mq.delay(200)
        end
        if mq.TLO.Target.ID() ~= petId then return end
        local gem = tonumber(self.config:get('Charm.Gem'))
        mq.cmdf('/cast %d', gem)

    elseif self.mode == 'petbuff' and self.pendingBuff then
        local buff  = self.pendingBuff
        local petId = State.charm.petId
        if not petId then return end
        if mq.TLO.Target.ID() ~= petId then
            Target:getTargetById(petId)
            mq.delay(200)
        end
        if mq.TLO.Target.ID() ~= petId then return end
        local t = (buff.type or 'spell'):lower()
        if t == 'aa' then
            if mq.TLO.Me.AltAbilityReady(buff.spell)() then
                mq.cmdf('/alt activate "%s"', buff.spell)
            end
        else
            local gem = tonumber(buff.gem)
            if gem and mq.TLO.Me.SpellReady(buff.spell)() then
                mq.cmdf('/cast %d', gem)
            end
        end
    end
end

return CharmDecision
