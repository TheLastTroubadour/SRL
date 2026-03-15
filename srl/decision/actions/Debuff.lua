local mq = require 'mq'
local DebuffDecision = {}
DebuffDecision.__index = DebuffDecision

function DebuffDecision:new(config)
    local self = setmetatable({}, DebuffDecision)
    self.name = "DebuffDecision"
    self.config = config
    self.retryTimer = {}
    self.pendingTarget = nil
    self.pendingDebuff = nil
    return self
end

function DebuffDecision:score(ctx)
    self.pendingTarget = nil
    self.pendingDebuff = nil

    if ctx.casting then return 0 end

    if not ctx.roles['debuff'] then return 0 end
    if not ctx.self.debuff then return 0 end
    if #ctx.self.debuff.onAssistSpells == 0 then return 0 end
    if not ctx.assist.Id or ctx.assist.dead then return 0 end
    if ctx.assist.distance and ctx.assist.distance > 200 then return 0 end
    if ctx.mana < 10 then return 0 end

    -- Check assist target first
    for _, debuff in ipairs(ctx.self.debuff.onAssistSpells) do
        local key = debuff.spell .. ":" .. tostring(ctx.assist.Id)
        if self:needsCast(key, debuff.spell) then
            self.pendingTarget = ctx.assist.Id
            self.pendingDebuff = debuff
            return 80
        end
    end

    -- Check xtargets if enabled
    if ctx.self.debuff.enabledForXTar then
        local slots = mq.TLO.Me.XTargetSlots()
        for i = 1, slots do
            local xt = mq.TLO.Me.XTarget(i)
            if xt() and xt.Type() == "NPC" and not xt.Dead() and xt.Aggressive() and xt.ID() ~= tonumber(ctx.assist.Id) then
                for _, debuff in ipairs(ctx.self.debuff.onAssistSpells) do
                    local key = debuff.spell .. ":" .. tostring(xt.ID())
                    if self:needsCast(key, debuff.spell) then
                        self.pendingTarget = xt.ID()
                        self.pendingDebuff = debuff
                        return 80
                    end
                end
            end
        end
    end

    return 0
end

function DebuffDecision:execute(ctx)
    if not self.pendingTarget or not self.pendingDebuff then return end

    local debuff = self.pendingDebuff
    local targetId = self.pendingTarget

    if not mq.TLO.Cast.Ready(debuff.spell)() then return end

    if mq.TLO.Target.ID() ~= targetId then
        mq.cmdf('/target id %s', targetId)
        mq.delay(100)
    end

    -- Set optimistic retry timer so we don't spam before it lands
    local spell = mq.TLO.Spell(debuff.spell)
    local duration = spell and spell.Duration.TotalSeconds() or 60
    local key = debuff.spell .. ":" .. tostring(targetId)
    self.retryTimer[key] = mq.gettime() + math.max((duration * 1000) - 18000, 30000)

    mq.cmd("/stick off")
    mq.cmd("/afollow off")
    mq.cmdf("/casting \"%s\"|%s", debuff.spell, debuff.gem)
end

function DebuffDecision:needsCast(key, spellName)
    if self.retryTimer[key] and mq.gettime() < self.retryTimer[key] then
        return false
    end
    return mq.TLO.Cast.Ready(spellName)()
end

return DebuffDecision
