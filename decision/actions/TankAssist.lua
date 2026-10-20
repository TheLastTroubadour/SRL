local mq         = require 'mq'
local State      = require 'core.State'
local AssistUtil = require 'util.AssistUtil'
local MoveUtil   = require 'util.MoveUtil'

-- Automates what a human MA does by hand: target a mob, run /srl assiston.
-- Fires whenever this bot's own target is a live hostile NPC the raid isn't
-- already fighting -- covers the first pull of a session and any time this
-- bot's own target changes to something new.
local TankAssistDecision = {}
TankAssistDecision.__index = TankAssistDecision

local REPULSE_MS = 30000 -- re-announce assist on the same target periodically, cheap safety net
local DEBUG_THROTTLE_MS = 3000 -- min gap between "why didn't I call assist" diagnostics

function TankAssistDecision:new(config)
    local self = setmetatable({}, TankAssistDecision)
    self.name = "TankAssistDecision"
    self.config = config
    self.safeWhileInvis = true
    self.pendingId = nil
    self.lastBroadcastAt = 0
    return self
end

-- Ground-truth check, independent of Pull.lua's own internal state tracking:
-- is this candidate actually within Pull.CampDragDistance of camp with LoS on us? Pull's state can get
-- out of sync with reality (aborts back to 'idle' on a mid-cycle safety net
-- without the mob having gone anywhere -- see the mid-drag abort in Pull.lua),
-- so gating solely on "Pull thinks it's still working on it" isn't reliable.
-- No camp set at all means there's no camp concept in play -- don't gate.
function TankAssistDecision:nearCampWithLoS(spawnId)
    local camp = State.pull.camp
    if not camp then return true end

    local spawn = mq.TLO.Spawn('id ' .. tostring(spawnId))
    if not spawn() then return false end
    if not spawn.LineOfSight() then return false end

    -- Measure the mob's distance to camp, not ours -- gating on our own
    -- position deadlocked when the tank was off camp (nothing walks it home
    -- while aggressive mobs are up, and assist never got called).
    local nearDist = (self.config and self.config:get('Pull.CampDragDistance')) or 80
    local dx, dy, dz = (spawn.X() or 0) - camp.x, (spawn.Y() or 0) - camp.y, (spawn.Z() or 0) - camp.z
    return math.sqrt(dx * dx + dy * dy + dz * dz) <= nearDist
end

-- Throttled diagnostic for the silent "returned 0" paths below, so it's
-- visible why no assist got called while a hostile is targeted/on xtarget.
function TankAssistDecision:debugSkip(reason, ctx)
    local now = mq.gettime()
    if now - (self.lastDebugAt or 0) < DEBUG_THROTTLE_MS then return end
    self.lastDebugAt = now

    local target = mq.TLO.Target
    local camp = State.pull.camp
    local mobToCamp
    if camp and (target.ID() or 0) ~= 0 then
        local dx, dy, dz = (target.X() or 0) - camp.x, (target.Y() or 0) - camp.y, (target.Z() or 0) - camp.z
        mobToCamp = math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    -- Per-mob view of the aggressive xtargets: this is what the camp+LoS gate
    -- actually evaluates when nothing usable is targeted.
    local xtInfo = {}
    for _, xt in ipairs(ctx.xtargets or {}) do
        if xt.type == 'NPC' and not xt.dead and xt.aggressive then
            local sp = mq.TLO.Spawn('id ' .. tostring(xt.id))
            local d
            if camp and sp() then
                local dx, dy, dz = (sp.X() or 0) - camp.x, (sp.Y() or 0) - camp.y, (sp.Z() or 0) - camp.z
                d = math.sqrt(dx * dx + dy * dy + dz * dz)
            end
            table.insert(xtInfo, string.format('%s(id=%s toCamp=%s los=%s)',
                tostring(xt.name), tostring(xt.id),
                d and string.format('%.1f', d) or 'nil', tostring(sp() and sp.LineOfSight())))
        end
    end
    print(string.format(
        '[SRL] TankAssist skip [v2 mob-to-camp gate]: %s | target=%s id=%s aggressive=%s los=%s | camp=%s targetToCamp=%s limit(CampDragDistance)=%s | assist.targetId=%s assist.targetName=%s | xtAggressive=%s [%s]',
        reason,
        tostring(target.CleanName()), tostring(target.ID()),
        tostring(target.Aggressive()), tostring(target.LineOfSight()),
        camp and 'set' or 'none',
        mobToCamp and string.format('%.1f', mobToCamp) or 'nil',
        tostring((self.config and self.config:get('Pull.CampDragDistance')) or 80),
        tostring(State.assist.targetId), tostring(State.assist.targetName),
        tostring(ctx.numberOfAggresiveInXTar), table.concat(xtInfo, ', ')))
end

