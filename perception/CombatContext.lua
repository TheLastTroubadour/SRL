local mq = require 'mq'
local RoleService = require 'service.RoleService'
local State = require 'core.State'
local TableUtil = require 'util.TableUtil'
local Context = {}
Context.__index = Context

-- WAR/MNK/ROG/BER have no mana pool at all. Everyone else (priests, pure
-- casters, hybrids) does.
local HAS_MANA_CLASS = {
    CLR = true, DRU = true, SHM = true,
    NEC = true, WIZ = true, MAG = true, ENC = true,
    PAL = true, RNG = true, SHD = true, BST = true,
}
Context.HAS_MANA_CLASS = HAS_MANA_CLASS -- exposed so other modules (Pull.lua) can gate DanNet mana fallbacks the same way

function Context:new(config)
    local self = setmetatable({}, Context)
    self.config = config

    -- Static per-session fields — queried once, reused every tick
    self.myName  = mq.TLO.Me.Name()
    self.myId    = mq.TLO.Me.ID()
    self.myClass = mq.TLO.Me.Class.ShortName()

    self.heal = {
        spells = config:get('Heals.Spells') or {},
        tanks = TableUtil.toList(config:get('Heals.Tanks')),
        importantBots = TableUtil.toList(config:get('Heals.ImportantBots'))
    }

    self.assistType       = config:get('AssistSettings.type') or 'off'
    self.stickPoint       = config:get('AssistSettings.meleeStickPoint') or 'behind'
    self.stickDistance    = config:get('AssistSettings.meleeStickDistance') or 10
    self:reloadSet('Main')
    return self
end

function Context:setStatusService(statusService)
    self.statusService = statusService
end

function Context:setDanNetHpService(danNetHpService)
    self.danNetHpService = danNetHpService
end

-- StatusService first -- it self-corrects every main-loop tick and explicitly
-- expires after 15s of silence (see StatusService.EXPIRY_MS), so it can't
-- silently freeze on a stale value. DanNet observers were tried first
-- previously (their push isn't gated behind the peer's own Lua script being
-- mid-cast in an mq.delay), but proved capable of getting stuck reporting a
-- stale value indefinitely with no expiry of their own -- confirmed live:
-- an observer kept reporting 50% for a peer who was actually at full HP.
-- DanNet is now only the fallback, for a peer whose own script isn't
-- running/reporting via StatusService at all. Never spawn HP.
function Context:getPeerHp(name)
    if self.statusService then
        local hp = self.statusService:getHp(name)
        if hp then return hp end
    end
    return self.danNetHpService and self.danNetHpService:getHp(name)
end

-- True if this tank currently appears to be the one actively getting
-- attacked (high self-reported aggro on their own target), not just
-- "configured as a tank in Heals.Tanks". MQ2SpawnType has no field for who a
-- mob is currently targeting, so each tank has to self-report via the
-- char_status aggro field -- self reads live (always accurate, no broadcast
-- round-trip needed).
local TANKING_AGGRO_THRESHOLD = 80

function Context:isPeerTanking(name)
    if name == mq.TLO.Me.Name() then
        return (mq.TLO.Me.PctAggro() or 0) >= TANKING_AGGRO_THRESHOLD
    end
    if self.statusService then
        local aggro = self.statusService:getAggro(name)
        if aggro then return aggro >= TANKING_AGGRO_THRESHOLD end
    end
    return false
end

function Context:setStickPoint(point)
    self.stickPoint = point
end

function Context:setStickDist(dist)
    if dist == nil or dist == '' then return end
    self.stickDistance = dist
end

