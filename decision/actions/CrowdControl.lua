local mq       = require 'mq'
local Target   = require 'service.TargetService'
local SpellUtil = require 'util.SpellUtil'
local State    = require 'core.State'

local CCDecision = {}
CCDecision.__index = CCDecision

-- In-memory override (/srl mezon|mezoff|mezdefault) always wins over config,
-- same precedence pattern as backgroundAssistEnabled/broadcastScope -- lets
-- mezzing be killed instantly at runtime without editing YAML + restarting.
local function mezEnabled(config)
    if State.flags.mezEnabled ~= nil then return State.flags.mezEnabled end
    return config:get('CrowdControl.Enabled') == true
end

function CCDecision:new(config)
    local self = setmetatable({}, CCDecision)
    self.name = "CCDecision"
    self.config = config
    self.spells = self:loadSpells()
    self.mezzed = {}            -- [targetId] = recastAt (timestamp)
    self.lastMezVerify = 0
    self.immune = {}            -- [targetId] = true (in-memory, current session)
    self.immuneNames = {}       -- [name:lower()] = true (persistent, from sidecar)
    self.maxTankedMobsOverride = nil
    self.pendingTarget = nil
    self.pendingSpell = nil
    self.pendingAeTargets = {}  -- targets AE mez will hit (populated when ae spell chosen)
    self.lastCastTargets = {}   -- targets from the most recent cast attempt
    self.waitingForResult = false
    self.melodyService = nil

    self:loadImmuneSidecar()

    -- Immunity event: fires when a mob resists mez entirely
    mq.event('CCImmune', '#*#is immune to changes in its environment#*#', function()
        for _, id in ipairs(self.lastCastTargets) do
            self.immune[id] = true
            self.mezzed[id] = nil
            -- Persist by name so it survives restart
            local spawn = mq.TLO.Spawn('id ' .. id)
            if spawn() then
                local spawnName = spawn.CleanName()
                if spawnName then
                    self.immuneNames[spawnName:lower()] = true
                    self:saveImmuneSidecar()
                end
            end
        end
    end)

    return self
end

function CCDecision:setMelodyService(ms)
    self.melodyService = ms
end

function CCDecision:resumeMelody()
    local ms = self.melodyService
    if ms and ms.active then
        ms:play(ms.active)
    end
end


function CCDecision:score(ctx)
    self.pendingTarget = nil
    self.pendingSpell = nil
    self.pendingAeTargets = {}

    if not ctx.roles['cc'] then return 0 end
    if not mezEnabled(self.config) then return 0 end

    -- Check result of previous mez cast once casting finishes
    if self.waitingForResult and (not ctx.casting or ctx.roles['bard']) then
        mq.doevents('CCImmune')
        for _, id in ipairs(self.lastCastTargets) do
            local spawn = mq.TLO.Spawn('id ' .. id)
            if not spawn() or spawn.Moving() then
                self.mezzed[id] = nil
            end
        end
        self.lastCastTargets = {}
        self.waitingForResult = false
    end

    if ctx.casting and not ctx.roles['bard'] then return 0 end

    local now = mq.gettime()
    self:verifyMezzedTargets()
    self:cleanMezTracker(ctx.assist.Id)

    if ctx.roles['bard'] then
        return self:scoreBard(ctx, now)
    else
        return self:scoreEnchanter(ctx)
    end
end

function CCDecision:scoreBard(ctx, now)
    -- Check expiring mez first (highest priority)
    local expiringId = self:findExpiring(now)
    if expiringId then
        local spell = self:findReadySingleSpell(expiringId)
        if spell then
            self.pendingTarget = expiringId
            self.pendingSpell = spell
            return 120
        end
    end

    -- Then look for new unmezzed adds
    local target = self:findUnmezzedAdd(ctx)
    if target then
        local spell = self:findReadySingleSpell(target)
        if spell then
            self.pendingTarget = target
            self.pendingSpell = spell
            return 120
        end
    end

    return 0
end

