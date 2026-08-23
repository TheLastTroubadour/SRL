local mq            = require 'mq'
local State         = require 'core.State'
local Target        = require 'service.TargetService'
local MoveUtil      = require 'util.MoveUtil'
local SpellUtil     = require 'util.SpellUtil'
local AssistUtil    = require 'util.AssistUtil'
local BroadcastUtil = require 'util.BroadcastUtil'

local STUCK_TIMEOUT_MS = 15000
local NO_CANDIDATE_WARN_MS = 10000 -- throttle for the "no mobs found" print so idle re-checks every tick don't spam it

-- Active KissAssist-style puller: finds an untagged mob near camp, tags it,
-- drags it back to camp, and hands off to the raid via the same Assist event
-- pipeline as /srl assiston. Runs as a per-tick state machine (not a blocking
-- coroutine) so Heal/CC/Resource can still preempt the puller mid-cycle.
--
-- automode='tankpuller' reuses this entire pipeline but holds the mob at
-- camp itself instead of handing off to someone else -- TankAssistDecision
-- (also gated to allow 'tankpuller') notices the live target and broadcasts
-- assist for the raid, same as a normal standalone tank would.
local PullDecision = {}
PullDecision.__index = PullDecision

function PullDecision:new(config)
    local self = setmetatable({}, PullDecision)
    self.name = "PullDecision"
    self.config = config
    self.state = 'idle'
    self.candidateId = nil
    self.stateStartTs = 0
    self.healerHold = false
    return self
end

function PullDecision:setDanNetHpService(danNetHpService)
    self.danNetHpService = danNetHpService
end

function PullDecision:setStatusService(statusService)
    self.statusService = statusService
end

-- Won't start a new pull while anyone in the EQ group is dead -- dragging in
-- another mob on top of a group that's already down a member just compounds
-- the wipe. Uses the self-reported char_status broadcast (StatusService)
-- rather than reading Dead() off our copy of their group-member spawn, since
-- self-reported death doesn't depend on our own client's view of their spawn
-- (out of range/zone, etc.) being current.
function PullDecision:groupHasDead(ctx)
    if ctx.dead then return true end
    if not self.statusService then return false end

    local gCount = mq.TLO.Me.GroupSize() or 0
    for i = 1, gCount do
        local m = mq.TLO.Group.Member(i)
        if m() then
            local name = m.CleanName()
            if name and self.statusService:isDead(name) then
                return true
            end
        end
    end
    return false
end

-- Any group member (including the puller itself) below Pull.HealerMedThreshold
-- on mana OR endurance -- whichever resource their class actually has, see the
-- HAS_MANA_CLASS gating in CombatContext.lua -- holds off the NEXT pull.
-- Doesn't touch a pull already in flight, just stops the puller from starting
-- a new one.
-- Hysteresis: once a hold is active, require the higher HealerMedResumeThreshold
-- (not just the trigger threshold) before clearing it -- otherwise the puller
-- would resume the instant a resource ticks back over 30% while the med break
-- (which rests everyone toward 100%) is still in progress.
function PullDecision:healersReady(ctx)
    local threshold = self.healerHold
        and (self.config:get('Pull.HealerMedResumeThreshold') or 90)
        or (self.config:get('Pull.HealerMedThreshold') or 30)

    for _, member in ipairs(ctx.groupMembers or {}) do
        -- Dead members never regen mana/endurance, so one stale low reading
        -- would otherwise jam the hold forever.
        if not member.hp or member.hp <= 0 then goto continueMember end

        -- Prefer the DanNet-reported value (member self-reporting their own
        -- mana/endurance, no reliability question) over the class-based
        -- ctx.groupMembers reading when we have one.
        local mana = (self.danNetHpService and self.danNetHpService:getMana(member.name)) or member.mana
        local endurance = (self.danNetHpService and self.danNetHpService:getEndurance(member.name)) or member.endurance

        if mana and mana < threshold then
            return false, member.name
        end
        if endurance and endurance < threshold then
            return false, member.name
        end

        ::continueMember::
    end
    return true
