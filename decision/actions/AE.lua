local mq    = require 'mq'
local State = require 'core.State'
local Target = require 'service.TargetService'
local SpellUtil = require 'util.SpellUtil'

-- AEDecision: casts AE spells/discs/AAs when aggressive mob count in the area
-- meets a configured threshold. Enabled/disabled in memory via /srl aeon|aeoff.
-- Disable when CC is mezzing to avoid breaking crowd control.

local AEDecision = {}
AEDecision.__index = AEDecision

function AEDecision:new(config)
    local self = setmetatable({}, AEDecision)
    self.name         = "AEDecision"
    self.config       = config
    self.pendingJobs  = {}
    self.recastTimers = {}
    self.lastCastAt     = {}  -- entry.name -> time the AE last actually landed
    self.buffVerifiedAt = {}  -- mob id -> time its buffs were last target-checked
    self.lastBuffVerify = 0
    return self
end

-- AA display names don't always match their underlying spell name, so range/AERange
-- lookups for 'aa' entries must resolve through Me.AltAbility(name).Spell rather than
-- assuming mq.TLO.Spell(entry.name) resolves directly. For spell/disc entries, config
-- often declares a base name while the character actually has a higher rank memmed/
-- known -- resolve once and cache on the entry, same pattern as MemSwapDecision.
-- NOTE: this is only for range/ready/cast lookups -- an 'aa' entry's own activation
-- name (AltAbilityReady/"/alt activate") must stay entry.name, never this resolved
-- underlying-spell name.
local function resolveSpellName(entry)
    if entry._resolvedName then return entry._resolvedName end
    local resolved
    if entry.type == 'aa' then
        resolved = mq.TLO.Me.AltAbility(entry.name).Spell.Name() or entry.name
    else
        resolved = SpellUtil.resolveRank(entry.name, entry.type)
    end
    entry._resolvedName = resolved
    return resolved
end

-- How long a target-hop buff check on a mob is trusted (another shaman may slow
-- it after we looked), and the minimum gap between hop passes.
local BUFF_VERIFY_TTL_MS      = 15000
local BUFF_VERIFY_INTERVAL_MS = 2000

-- Counts aggressive XTarget NPCs within radius of (y, x, z) that have none of the
-- entry's checkBuff buffs. Spawn.Buff reads MQ's cached buffs, which only exist
-- for spawns this character has targeted -- a mob with no cached data counts as
-- NOT having the buff, so a fresh pile of untargeted adds still triggers the AE.
-- Also returns the IDs of counted mobs whose cache can't be trusted yet (never
-- target-checked, checked before this AE last landed, or checked too long ago).
function AEDecision:countMissingBuff(entry, radius, y, x, z)
    local names = type(entry.checkBuff) == 'table' and entry.checkBuff or { entry.checkBuff }
    local now = mq.gettime()
    local lastCast = self.lastCastAt[entry.name] or 0
    local count, unverified = 0, {}
    for i = 1, (mq.TLO.Me.XTargetSlots() or 0) do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and xt.Type() == 'NPC' and not xt.Dead() and xt.Aggressive() then
            local id = xt.ID()
            local spawn = mq.TLO.Spawn('id ' .. id)
            if spawn() then
                local dist = math.sqrt((spawn.Y() - y) ^ 2 + (spawn.X() - x) ^ 2 + (spawn.Z() - z) ^ 2)
                if dist <= radius then
                    local hasBuff = false
                    for _, n in ipairs(names) do
                        if spawn.Buff(n)() then hasBuff = true break end
                    end
                    if not hasBuff then
                        count = count + 1
                        local checkedAt = self.buffVerifiedAt[id]
                        if not checkedAt or checkedAt < lastCast or (now - checkedAt) > BUFF_VERIFY_TTL_MS then
                            table.insert(unverified, id)
                        end
                    end
                end
            end
        end
    end
    return count, unverified
end

