local mq = require 'mq'
local Target = require 'service.TargetService'
local SpellUtil = require 'util.SpellUtil'

-- Fires a configured high-value spell while the Twincast buff is up (doubles
-- the next cast's effect) instead of letting normal nuke rotation burn it on
-- whatever's next in line. Source of the buff doesn't matter -- a wizard's own
-- long-recast Twincast AA, a beastlord's group Twincast, a bard song, etc. --
-- this only reacts to the buff being present.
-- Config: Twincast: { spell, gem, target }  (target: 'assist' | 'self', default 'assist')

local Twincast = {}
Twincast.__index = Twincast

local CASTING_ROLES = { caster = true, healer = true, hybrid = true }
local BUFF_NAME     = 'Twincast'

local function hasTwincast()
    return mq.TLO.Me.Buff(BUFF_NAME)() ~= nil
        or mq.TLO.Me.Song(BUFF_NAME)() ~= nil
end

function Twincast:new(config)
    local self = setmetatable({}, Twincast)
    self.name   = "Twincast"
    self.config = config
    self.job    = nil
    return self
end

function Twincast:score(ctx)
    self.job = nil

    if ctx.casting then return 0 end

    local hasRole = false
    for role, _ in pairs(CASTING_ROLES) do
        if ctx.roles[role] then hasRole = true break end
    end
    if not hasRole then return 0 end

    if not hasTwincast() then return 0 end

    local entry = self.config:get('Twincast')
    if not entry or not entry.spell then return 0 end

    local spellName = SpellUtil.resolveRank(entry.spell, 'spell')
    if not mq.TLO.Me.SpellReady(spellName)() then return 0 end

    self.job = { spell = spellName, gem = entry.gem, target = entry.target }
    return 97
end

function Twincast:execute(ctx)
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
    mq.cmd('/stick off')
    if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
    mq.cmdf('/cast %s', gem)
end

return Twincast
