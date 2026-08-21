local mq    = require 'mq'
local Job   = require 'model.Job'
local State = require 'core.State'
local SpellUtil = require 'util.SpellUtil'

-- Fires Cannibalize when mana is below CanniManaThreshold and HP is safely
-- above CanniHPThreshold so the HP sacrifice doesn't endanger the shaman.
--
-- YAML (under Shaman:):
--   AutoCanni: true
--   CanniManaThreshold: 80   # cast when mana % is below this
--   CanniHPThreshold: 70     # only cast when HP % is above this
--   CanniSpells:
--     CanniSpell: Cannibalize IV
--     CanniType: spell        # 'spell' (memorized gem) or 'aa'
--     CanniGem: 7             # gem number; only used when CanniType is 'spell'

local CanniDecision = {}
CanniDecision.__index = CanniDecision

function CanniDecision:new(config, castService)
    local self = setmetatable({}, CanniDecision)
    self.name        = 'CanniDecision'
    self.config      = config
    self.castService = castService
    self.job         = nil
    self.castType    = nil
    return self
end

function CanniDecision:isReady(spellName, castType)
    if castType == 'aa' then
        return mq.TLO.Me.AltAbilityReady(spellName)() == true
    else
        return mq.TLO.Me.SpellReady(spellName)() == true
    end
end

function CanniDecision:score(ctx)
    self.job      = nil
    self.castType = nil

    if ctx.casting then return 0 end
    -- ctx.moving (Me.Moving()) reads false during brief mid-route stutters
    -- (waypoint transitions, corners, repaths) even while actively navigating,
    -- which let Canni fire and yank us out of formation. Match BuffService's
    -- gate instead: only block when actually still catching up or navigating.
    if State.move.active then return 0 end
    if State.follow.active and mq.TLO.Stick.Active() then return 0 end
    if mq.TLO.Plugin("MQ2Nav").IsLoaded() and mq.TLO.Navigation.Active() then return 0 end
    if ctx.myClass ~= 'SHM' then return 0 end
    if not self.config:get('Shaman.AutoCanni') then return 0 end

    local spellName = self.config:get('Shaman.CanniSpells.CanniSpell')
    if not spellName or spellName == '' then return 0 end

    local castType   = self.config:get('Shaman.CanniSpells.CanniType') or 'spell'
    spellName = SpellUtil.resolveRank(spellName, castType)
    local manaThresh = self.config:get('Shaman.CanniManaThreshold') or 80
    local hpThresh   = self.config:get('Shaman.CanniHPThreshold')   or 70

    if (ctx.mana or 100) >= manaThresh then return 0 end
    if (ctx.hp   or 0)   <= hpThresh   then return 0 end
    if not self:isReady(spellName, castType) then return 0 end

    self.castType = castType

    if castType == 'spell' then
        local gem = self.config:get('Shaman.CanniSpells.CanniGem')
                 or mq.TLO.Me.Gem(spellName)()
        self.job = Job:new(mq.TLO.Me.ID(), mq.TLO.Me.Name(), spellName, 'spell', 60, gem)
    else
        -- AA: store name in job for execute; no gem needed
        self.job = Job:new(mq.TLO.Me.ID(), mq.TLO.Me.Name(), spellName, 'aa', 60, nil)
    end

    return 60
end

function CanniDecision:execute(ctx)
    if not self.job then return end

    if self.castType == 'aa' then
        mq.cmdf('/alt activate "%s"', self.job.name)
        local castTime = mq.TLO.Me.AltAbility(self.job.name).Spell.CastTime() or 0
        if castTime > 0 then
            mq.delay(castTime + 500, function() return not mq.TLO.Me.Casting() end)
        end
    else
        if self.castService then
            self.castService:enqueue(self.job)
        else
            -- fallback if castService not injected
            local gem = self.job.gem
            if not gem then
                print(string.format('[SRL] CanniDecision: %s not in a gem slot', self.job.name))
                return
            end
            mq.cmdf('/cast %s', gem)
            mq.delay(3000, function() return not mq.TLO.Me.Casting() end)
        end
    end
end

return CanniDecision