function Context:reloadSet(set)
    local onAssist  = self.config:get('Debuff.DebuffOnAssist.' .. set) or {}
    local onCommand = self.config:get('Debuff.DebuffOnCommand.' .. set) or {}
    local onXTar    = self.config:get('Debuff.DebuffOnXTar.' .. set) or {}

    self.debuff = {
        onAssistSpells  = self:sortByPriority(#onAssist  > 0 and onAssist  or (self.config:get('Debuff.DebuffOnAssist.Main')  or {})),
        onCommandSpells = self:sortByPriority(#onCommand > 0 and onCommand or (self.config:get('Debuff.DebuffOnCommand.Main') or {})),
        enabledForXTar  = self.config:get('Debuff.DebuffTargetsOnXTarEnabled') or false,
        onXTarSpells    = self:sortByPriority(#onXTar    > 0 and onXTar    or (self.config:get('Debuff.DebuffOnXTar.Main')    or {})),
        minXTarTargets  = self.config:get('Debuff.MinimumAmountToStartDebuffOnXTar') or 2
    }

    local dotsOnAssist  = self.config:get('Dots.DotsOnAssist.' .. set) or {}
    local dotsOnCommand = self.config:get('Dots.DotsOnCommand.' .. set) or {}

    self.dot = {
        onAssistSpells  = self:sortByPriority(#dotsOnAssist  > 0 and dotsOnAssist  or (self.config:get('Dots.DotsOnAssist.Main')  or {})),
        onCommandSpells = self:sortByPriority(#dotsOnCommand > 0 and dotsOnCommand or (self.config:get('Dots.DotsOnCommand.Main') or {})),
    }
end

function Context:build(state)

    local ctx = {}
    ctx.assist = {}
    ctx.self = {}

    ctx.assist.assistType    = self.assistType
    ctx.assist.stickPoint    = self.stickPoint
    ctx.assist.stickDistance = self.stickDistance

    -- Static fields (never change per session)
    ctx.myName      = self.myName
    ctx.myId        = self.myId
    ctx.myClass     = self.myClass
    ctx.myCleanName = mq.TLO.Me.CleanName()

    ctx.self.Id = ctx.myId
    ctx.mana = mq.TLO.Me.PctMana()
    ctx.currentMana = mq.TLO.Me.CurrentMana()
    ctx.hp = mq.TLO.Me.PctHPs()
    ctx.endurance = mq.TLO.Me.PctEndurance()
    ctx.moving = mq.TLO.Me.Moving()
    ctx.casting  = mq.TLO.Me.Casting()
    ctx.sitting  = mq.TLO.Me.Sitting()
    ctx.stunned  = mq.TLO.Me.Stunned()
    ctx.silenced = mq.TLO.Me.Silenced()
    ctx.feared   = mq.TLO.Me.Feared()
    ctx.dead     = mq.TLO.Me.Dead()
    ctx.invis    = mq.TLO.Me.Invis()

    -- Per-tick fields computed once and shared
    ctx.aggro      = mq.TLO.Me.PctAggro() or 0
    ctx.activeDisc = mq.TLO.Me.ActiveDisc()

    ctx.isForeground = mq.TLO.EverQuest.Foreground()

    ctx.roles = RoleService:getRoles()
    ctx.addCount = nil

    ctx.myCurrentTargetId = mq.TLO.Target.ID()

    --Target of Current Target
    -- Me.TargetOfTarget (not Target.TargetOfTarget) is the TLO that actually
    -- populates -- it returns the character/mob name as a string, so resolve
    -- it through Spawn to get a usable id.
    local totName = mq.TLO.Me.TargetOfTarget()
    ctx.myCurrentTargetsTargetId = totName and mq.TLO.Spawn('=' .. totName).ID() or nil

    --target info
    ctx.assist.Id = State.assist.targetId

    if ctx.assist.Id then
        local spawn = mq.TLO.Spawn('id ' .. tostring(ctx.assist.Id))
        if spawn() and not spawn.Dead() then
            ctx.assist.distance = spawn.Distance()
            ctx.assist.HP = spawn.PctHPs()
            ctx.assist.lineOfSight = spawn.LineOfSight()
            ctx.assist.dead = false
        elseif spawn() and spawn.Dead() then
            -- Confirmed dead — clear everything
            State.assist.targetId = nil
            ctx.assist.HP = nil
            ctx.assist.distance = nil
            ctx.assist.Id = nil
            ctx.assist.dead = true
        else
            -- Spawn not yet visible to this client — preserve State for retry next tick,
            -- nil ctx.Id so decisions idle rather than acting on an invisible mob
            ctx.assist.Id = nil
            ctx.assist.HP = nil
            ctx.assist.distance = nil
            ctx.assist.lineOfSight = nil
            ctx.assist.dead = false
        end
    end

    -- Build XTarget list once; derive numberOfAggressive from it
    ctx.xtargets = {}
    local numberOfAggressive = 0
    local slots = mq.TLO.Me.XTargetSlots()
    for i = 1, slots do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() then
            local entry = {
                id         = xt.ID(),
                name       = xt.CleanName(),
                type       = xt.Type(),
                aggressive = xt.Aggressive(),
                dead       = xt.Dead(),
                hp         = xt.PctHPs(),
            }
            table.insert(ctx.xtargets, entry)
            if entry.type == 'NPC' and not entry.dead and entry.aggressive then
                numberOfAggressive = numberOfAggressive + 1
            end
        end
    end

    ctx.numberOfAggresiveInXTar = numberOfAggressive

    -- Group member list (self + live group members); used by Rez/Heal/Shrink/Pull/etc.
    -- mana only included for classes that actually have a mana pool -- MaxMana()
    -- is NOT a real GroupMember field (falls through to Spawn.MaxMana(), which is
    -- only reliable for yourself; for other group members it can read back
    -- garbage instead of a clean 0, so a real 0-mana melee class could spuriously
    -- pass a "> 0" gate). Class is a real, always-correct GroupMember field, so
    -- use that instead. PctMana()/PctEndurance() themselves ARE reliable for
    -- group members (same live-percentage broadcast that makes PctHPs trustworthy),
    -- it's only the Max* pool-size fields that fall back to unreliable spawn data.
    ctx.groupMembers = {}
    table.insert(ctx.groupMembers, {
        id        = ctx.myId,
        name      = ctx.myName,
        hp        = ctx.hp,
        mana      = HAS_MANA_CLASS[ctx.myClass] and ctx.mana or nil,
        endurance = ctx.endurance,
        class     = ctx.myClass,
        dead      = false,
    })
    local gCount = mq.TLO.Group.Members()
    for i = 1, gCount do
        local m = mq.TLO.Group.Member(i)
        if m() and m.Spawn() and not m.Dead() then
            local mClass = m.Class.ShortName()
            table.insert(ctx.groupMembers, {
                id        = m.ID(),
                name      = m.CleanName(),
                hp        = m.PctHPs(),
                mana      = HAS_MANA_CLASS[mClass] and m.PctMana() or nil,
                endurance = m.PctEndurance(),
                class     = mClass,
                dead      = false,
            })
        end
    end

    ctx.inCombat = mq.TLO.Me.Combat()

    --healing
    if ctx.roles['healer'] then
        ctx.self.heal = {}
        ctx.self.heal.group = {}
        ctx.self.heal.group.memberStatus = {}
        if next(self.heal.spells) then
            for _,roleSpells in pairs(self.heal.spells) do
                table.sort(roleSpells,function(a,b)
                    return a.threshold < b.threshold
                end)
            end
            ctx.self.heal.spells = self.heal.spells
            ctx.self.heal.group.members = mq.TLO.Group.Members()

            local seen = {}

            -- Always include self as a heal target
            local myName = mq.TLO.Me.Name()
            seen[myName] = true
            local myRole = self:getHealerRole(myName)
            table.insert(ctx.self.heal.group.memberStatus, {
                id      = mq.TLO.Me.ID(),
                name    = myName,
                hp      = mq.TLO.Me.PctHPs(),
                role    = myRole,
                inGroup = true,
                tanking = myRole == 'tank' and self:isPeerTanking(myName) or false,
            })

            for i = 1, ctx.self.heal.group.members do
                local m = mq.TLO.Group.Member(i)

                if m() and m.Spawn() and not m.Dead() then
                    local name = m.CleanName()
                    if name and not seen[name] then
                        seen[name] = true
                        local role = self:getHealerRole(name)
                        table.insert(ctx.self.heal.group.memberStatus, {
                            id      = m.ID(),
                            name    = name,
                            hp      = m.PctHPs(),
                            role    = role,
                            inGroup = true,
                            tanking = role == 'tank' and self:isPeerTanking(name) or false,
                        })
                    end
                end
            end

            -- Raid members
            -- NOTE: r.CleanName()/r.Dead() are NOT real RaidMember TLO fields (only
            -- Name/Group/GroupLeader/RaidLeader/Spawn/Looter/Class/Level are) -- calling
            -- them silently falls through to a SECOND independent GetSpawnByName lookup
            -- per call. r.Name() and r.Spawn are both native fields (single lookup),
            -- so use those instead of stacking two-to-three separate name resolutions
            -- that can each silently fail and drop the member with zero error output.
            local raidMembers = mq.TLO.Raid.Members() or 0
            for i = 1, raidMembers do
                local r = mq.TLO.Raid.Member(i)
                if r() then
                    local name = r.Name()
                    if name and not seen[name] then
                        local spawn = r.Spawn
                        -- spawn.PctHPs() is NOT trusted here -- raid data carries no native HP
                        -- field at all (see RaidMember struct in eqlib), so it silently falls
                        -- back to whatever this client last happened to sync for that spawn,
                        -- which can be badly stale (proven: read 71% for a target actually at
                        -- 100%). Only the bus-broadcast, self-reported HP is trustworthy -- if
                        -- this raid member isn't a known SRL peer reporting one, skip them
                        -- entirely rather than heal off a number that might just be wrong.
                        local hp = self:getPeerHp(name)
                        if spawn() and not spawn.Dead() and hp then
                            seen[name] = true
                            local role = self:getHealerRole(name)
                            table.insert(ctx.self.heal.group.memberStatus, {
                                id      = spawn.ID(),
                                name    = name,
                                hp      = hp,
                                role    = role,
                                inGroup = false,
                                tanking = role == 'tank' and self:isPeerTanking(name) or false,
                            })
                        end
                    end
                end
            end

            -- DanNet peers not already captured above (self/group/raid) -- lets healing
            -- work without a formal EQ raid, and covers the whole bot network
            -- automatically as people connect/disconnect (same philosophy as
            -- DanNetHpService:ensureObservers) instead of requiring every healer's
            -- Tanks/ImportantBots list to enumerate who's out there. Heals.Tanks/
            -- ImportantBots still matters -- getHealerRole cross-references it for
            -- priority (tank/important), falling back to normal for anyone unlisted.
            -- Peer-reported HP only (never spawn HP -- same staleness concern as raid
            -- members above). Requiring a resolvable, live nearby spawn for id/range
            -- doubles as the filter that keeps out peers who aren't actually in this
            -- zone (different server/session/task) -- their spawn just won't resolve.
            if self.danNetHpService then
                for _, name in ipairs(self.danNetHpService:getPeerNames()) do
                    if name and not seen[name] then
                        local hp = self:getPeerHp(name)
                        if hp then
                            local spawn = mq.TLO.Spawn(name)
                            if spawn() and not spawn.Dead() then
                                -- DanNet peer names aren't guaranteed to match display
                                -- casing (Me.Name()/CleanName()) -- re-derive the real
                                -- name from the resolved spawn so seen[]/getHealerRole
                                -- compare correctly against self and the properly-cased
                                -- Heals.Tanks/ImportantBots entries.
                                local canonicalName = spawn.CleanName() or name
                                if not seen[canonicalName] then
                                    seen[canonicalName] = true
                                    local role = self:getHealerRole(canonicalName)
                                    table.insert(ctx.self.heal.group.memberStatus, {
                                        id      = spawn.ID(),
                                        name    = canonicalName,
                                        hp      = hp,
                                        role    = role,
                                        inGroup = false,
                                        tanking = role == 'tank' and self:isPeerTanking(canonicalName) or false,
                                    })
                                end
                            end
                        end
                    end
                end
            end

            -- XTarget friendly slots
            local xtSlots = mq.TLO.Me.XTargetSlots() or 0
            for i = 1, xtSlots do
                local xt = mq.TLO.Me.XTarget(i)
                if xt() and not xt.Dead() and xt.Type() ~= 'NPC' and not xt.Aggressive() then
                    local name = xt.CleanName()
                    if name and not seen[name] then
                        seen[name] = true
                        local role = self:getHealerRole(name)
                        table.insert(ctx.self.heal.group.memberStatus, {
                            id      = xt.ID(),
                            name    = name,
                            hp      = xt.PctHPs(),
                            role    = role,
                            inGroup = false,
                            tanking = role == 'tank' and self:isPeerTanking(name) or false,
                        })
                    end
                end
            end
        end
    end

    if ctx.roles['debuff'] then
        ctx.self.debuff = {
            onAssistSpells  = self.debuff.onAssistSpells,
            onCommandSpells = self.debuff.onCommandSpells,
            enabledForXTar  = self.debuff.enabledForXTar,
            minXTarTargets  = self.debuff.minXTarTargets,
            xTarSpells      = self.debuff.onXTarSpells
        }
    end

    if ctx.roles['dot'] then
        ctx.self.dot = {
            onAssistSpells  = self.dot.onAssistSpells,
            onCommandSpells = self.dot.onCommandSpells,
        }
    end

    return ctx
end

function Context:getHealerRole(name)
    for _,t in ipairs(self.heal.tanks) do
        if t == name then
            return "tank"
        end
    end

    for _,b in ipairs(self.heal.importantBots) do
        if b == name then
            return "important"
        end
    end

    return "normal"
end

function Context:sortByPriority(list)
    -- Preserve original order for ungrouped entries; sort by priority only within the same group.
    -- priority: true (boolean) is used by DebuffDecision for score boosting — ignore it here.
    for i, v in ipairs(list) do v._idx = i end
    table.sort(list, function(a, b)
        if a.group and b.group and a.group == b.group then
            local pa = type(a.priority) == 'number' and a.priority or 99
            local pb = type(b.priority) == 'number' and b.priority or 99
            return pa < pb
        end
        return a._idx < b._idx
    end)
    for _, v in ipairs(list) do v._idx = nil end
    return list
end

return Context