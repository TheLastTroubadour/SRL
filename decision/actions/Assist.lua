local mq = require 'mq'
local Target = require 'service.TargetService'
local State  = require 'core.State'
local AssistDecision = {}
AssistDecision.__index = AssistDecision


function AssistDecision:new()
    local self = setmetatable({}, AssistDecision)
    self.name            = "AssistDecision"
    self.safeWhileInvis  = true  -- attacking breaks invis anyway; let the bot engage when called
    self.lastEngagedId   = nil   -- target ID we last issued /stick + /attack on for
    self.engagedInCombat = false -- true once the mob confirmed fighting back after engage
    self.lastPetAssistId = nil   -- assist ID the pet was last directed at
    self.mode            = nil   -- 'assist' | 'petattack'
    return self
end

function AssistDecision:score(ctx)
    self.mode = nil

    if not ctx.assist.Id then
        if self.lastEngagedId then
            local lastSpawn = mq.TLO.Spawn('id ' .. tostring(self.lastEngagedId))
            if lastSpawn() and lastSpawn.Dead() then
                mq.cmd('/attack off')
            end
        end
        self.lastEngagedId   = nil
        self.lastPetAssistId = nil
        self.engagedInCombat = false
        return 0
    end

    -- Never assist (attack/stick) while FD — would cause puller to stand up
    if State.flags.isPuller and mq.TLO.Me.Feigning() then
        return 0
    end

    -- Pet redirect scores independently — fires even when assistType is off
    local hasPet = (mq.TLO.Me.Pet.ID() or 0) > 0
    if hasPet and ctx.assist.Id ~= self.lastPetAssistId then
        self.mode = 'petattack'
        -- Fall through so melee/ranged can score higher and handle both in one execute
    end

    if ctx.assist.assistType:lower() == 'off' then
        return self.mode == 'petattack' and 88 or 0
    end

    if ctx.isForeground then
        return 0
    end

    if ctx.assist.dead then
        mq.cmd('/attack off')
        mq.cmd('/stick off')
        self.lastEngagedId = nil
        return 0
    end

    -- Wrong target — need to retarget and re-engage
    if not ctx.myCurrentTargetId or tonumber(ctx.assist.Id) ~= tonumber(ctx.myCurrentTargetId) then
        return 90
    end

    -- New target or stick fell off — need to engage
    if not mq.TLO.Stick.Active() or tostring(ctx.assist.Id) ~= tostring(self.lastEngagedId) then
        return 90
    end

    -- Track whether this mob has fought back; re-engage if combat drops after it was established
    if ctx.inCombat then
        self.engagedInCombat = true
    elseif self.engagedInCombat then
        return 90
    end

    return 0
end

function AssistDecision:execute(ctx)

    if self.mode == 'petattack' then
        mq.cmd('/pet attack')
        self.lastPetAssistId = ctx.assist.Id
        return
    end

    Target:getTargetById(ctx.assist.Id)

    local dist = ctx.assist.stickDistance
    if tostring(dist):lower() == 'maxmelee' then
        dist = (mq.TLO.Target.MaxMeleeTo() or 15) - 1
    end

    mq.cmdf('/stick %s %s moveback uw', ctx.assist.stickPoint, dist)
    if mq.TLO.Target.ID() ~= tonumber(ctx.assist.Id) then
        mq.delay(50, function() return mq.TLO.Target.ID() == tonumber(ctx.assist.Id) end)
    end
    mq.cmd('/attack on')
    self.lastEngagedId   = tostring(ctx.assist.Id)
    self.engagedInCombat = false

    if (mq.TLO.Me.Pet.ID() or 0) > 0 and ctx.assist.Id ~= self.lastPetAssistId then
        mq.cmd('/pet attack')
        self.lastPetAssistId = ctx.assist.Id
    end
end

return AssistDecision
