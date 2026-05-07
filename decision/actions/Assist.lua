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
    return self
end

function AssistDecision:score(ctx)

    if not ctx.assist.Id then
        if self.lastEngagedId then
            local lastSpawn = mq.TLO.Spawn('id ' .. tostring(self.lastEngagedId))
            if lastSpawn() and lastSpawn.Dead() then
                mq.cmd('/attack off')
            end
        end
        self.lastEngagedId   = nil
        self.engagedInCombat = false
        return 0
    end

    -- Never assist (attack/stick) while FD — would cause puller to stand up
    if State.flags.isPuller and mq.TLO.Me.Feigning() then
        return 0
    end

    if ctx.assist.assistType:lower() == 'off' then
        return 0
    end

    if ctx.isForeground then
        return 0
    end

    if ctx.assist.dead then
        mq.cmd('/attack off')
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

    Target:getTargetById(ctx.assist.Id)

    mq.cmdf('/stick %s %s moveback uw', ctx.assist.stickPoint, ctx.assist.stickDistance)
    mq.delay(50)
    mq.cmd('/attack on')
    self.lastEngagedId   = tostring(ctx.assist.Id)
    self.engagedInCombat = false
end

return AssistDecision
