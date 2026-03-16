local mq = require 'mq'
local Target = require 'srl/service/TargetService'

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
    if not self.config:get('Shrink.Enabled') then return 0 end

    local entry = self.config:get('Shrink')
    if not entry or not entry.name then return 0 end

    if not self:isReady(entry) then return 0 end

    local threshold = entry.sizeThreshold or 4
    local range = self:getRange(entry)

    local members = mq.TLO.Group.Members() or 0
    for i = 1, members do
        local m = mq.TLO.Group.Member(i)
        if m() and m.Spawn() and not m.Dead() then
            local spawn = mq.TLO.Spawn(m.ID())
            if spawn() and (spawn.Height() or 0) > threshold then
                if range == 0 or spawn.Distance() <= range then
                    self.pending = { entry = entry, targetId = m.ID(), targetName = m.CleanName() }
                    return 30
                end
            end
        end
    end

    return 0
end

function ShrinkDecision:execute(ctx)
    if not self.pending then return end

    local entry    = self.pending.entry
    local targetId = self.pending.targetId

    if mq.TLO.Target.ID() ~= targetId then
        Target:getTargetById(targetId)
    end

    local entryType = entry.type or 'spell'
    if entryType == 'item' then
        mq.cmdf('/useitem "%s"', entry.name)
    elseif entryType == 'aa' then
        mq.cmdf('/alt activate "%s"', entry.name)
    else
        mq.cmdf('/casting "%s"|%s', entry.name, entry.gem or 1)
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
        return mq.TLO.FindItem('=' .. entry.name)() ~= nil
    elseif entryType == 'aa' then
        return mq.TLO.Me.AltAbilityReady(entry.name)() == true
    else
        return mq.TLO.Cast.Ready(entry.name)() == true
    end
end

return ShrinkDecision
