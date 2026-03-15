local mq = require 'mq'


local CCDecision = {}
CCDecision.__index = CCDecision

function CCDecision:new(config)
    local self = setmetatable({}, CCDecision)
    self.name = "CCDecision"
    self.config = config
    self.spells = self:loadSpells()
    self.mezzed = {}            -- [targetId] = recastAt (timestamp)
    self.maxTankedMobsOverride = nil
    self.pendingTarget = nil
    self.pendingSpell = nil
    self.pendingAeTargets = {}  -- targets AE mez will hit (populated when ae spell chosen)
    self.lastCastTargets = {}   -- targets from the most recent cast attempt
    self.waitingForResult = false
    return self
end

local FAILED_CAST = {
    CAST_FIZZLE      = true,
    CAST_RESIST      = true,
    CAST_INTERRUPTED = true,
    CAST_CANCELLED   = true,
}

function CCDecision:score(ctx)
    self.pendingTarget = nil
    self.pendingSpell = nil
    self.pendingAeTargets = {}

    if not ctx.roles['cc'] then return 0 end
    if not self.config:get('CrowdControl.Enabled') then return 0 end

    -- Check result of previous mez cast once casting finishes
    if self.waitingForResult and not ctx.casting then
        local result = mq.TLO.Cast.Result()
        if FAILED_CAST[result] then
            for _, id in ipairs(self.lastCastTargets) do
                self.mezzed[id] = nil
            end
        end
        self.lastCastTargets = {}
        self.waitingForResult = false
    end

    if ctx.casting then return 0 end

    local now = mq.gettime()
    self:cleanMezTracker()

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
            return 95
        end
    end

    -- Then look for new unmezzed adds
    local target = self:findUnmezzedAdd(ctx)
    if target then
        local spell = self:findReadySingleSpell(target)
        if spell then
            self.pendingTarget = target
            self.pendingSpell = spell
            return 95
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
        return 95
    end

    -- Fall back to single target mez
    local target = self:findUnmezzedAdd(ctx)
    if not target then return 0 end
    local spell = self:findReadySingleSpell(target)
    if not spell then return 0 end
    self.pendingTarget = target
    self.pendingSpell = spell
    return 95
end

function CCDecision:execute(ctx)
    if mq.TLO.Me.Combat() then
        mq.cmd('/attack off')
    end

    if not self.pendingTarget or not self.pendingSpell then return end

    if mq.TLO.Target.ID() ~= self.pendingTarget then
        mq.cmdf('/target id %s', self.pendingTarget)
        mq.delay(100)
    end

    local duration = mq.TLO.Spell(self.pendingSpell.spell).Duration.TotalSeconds() or 60
    local recastBuffer = self.config:get('CrowdControl.RecastBuffer') or 10
    local recastAt = mq.gettime() + ((duration - recastBuffer) * 1000)

    -- Track which targets this cast is for so fizzle/resist can clear them
    self.lastCastTargets = {}
    if #self.pendingAeTargets > 0 then
        for _, id in ipairs(self.pendingAeTargets) do
            self.mezzed[id] = recastAt
            table.insert(self.lastCastTargets, id)
        end
    else
        self.mezzed[self.pendingTarget] = recastAt
        self.lastCastTargets = { self.pendingTarget }
    end

    if ctx.roles['bard'] then
        mq.cmd('/stopsong')
    else
        mq.cmd('/stick off')
        mq.cmd('/afollow off')
    end
    self.waitingForResult = true
    mq.cmdf('/casting "%s"|%s', self.pendingSpell.spell, self.pendingSpell.gem)
end

-- Finds an AE spell opportunity: returns (spell, centerId, {allHitIds})
-- centerId is the target to cast on; allHitIds are all unmezzed adds within range of it.
-- Returns nil if no AE spell is ready or the cluster isn't large enough.
function CCDecision:findAeMezOpportunity(ctx)
    local unmezzed = self:getUnmezzedAdds(ctx)
    if #unmezzed < 2 then return nil end

    for _, aeSpell in ipairs(self.spells) do
        if not aeSpell.ae then goto continue end
        if not mq.TLO.Cast.Ready(aeSpell.spell)() then goto continue end

        local aeRange = mq.TLO.Spell(aeSpell.spell).AERange() or 30
        local minTargets = aeSpell.aeMinTargets or 2

        for _, centerId in ipairs(unmezzed) do
            local centerLevel = mq.TLO.Spawn('id ' .. centerId).Level() or 0
            if aeSpell.maxLevel and centerLevel > aeSpell.maxLevel then goto nextCenter end
            local hits = self:getTargetsInRange(centerId, unmezzed, aeRange)
            -- filter hits by maxLevel too
            if aeSpell.maxLevel then
                local filtered = {}
                for _, id in ipairs(hits) do
                    local lvl = mq.TLO.Spawn('id ' .. id).Level() or 0
                    if lvl <= aeSpell.maxLevel then
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

-- Returns all unmezzed aggressive add IDs, excluding the assist target and
-- the first MaxTankedMobs mobs (left for tanks to handle).
function CCDecision:getUnmezzedAdds(ctx)
    local maxTanked = self.maxTankedMobsOverride or self.config:get('CrowdControl.MaxTankedMobs') or 1
    local allAdds = {}
    local slots = mq.TLO.Me.XTargetSlots()
    for i = 1, slots do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and xt.Type() == "NPC" and not xt.Dead() and xt.Aggressive() then
            local id = xt.ID()
            if id ~= tonumber(ctx.assist.Id) and not self.mezzed[id] then
                table.insert(allAdds, id)
            end
        end
    end

    -- Leave the first MaxTankedMobs for tanks, mez the rest
    local result = {}
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

-- Single-target spells only (ae = false or nil). Checks maxLevel against target if provided.
function CCDecision:findReadySingleSpell(targetId)
    local targetLevel = targetId and mq.TLO.Spawn('id ' .. targetId).Level() or nil
    for _, spell in ipairs(self.spells) do
        if not spell.ae
            and mq.TLO.Cast.Ready(spell.spell)()
            and (not spell.maxLevel or not targetLevel or targetLevel <= spell.maxLevel)
        then
            return spell
        end
    end
    return nil
end

function CCDecision:cleanMezTracker()
    for id, _ in pairs(self.mezzed) do
        local spawn = mq.TLO.Spawn('id ' .. id)
        if not spawn() or spawn.Dead() then
            self.mezzed[id] = nil
        end
    end
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
