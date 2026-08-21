local mq = require 'mq'
local Target = require 'service.TargetService'
local State  = require 'core.State'
local AssistDecision = {}
AssistDecision.__index = AssistDecision

local KNOCKBACK_BUFFER = 20 -- yards beyond stick distance before we treat it as a knockback

local function resolveStickDist(ctx)
    local dist = ctx.assist.stickDistance
    if tostring(dist):lower() == 'maxmelee' then
        return (mq.TLO.Target.MaxMeleeTo() or 15) - 1
    end
    return tonumber(dist) or 10
end


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
    if State.flags.automode == 'puller' and mq.TLO.Me.Feigning() then
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

    -- Foreground normally means a human is driving this client manually, so stay
    -- hands-off. Automode is an explicit opt-in to automation even while foregrounded,
    -- so the caller still engages instead of standing there waiting for manual input.
    if ctx.isForeground and not State.flags.automode then
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

    -- Knocked back -- Stick still reports active but we're well past our intended
    -- distance (mob push/knockback effects can leave /stick unable to catch up on its own)
    if ctx.assist.distance and ctx.assist.distance > resolveStickDist(ctx) + KNOCKBACK_BUFFER then
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

    local dist = resolveStickDist(ctx)

    -- "behind" continuously re-forces behind-positioning on every correction,
    -- which compounds with moveback into constant repositioning as the mob
    -- turns/moves. "behindonce" (KissAssist uses this in its own combat stick
    -- calls) only aims for behind once, then just holds distance afterward.
    local stickPoint = ctx.assist.stickPoint
    if tostring(stickPoint):lower() == 'behind' then
        stickPoint = 'BehindOnce'
    end

    mq.cmdf('/stick %s %s moveback uw', stickPoint, dist)
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
