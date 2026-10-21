local mq  = require 'mq'
local Job = require 'model.Job'
local SpellUtil = require 'util.SpellUtil'

-- Self-heal lifetap for SHD, matching the old KissAssist Heals|Tap behavior:
-- cast on self whenever own HP drops below ShadowKnight.LifeTapThreshold.
-- Cast directly (CastService:castNow, non-blocking); score() already requires
-- the spell memmed and ready, so nothing needs to memorize on demand.
local RETRY_MS = 1000
local LifeTapDecision = {}
LifeTapDecision.__index = LifeTapDecision

function LifeTapDecision:new(config)
    local self = setmetatable({}, LifeTapDecision)
    self.name        = "LifeTapDecision"
    self.config      = config
    self.castService = nil
    self.job         = nil
    self.retryAt     = 0
    return self
end

function LifeTapDecision:setCastService(cs)
    self.castService = cs
end

function LifeTapDecision:score(ctx)
    self.job = nil

    if ctx.casting then return 0 end
    if mq.TLO.Me.Class.ShortName() ~= 'SHD' then return 0 end
    if not self.castService then return 0 end

    local spellName = self.config:get('ShadowKnight.LifeTap')
    if not spellName or spellName == '' then return 0 end
    spellName = SpellUtil.resolveRank(spellName, 'spell')

    -- LifeTapGem must be configured (castNow casts from the memmed gem and
    -- never memorizes; the SpellReady check below implies it's memmed).
    local gem = self.config:get('ShadowKnight.LifeTapGem')
    if not gem then return 0 end

    local threshold = self.config:get('ShadowKnight.LifeTapThreshold') or 85
    if (ctx.hp or 100) > threshold then return 0 end

    if mq.TLO.Me.SpellReady(spellName)() ~= true then return 0 end

    if mq.gettime() < self.retryAt then return 0 end

    local job = Job:new(mq.TLO.Me.ID(), mq.TLO.Me.Name(), spellName, "heal", 450, gem)

    self.job = job
    return 88
end

function LifeTapDecision:execute(ctx)
    if not self.job then return end
    self.castService:castNow(self.job)
    self.retryAt = mq.gettime() + RETRY_MS
end

return LifeTapDecision
