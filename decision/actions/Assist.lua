local mq = require 'mq'
local Target = require 'service.TargetService'
local State  = require 'core.State'
local MoveUtil = require 'util.MoveUtil'
local AssistDecision = {}
AssistDecision.__index = AssistDecision

local KNOCKBACK_BUFFER = 20 -- yards beyond stick distance before we treat it as a knockback

-- Same set Taunt.lua uses. Camp-drag is restricted to these classes even
-- though the underlying "who can actually drag the mob" question is really
-- about aggro, not class -- melee DPS shouldn't break off and run home mid-
-- fight just because they got unlucky and picked up aggro for a moment.
local TANK_CLASSES = { WAR = true, SHD = true, PAL = true }

local function resolveStickDist(ctx)
    return MoveUtil.resolveStickDist(ctx.assist.stickDistance, 10)
end

local function backgroundAssistEnabled(config)
    if State.flags.backgroundAssist ~= nil then return State.flags.backgroundAssist end
    if config then
        local v = config:get('AssistSettings.enabled')
        if v ~= nil then return v end
    end
    return true
end


function AssistDecision:new(config)
    local self = setmetatable({}, AssistDecision)
    self.name            = "AssistDecision"
    self.config           = config
    self.safeWhileInvis  = true  -- attacking breaks invis anyway; let the bot engage when called
    self.lastEngagedId   = nil   -- target ID we last issued /stick + /attack on for
    self.engagedInCombat = false -- true once the mob confirmed fighting back after engage
    self.lastPetAssistId = nil   -- assist ID the pet was last directed at
    self.mode            = nil   -- 'assist' | 'petattack' | 'campdrag'
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
    if not State.flags.automode then
        if ctx.isForeground then
            return 0
        end
        -- Backgrounded and not in automode: only auto-follow the active assist
        -- target if AssistSettings.enabled allows it (in-memory override via
        -- /srl backgroundassist wins over config; defaults to on).
        if not backgroundAssistEnabled(self.config) then
            return 0
        end
    end

    if ctx.assist.dead then
        mq.cmd('/attack off')
        mq.cmd('/stick off')
        self.lastEngagedId = nil
        return 0
    end

    -- A tank-class currently holding the mob's aggro drifted too far from
    -- camp -- mob knockback, fear, or a runner dragged the fight away from
    -- where the healer is standing. Drag it back to camp instead of just
    -- fighting wherever the knockback landed; the mob stays aggroed on
    -- whoever's dragging it, so it follows along as they reposition. Gated
    -- on holding aggro (not automode) since dragging only works if the mob
    -- is actually following you -- but restricted to tank classes so melee
    -- DPS doesn't break off and run home mid-fight over a momentary aggro
    -- flip. Takes priority over the normal re-stick checks below since being
    -- out of heal range is the more urgent problem.
    if TANK_CLASSES[ctx.myClass] and ctx.myCurrentTargetsTargetId and ctx.myCurrentTargetsTargetId == ctx.myId and State.pull.camp then
        local camp = State.pull.camp
        local dragDistance = (self.config and self.config:get('Pull.CampDragDistance')) or 80
        -- Real walkable path length, not straight-line distance -- see
        -- MoveUtil.pathLengthToLoc. nil means no path at all (unreachable/
        -- no mesh), which counts as "too far" -- execute() below will nav-
        -- then-warp-fallback the same way Pull.lua's tickReturn does.
        local dist = MoveUtil.pathLengthToLoc(camp.x, camp.y, camp.z)
        local tooFar = (not dist) or (dist > dragDistance)
        print(string.format(
            '[SRL] Assist: campdrag check -- me=(%.1f, %.1f) camp=(%.1f, %.1f) pathLen=%s threshold=%d %s',
            mq.TLO.Me.X() or 0, mq.TLO.Me.Y() or 0, camp.x, camp.y,
            dist and string.format('%.1f', dist) or 'NO PATH', dragDistance,
            tooFar and '-- DRAGGING' or '-- ok'))
        if tooFar then
            self.mode = 'campdrag'
            return 91
        end
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

    if self.mode == 'campdrag' then
        -- Deliberately NOT retargeting to ctx.assist.Id here -- score() based
        -- this on whatever's currently targeted having me as its ToT (i.e.
        -- actually aggroed on me right now), which could differ from the
        -- official assist target in an edge case (an add on me while the
        -- assist target is something else). Drag whatever's actually
        -- following, not necessarily the assist target.
        local camp = State.pull.camp
        local returnDist = (self.config and self.config:get('Pull.ReturnDist')) or 15
        if not mq.TLO.Navigation.Active() then
            mq.cmd('/stick off') -- don't fight /nav for movement control
            if not MoveUtil.navToLoc(camp.x, camp.y, camp.z, returnDist) then
                -- No mesh path -- usually a wall/disconnected area between
                -- here and camp. Warp straight there (MQWarp bypasses
                -- collision/pathing) rather than giving up and fighting on
                -- the wrong side of the wall forever. Requires MQWarp.ini
                -- [Settings] Enabled=1 -- if off, the warp silently no-ops
                -- and the distance check below falls through to normal fight.
                mq.cmdf('/warp loc %s %s %s', camp.y, camp.x, camp.z)
                mq.delay(200)
                if MoveUtil.distanceToLoc(camp.x, camp.y) > returnDist then
                    self.mode = nil
                end
            end
        end
        mq.cmd('/attack on')
        if self.mode == 'campdrag' then return end
    end

    if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end -- hand movement control back from a just-finished camp drag

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
