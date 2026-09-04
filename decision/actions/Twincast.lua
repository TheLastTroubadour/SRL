local mq = require 'mq'
local SpellUtil = require 'util.SpellUtil'

-- Twincast could just be another Buffs.CombatBuff entry, cast opportunistically
-- whenever CastService's own separately-scheduled queue happens to get a turn while
-- idle -- but that gives no guarantee it lines up with a twincast-flagged nuke
-- actually being ready (see Nuke.lua's findReady twincast branch, which only fires
-- a flagged nuke once the buff already happens to be up). This decision is proactive
-- instead: scores above Nuke's normal tier specifically when a twincast-flagged nuke
-- is ready to fire, so the buff lands right before the strike rather than randomly.
-- Stays below Nuke's lifetap tier (88) so a genuine emergency self-heal nuke still
-- wins instead of being delayed by a buff cast first.
-- Applies to any character with a Twincast entry configured -- no class hardcoding.
-- Own top-level config section (Twincast.spell/gem) rather than another entry in
-- Buffs.CombatBuff -- that key is a plain list everywhere else it's used, so a
-- named sub-entry there would've meant it's simultaneously a list and a map.
local TwincastDecision = {}
TwincastDecision.__index = TwincastDecision

local function hasTwincastBuff()
    return mq.TLO.Me.Buff('Twincast')() ~= nil
        or mq.TLO.Me.Song('Twincast')() ~= nil
end

function TwincastDecision:new(config, nukeDecision)
    local self = setmetatable({}, TwincastDecision)
    self.name = "TwincastDecision"
    self.config = config
    self.nukeDecision = nukeDecision
    self.spellName = nil
    self.gem = nil
    return self
end

function TwincastDecision:findEntry()
    return self.config:get('Twincast')
end

function TwincastDecision:score(ctx)
    self.spellName = nil
    self.gem = nil

    if ctx.casting then return 0 end
    if hasTwincastBuff() then return 0 end -- already up -- Nuke's own twincast branch handles firing the flagged nuke

    local entry = self:findEntry()
    if not entry then return 0 end -- this character doesn't have Twincast configured

    if not self.nukeDecision or not self.nukeDecision:hasReadyTwincastEntry(ctx) then
        return 0 -- nothing to combo it with right now
    end

    local spellName = SpellUtil.resolveRank(entry.spell or entry.name, 'spell')
    if not mq.TLO.Me.SpellReady(spellName)() then return 0 end

    self.spellName = spellName
    self.gem = entry.gem
    return 85 -- above Nuke's normal tier (80) so it preempts the flagged nuke this
              -- tick, below its lifetap tier (88) so a self-heal emergency still wins
end

function TwincastDecision:execute(ctx)
    if not self.spellName then return end
    -- Same convention as Nuke.lua: cast by gem slot, not spell name --
    -- resolve via Me.Gem() first (handles it being memmed in a different
    -- slot than configured), falling back to the configured gem.
    local gem = mq.TLO.Me.Gem(self.spellName)() or self.gem
    if not gem then return end
    mq.cmdf('/cast %s', gem)
end

return TwincastDecision