-- Nearest aggressive NPC on xtarget that failed the camp gate but is still a
-- reasonable pull: line of sight, within Pull.Radius of camp, and within 200 of
-- us (a mezzed mob is inside the enchanter's cast range, so it can't be farther
-- than that). Only called when nothing aggressive is inside the camp radius.
function TankAssistDecision:findFarAggressive(ctx)
    local camp = State.pull.camp
    if not camp then return nil end

    local radius = (self.config and self.config:get('Pull.Radius')) or 100
    local bestId, bestDist
    for _, xt in ipairs(ctx.xtargets or {}) do
        if xt.type == 'NPC' and not xt.dead and xt.aggressive
                and tostring(xt.id) ~= tostring(State.assist.targetId) then
            local sp = mq.TLO.Spawn('id ' .. tostring(xt.id))
            if sp() and sp.LineOfSight() then
                local dx, dy, dz = (sp.X() or 0) - camp.x, (sp.Y() or 0) - camp.y, (sp.Z() or 0) - camp.z
                local toCamp = math.sqrt(dx * dx + dy * dy + dz * dz)
                local toMe = sp.Distance() or math.huge
                if toCamp <= radius and toMe <= 200 and (not bestDist or toMe < bestDist) then
                    bestId, bestDist = xt.id, toMe
                end
            end
        end
    end
    return bestId
end

function TankAssistDecision:score(ctx)
    self.pendingId = nil
    self.localOnly = false
    if State.flags.automode ~= 'tank' and State.flags.automode ~= 'tankpuller' then return 0 end

    local target = mq.TLO.Target
    local targetId = target.ID()
    -- Camp/LoS check is part of what makes a target "usable" here, not a
    -- separate early-out -- otherwise a stale/irrelevant current target that
    -- fails it short-circuits before ever falling through to check whether
    -- something else nearby (e.g. an already-mezzed add sitting at camp) is
    -- actually ready to engage.
    local hasLiveTarget = targetId and targetId ~= 0
        and target.Type() == 'NPC' and not target.Dead() and target.Aggressive()
        and self:nearCampWithLoS(targetId)

    if not hasLiveTarget then
        -- Nothing useful targeted -- if something's already aggressive (an
        -- add, a mob that got pulled indirectly, a pull we just abandoned)
        -- and nobody's called assist on it, pick it up directly rather than
        -- just sitting there with a stale/no target waiting for a human to
        -- manually retarget.
        -- An assist is already live: leave it to AssistDecision to retarget it.
        -- Otherwise (no live target yet, e.g. stale corpse target) we'd keep
        -- "claiming" a different xtarget every tick -- A, then B, then A... --
        -- and flood assist calls while AssistDecision (90 < 93) never gets to run.
        if State.assist.targetId then
            local assistSpawn = mq.TLO.Spawn('id ' .. tostring(State.assist.targetId))
            if assistSpawn() and not assistSpawn.Dead() then return 0 end
        end

        local pick = self:findUnclaimedAggressive(ctx)
        if not pick then
            -- Camp is clear (nothing aggressive inside the camp radius). A far
            -- aggressive mob -- typically one an enchanter has mezzed -- is what
            -- a player would go break and pull home. Engage it tank-only: set
            -- our own assist state without a raid broadcast, so only this
            -- client's AssistDecision acts. Once it's dragged inside the camp
            -- radius the normal path above announces it to the raid.
            local far = self:findFarAggressive(ctx)
            if far then
                self.pendingId = far
                self.localOnly = true
                return 93
            end
            -- Only worth reporting when there's actually a hostile around
            if (targetId and targetId ~= 0 and target.Type() == 'NPC') or (ctx.numberOfAggresiveInXTar or 0) > 0 then
                self:debugSkip('no usable target (not aggressive / failed camp+LoS gate) and no unclaimed aggressive xtarget', ctx)
            end
            return 0
        end
        self.pendingId = pick
        return 93
    end

    -- Same id AND name as our last broadcast -- genuinely the same ongoing
    -- engagement (id alone isn't a safe match: EQ recycles spawn ids, so a
    -- later mob could reuse an old target's id). Still re-pulse periodically
    -- as a cheap safety net in case a broadcast ever got missed.
    local sameEngagement = tostring(targetId) == tostring(State.assist.targetId)
        and target.CleanName() == State.assist.targetName
    if sameEngagement and mq.gettime() - self.lastBroadcastAt < REPULSE_MS then
        self:debugSkip('target already the announced assist (same id+name), within re-pulse window', ctx)
        return 0
    end

    self.pendingId = targetId
    return 93
end

-- First aggressive NPC on xtarget that isn't already the active raid assist
-- target (that one's already being handled by AssistDecision) and is
-- actually near camp with LoS -- see nearCampWithLoS.
function TankAssistDecision:findUnclaimedAggressive(ctx)
    for _, xt in ipairs(ctx.xtargets or {}) do
        if xt.type == 'NPC' and not xt.dead and xt.aggressive
                and tostring(xt.id) ~= tostring(State.assist.targetId)
                and self:nearCampWithLoS(xt.id) then
            return xt.id
        end
    end
    return nil
end

function TankAssistDecision:execute(ctx)
    if not self.pendingId then return end
    if self.localOnly then
        -- Tank-only engage: no raid broadcast. lastBroadcastAt reset so the
        -- real announcement fires as soon as the mob is back inside camp.
        State:updateAssistState({
            id = self.pendingId,
            name = mq.TLO.Spawn('id ' .. tostring(self.pendingId)).CleanName(),
            sender = mq.TLO.Me.Name(),
        })
        self.lastBroadcastAt = 0
        print(string.format('[SRL] TankAssist: camp clear, engaging far mob id=%s alone', tostring(self.pendingId)))
        return
    end
    AssistUtil.broadcastAssist(self.pendingId)
    self.lastBroadcastAt = mq.gettime()
end

return TankAssistDecision
