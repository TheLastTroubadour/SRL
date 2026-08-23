local mq = require 'mq'
local Job = require 'model.Job'
local TableUtil = require 'util.TableUtil'
local Target = require 'service.TargetService'
local SpellUtil = require 'util.SpellUtil'
local State = require 'core.State'
local HealDecision = {}

HealDecision.__index = HealDecision

local HEALER_ROLE = 'healer'

local function hasTwincast()
    return mq.TLO.Me.Buff('Twincast')() ~= nil
        or mq.TLO.Me.Song('Twincast')() ~= nil
end

function HealDecision:new(config)
    local self = setmetatable({}, HealDecision)
    self.config = config
    self.name = "HealDecision"
    self.job = nil
    self.groupHealPending = false
    self.bus = nil
    self.castService = nil
    self.healCooldown = {}
    self.healCooldownThreshold = {}
    self.hpHistory = {}

    return self
end

function HealDecision:setBus(bus)
    self.bus = bus
end

function HealDecision:setCastService(cs)
    self.castService = cs
end

function HealDecision:suppressGroupHeal(ms)
    self.groupHealLock = mq.gettime() + ms
end

local HP_HISTORY_WINDOW_MS  = 6000  -- how far back we keep samples
local HP_HISTORY_MIN_GAP_MS = 500   -- don't sample faster than this (kills tick noise)