function CCDecision:scoreEnchanter(ctx)
    -- Try AE mez first if multiple adds are clustered
    local aeSpell, aeCenter, aeTargets = self:findAeMezOpportunity(ctx)
    if aeSpell and aeCenter then
        self.pendingTarget = aeCenter
        self.pendingSpell = aeSpell
        self.pendingAeTargets = aeTargets
        return 120
    end

    -- Fall back to single target mez
    local target = self:findUnmezzedAdd(ctx)
    if not target then return 0 end
    local spell = self:findReadySingleSpell(target)
    if not spell then return 0 end
    self.pendingTarget = target
    self.pendingSpell = spell
    return 116
end

function CCDecision:execute(ctx)
    if mq.TLO.Me.Combat() then
        mq.cmd('/attack off')
    end

    if not self.pendingTarget or not self.pendingSpell then return end

    if mq.TLO.Target.ID() ~= self.pendingTarget then
        Target:getTargetById(self.pendingTarget)
        -- Without this, a target switched onto this same tick can read
        -- Target.Mezzed() as nil simply because its buffs haven't populated
        -- yet, not because the mez actually dropped, causing the authoritative
        -- check below to needlessly recast on something that's still fine.
        -- 2s cap (vs verifyMezzedTargets()'s 500ms) -- exits as soon as
        -- BuffsPopulated flips true, this is just the worst-case wait.
        mq.delay(2000, function() return mq.TLO.Target.ID() == self.pendingTarget and mq.TLO.Target.BuffsPopulated() == true end)
    end

    local spellName = self.pendingSpell._resolved or SpellUtil.resolveRank(self.pendingSpell.spell, 'spell')
    local castTime = (mq.TLO.Spell(spellName).CastTime.TotalSeconds() or 3) * 1000 + 1500
    local recastBuffer = self.config:get('CrowdControl.RecastBuffer') or 10

    -- Authoritative check: mob may be standing still but not mezzed (attacking),
    -- or may still be mezzed despite timer expiry (AE landed, etc.). Only defer
    -- if there's more than RecastBuffer left on the current mez -- otherwise
    -- recast now so the new mez lands with room to spare before the old one
    -- actually drops, instead of waiting for true expiry every time.
    if mq.TLO.Target.Mezzed() then
        local remainingMs = mq.TLO.Target.Mezzed.Duration() or 0
        if remainingMs > (recastBuffer * 1000) then
            self.mezzed[self.pendingTarget] = self:calcRecastAt(ctx)
            return
        end
    end

    local baseRecastAt = self:calcRecastAt(ctx)

    -- Track which targets this cast is for so fizzle/resist can clear them
    self.lastCastTargets = {}
    if #self.pendingAeTargets > 0 then
        for _, id in ipairs(self.pendingAeTargets) do
            self.mezzed[id] = baseRecastAt
            table.insert(self.lastCastTargets, id)
        end
    else
        self.mezzed[self.pendingTarget] = baseRecastAt
        self.lastCastTargets = { self.pendingTarget }
    end

    if ctx.roles['bard'] then
        mq.cmd('/stopsong')
        -- Wait for the current song to fully stop before casting mez
        mq.delay(2000, function() return not mq.TLO.Me.Casting() end)
    else
        mq.cmd('/stick off')
        if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
    end
    self.waitingForResult = true
    local gem = mq.TLO.Me.Gem(spellName)() or self.pendingSpell.gem
    if not gem then return end

    local targetName = mq.TLO.Spawn('id ' .. self.pendingTarget).CleanName() or '?'
    if #self.pendingAeTargets > 1 then
        targetName = string.format('%s + %d others', targetName, #self.pendingAeTargets - 1)
    end
    mq.cmdf('/dga all /echo [SRL] %s mezzing %s with %s', mq.TLO.Me.Name(), targetName, spellName)

    mq.cmdf('/cast %s', gem)
    mq.delay(1000, function() return mq.TLO.Me.Casting() ~= nil end)
    mq.delay(castTime, function() return not mq.TLO.Me.Casting() end)

    -- Post-cast: for enchanters, read actual focused duration from the cast target.
    -- Works for both ST and AE mez — AE hit mobs share the same focused duration.
    if not ctx.roles['bard'] then
        mq.delay(500, function() return mq.TLO.Target.BuffsPopulated() == true end)
        if mq.TLO.Target.ID() == self.pendingTarget and mq.TLO.Target.Mezzed() then
            local focusedMs = mq.TLO.Target.Mezzed.Duration() or 0
            if focusedMs > 0 then
                local focusedRecastAt = mq.gettime() + math.max(0, focusedMs - (recastBuffer * 1000))
                if #self.pendingAeTargets > 0 then
                    for _, id in ipairs(self.pendingAeTargets) do
                        self.mezzed[id] = focusedRecastAt
                    end
                else
                    self.mezzed[self.pendingTarget] = focusedRecastAt
                end
            end
        end
    else
        -- Bard mez songs take roughly 0.5-2s after the cast finishes for the
        -- effect to actually register on the target (Mezzed()/Moving() lag
        -- behind the cast completing). Without this wait, score()'s very next
        -- tick (which checks waitingForResult immediately for bards, not
        -- gated on ctx.casting) sees the target still "Moving", wrongly
        -- concludes the mez failed, clears self.mezzed[id], and triggers an
        -- unnecessary /stopsong + recast on a mez that actually landed fine
        -- -- confirmed live: it kept interrupting its own melody to redundantly
        -- resing a mez that had already taken hold.
        mq.delay(2000, function() return mq.TLO.Target.Mezzed() ~= nil or not mq.TLO.Target.Moving() end)
        self:resumeMelody()
    end
end

-- Finds an AE spell opportunity: returns (spell, centerId, {allHitIds})
-- centerId is the target to cast on; allHitIds are all unmezzed adds within range of it.
-- Returns nil if no AE spell is ready or the cluster isn't large enough.
function CCDecision:findAeMezOpportunity(ctx)
    local unmezzed = self:getUnmezzedAdds(ctx)
    if #unmezzed < 2 then return nil end

    for _, aeSpell in ipairs(self.spells) do
        if not aeSpell.ae then goto continue end
        local aeResolved = SpellUtil.resolveRank(aeSpell.spell, 'spell')
        if not mq.TLO.Me.SpellReady(aeResolved)() then goto continue end

        local aeRange = mq.TLO.Spell(aeResolved).AERange() or 30
        local minTargets = aeSpell.aeMinTargets or 2

        for _, centerId in ipairs(unmezzed) do
            local centerSpawn = mq.TLO.Spawn('id ' .. centerId)
            if not centerSpawn() then goto nextCenter end
            local centerLevel = centerSpawn.Level() or 0
            if aeSpell.maxLevel and centerLevel > aeSpell.maxLevel then goto nextCenter end
            if aeSpell.minLevel and centerLevel < aeSpell.minLevel then goto nextCenter end

            -- Caster must actually be able to land the AE on this center --
            -- aeRange above is just the blast radius from the center, not the
            -- cast range to reach it.
            local castRange = SpellUtil.castRange(aeResolved) or 0
            if castRange > 0 and (centerSpawn.Distance() or 0) > castRange then goto nextCenter end
            if not centerSpawn.LineOfSight() then goto nextCenter end

            local hits = self:getTargetsInRange(centerId, unmezzed, aeRange)
            -- filter hits by minLevel/maxLevel too
            if aeSpell.maxLevel or aeSpell.minLevel then
                local filtered = {}
                for _, id in ipairs(hits) do
                    local lvl = mq.TLO.Spawn('id ' .. id).Level() or 0
                    if (not aeSpell.maxLevel or lvl <= aeSpell.maxLevel)
                        and (not aeSpell.minLevel or lvl >= aeSpell.minLevel) then
                        table.insert(filtered, id)
                    end
                end
                hits = filtered
            end
            if #hits >= minTargets then
                return aeSpell, centerId, hits
            end
            ::nextCenter::
        end

        ::continue::
    end

    return nil
end

-- Returns all unmezzed, non-immune aggressive add IDs, excluding the assist target and
-- the first MaxTankedMobs fresh adds (left for tanks to handle). Mobs we already
-- mezzed whose recast window has arrived always come first and are never skipped --
-- otherwise, once the other adds die, the lone remaining mezzed mob is the "first"
-- add and gets left for the tank, letting its mez run to zero.
function CCDecision:getUnmezzedAdds(ctx)
    local maxTanked = self.maxTankedMobsOverride or self.config:get('CrowdControl.MaxTankedMobs') or 1
    local now = mq.gettime()
    local expiring = {}
    local allAdds = {}
    local slots = mq.TLO.Me.XTargetSlots()
    for i = 1, slots do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and xt.Type() == "NPC" and not xt.Dead() and xt.Aggressive() then
            local id = xt.ID()
            local mezExpired = self.mezzed[id] and now >= self.mezzed[id]
            if id ~= tonumber(ctx.assist.Id)
                    and (not self.mezzed[id] or mezExpired)
                    and not self.immune[id] then
                local spawnName = mq.TLO.Spawn('id ' .. id).CleanName()
                if spawnName and self.immuneNames[spawnName:lower()] then
                    self.immune[id] = true  -- cache by id to skip name lookup next tick
                elseif mezExpired then
                    table.insert(expiring, id)
                else
                    table.insert(allAdds, id)
                end
            end
        end
    end

    -- Remez expiring mobs first, then leave the first MaxTankedMobs fresh adds
    -- for tanks and mez the rest
    local result = expiring
    for i = maxTanked + 1, #allAdds do
        table.insert(result, allAdds[i])
    end
    return result
end


-- From a list of IDs, returns those within aeRange of centerId (including centerId itself).
function CCDecision:getTargetsInRange(centerId, ids, aeRange)
    local center = mq.TLO.Spawn('id ' .. centerId)
    if not center() then return {} end

    local cx, cy = center.X(), center.Y()
    local inRange = { centerId }

    for _, id in ipairs(ids) do
        if id ~= centerId then
            local s = mq.TLO.Spawn('id ' .. id)
            if s() then
                local dx = s.X() - cx
                local dy = s.Y() - cy
                if math.sqrt(dx * dx + dy * dy) <= aeRange then
                    table.insert(inRange, id)
                end
            end
        end
    end

    return inRange
end

-- Returns the first unmezzed aggressive add ID, excluding the assist target.
function CCDecision:findUnmezzedAdd(ctx)
    local adds = self:getUnmezzedAdds(ctx)
    return adds[1]
end

function CCDecision:findExpiring(now)
    for id, recastAt in pairs(self.mezzed) do
        if now >= recastAt then
            return id
        end
    end
    return nil
end

-- Single-target spells only (ae = false or nil). Checks maxLevel, range, and LoS against target if provided.
function CCDecision:findReadySingleSpell(targetId)
    local spawn = targetId and mq.TLO.Spawn('id ' .. targetId) or nil
    local targetLevel = spawn and spawn() and spawn.Level() or nil
    for _, spell in ipairs(self.spells) do
        if not spell.ae then
            local resolved = SpellUtil.resolveRank(spell.spell, 'spell')
            if mq.TLO.Me.SpellReady(resolved)()
                and (not spell.maxLevel or not targetLevel or targetLevel <= spell.maxLevel)
                and (not spell.minLevel or not targetLevel or targetLevel >= spell.minLevel)
            then
                if spawn and spawn() then
                    local spellRange = SpellUtil.castRange(resolved) or 0
                    if spellRange > 0 and (spawn.Distance() or 0) > spellRange then goto continue end
                    if not spawn.LineOfSight() then goto continue end
                end
                spell._resolved = resolved
                return spell
            end
        end
        ::continue::
    end
    return nil
end

local MEZ_VERIFY_INTERVAL = 2000

function CCDecision:verifyMezzedTargets()
    local now = mq.gettime()
    if (now - self.lastMezVerify) < MEZ_VERIFY_INTERVAL then return end
    self.lastMezVerify = now

    local prevTargetId = mq.TLO.Target.ID()

    for id, _ in pairs(self.mezzed) do
        local spawn = mq.TLO.Spawn('id ' .. id)
        if not spawn() then goto continue end
        mq.cmdf('/target id %d', id)
        mq.delay(1000, function() return mq.TLO.Target.ID() == id and mq.TLO.Target.BuffsPopulated() == true end)
        -- Only trust Mezzed() once the buff packet has actually arrived --
        -- unpopulated buffs read as nil, which would wrongly forget a mob
        -- that's still mezzed and send CC back to re-check/re-mez it.
        if mq.TLO.Target.ID() == id and mq.TLO.Target.BuffsPopulated()
                and not mq.TLO.Target.Mezzed() then
            self.mezzed[id] = nil
        end
        ::continue::
    end

    if prevTargetId and prevTargetId ~= 0 then
        Target:getTargetById(prevTargetId)
    end
end

function CCDecision:cleanMezTracker(assistId)
    for id, _ in pairs(self.mezzed) do
        if id == tonumber(assistId) then
            self.mezzed[id] = nil
        else
            local spawn = mq.TLO.Spawn('id ' .. id)
            if not spawn() or spawn.Dead() or spawn.Moving() then
                self.mezzed[id] = nil
            end
        end
    end
end

-- Absolute path off mq.configDir -- a bare relative path here depended on
-- whatever the process's current working directory happened to be at
-- runtime, which isn't guaranteed to be the MacroQuest root (confirmed live:
-- "could not write config/srl/nomez.txt"). Lives alongside settings.yaml in
-- config/general -- it's shared/global state, not per-character.
local NOMEZ_FILE = mq.configDir .. '\\srl\\config\\general\\nomez.txt'

function CCDecision:loadImmuneSidecar()
    local f = io.open(NOMEZ_FILE, 'r')
    if not f then return end
    for line in f:lines() do
        local name = line:match('^%s*(.-)%s*$')
        if name and name ~= '' then
            self.immuneNames[name:lower()] = true
        end
    end
    f:close()
end

function CCDecision:saveImmuneSidecar()
    local f = io.open(NOMEZ_FILE, 'w')
    if not f then
        print('[SRL] Warning: could not write ' .. NOMEZ_FILE)
        return
    end
    for name in pairs(self.immuneNames) do
        f:write(name .. '\n')
    end
    f:close()
end

function CCDecision:addImmune(id, name)
    self.immune[id] = true
    self.mezzed[id] = nil
    if name and name ~= '' then
        self.immuneNames[name:lower()] = true
        self:saveImmuneSidecar()
    end
    print(string.format('[SRL] %s (%d) added to no-mez list', name or 'unknown', id))
end

-- Returns recastAt timestamp using focused duration for enchanters (target must already be targeted).
-- Falls back to base spell duration for bards or when focused duration is unavailable.
function CCDecision:calcRecastAt(ctx)
    local recastBuffer = self.config:get('CrowdControl.RecastBuffer') or 10
    if not ctx.roles['bard'] and mq.TLO.Target.Mezzed() then
        local focusedMs = mq.TLO.Target.Mezzed.Duration() or 0
        if focusedMs > 0 then
            return mq.gettime() + math.max(0, focusedMs - (recastBuffer * 1000))
        end
    end
    local duration = mq.TLO.Spell(self.pendingSpell.spell).Duration.TotalSeconds() or 60
    return mq.gettime() + ((duration - recastBuffer) * 1000)
end

function CCDecision:setMaxTankedMobs(n)
    self.maxTankedMobsOverride = tonumber(n)
end

function CCDecision:loadSpells()
    local values = self.config:get('CrowdControl.Spells') or {}
    table.sort(values, function(a, b)
        return (a.priority or 99) < (b.priority or 99)
    end)
    return values
end

return CCDecision
