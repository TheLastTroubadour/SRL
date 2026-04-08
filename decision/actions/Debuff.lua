local mq    = require 'mq'
local State = require 'core.State'
local Target = require 'service.TargetService'
local DebuffDecision = {}
DebuffDecision.__index = DebuffDecision

local IMMUNE_BACKOFF_MS = 3600000  -- 1 hour; effectively skip for the session
local NOSLOW_FILE = 'config/srl/noslow.txt'

function DebuffDecision:new(config)
    local self = setmetatable({}, DebuffDecision)
    self.name = "DebuffDecision"
    self.config = config
    self.retryTimer   = {}
    self.pendingTarget = nil
    self.pendingDebuff = nil
    self.lastCastKey   = nil  -- set in execute() so immune events know what to back off
    self.noSlowIds     = {}   -- [spawnId] = true
    self.noSlowNames   = {}   -- [name:lower()] = true
    self:loadNoSlowFile()
    return self
end

function DebuffDecision:loadNoSlowFile()
    local f = io.open(NOSLOW_FILE, 'r')
    if not f then return end
    for line in f:lines() do
        local name = line:match('^%s*(.-)%s*$')
        if name and name ~= '' then
            self.noSlowNames[name:lower()] = true
        end
    end
    f:close()
end

function DebuffDecision:saveNoSlowFile()
    local f = io.open(NOSLOW_FILE, 'w')
    if not f then
        print('[SRL] Warning: could not write ' .. NOSLOW_FILE)
        return
    end
    for name in pairs(self.noSlowNames) do
        f:write(name .. '\n')
    end
    f:close()
end

function DebuffDecision:addNoSlow(id, name)
    self.noSlowIds[id] = true
    if name and name ~= '' then
        self.noSlowNames[name:lower()] = true
        self:saveNoSlowFile()
    end
    print(string.format('[SRL] %s (%d) added to no-slow list', name or 'unknown', id))
end

function DebuffDecision:isSlowImmune(targetId)
    if self.noSlowIds[targetId] then return true end
    local spawn = mq.TLO.Spawn('id ' .. targetId)
    if not spawn() then return false end
    local name = spawn.CleanName()
    if name and self.noSlowNames[name:lower()] then
        self.noSlowIds[targetId] = true  -- cache by id
        return true
    end
    return false
end

function DebuffDecision:markLastCastImmune()
    if self.lastCastKey then
        self.retryTimer[self.lastCastKey] = mq.gettime() + IMMUNE_BACKOFF_MS
        print(string.format('[SRL] Debuff immune — skipping %s for this session', self.lastCastKey))
        self.lastCastKey = nil
    end
end

function DebuffDecision:score(ctx)
    self.pendingTarget = nil
    self.pendingDebuff = nil

    if ctx.casting then return 0 end
    if not ctx.roles['debuff'] then return 0 end
    if not ctx.self.debuff then return 0 end
    if ctx.mana < 10 then return 0 end

    -- Command debuff: /srl debuffon targets a specific mob
    local cmdId = State.flags.commandDebuffTargetId
    if cmdId then
        local spawn = mq.TLO.Spawn('id ' .. cmdId)
        if not spawn() or spawn.Dead() then
            State.flags.commandDebuffTargetId = nil
        elseif #ctx.self.debuff.onCommandSpells > 0 then
            if self:findDebuff(ctx.self.debuff.onCommandSpells, cmdId) then
                return 115
            end
        end
    end

    -- Assist target debuffs
    if ctx.assist.Id and not ctx.assist.dead then
        if ctx.assist.distance == nil or ctx.assist.distance <= 200 then
            if not ctx.assist.lineOfSight then return 0 end
            if #ctx.self.debuff.onAssistSpells > 0 then
                if self:findDebuff(ctx.self.debuff.onAssistSpells, ctx.assist.Id) then
                    return self.pendingDebuff.priority and 115 or 80
                end
            end
        end
    end

    -- XTarget debuffs (independent of assist target)
    if ctx.self.debuff.enabledForXTar
            and ctx.numberOfAggresiveInXTar
            and ctx.numberOfAggresiveInXTar >= (ctx.self.debuff.minXTarTargets or 2) then
        local slots = mq.TLO.Me.XTargetSlots()
        for i = 1, slots do
            local xt = mq.TLO.Me.XTarget(i)
            if xt() and xt.Type() == "NPC" and not xt.Dead() and xt.Aggressive()
                    and xt.ID() ~= tonumber(ctx.assist.Id)
                    and xt.LineOfSight() then
                if self:findDebuff(ctx.self.debuff.xTarSpells, xt.ID()) then
                    return self.pendingDebuff.priority and 115 or 80
                end
            end
        end
    end

    return 0
