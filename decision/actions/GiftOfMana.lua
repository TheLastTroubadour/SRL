local mq = require 'mq'
local Target = require 'service.TargetService'
local SpellUtil = require 'util.SpellUtil'

local GiftOfMana = {}
GiftOfMana.__index = GiftOfMana

local CASTING_ROLES = { caster = true, healer = true, hybrid = true }
local BUFF_NAME     = 'Gift of Mana'

local function hasGiftOfMana()
    return mq.TLO.Me.Buff(BUFF_NAME)() ~= nil
        or mq.TLO.Me.Song(BUFF_NAME)() ~= nil
end

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

    if not hasGiftOfMana() then return 0 end

    local entry = self.config:get('GiftOfMana')
    if not entry or not entry.spell then return 0 end

    local spellName = SpellUtil.resolveRank(entry.spell, 'spell')
    if not mq.TLO.Me.SpellReady(spellName)() then return 0 end

    self.job = { spell = spellName, gem = entry.gem, target = entry.target }
    return 98
end

function GiftOfMana:execute(ctx)
    if not self.job then return end

    local target = self.job.target or 'assist'

    if target == 'assist' and ctx.assist.Id then
        if mq.TLO.Target.ID() ~= ctx.assist.Id then
            Target:getTargetById(ctx.assist.Id)
        end
    elseif target == 'self' then
        if mq.TLO.Target.ID() ~= mq.TLO.Me.ID() then
            Target:getTargetById(mq.TLO.Me.ID())
        end
    end

    local gem = mq.TLO.Me.Gem(self.job.spell)() or self.job.gem
    if not gem then return end
    mq.cmdf('/cast %s', gem)
end

return GiftOfMana
