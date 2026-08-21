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

        local spellName = resolveSpellName(entry)

        if entry.targeted then
            if not (ctx.assist and ctx.assist.Id) then goto continue end
            local maxRange  = entry.maxRange  or tonumber(mq.TLO.Spell(spellName).Range())   or 150
            local beamWidth = entry.beamWidth or tonumber(mq.TLO.Spell(spellName).AERange()) or 30
            if (ctx.assist.distance or 999) > maxRange then goto continue end
            local target = mq.TLO.Spawn('id ' .. ctx.assist.Id)
            if not target() then goto continue end
            local y, x, z = target.Y(), target.X(), target.Z()
            local raw = mq.TLO.SpawnCount(
                string.format('npc radius %d loc %s %s %s', beamWidth, y, x, z))() or 0
            mobCount = math.min(raw, 12)
        else
            local radius = tonumber(mq.TLO.Spell(spellName).AERange()) or 0
            if radius <= 0 then radius = tonumber(mq.TLO.Spell(spellName).Range()) or 50 end
            mobCount = mq.TLO.SpawnCount(string.format('npc radius %d', radius))() or 0
        end

        if mobCount < threshold then goto continue end

        local timerKey = entry.name
        if self.recastTimers[timerKey] and now < self.recastTimers[timerKey] then
            goto continue
        end

        if self:isReady(entry) then
            table.insert(self.pendingJobs, entry)
        end

        ::continue::
    end

    if #self.pendingJobs == 0 then return 0 end

    -- AE debuffs (slows, etc.) marked with debuff:true outrank heals
    for _, job in ipairs(self.pendingJobs) do
        if job.debuff then
            return 115
        end
    end

    return 82
end

function AEDecision:execute(ctx)
    if ctx.silenced then return end

    for _, entry in ipairs(self.pendingJobs) do
        -- Targeted AE: require assist target within range, face it before casting
        if entry.targeted then
            if not (ctx.assist and ctx.assist.Id) then goto continueExec end
            local maxRange = entry.maxRange or tonumber(mq.TLO.Spell(resolveSpellName(entry)).Range()) or 150
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
            local recast = (mq.TLO.Spell(spellName).RecastTime.TotalSeconds() or 0) * 1000
            self.recastTimers[entry.name] = mq.gettime() + math.max(recast, 2000)

        elseif entry.type == 'disc' then
            local discName = resolveSpellName(entry)
            if mq.TLO.Me.Casting() then
                mq.cmd('/stopcast')
                mq.delay(300, function() return not mq.TLO.Me.Casting() end)
            end
            mq.cmdf('/disc "%s"', discName)
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