function HealDecision:recordHpSample(id, hp, now)
    local hist = self.hpHistory[id]
    if not hist then
        hist = {}
        self.hpHistory[id] = hist
    end

    local last = hist[#hist]
    if last and (now - last.t) < HP_HISTORY_MIN_GAP_MS then return end

    table.insert(hist, { hp = hp, t = now })

    while hist[1] and (now - hist[1].t) > HP_HISTORY_WINDOW_MS do
        table.remove(hist, 1)
    end
end

-- %HP lost per second, positive = losing HP. Stable/healing targets return 0
-- so callers fall back to the live snapshot instead of projecting downward.
function HealDecision:getHpVelocity(id)
    local hist = self.hpHistory[id]
    if not hist or #hist < 2 then return 0 end

    local oldest, newest = hist[1], hist[#hist]
    local dt = newest.t - oldest.t
    if dt <= 0 then return 0 end

    local velocity = (oldest.hp - newest.hp) / (dt / 1000)
    return velocity > 0 and velocity or 0
end

-- Where this target's HP will be by the time a heal actually lands, not
-- where it is right now — a human healer reacts to the trend, not the frame.
function HealDecision:getProjectedHp(t, lookaheadMs)
    local velocity = self:getHpVelocity(t.id)
    if velocity <= 0 then return t.hp end
    local projected = t.hp - (velocity * (lookaheadMs / 1000))
    return projected < 0 and 0 or projected
end

function HealDecision:score(ctx)
    self.job = nil
    self.groupHealPending = false

    if not ctx.roles[HEALER_ROLE] then return 0 end

    local targets = ctx.self.heal.group.memberStatus

    if self:checkGroupHeal(targets) then
        self.groupHealPending = true
        return 110
    end

    -- Strict tier cascade: tank first, then important, then normal. Only fall
    -- through to the next tier if nothing in the current one actually has a
    -- qualifying (threshold-crossed) heal available -- a tank sitting above
    -- their own threshold never blocks a lower tier that's genuinely in trouble.
    local now = mq.gettime()
    local DEFAULT_LOOKAHEAD_MS = 2000 -- rough guess until a candidate heal's real cast time is known
    local TIERS = { 'tank', 'important', 'normal' }

    for _, tier in ipairs(TIERS) do
        local bestTarget, bestHeal, bestScore = nil, nil, 0

        for _, t in ipairs(targets) do
            if t.role ~= tier or not t.hp then goto continue end

            -- 0% HP means dead, not "needs a heal desperately" -- without this
            -- a dead target scores the maximum possible urgency (100 - 0 = 100)
            -- and wins every tick forever, since a heal landing on a corpse
            -- never actually raises their HP back off zero.
            if t.hp <= 0 then goto continue end

            -- Trend-tracking is a tank thing: they eat sustained, repeated damage
            -- and the trend genuinely predicts more incoming. DPS just take an
            -- occasional single dip — feeding that through velocity/projection
            -- would just react to noise, so they stay on the plain snapshot.
            local projectedHp = t.hp
            if t.role == 'tank' then
                self:recordHpSample(t.id, t.hp, now)
                projectedHp = self:getProjectedHp(t, DEFAULT_LOOKAHEAD_MS)
            end

            if t.role ~= 'tank' and self.healCooldown[t.id] and now < self.healCooldown[t.id] then
                -- Still cooling down from a previously queued heal -- only bypass
                -- if they've worsened enough since then to need a MORE urgent
                -- tier (lower threshold) than what's already queued, so a stale/
                -- insufficient heal doesn't block an escalation while they keep dropping.
                local candidate = self:selectHealSpell(t, ctx.self.heal.spells, projectedHp)
                local coolingThreshold = self.healCooldownThreshold[t.id]
                if not (candidate and coolingThreshold and candidate.threshold < coolingThreshold) then
                    goto continue
                end
            end

            local inGroupMult = (t.inGroup == false) and 0.8 or 1
            local score       = (100 - projectedHp) * inGroupMult

            if score > bestScore then
                local heal = self:selectHealSpell(t, ctx.self.heal.spells, projectedHp)
                if heal then
                    -- Twincast up: use the flagged spell on whichever target normal
                    -- tier/threshold logic already picked, instead of burning the
                    -- double-effect on whatever selectHealSpell would've chosen.
                    -- Only swap if it's actually ready right now -- if not, don't
                    -- wait around for it, just keep the normal pick.
                    if hasTwincast() then
                        local roleSpells = ctx.self.heal.spells[t.role] or ctx.self.heal.spells['normal']
                        if roleSpells then
                            for _, candidate in ipairs(roleSpells) do
                                if candidate.twincast then
                                    if not candidate._rspell then
                                        candidate._rspell = SpellUtil.resolveRank(candidate.spell, 'spell')
                                    end
                                    if mq.TLO.Me.SpellReady(candidate._rspell or candidate.spell)() then
                                        heal = candidate
                                    end
                                    break
                                end
                            end
                        end
                    end

                    -- Lazy-resolve rank once; same pattern as HoTDecision
                    if not heal._rspell then
                        heal._rspell = SpellUtil.resolveRank(heal.spell, 'spell')
                    end
                    local rspell = heal._rspell or heal.spell

                    -- Re-project using this spell's actual cast time — if the target
                    -- is falling fast enough that they'll still be under threshold
                    -- when THIS heal lands, see if a bigger tier now applies.
                    local realCastMs = (mq.TLO.Spell(rspell).CastTime.TotalSeconds() or 0) * 1000
                    if realCastMs > 0 then
                        local refinedHp = self:getProjectedHp(t, realCastMs)
                        local escalated = self:selectHealSpell(t, ctx.self.heal.spells, refinedHp)
                        if escalated and escalated ~= heal then
                            heal = escalated
                            if not heal._rspell then
                                heal._rspell = SpellUtil.resolveRank(heal.spell, 'spell')
                            end
                            rspell = heal._rspell or heal.spell
                        end
                    end

                    local spell         = mq.TLO.Spell(rspell)
                    local spellManaCost = spell.Mana() or 0
                    local spellRange    = tonumber(spell.Range()) or 200
                    local healSpawn     = mq.TLO.Spawn('id ' .. tostring(t.id))
                    local spawnOk       = healSpawn() and not healSpawn.Dead()
                    local dist          = spawnOk and tonumber(healSpawn.Distance()) or nil
                    local inRange       = spawnOk and dist and dist <= spellRange

                    if inRange then
                        if ctx.currentMana > spellManaCost and mq.TLO.Me.SpellReady(rspell)() then
                            bestScore  = score
                            bestTarget = t
                            bestHeal   = heal
                        end
                    end
                end
            end

            ::continue::
        end

        if bestTarget and bestHeal then
            local resolvedName = bestHeal._rspell or bestHeal.spell
            self.job = Job:new(
                bestTarget.id,
                bestTarget.name,
                resolvedName,
                "heal",
                bestHeal.priority or 450,
                bestHeal.gem
            )
            self.job.targetRole = bestTarget.role
            self.job.healThreshold = bestHeal.threshold
            return 105
        end
    end

    -- Top-off: heal anyone below threshold when nothing urgent is needed (out of combat only)
    local topOff = self.config:get('Heals.TopOff')
    if topOff and topOff.spell and ctx.numberOfAggresiveInXTar == 0 then
        if not topOff._rspell then
            topOff._rspell = SpellUtil.resolveRank(topOff.spell, 'spell')
        end
        local rspell = topOff._rspell or topOff.spell
        local threshold = topOff.threshold or 99
        if mq.TLO.Me.SpellReady(rspell)() then
            for _, t in ipairs(targets) do
                -- t.dead is never actually set on any memberStatus entry --
                -- this was always a no-op. t.hp > 0 is the real dead check.
                if t.hp and t.hp > 0 and t.hp < threshold then
                    local healSpawn = mq.TLO.Spawn('id ' .. tostring(t.id))
                    local spellRange = tonumber(mq.TLO.Spell(rspell).Range()) or 200
                    if healSpawn() and not healSpawn.Dead() and (tonumber(healSpawn.Distance()) or 0) <= spellRange then
                        self.job = Job:new(t.id, t.name, rspell, 'heal', 450, topOff.gem)
                        return 50
                    end
                end
            end
        end
    end

    return 0
end

function HealDecision:execute(ctx)
    if not self.job then return end
    if not self.castService then return end
    if self.castService:isQueued(self.job) then return end

    -- Set cooldown immediately to prevent re-queueing same target every tick
    if self.job.targetRole ~= 'tank' then
        local castMs = (mq.TLO.Spell(self.job.name).CastTime.TotalSeconds() or 0) * 1000
        self.healCooldown[self.job.targetId] = mq.gettime() + castMs + 2000
        self.healCooldownThreshold[self.job.targetId] = self.job.healThreshold
    end

    if self.groupHealPending then
        local suppressMs = 8000
        self.groupHealLock = mq.gettime() + suppressMs
        if self.bus then
            self.bus.actor:broadcast('group_heal_cast', {
                casterName = mq.TLO.Me.Name(),
                suppressMs = tostring(suppressMs),
            })
        end
    end

    self.castService:enqueue(self.job)
end

function HealDecision:checkGroupHeal(targets)

    if State.flags.groupHealDisabled then return false end

    if self.groupHealLock and mq.gettime() < self.groupHealLock then
        return false
    end

    local groupSpell   = self.config:get("Heals.GroupSpell")
    local threshold    = (groupSpell and groupSpell.threshold) or self.config:get("Heals.GroupThreshold")    or 65
    local minInjured   = (groupSpell and groupSpell.minInjured) or self.config:get("Heals.GroupHealMinInjured") or 4
    local minInjuredWithTank = (groupSpell and groupSpell.minInjuredWithTank) or math.max(1, minInjured - 1)
    local groupOnlyCfg = self.config:get("Heals.GroupHealGroupOnly")
    local groupOnly    = groupOnlyCfg == nil or groupOnlyCfg == true

    if not (groupSpell and groupSpell.spell) then return false end

    local tanks        = TableUtil.toList(self.config:get("Heals.Tanks"))
    local tankSet      = {}
    for _, n in ipairs(tanks) do tankSet[n] = true end

    local aeRange        = mq.TLO.Spell(groupSpell.spell).AERange() or 100
    local injuredInRange = 0
    local tankInjured    = false

    if groupOnly then
        -- Only count EQ group members + self as injured
        if (mq.TLO.Me.PctHPs() or 100) <= threshold then
            injuredInRange = injuredInRange + 1
        end
        local gCount = mq.TLO.Group.Members() or 0
        for i = 1, gCount do
            local m = mq.TLO.Group.Member(i)
            if m() and not m.Dead() then
                local hp   = m.PctHPs()
                local dist = m.Distance() or 999
                -- 0 HP means dead, not injured -- same direct HP backstop as
                -- the tier-cascade loop above.
                if hp and hp > 0 and hp <= threshold and dist <= aeRange then
                    injuredInRange = injuredInRange + 1
                    if tankSet[m.CleanName()] then tankInjured = true end
                end
            end
        end
    else
        for _, t in ipairs(targets) do
            if t.hp and t.hp > 0 and t.hp <= threshold then
                local spawn = mq.TLO.Spawn('id ' .. tostring(t.id))
                if spawn() and (spawn.Distance() or 999) <= aeRange then
                    injuredInRange = injuredInRange + 1
                    if tankSet[t.name] then tankInjured = true end
                end
            end
        end
    end

    local required = tankInjured and minInjuredWithTank or minInjured
    if injuredInRange >= required then
        if not groupSpell._rspell then
            groupSpell._rspell = SpellUtil.resolveRank(groupSpell.spell, 'spell')
        end
        self.job = Job:new(
                mq.TLO.Me.ID(),
                mq.TLO.Me.Name(),
                groupSpell._rspell or groupSpell.spell,
                "heal",
                480,
                groupSpell.gem
        )
        return true
    end

end

function HealDecision:selectHealSpell(target, healSpells, hpOverride)

    local spells = healSpells[target.role]

    if not spells then
        spells = healSpells["normal"]
    end

    if not spells then return nil end

    local hp = hpOverride or target.hp
    local chosen = nil

    for _,heal in ipairs(spells) do

        if hp and hp <= heal.threshold then

            if not chosen or heal.threshold < chosen.threshold then
                chosen = heal
            end

        end

    end

    return chosen
end

return HealDecision