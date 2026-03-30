local mq = require 'mq'
local Target = require 'service.TargetService'

local ShrinkDecision = {}
ShrinkDecision.__index = ShrinkDecision

function ShrinkDecision:new(config)
    local self = setmetatable({}, ShrinkDecision)
    self.name    = "ShrinkDecision"
    self.config  = config
    self.pending = nil
    return self
end

function ShrinkDecision:score(ctx)
    self.pending = nil

    if ctx.casting then return 0 end
    if ctx.inCombat then return 0 end
    if mq.TLO.Me.Invis() then return 0 end
    if not self.config:get('Shrink.Enabled') then return 0 end

    local entry = self.config:get('Shrink')
    if not entry or not entry.name then return 0 end

    if not self:isReady(entry) then return 0 end

    local threshold = entry.sizeThreshold or 4
    local range = self:getRange(entry)

    -- Check self (Group.Member(0) is self but loop starts at 1)
    if (mq.TLO.Me.Height() or 0) > threshold then
        self.pending = { entry = entry, targetId = ctx.myId, targetName = ctx.myName, isSelf = true }
        return 30
    end

    local members = mq.TLO.Group.Members() or 0
    for i = 1, members do
        local m = mq.TLO.Group.Member(i)
        if not m() then goto continue end
        local id = m.ID()
        if not id or id == 0 then goto continue end
        local spawn = mq.TLO.Spawn('id ' .. tostring(id))
        if not spawn() or spawn.Dead() then goto continue end
        if (spawn.Height() or 0) > threshold then
            if range == 0 or (spawn.Distance() or 999) <= range then
                self.pending = { entry = entry, targetId = id, targetName = m.CleanName() }
                return 30
            end
        end
        ::continue::
    end

    return 0
end

function ShrinkDecision:execute(ctx)
    if not self.pending then return end

    local entry    = self.pending.entry
    local targetId = self.pending.targetId

    if self.pending.isSelf then
        if mq.TLO.Target.ID() ~= mq.TLO.Me.ID() then
            mq.cmdf('/target %s', ctx.myCleanName)
            mq.delay(150, function() return mq.TLO.Target.ID() == mq.TLO.Me.ID() end)
        end
    elseif mq.TLO.Target.ID() ~= targetId then
        Target:getTargetById(targetId)
    end

    local entryType = entry.type or 'spell'
    if entryType == 'item' then
        local castTime = (mq.TLO.FindItem('=' .. entry.name).Clicky.CastTime() or 1000) + 1000
        mq.cmdf('/useitem "%s"', entry.name)
        mq.delay(castTime)
    elseif entryType == 'aa' then
        mq.cmdf('/alt activate "%s"', entry.name)
        mq.delay(1500)
    else
        local gem = mq.TLO.Me.Gem(entry.name)() or entry.gem or 1
        local castTime = (mq.TLO.Spell(entry.name).CastTime.TotalSeconds() or 1) * 1000 + 1500
        mq.cmdf('/cast %s', gem)
        mq.delay(1000, function() return mq.TLO.Me.Casting() ~= nil end)
        mq.delay(castTime, function() return not mq.TLO.Me.Casting() end)
    end
end

function ShrinkDecision:getRange(entry)
    local entryType = entry.type or 'spell'
    local spellName
    if entryType == 'item' then
        spellName = mq.TLO.FindItem('=' .. entry.name).Clicky.Spell.Name()
    else
        spellName = entry.name
    end

    if not spellName then return 0 end

    local ae = tonumber(mq.TLO.Spell(spellName).AERange()) or 0
    if ae > 0 then return ae end
    return tonumber(mq.TLO.Spell(spellName).Range()) or 0
end

function ShrinkDecision:isReady(entry)
    local entryType = entry.type or 'spell'
    if entryType == 'item' then
        local item = mq.TLO.FindItem('=' .. entry.name)
        return item() and (item.TimerReady() or 1) == 0
    elseif entryType == 'aa' then
        return mq.TLO.Me.AltAbilityReady(entry.name)() == true
    else
        return mq.TLO.Me.SpellReady(entry.name)() == true
    end
end

return ShrinkDecision
