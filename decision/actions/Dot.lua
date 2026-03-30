local mq    = require 'mq'
local State = require 'core.State'
local Target = require 'service.TargetService'
local DotDecision = {}
DotDecision.__index = DotDecision

function DotDecision:new(config)
    local self = setmetatable({}, DotDecision)
    self.name = "DotDecision"
    self.config = config
    self.retryTimer = {}
    self.pendingTarget = nil
    self.pendingDot = nil
    return self
end

function DotDecision:score(ctx)
    self.pendingTarget = nil
    self.pendingDot = nil

    if ctx.casting then return 0 end
    if not ctx.roles['dot'] then return 0 end
    if not ctx.self.dot then return 0 end
    if ctx.mana < 10 then return 0 end

    -- Command dot: /srl doton targets a specific mob
    local cmdId = State.flags.commandDotTargetId
    if cmdId then
        local spawn = mq.TLO.Spawn('id ' .. cmdId)
        if not spawn() or spawn.Dead() then
            State.flags.commandDotTargetId = nil
        elseif #ctx.self.dot.onCommandSpells > 0 then
            if self:findDot(ctx.self.dot.onCommandSpells, cmdId) then
                return 79
            end
        end
    end

    -- Assist target dots
    if ctx.assist.Id and not ctx.assist.dead then
        if ctx.assist.distance == nil or ctx.assist.distance <= 200 then
            if not ctx.assist.lineOfSight then return 0 end
            if #ctx.self.dot.onAssistSpells > 0 then
                if self:findDot(ctx.self.dot.onAssistSpells, ctx.assist.Id) then
                    return 78
                end
            end
        end
    end

    return 0
end

-- Finds the first castable dot for targetId, respecting groups and checkBuff.
-- Sets self.pendingTarget and self.pendingDot if found. Returns true if found.
function DotDecision:findDot(spells, targetId)
    local handledGroups = {}

    for _, dot in ipairs(spells) do
        local group = dot.group

        if group and handledGroups[group] then
            goto continue
        end

        if dot.checkBuff and self:targetHasBuff(targetId, dot.checkBuff) then
            if group then handledGroups[group] = true end
            goto continue
        end

        local k = dot.spell .. ':' .. tostring(targetId)
        if self:isEntryReady(k, dot) then
            self.pendingTarget = targetId
            self.pendingDot = dot
            if group then handledGroups[group] = true end
            return true
        end

        ::continue::
    end

    return false
end

function DotDecision:execute(ctx)
    if not self.pendingTarget or not self.pendingDot then return end

    local dot      = self.pendingDot
    local targetId = self.pendingTarget
    local entryType = dot.type or 'spell'
    local k = dot.spell .. ':' .. tostring(targetId)

    if mq.TLO.Target.ID() ~= targetId then
        Target:getTargetById(targetId)
    end

    local spawn = mq.TLO.Spawn('id ' .. targetId)
    if spawn() and not spawn.LineOfSight() then return end

    if entryType == 'item' then
        local item = mq.TLO.FindItem('=' .. dot.spell)
        if not item() or (item.TimerReady() or 1) ~= 0 then return end

        local buffName = mq.TLO.FindItem('=' .. dot.spell).Clicky.Spell.Name() or dot.spell
        local spell = mq.TLO.Spell(buffName)
        local duration = spell and spell.Duration.TotalSeconds() or 60
        self.retryTimer[k] = mq.gettime() + math.max((duration * 1000) - 18000, 30000)

        mq.cmdf('/useitem "%s"', dot.spell)
    else
        if not mq.TLO.Me.SpellReady(dot.spell)() then return end

        local spell = mq.TLO.Spell(dot.spell)
        local duration = spell and spell.Duration.TotalSeconds() or 60
        self.retryTimer[k] = mq.gettime() + math.max((duration * 1000) - 18000, 30000)

        mq.cmd('/stick off')
        mq.cmd('/nav stop')
        local gem = mq.TLO.Me.Gem(dot.spell)() or dot.gem
        if not gem then return end
        mq.cmdf('/cast %s', gem)
    end
end

function DotDecision:isEntryReady(key, dot)
    if self.retryTimer[key] and mq.gettime() < self.retryTimer[key] then
        return false
    end
    local entryType = dot.type or 'spell'
    if entryType == 'item' then
        local item = mq.TLO.FindItem('=' .. dot.spell)
        return item() and (item.TimerReady() or 1) == 0
    else
        return mq.TLO.Me.SpellReady(dot.spell)() == true
    end
end

function DotDecision:targetHasBuff(targetId, checkBuff)
    local spawn = mq.TLO.Spawn('id ' .. targetId)
    if not spawn() then return false end

    local names = type(checkBuff) == 'table' and checkBuff or { checkBuff }
    for _, buffName in ipairs(names) do
        if spawn.Buff(buffName)() then return true end
        local base = buffName:gsub('%s+Rk%.%s*%a+$', '')
        if base ~= buffName and spawn.Buff(base)() then return true end
    end
    return false
end

return DotDecision
