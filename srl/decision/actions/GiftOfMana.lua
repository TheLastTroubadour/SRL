local mq = require 'mq'

local GiftOfMana = {}
GiftOfMana.__index = GiftOfMana

local CASTING_ROLES = { caster = true, healer = true, hybrid = true }
local BUFF_NAME     = 'Gift of Mana'

function GiftOfMana:new(config)
    local self = setmetatable({}, GiftOfMana)
    self.name   = "GiftOfMana"
    self.config = config
    self.job    = nil
    return self
end

function GiftOfMana:score(ctx)
    self.job = nil

    if ctx.casting then return 0 end

    local hasRole = false
    for role, _ in pairs(CASTING_ROLES) do
        if ctx.roles[role] then hasRole = true break end
    end
    if not hasRole then return 0 end

    if not mq.TLO.Me.Buff(BUFF_NAME)() then return 0 end

    local entry = self.config:get('GiftOfMana')
    if not entry or not entry.spell then return 0 end

    if not mq.TLO.Cast.Ready(entry.spell)() then return 0 end

    self.job = entry
    return 98
end

function GiftOfMana:execute(ctx)
    if not self.job then return end

    local target = self.job.target or 'assist'

    if target == 'assist' and ctx.assist.Id then
        if mq.TLO.Target.ID() ~= ctx.assist.Id then
            mq.cmdf('/target id %s', ctx.assist.Id)
            mq.delay(100)
        end
    elseif target == 'self' then
        if mq.TLO.Target.ID() ~= mq.TLO.Me.ID() then
            mq.cmdf('/target id %s', mq.TLO.Me.ID())
            mq.delay(100)
        end
    end

    mq.cmdf('/casting "%s"|%s', self.job.spell, self.job.gem)
end

return GiftOfMana