end

function PullDecision:score(ctx)
    if State.flags.automode ~= 'puller' and State.flags.automode ~= 'tankpuller' then
        self:abort()
        return 0
    end
    if not State.pull.camp then return 0 end

    -- Safety net: score() runs every tick on every module regardless of which
    -- one actually wins, so this can fire even if Pull keeps losing the
    -- DecisionEngine comparison to something else (CrowdControl mez scores up
    -- to 120, well above Pull's 95). Without this, a starved mid-cycle state
    -- machine would never reach its own tick*() timeout checks -- those only
    -- run inside execute(), which never gets called while Pull keeps losing --
    -- so the puller could sit frozen (not fighting, not fleeing, not
    -- returning) indefinitely instead of just past the intended 15s.
    if self.state ~= 'idle' and mq.gettime() - self.stateStartTs > STUCK_TIMEOUT_MS then
        print(string.format('[SRL] Pull: stuck in state "%s" past timeout (likely starved by a higher-priority action), aborting', self.state))
        self:abort()
        return 0
    end

    local isBard = ctx.myClass == 'BRD'
    if ctx.casting and not isBard then return 0 end

    -- The idle-state MaxActive gate only stops a NEW pull from starting --
    -- it doesn't re-check once one's already in flight. Without this, a mid-
    -- cycle pull just keeps grinding through its own state machine no matter
    -- how many other mobs pile up in the meantime (adds, chain aggro, etc.),
    -- tunnel-visioned on its own candidate instead of ever yielding to help
    -- fight what's already active. > not >= since a successful pull's own
    -- candidate becoming aggressive is expected and shouldn't self-abort.
    if self.state ~= 'idle' then
        local maxActive = self.config:get('Pull.MaxActive') or 1
        if (ctx.numberOfAggresiveInXTar or 0) > maxActive then
            print(string.format('[SRL] Pull: %d mobs already aggressive mid-pull, aborting to help fight',
                ctx.numberOfAggresiveInXTar))
            self:abort()
            return 0
        end
    end

    if self.state == 'idle' then
        if self:groupHasDead(ctx) then
            if not self.deadHold then
                self.deadHold = true
                print('[SRL] Pull: holding, a group member is dead')
            end
            return 0
        end
        if self.deadHold then
            self.deadHold = false
            print('[SRL] Pull: group member back up, resuming')
        end

        local maxActive = self.config:get('Pull.MaxActive') or 1
        if (ctx.numberOfAggresiveInXTar or 0) >= maxActive then return 0 end

        local ready, lowName = self:healersReady(ctx)
        if not ready then
            if not self.healerHold then
                self.healerHold = true
                print(string.format('[SRL] Pull: holding, %s is low on mana/endurance -- calling med break', tostring(lowName)))
                local me = mq.TLO.Me.Name()
                mq.cmdf('%s /srlevent MedFull sender=%s', BroadcastUtil.prefix(self.config), me)
                mq.cmdf('/srlevent MedFull sender=%s', me)
            end
            return 0
        end
        if self.healerHold then
            self.healerHold = false
            print('[SRL] Pull: healer mana recovered, resuming')
            -- MedFull forces sitting until ResourceDecision's own stopThreshold
            -- (100%), well above our resume threshold (default 90%) -- without
            -- this, Pull would start dragging a new mob back while people are
            -- still explicitly forced to sit.
            local me = mq.TLO.Me.Name()
            mq.cmdf('%s /srlevent MedOff sender=%s', BroadcastUtil.prefix(self.config), me)
            mq.cmdf('/srlevent MedOff sender=%s', me)
        end

        local candidate = self:findPullTarget(ctx)
        if not candidate then return 0 end
        self.candidateId = candidate
    end

    return 95
end

function PullDecision:execute(ctx)
    if self.state == 'idle' then self:beginTravelOut(ctx)
    elseif self.state == 'travelOut' then self:tickTravelOut(ctx)
    elseif self.state == 'engaging' then self:tickEngage(ctx)
    elseif self.state == 'confirmingAggro' then self:tickConfirmAggro(ctx)
    elseif self.state == 'returning' then self:tickReturn(ctx)
    elseif self.state == 'handoff' then self:tickHandoff(ctx)
    end
end

function PullDecision:abort()
    if self.state ~= 'idle' then
        if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
        mq.cmd('/attack off')
    end
    self.state, self.candidateId = 'idle', nil
end

function PullDecision:getApproachDist()
    local spells = self.config:get('Pull.Spells') or {}
    local first = spells[1]
    if first and first.range then return first.range end
    return 15
end

function PullDecision:findPullTarget(ctx)
    local camp = State.pull.camp
    local radius = self.config:get('Pull.Radius') or 100
    local zRange = self.config:get('Pull.MaxZRange') or 70
    local searchStr = string.format('npc radius %d zradius %d loc %s %s %s', radius, zRange, camp.y, camp.x, camp.z)
    local count = mq.TLO.SpawnCount(searchStr)() or 0

    -- KissAssist-style selection for nav-based pulling: reject candidates
    -- MQ2Nav has no path to at all, then pick whichever has the SHORTEST
    -- real path length -- not raw radial distance -- since a mob that's
    -- radially closer but behind a long detour can take longer to reach
    -- than a slightly-farther mob with a clean path.
    local bestId, bestPathLen = nil, nil
    for i = 1, count do
        local spawn = mq.TLO.NearestSpawn(i, searchStr)
        if spawn() then
            local id = spawn.ID()
            if id and id ~= 0 and id ~= State.charm.petId
                and not spawn.Dead() and not spawn.Aggressive() then
                local pathLen = mq.TLO.Navigation.PathLength('id ' .. id)()
                if pathLen and pathLen > 0 and (not bestPathLen or pathLen < bestPathLen) then
                    bestId, bestPathLen = id, pathLen
                end
            end
        end
    end

    if not bestId then
        local now = mq.gettime()
        if not self.lastNoCandidateWarn or now - self.lastNoCandidateWarn > NO_CANDIDATE_WARN_MS then
            self.lastNoCandidateWarn = now
            print(string.format(
                '[SRL] Pull: no valid candidates (radius=%d zradius=%d loc %s %s %s) -- %d spawn(s) in radius, none usable (dead/already-aggressive/no path)',
                radius, zRange, camp.y, camp.x, camp.z, count))
        end
    end

    return bestId
end

function PullDecision:beginTravelOut(ctx)
    Target:getTargetById(self.candidateId)
    -- No dist= here -- KissAssist-style: nav all the way and stop ourselves
    -- (see tickTravelOut) rather than trusting /nav's own stop-distance handling.
    mq.cmdf('/nav id %s', self.candidateId)
    self.state = 'travelOut'
    self.stateStartTs = mq.gettime()
end

function PullDecision:tickTravelOut(ctx)
    local spawn = mq.TLO.Spawn('id ' .. self.candidateId)
    if not spawn() or spawn.Dead() then
        self:abort()
        return
    end

    -- Poll real distance every tick and explicitly stop once close enough,
    -- same as KissAssist's PullUsingNav -- more responsive/reliable than
    -- waiting on /nav's own dist= handling, and lets us react mid-approach.
    local dist3D = spawn.Distance3D()
    if dist3D and dist3D <= self:getApproachDist() then
        if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
        self.state = 'engaging'
        self.stateStartTs = mq.gettime()
        return
    end

    -- Mob fled/kited us too far from camp -- abandon rather than chase
    -- indefinitely outside the intended pull area.
    local camp = State.pull.camp
    local radius = self.config:get('Pull.Radius') or 100
    if camp and MoveUtil.distanceToLoc(camp.x, camp.y) > radius * 0.95 then
        print('[SRL] Pull: chase exceeded pull radius, abandoning')
        self:abort()
        return
    end

    -- Nav stopped short of arrival (lost path, obstacle, etc.) -- retry
    if not mq.TLO.Navigation.Active() then
        mq.cmdf('/nav id %s', self.candidateId)
    end

    if mq.gettime() - self.stateStartTs > STUCK_TIMEOUT_MS then
        print('[SRL] Pull: stuck traveling to target, aborting')
        self:abort()
    end
end

function PullDecision:tickEngage(ctx)
    local spawn = mq.TLO.Spawn('id ' .. self.candidateId)
    if not spawn() or spawn.Dead() then
        self:abort()
        return
    end

    if mq.TLO.Target.ID() ~= self.candidateId then
        Target:getTargetById(self.candidateId)
    end

    if not spawn.LineOfSight() then
        -- No LoS from here (this is the fallback-candidate case) -- keep closing
        -- distance/navving around obstacles until LoS clears, then fall through to cast.
        if not mq.TLO.Navigation.Active() then
            mq.cmdf('/nav id %s dist=5', self.candidateId)
        end
        if mq.gettime() - self.stateStartTs > STUCK_TIMEOUT_MS then
            print('[SRL] Pull: stuck trying to get LoS on target, aborting')
            self:abort()
        end
        return
    end

    local spells = self.config:get('Pull.Spells') or {}
    for _, entry in ipairs(spells) do
        local entryType = entry.type or 'spell'
        local name = SpellUtil.resolveRank(entry.spell, entryType)
        local ready
        if entryType == 'item' then
            local item = mq.TLO.FindItem('=' .. entry.spell)
            ready = item() and (item.TimerReady() or 1) == 0
        elseif entryType == 'aa' then
            ready = mq.TLO.Me.AltAbilityReady(entry.spell)() == true
        elseif entryType == 'ability' then
            ready = mq.TLO.Me.AbilityReady(entry.spell)() == true
        else
            ready = mq.TLO.Me.SpellReady(name)() == true
        end

        if ready then
            if entryType == 'item' then
                mq.cmdf('/useitem "%s"', entry.spell)
                mq.delay(1000)
            elseif entryType == 'aa' then
                mq.cmdf('/alt activate "%s"', entry.spell)
                mq.delay(1500)
            elseif entryType == 'ability' then
                mq.cmdf('/doability "%s"', entry.spell)
                mq.delay(500)
            else
                local gem = mq.TLO.Me.Gem(name)() or entry.gem
                if gem then
                    local castTime = (mq.TLO.Spell(name).CastTime.TotalSeconds() or 1) * 1000 + 1500
                    mq.cmdf('/cast %s', gem)
                    mq.delay(1000, function() return mq.TLO.Me.Casting() ~= nil end)
                    mq.delay(castTime, function() return not mq.TLO.Me.Casting() end)
                end
            end
            self.state = 'confirmingAggro'
            self.stateStartTs = mq.gettime()
            return
        end
    end

    -- nothing configured/ready: melee fallback
    mq.cmd('/attack on')
    self.state = 'confirmingAggro'
    self.stateStartTs = mq.gettime()
end

function PullDecision:tickConfirmAggro(ctx)
    local spawn = mq.TLO.Spawn('id ' .. self.candidateId)
    if not spawn() or spawn.Dead() then
        mq.cmd('/attack off')
        self:abort()
        return
    end

    local targetIsCandidate = mq.TLO.Target.ID() == self.candidateId
    local aggroed = mq.TLO.Me.Combat()
        or (targetIsCandidate and mq.TLO.Target.TargetOfTarget.ID() == mq.TLO.Me.ID())
        or (targetIsCandidate and (mq.TLO.Target.PctAggro() or 0) > 0)
    local timedOut = mq.gettime() - self.stateStartTs > STUCK_TIMEOUT_MS

    if aggroed or timedOut then
        mq.cmd('/attack off')
        mq.cmd('/stick off')

        if timedOut and not aggroed and State.pull.camp then
            -- Never got aggro before timing out -- likely stuck on broken
            -- geometry (can't reach/see the candidate at all), same failure
            -- mode as the return-to-camp nav gap. Warp straight back to camp
            -- to reset rather than transitioning into 'returning' and hoping
            -- nav can path out of the same stuck spot.
            local camp = State.pull.camp
            print('[SRL] Pull: stuck confirming aggro, warping back to camp')
            mq.cmdf('/warp loc %s %s %s', camp.y, camp.x, camp.z)
        end

        self.state = 'returning'
        self.stateStartTs = mq.gettime()
    end
end


function PullDecision:tickReturn(ctx)
    local camp = State.pull.camp
    if not camp then
        self:abort()
        return
    end

    local returnDist = self.config:get('Pull.ReturnDist') or 15
    if MoveUtil.distanceToLoc(camp.x, camp.y) <= returnDist then
        if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
        self.state = 'handoff'
        self.stateStartTs = mq.gettime()
        return
    end

    if not mq.TLO.Navigation.Active() then
        if not MoveUtil.navToLoc(camp.x, camp.y, camp.z, returnDist) then
            -- No mesh path at all -- usually means we're standing somewhere
            -- off-mesh (clipped into geometry, e.g. under a staircase), so
            -- ANY nav target would fail the same way, camp included. Warp
            -- straight there (MQWarp bypasses collision/pathing entirely)
            -- to reset the position instead of leaving the character stuck
            -- in that same broken spot. Requires MQWarp.ini [Settings]
            -- Enabled=1 -- if it's off, the warp silently no-ops and the
            -- distance check below just falls through to the normal abort.
            print('[SRL] Pull: no path back to camp, warping to reset')
            mq.cmdf('/warp loc %s %s %s', camp.y, camp.x, camp.z)
            mq.delay(200)
            if MoveUtil.distanceToLoc(camp.x, camp.y) <= returnDist then
                self.state = 'handoff'
                self.stateStartTs = mq.gettime()
                return
            end
            print('[SRL] Pull: warp failed (MQWarp disabled?), aborting')
            self:abort()
            return
        end
    end

    if mq.gettime() - self.stateStartTs > STUCK_TIMEOUT_MS then
        print('[SRL] Pull: stuck returning to camp, aborting')
        self:abort()
    end
end

function PullDecision:tickHandoff(ctx)
    local spawn = mq.TLO.Spawn('id ' .. self.candidateId)
    if not spawn() or spawn.Dead() then
        -- Died/vanished before hand-off -- nothing to broadcast
        self.state = 'idle'
        self.candidateId = nil
        return
    end

    if not spawn.LineOfSight() then
        -- Too early -- mob hasn't caught up / LoS still blocked. Wait rather
        -- than calling assist onto something the raid can't actually see yet.
        if mq.gettime() - self.stateStartTs > STUCK_TIMEOUT_MS then
            print('[SRL] Pull: no LoS on candidate at camp after timeout, handing off anyway')
        else
            return
        end
    end

    if State.flags.automode == 'tankpuller' then
        -- Hold and tank it ourselves rather than handing off to someone else --
        -- re-engage attack (tickConfirmAggro turned it off for the drag back),
        -- make sure we're targeting the candidate, then let TankAssistDecision
        -- (now allowed for tankpuller too) notice this live target and
        -- broadcast assist for the raid on its own, same as a normal tank.
        if mq.TLO.Target.ID() ~= self.candidateId then
            Target:getTargetById(self.candidateId)
        end
        mq.cmd('/attack on')
    else
        AssistUtil.broadcastAssist(self.candidateId)
    end
    self.state = 'idle'
    self.candidateId = nil
end

return PullDecision
