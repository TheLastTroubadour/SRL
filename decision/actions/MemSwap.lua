local mq = require 'mq'

-- MemSwapDecision keeps GemSwap entries as the permanent home for those gem
-- slots. Buff spells borrow a slot temporarily (via CastService's
-- memSpellIfNeeded). Once the borrowing job is no longer queued or in-flight,
-- this decision restores the slot to its declared combat spell.
--
-- YAML:
--   GemSwap:
--     - gem: 2
--       name: Balance of Discord
--     - gem: 8
--       name: "Tortugone's Drowse"

local MemSwapDecision = {}
MemSwapDecision.__index = MemSwapDecision

function MemSwapDecision:new(config, castService)
    local self = setmetatable({}, MemSwapDecision)
    self.name        = "MemSwapDecision"
    self.config      = config
    self.castService = castService
    self.pending     = nil
    self.activeSet   = 'Main'
    return self
end

function MemSwapDecision:reloadSet(set)
    self.activeSet = set or 'Main'
end

-- Returns true if spellName is currently queued or in-flight in CastService.
function MemSwapDecision:isSpellNeeded(spellName)
    if not self.castService or not spellName or spellName == '' then return false end

    local inf = self.castService.currentlyInFlight
    if inf and inf.name == spellName then return true end

    for _, job in ipairs(self.castService.queue) do
        if job.name == spellName then return true end
    end

    return false
end

function MemSwapDecision:score(ctx)
    self.pending = nil

    if ctx.casting then return 0 end

    local loadout = self.config:get('GemSwap.' .. self.activeSet)
    if not loadout or #loadout == 0 then return 0 end

    local swaps = {}
    for _, entry in ipairs(loadout) do
        if entry.gem and entry.name then
            local current = mq.TLO.Me.Gem(entry.gem)()
            if current ~= entry.name
                    and not self:isSpellNeeded(current)
                    and not self.castService:isGemLocked(entry.gem)
                    and mq.TLO.Me.Spell(entry.name)() then
                table.insert(swaps, entry)
            end
        end
    end

    if #swaps == 0 then return 0 end

    self.pending = swaps
    return 25
end

function MemSwapDecision:execute(ctx)
    if not self.pending then return end

    for _, entry in ipairs(self.pending) do
        local current = mq.TLO.Me.Gem(entry.gem)()
        if current ~= entry.name and not self:isSpellNeeded(current) then
            -- Wait up to 20s for a buff to finish borrowing this slot
            mq.delay(20000, function() return not self.castService:isGemLocked(entry.gem) end)
            self.castService:lockGem(entry.gem)
            mq.cmdf('/memspell %d "%s"', entry.gem, entry.name)
            mq.delay(15000, function()
                return mq.TLO.Me.Gem(entry.gem)() == entry.name
            end)
            self.castService:unlockGem(entry.gem)
        end
    end
end

return MemSwapDecision