-- Target-hops each mob so MQ's buff cache refreshes (same approach as CC's
-- verifyMezzedTargets), then restores the previous target. A mob whose buffs
-- never populate stays unverified and keeps counting as unslowed.
function AEDecision:verifyBuffs(ids)
    local now = mq.gettime()
    if (now - self.lastBuffVerify) < BUFF_VERIFY_INTERVAL_MS then return false end
    self.lastBuffVerify = now

    local prevTargetId = mq.TLO.Target.ID()
    for _, id in ipairs(ids) do
        if mq.TLO.Spawn('id ' .. id)() then
            mq.cmdf('/target id %d', id)
            mq.delay(1000, function() return mq.TLO.Target.ID() == id and mq.TLO.Target.BuffsPopulated() == true end)
            if mq.TLO.Target.ID() == id and mq.TLO.Target.BuffsPopulated() then
                self.buffVerifiedAt[id] = mq.gettime()
            end
        end
    end
    if prevTargetId and prevTargetId ~= 0 and mq.TLO.Target.ID() ~= prevTargetId then
        Target:getTargetById(prevTargetId)
    end
    return true
end

function AEDecision:score(ctx)
    self.pendingJobs = {}

    local now = mq.gettime()

    if not State.flags.aeEnabled then return 0 end
    if ctx.silenced then return 0 end
    if not ctx.assist.Id then return 0 end

    local spells = self.config:get('AE.Spells') or {}
    if #spells == 0 then return 0 end

    for _, entry in ipairs(spells) do
        local threshold = entry.threshold or 3
        local mobCount
        local cy, cx, cz, radius  -- AE center + radius, only needed for checkBuff recounts

        local spellName = resolveSpellName(entry)

        if entry.targeted then
            if not (ctx.assist and ctx.assist.Id) then goto continue end
            local maxRange  = entry.maxRange  or SpellUtil.castRange(spellName)   or 150
            local beamWidth = entry.beamWidth or tonumber(mq.TLO.Spell(spellName).AERange()) or 30
            if (ctx.assist.distance or 999) > maxRange then goto continue end
            local target = mq.TLO.Spawn('id ' .. ctx.assist.Id)
            if not target() then goto continue end
            local y, x, z = target.Y(), target.X(), target.Z()
            if entry.checkBuff then
                cy, cx, cz, radius = y, x, z, beamWidth
            else
                local raw = mq.TLO.SpawnCount(
                    string.format('npc radius %d loc %s %s %s', beamWidth, y, x, z))() or 0
                mobCount = math.min(raw, 12)
            end
        else
            radius = tonumber(mq.TLO.Spell(spellName).AERange()) or 0
            if radius <= 0 then radius = tonumber(mq.TLO.Spell(spellName).Range()) or 50 end
            if entry.checkBuff then
                cy, cx, cz = mq.TLO.Me.Y(), mq.TLO.Me.X(), mq.TLO.Me.Z()
            else
                mobCount = mq.TLO.SpawnCount(string.format('npc radius %d', radius))() or 0
            end
        end

        local unverified
        if entry.checkBuff then
            mobCount, unverified = self:countMissingBuff(entry, radius, cy, cx, cz)
        end

        if mobCount < threshold then goto continue end

        local timerKey = entry.name
        if self.recastTimers[timerKey] and now < self.recastTimers[timerKey] then
            goto continue
        end

        if not self:isReady(entry) then goto continue end

        -- Enough apparently-unslowed mobs and the AE is ready: target-check any
        -- whose cached buffs can't be trusted, then recount. While casting, wait
        -- for the cast to finish instead -- don't hop targets or /stopcast a heal
        -- over mobs that may already be slowed.
        if unverified and #unverified > 0 then
            if ctx.casting then goto continue end
            if self:verifyBuffs(unverified) then
                mobCount = self:countMissingBuff(entry, radius, cy, cx, cz)
                if mobCount < threshold then goto continue end
            end
        end

        table.insert(self.pendingJobs, entry)

        ::continue::
    end

    if #self.pendingJobs == 0 then return 0 end

    -- AE debuffs (slows, etc.) marked with debuff:true outrank heals
    for _, job in ipairs(self.pendingJobs) do
        if job.debuff then
            return 115
        end
    end

    -- Above the lifetap-triggered nuke tier (88, Nuke.lua's selfHeal escalation)
    -- -- hitting everyone in an AE-worthy pile matters more than a single-
    -- target self-heal side effect, even when own HP is also low enough to
    -- trigger that escalation.
    return 90
end

function AEDecision:execute(ctx)
    if ctx.silenced then return end

    for _, entry in ipairs(self.pendingJobs) do
        -- Targeted AE: require assist target within range, face it before casting
        if entry.targeted then
            if not (ctx.assist and ctx.assist.Id) then goto continueExec end
            local maxRange = entry.maxRange or SpellUtil.castRange(resolveSpellName(entry)) or 150
            if (ctx.assist.distance or 999) > maxRange then goto continueExec end
            local targetId = tonumber(ctx.assist.Id)
            if mq.TLO.Target.ID() ~= targetId then
                Target:getTargetById(targetId)
            end
            if mq.TLO.Target.ID() ~= targetId then goto continueExec end
        end

        if entry.type == 'spell' then
            local spellName = resolveSpellName(entry)
            local gem = mq.TLO.Me.Gem(spellName)() or entry.gem
            if not gem then goto continueExec end
            -- Confirmed we can cast — stop any ongoing cast, then face and fire
            if mq.TLO.Me.Casting() then
                mq.cmd('/stopcast')
                mq.delay(300, function() return not mq.TLO.Me.Casting() end)
            end
            if entry.targeted then
                local targetId = tonumber(ctx.assist.Id)
                mq.cmdf('/face id %s', targetId)
                mq.delay(500, function()
                    local myHeading     = mq.TLO.Me.Heading()
                    local targetHeading = mq.TLO.Spawn('id ' .. targetId).HeadingTo()
                    if not myHeading or not targetHeading then return true end
                    local diff = math.abs(myHeading - targetHeading)
                    if diff > 180 then diff = 360 - diff end
                    return diff < 10
                end)
            end
            local castTime = (mq.TLO.Spell(spellName).CastTime.TotalSeconds() or 2) * 1000 + 1000
            mq.cmdf('/cast %s', gem)
            mq.delay(1000, function() return mq.TLO.Me.Casting() ~= nil end)
            mq.delay(castTime, function() return not mq.TLO.Me.Casting() end)
            -- Only lock out re-consideration if the cast actually landed --
            -- confirmed by the spell's own reuse timer having been consumed
            -- (SpellReady flipped false). If it's still ready, the cast
            -- failed/got interrupted/fizzled and the real cooldown never
            -- started, so don't self-impose the full recast duration as an
            -- artificial lockout on top of that.
            if not mq.TLO.Me.SpellReady(spellName)() then
                local recast = (mq.TLO.Spell(spellName).RecastTime.TotalSeconds() or 0) * 1000
                self.recastTimers[entry.name] = mq.gettime() + math.max(recast, 2000)
                -- Invalidates earlier buff checks so mobs get re-checked for this cast's debuff
                self.lastCastAt[entry.name] = mq.gettime()
            end

        elseif entry.type == 'disc' then
            local discName = resolveSpellName(entry)
            if mq.TLO.Me.Casting() then
                mq.cmd('/stopcast')
                mq.delay(300, function() return not mq.TLO.Me.Casting() end)
            end
            mq.cmdf('/disc %s', discName)
            local castTime = (mq.TLO.Spell(discName).CastTime.TotalSeconds() or 0) * 1000 + 500
            if castTime > 500 then
                mq.delay(castTime, function() return not mq.TLO.Me.Casting() end)
            end
            self.recastTimers[entry.name] = mq.gettime() + 2000

        elseif entry.type == 'aa' then
            if mq.TLO.Me.Casting() then
                mq.cmd('/stopcast')
                mq.delay(300, function() return not mq.TLO.Me.Casting() end)
            end
            mq.cmdf('/alt activate "%s"', entry.name)
            local castTime = mq.TLO.Me.AltAbility(entry.name).Spell.CastTime() or 0
            if castTime > 0 then
                mq.delay(castTime + 500, function() return not mq.TLO.Me.Casting() end)
            end
            self.recastTimers[entry.name] = mq.gettime() + 2000
        end

        ::continueExec::
    end
end

function AEDecision:isReady(entry)
    if entry.type == 'spell' then
        return mq.TLO.Me.SpellReady(resolveSpellName(entry))() == true
    elseif entry.type == 'disc' then
        return mq.TLO.Me.CombatAbilityReady(resolveSpellName(entry))() == true
    elseif entry.type == 'aa' then
        return mq.TLO.Me.AltAbilityReady(entry.name)() == true
    end
    return false
end

return AEDecision
