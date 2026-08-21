local mq = require 'mq'
local SpellUtil = require 'util.SpellUtil'

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

    -- Never swap mid-fight: execute() is a fully blocking mq.delay sequence
    -- (up to ~35s waiting on a gem lock + /memspell), and mq.delay freezes the
    -- entire script -- not just this decision -- until it resolves. Since this
    -- only scores 25 (well below combat actions), it should never normally win,
    -- but it CAN win by default on any tick where nothing else happens to be
    -- scoring yet (e.g. between Pull cycles, before TankAssist has picked up a
    -- target) -- and once it wins, it can't be interrupted even if a real
    -- threat shows up mid-swap. Gem administration can wait for downtime.
    if (ctx.numberOfAggresiveInXTar or 0) > 0 or ctx.inCombat then return 0 end

    local loadout = self.config:get('GemSwap.' .. self.activeSet)
    if not loadout or #loadout == 0 then return 0 end

    local swaps = {}
    for _, entry in ipairs(loadout) do
        if entry.gem and entry.name then
            -- Resolve once and cache on the entry -- entry.name may be a base
            -- name (e.g. "Terror of Jelvalak") while the character actually has
            -- a higher rank memmed (e.g. "Terror of Jelvalak Rk. III"). Without
            -- this, every ranked spell reads as "wrong" forever (exact string
            -- compare against the live gem), and blindly /memspell-ing the base
            -- name risks re-memming at Rank 1, downgrading what's already correct.
            if not entry._resolvedName then
                entry._resolvedName = SpellUtil.resolveRank(entry.name, 'spell')
            end
            local wanted = entry._resolvedName
            local current = mq.TLO.Me.Gem(entry.gem)()
            if current ~= wanted
                    and not self:isSpellNeeded(current)
                    and not self.castService:isGemLocked(entry.gem)
                    and mq.TLO.Me.Spell(wanted)() then
                table.insert(swaps, entry)
                print(string.format("[SRL] MemSwap: gem %d has \"%s\", wants \"%s\"",
                    entry.gem, tostring(current), wanted))
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
        local wanted = entry._resolvedName or entry.name
        local current = mq.TLO.Me.Gem(entry.gem)()
        if current ~= wanted and not self:isSpellNeeded(current) then
            print(string.format("[SRL] MemSwap: swapping gem %d \"%s\" -> \"%s\" (waiting on gem lock if held)...",
                entry.gem, tostring(current), wanted))
            local lockWaitStart = mq.gettime()
            -- Wait up to 20s for a buff to finish borrowing this slot
            mq.delay(20000, function() return not self.castService:isGemLocked(entry.gem) end)
            if self.castService:isGemLocked(entry.gem) then
                print(string.format("[SRL] MemSwap: gem %d still locked after 20s wait, proceeding anyway", entry.gem))
            end
            self.castService:lockGem(entry.gem)
            print(string.format("[SRL] MemSwap: /memspell %d \"%s\" (waited %dms on lock)",
                entry.gem, wanted, mq.gettime() - lockWaitStart))
            mq.cmdf('/memspell %d "%s"', entry.gem, wanted)
            local memStart = mq.gettime()
            mq.delay(15000, function()
                return mq.TLO.Me.Gem(entry.gem)() == wanted
            end)
            local landed = mq.TLO.Me.Gem(entry.gem)() == wanted
            print(string.format("[SRL] MemSwap: gem %d now \"%s\" after %dms (%s)",
                entry.gem, tostring(mq.TLO.Me.Gem(entry.gem)()), mq.gettime() - memStart,
                landed and "success" or "TIMED OUT"))
            if mq.TLO.Window("SpellBookWnd").Open() then
                mq.cmd('/book')
                mq.delay(2000, function() return not mq.TLO.Window("SpellBookWnd").Open() end)
            end
            self.castService:unlockGem(entry.gem)
        end
    end
end

return MemSwapDecision