end

-- Finds the first castable debuff for targetId, respecting groups and checkBuff.
-- Sets self.pendingTarget and self.pendingDebuff if found. Returns true if found.
function DebuffDecision:findDebuff(spells, targetId)
    local handledGroups = {}

    for _, debuff in ipairs(spells) do
        local group = debuff.group

        -- Skip if this group already resolved (buff present or candidate found)
        if group and handledGroups[group] then
            goto continue
        end

        -- Skip slow-group entries for mobs on the no-slow list
        if group == 'slow' and self:isSlowImmune(targetId) then
            handledGroups['slow'] = true
            goto continue
        end

        -- If checkBuff is present on target, skip this entry.
        -- passThrough: true means don't lock the group — subsequent entries in the
        -- group can still fire (e.g. fast slow already landed → try long slow next).
        if debuff.checkBuff and self:targetHasBuff(targetId, debuff.checkBuff) then
            if group and not debuff.passThrough then
                handledGroups[group] = true
            end
            goto continue
        end

        local k = debuff.spell .. ':' .. tostring(targetId)
        if self:isEntryReady(k, debuff) then
            self.pendingTarget = targetId
            self.pendingDebuff = debuff
            if group then handledGroups[group] = true end
            return true
        end

        ::continue::
    end

    return false
end

function DebuffDecision:execute(ctx)
    if not self.pendingTarget or not self.pendingDebuff then return end

    local debuff   = self.pendingDebuff
    local targetId = self.pendingTarget
    local entryType = debuff.type or 'spell'
    local k = debuff.spell .. ':' .. tostring(targetId)

    if mq.TLO.Target.ID() ~= targetId then
        Target:getTargetById(targetId)
    end

    -- Don't commit the retry timer if the target isn't in LoS yet
    local spawn = mq.TLO.Spawn('id ' .. targetId)
    if spawn() and not spawn.LineOfSight() then return end

    if entryType == 'item' then
        local item = mq.TLO.FindItem('=' .. debuff.spell)
        if not item() or (item.TimerReady() or 1) ~= 0 then return end

        local buffName = mq.TLO.FindItem('=' .. debuff.spell).Clicky.Spell.Name() or debuff.spell
        local spell = mq.TLO.Spell(buffName)
        local duration = spell and spell.Duration.TotalSeconds() or 60
        self.retryTimer[k] = mq.gettime() + math.max((duration * 1000) - 18000, 30000)
        self.lastCastKey = k

        mq.cmdf('/useitem "%s"', debuff.spell)
    else
        if not mq.TLO.Me.SpellReady(debuff.spell)() then return end

        local spell = mq.TLO.Spell(debuff.spell)
        local duration = spell and spell.Duration.TotalSeconds() or 60
        self.retryTimer[k] = mq.gettime() + math.max((duration * 1000) - 18000, 30000)
        self.lastCastKey = k

        mq.cmd('/stick off')
        mq.cmd('/nav stop')
        local gem = mq.TLO.Me.Gem(debuff.spell)() or debuff.gem
        if not gem then return end
        mq.cmdf('/cast %s', gem)
    end
end

function DebuffDecision:isEntryReady(key, debuff)
    if self.retryTimer[key] and mq.gettime() < self.retryTimer[key] then
        return false
    end
    local entryType = debuff.type or 'spell'
    if entryType == 'item' then
        local item = mq.TLO.FindItem('=' .. debuff.spell)
        return item() and (item.TimerReady() or 1) == 0
    else
        return mq.TLO.Me.SpellReady(debuff.spell)() == true
    end
end

function DebuffDecision:targetHasBuff(targetId, checkBuff)
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

return DebuffDecision
