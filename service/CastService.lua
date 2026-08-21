local mq = require 'mq'
local TableUtil = require 'util.TableUtil'
local Logging = require 'core.Write'
local Target = require 'service.TargetService'
local State = require 'core.State'
local StringUtil = require 'util.StringUtil'

local CastService = {}
CastService.__index = CastService

-- mq.delay() blocks the entire script (mainLoop, DecisionEngine, everything)
-- until it resolves — only the delay's own condition callback keeps polling.
-- So a job can't interrupt an in-flight cast by sitting in the queue (nothing
-- can get enqueued while the script is frozen); instead we re-check live HP
-- directly in that callback. A hard emergency floor (rather than a priority
-- comparison) keeps this from firing on ordinary heal/buff contention — only
-- a genuinely critical target crosses it — and the cooldown stops rapid
-- chain-interrupting even if multiple people are critical at once.
local EMERGENCY_HP_THRESHOLD = 20
local INTERRUPT_COOLDOWN_MS  = 2000

function CastService:new(scheduler, combatService)
    local self = setmetatable({}, CastService)

    self.scheduler = scheduler
    self.combatService = combatService
    self.buffService = {}
    self.queue = {}
    self.queuedKeys = {}
    self.currentlyInFlight = nil
    self.lockedGems = {}
    self.lastInterruptAt = 0
    self.lastGemCastAt = {} -- [gemNumber] = gettime() of last /cast issued from that gem
    self:startWorker()

    return self
end

-- True if someone other than the current cast's own target has dropped to a
-- genuinely critical HP% right now. Live TLO reads, so this stays accurate
-- even while the rest of the script is frozen inside this same mq.delay.
-- Group members use native, always-fresh GroupMember fields. Raid-wide
-- coverage comes from the bus-broadcast statusService instead of raid-member
-- spawn HP -- raid data has no native HP field at all, so PctHPs()/Dead() on
-- a raid member silently fall back to spawn data that's only fresh if this
-- client happens to be actively tracking that entity (proven stale in testing).
function CastService:emergencyInterruptNeeded(job)
    if mq.gettime() - self.lastInterruptAt < INTERRUPT_COOLDOWN_MS then
        return false
    end

    local function isCritical(name, hp, dead)
        return name and name ~= job.targetName and not dead and hp and hp <= EMERGENCY_HP_THRESHOLD
    end

    for i = 1, mq.TLO.Group.Members() do
        local m = mq.TLO.Group.Member(i)
        if m() and isCritical(m.CleanName(), m.PctHPs(), m.Dead()) then
            return true
        end
    end

    if self.statusService then
        for _, peer in ipairs(self.statusService:getAll()) do
            -- Prefer the DanNet observer's HP when we have one (fresher --
            -- driven by the peer's own plugin, not their Lua main loop).
            local hp = (self.danNetHpService and self.danNetHpService:getHp(peer.name)) or peer.hp
            if isCritical(peer.name, hp, peer.dead) then
                return true
            end
        end
    end

    return false
end

function CastService:setStatusService(statusService)
    self.statusService = statusService
end

function CastService:setDanNetHpService(danNetHpService)
    self.danNetHpService = danNetHpService
end

function CastService:setBus(bus)
    self.bus = bus
end

function CastService:setMelodyService(melodyService)
    self.melodyService = melodyService
end

function CastService:enqueue(job)
    if self.queuedKeys[job.key] then return end

    table.insert(self.queue, job)
    self.queuedKeys[job.key] = true
end

function CastService:startWorker()

    self.scheduler:spawn(function()

        while true do
            local ok, err = pcall(function()
            for i = #self.queue, 1, -1 do
                local job = self.queue[i]
                if not job then
                    table.remove(self.queue, i)
                    goto continue
                end

                -- Stale generation
                if job.generation and job.generation ~= State.assist.generation then
                    self.queuedKeys[job.key] = nil
                    table.remove(self.queue, i)
                    goto continue
                end

                -- Spawn gone (zoned, died, etc.)
                local spawn = mq.TLO.Spawn('id ' .. job.targetId)
                if not spawn() then
                    print("Removing from queue spawn not alive")
                    table.remove(self.queue, i)
                    goto continue
                end

                -- Dead target
                if spawn.Dead() then
                    table.remove(self.queue, i)
                    goto continue
                end

                -- Out of range
                if job.type ~= 'ability' and job.type ~= 'disc' and job.type ~= 'item' and job.type ~= 'aa' then
                    local spellRange
                    if job.range then
                        spellRange = tonumber(job.range)
                    else
                        local range   = tonumber(mq.TLO.Spell(job.name).Range())   or 0
                        local aeRange = tonumber(mq.TLO.Spell(job.name).AERange()) or 0
                        spellRange = range > 0 and range or aeRange
                    end
                    if spellRange > 0 and spellRange < tonumber(spawn.Distance()) then
                        print(string.format("Removing due to spell distance: %s | target: %s (id: %s) | dist: %.1f | range: %.1f",
                            job.name, job.targetName, job.targetId, tonumber(spawn.Distance()), spellRange))
                        table.remove(self.queue, i)
                        goto continue
                    end
                end

                ::continue::
            end

            if self.currentlyInFlight
                    and self.currentlyInFlight.generation
                    and self.currentlyInFlight.generation ~= State.assist.generation then
                -- Let cast finish naturally
                self.currentlyInFlight = nil
            end

            if self.currentlyInFlight then
                mq.delay(25)
                return
            end

            if #self.queue == 0 then
                mq.delay(50)
            else
                if #self.queue > 1 then
                    table.sort(self.queue, function(a, b)
                        if not a then return false end
                        if not b then return true end
                        return a.priority > b.priority
                    end)
                end

                -- Find first job past its notBefore time
                local jobIdx = nil
                local nowMs = mq.gettime()
                for idx = 1, #self.queue do
                    local j = self.queue[idx]
                    if not j.notBefore or nowMs >= j.notBefore then
                        jobIdx = idx
                        break
                    end
                end

                if not jobIdx then
                    mq.delay(50)
                    goto workerNext
                end

                -- Don't cast while invisible — would break invis for the group
                if mq.TLO.Me.Invis() then
                    mq.delay(50)
                    goto workerNext
                end

                local job = table.remove(self.queue, jobIdx)

                -- For buff jobs, pull all pending casts of the same spell into a batch
                -- so they share the one gem-swap instead of each paying the 12s mem cost.
                local batch = { job }
                if job.type == 'buff' then
                    for i = #self.queue, 1, -1 do
                        local j = self.queue[i]
                        if j and j.name == job.name and j.type == 'buff' then
                            self.queuedKeys[j.key] = nil
                            table.remove(self.queue, i)
                            table.insert(batch, j)
                        end
                    end
                end

                State.flags.castInFlight = true
                for _, batchJob in ipairs(batch) do
                    -- Validate every batch entry: target may have zoned, died, or walked out of range
                    local s = mq.TLO.Spawn('id ' .. batchJob.targetId)
                    if not s() or s.Dead() then
                        self.queuedKeys[batchJob.key] = nil
                        goto batchNext
                    end
                    local range = mq.TLO.Spell(batchJob.name).Range() or 0
                    local spellRange = tonumber(range) == 0 and (mq.TLO.Spell(batchJob.name).AERange() or 0) or range
                    if tonumber(spellRange) > 0 and (s.Distance() or 0) > tonumber(spellRange) then
                        self.queuedKeys[batchJob.key] = nil
                        goto batchNext
                    end

                    self.currentlyInFlight = batchJob
                    local result = self:performCast(batchJob)
                    if result == "NOT_READY" and (batchJob.type == 'disc' or batchJob.type == 'aa') then
                        -- Burn job not ready yet — put it back so it fires when it comes off cooldown.
                        -- Set notBefore to prevent immediate retry, which would starve lower-priority
                        -- burn jobs and spin the coroutine without yielding.
                        self.queuedKeys[batchJob.key] = nil
                        batchJob.notBefore = mq.gettime() + 500
                        self:enqueue(batchJob)
                    else
                        if batchJob.type == 'buff' then
                            mq.delay(500, function() return mq.TLO.Target.BuffsPopulated() == true end)
                        end
                        if batchJob.type == 'buff' and self:checkIfHasBuff(batchJob) then
                            self.buffService:setTakeHoldCooldownOnJob(batchJob)
                            -- Notify all bots so group members can confirm they
                            -- received it and suppress duplicate casts.
                            if self.bus then
                                self.bus.actor:broadcast('buff_cast', {
                                    casterName = mq.TLO.Me.Name(),
                                    spellName  = batchJob.buffName or batchJob.name,
                                    sender     = mq.TLO.Me.Name(),
                                })
                            end
                        end
                        self.queuedKeys[batchJob.key] = nil
                        self.queuedKeys[batchJob.name] = nil
                    end
                    ::batchNext::
                end
                self.currentlyInFlight = nil
                State.flags.castInFlight = false
            end
            ::workerNext::
            end) -- end pcall
            if not ok then
                print("CastService worker error:", err)
                self.currentlyInFlight = nil
                State.flags.castInFlight = false
            end
        end
    end)
end

function CastService:performCast(job)
    --[[
    self.bus:broadcast("cast_started " .. mq.TLO.Me.Name() .. " spell: " .. job.name .. " targetId: " .. job.targetId, {
        caster = mq.TLO.Me.Name(),
        spell = job.name,
        targetId = job.targetId,
        type = job.type
    })
    --]]

    local result

    local spellType = job.type == "spell" or job.type == "heal" or job.type == "buff" or job.type == "nuke" or job.type == "aa" or job.type == "item"
    if spellType and mq.TLO.Me.Silenced() then
        return "SILENCED"
    end

    if job.type == "spell" or job.type == "heal" or job.type == "buff" or job.type == "nuke" then
        result = self:castSpell(job)
    elseif job.type == "aa" then
        result = self:castAA(job)
    elseif job.type == "item" then
        result = self:castItem(job)
    elseif job.type == "disc" then
        result = self:castDisc(job)
    elseif job.type == 'ability' then
        result = self:castAbility(job)
    end

    --[[
    -- announce completion
    self.bus:broadcast("cast_finished " .. mq.TLO.Me.Name() .. "spell" .. job.name .. " targetId: " .. job.targetId, {
        caster = mq.TLO.Me.Name(),
        spell = job.name,
        targetId = job.targetId,
        success = result
    })
    --]]

    return result
end

function CastService:isQueued(job)
    return self.queuedKeys[job.key] == true
end

function CastService:lockGem(gemNum)
    self.lockedGems[tonumber(gemNum)] = true
end

function CastService:unlockGem(gemNum)
    self.lockedGems[tonumber(gemNum)] = nil
end

function CastService:isGemLocked(gemNum)
    return self.lockedGems[tonumber(gemNum)] == true
end

local function hasEnoughMana(spellName)
    local spell = mq.TLO.Spell(spellName)
    if not spell() then
        return true -- spell not in DB, let the cast attempt handle it
    end

    local manaCost = spell.Mana() or 0
    if manaCost == 0 then return true end

    local currentMana = mq.TLO.Me.CurrentMana() or 0

    return currentMana >= manaCost
end

function CastService:castAA(job)
    if not mq.TLO.Me.AltAbilityReady(job.name)() then return "NOT_READY" end
    mq.cmdf('/alt activate "%s"', job.name)
    local castTime = (mq.TLO.Me.AltAbility(job.name).Spell.CastTime() or 0)
    if castTime > 0 then
        mq.delay(castTime + 500, function() return not mq.TLO.Me.Casting() end)
    end
end

function CastService:castAbility(job)
    mq.cmdf('/doability %s', job.name)
end

function CastService:castItem(job)
    local item = mq.TLO.FindItem('=' .. job.name)
    if not item() then return end

    local resumeMelody = nil
    if self.melodyService and mq.TLO.Me.Class.ShortName() == 'BRD' then
        resumeMelody = self.melodyService.active
        self.melodyService:stop()
        mq.delay(100, function() return not mq.TLO.Me.Casting() end)
    end

    mq.cmdf('/useitem "%s"', job.name)
    local castTime = item.Clicky.CastTime() or 0
    if castTime > 0 then
        mq.delay(castTime + 500, function() return not mq.TLO.Me.Casting() end)
    end

    if resumeMelody then
        self.melodyService:play(resumeMelody)
    end
end

function CastService:castDisc(job)
    local baseName = job.name:gsub('%s+Rk%.%s*%a+$', '')

    -- Already active: this exact disc is running, no need to re-cast
    local activeDisc = mq.TLO.Me.ActiveDisc()
    if activeDisc and activeDisc ~= '' then
        local activeBase = activeDisc:gsub('%s+Rk%.%s*%a+$', '')
        if activeBase == baseName then
            return "NOT_READY"
        end
    end

    -- Buff-granting discs (CombatBuff/SelfBuff entries) shouldn't refire while the
    -- buff they grant is still up -- ActiveDisc above only covers the disc's own
    -- brief channel window, not the resulting buff's actual duration.
    if job.buffName and not job.force and self:checkIfHasBuff(job) then
        return "NOT_READY"
    end

    if not mq.TLO.Me.CombatAbilityReady(job.name)() then
        return "NOT_READY"
    end

    mq.cmdf('/disc %s', job.name)
    -- Brief wait then verify the reuse timer was consumed.
    -- If still ready, a different active disc's mutex blocked it silently.
    mq.delay(250)
    if mq.TLO.Me.CombatAbilityReady(job.name)() then
        return "NOT_READY"
    end

    local castTime = (mq.TLO.Spell(job.name).CastTime.TotalSeconds() or 0) * 1000
    if castTime > 250 then
        mq.delay(castTime - 250, function() return not mq.TLO.Me.Casting() end)
    end
end


function CastService:castSpell(job)
    if not hasEnoughMana(job.name) then
        print(string.format("Not enough mana for: %s (have %d, need %d)",
            job.name,
            mq.TLO.Me.CurrentMana() or 0,
            mq.TLO.Spell(job.name).Mana() or 0
        ))
        return
    end
    if job.type == 'buff' and not job.force then
        if self:checkIfHasBuff(job) then
            return
        end
    end
    return self:srlCast(job)
end

function CastService:checkIfHasBuff(job)
    local checkName = job.buffName or job.name
    -- Check distributed cache first — populated by each bot broadcasting its own buff changes
    if self.buffService and self.buffService:hasKnownBuff(job.targetName, checkName) then
        return true
    end
    -- Self-targeted jobs can always check directly, regardless of current target
    if job.targetId == mq.TLO.Me.ID() then
        local baseName = checkName:gsub('%s+Rk%.%s*%a+$', '')
        return mq.TLO.Me.Buff('=' .. checkName)() ~= nil
                or mq.TLO.Me.Buff(baseName)() ~= nil
                or mq.TLO.Me.Song('=' .. checkName)() ~= nil
                or mq.TLO.Me.Song(baseName)() ~= nil
    end
    -- Fall back to target buff window, only reliable when already targeting this character
    if mq.TLO.Target.ID() == job.targetId then
        if mq.TLO.Target.Buff('=' .. checkName)() then return true end
        local baseName = checkName:gsub('%s+Rk%.%s*%a+$', '')
        local jobRank  = StringUtil.parseRank(checkName)
        local existing = mq.TLO.Target.Buff(baseName)
        if existing() then
            -- Only treat as "already buffed" if existing rank is equal or higher
            if jobRank == 0 or StringUtil.parseRank(existing.Name() or '') >= jobRank then
                return true
            end
        end
    end
    return false
end


function CastService:memSpellIfNeeded(job)
    if job then
        if mq.TLO.Me.Spell(job.name)() then
            if not mq.TLO.Me.Gem(job.name)() then
                local gemNum = tonumber(job.gem)
                -- Wait up to 20s for MemSwap to release the slot
                mq.delay(20000, function() return not self:isGemLocked(gemNum) end)
                self:lockGem(gemNum)
                mq.cmdf("/memspell %s \"%s\"", job.gem, job.name)
                mq.delay(12000, function()
                    return mq.TLO.Me.Gem(job.name)() ~= nil
                end)
                if mq.TLO.Window("SpellBookWnd").Open() then
                    mq.cmd('/book')
                    mq.delay(2000, function() return not mq.TLO.Window("SpellBookWnd").Open() end)
                end
                self:unlockGem(gemNum)
            end
        end
    end
end


function CastService:srlCast(job)
    Logging.Debug("Cast Util Export SRL Cast Start")
    self:memSpellIfNeeded(job)
    if not mq.TLO.Me.SpellReady(job.name)() then
        -- Wait long enough to cover the spell's own recast/gem-refresh window
        -- (a spell that was just swapped into this gem, or just cast, may not
        -- show ready for several seconds) -- fixed 2000ms was too short for
        -- some spells, causing the cast to silently give up and never fire.
        -- Capped so a genuinely long-cooldown spell (minutes) doesn't block
        -- the whole script for that long; it just won't be ready in time and
        -- the job falls through as before.
        local recastMs = (mq.TLO.Spell(job.name).RecastTime.TotalSeconds() or 0) * 1000
        local waitMs = math.min(math.max(recastMs, 2000), 8000)
        mq.delay(waitMs, function() return mq.TLO.Me.SpellReady(job.name)() end)
    end
    local isSpellReady = mq.TLO.Me.SpellReady(job.name)()
    Logging.Debug(("Is spell ready %s --- %s "):format(job.name, tostring(isSpellReady)))
    if isSpellReady then
        if not job.targetId then
            return "BAD_TARGET_ID"
        end

        -- Self-only spells land on the caster regardless of current target in
        -- EQ -- no need to retarget self, which would otherwise needlessly
        -- knock a mid-combat character off its actual assist/combat target.
        local isSelfCast = job.targetId == mq.TLO.Me.ID()
        if not isSelfCast and mq.TLO.Target.ID() ~= job.targetId then
            Target:getTargetById(job.targetId)
        end
        mq.cmd("/stick off")
        mq.cmd('/nav stop')
        local gem = mq.TLO.Me.Gem(job.name)() or job.gem
        if not gem then return end
        local castTime = mq.TLO.Spell(job.name).CastTime.TotalSeconds() * 1000 + 1500

        if job.type == 'heal' then
            mq.cmdf('/dga all /echo [SRL] %s healing %s with %s', mq.TLO.Me.Name(), job.targetName or '?', job.name)
        end

        self.lastGemCastAt[tonumber(gem)] = mq.gettime()
        mq.cmdf('/cast %s', gem)
        mq.delay(1000, function() return mq.TLO.Me.Casting() ~= nil end)
        -- Main loop is blocked during mq.delay, so broadcast casting status now
        -- so the group overlay shows the spell name during the cast.
        if self.bus then
            self.bus.actor:broadcast('char_status', {
                name      = mq.TLO.Me.Name() or '',
                hp        = mq.TLO.Me.PctHPs() or 0,
                mana      = mq.TLO.Me.PctMana() or 0,
                endurance = mq.TLO.Me.PctEndurance() or 0,
                target    = mq.TLO.Target.CleanName() or '',
                casting   = mq.TLO.Me.Casting() or '',
                dead      = mq.TLO.Me.Dead() == true,
                zone      = mq.TLO.Zone.ShortName() or '',
                class     = mq.TLO.Me.Class.ShortName() or '',
            })
        end
        mq.delay(castTime, function()
            return not mq.TLO.Me.Casting() or self:emergencyInterruptNeeded(job)
        end)
        if mq.TLO.Me.Casting() and self:emergencyInterruptNeeded(job) then
            mq.cmd('/interrupt')
            self.lastInterruptAt = mq.gettime()
        end
    end
    Logging.Debug("Cast Util Export SRL Cast End")
end

function CastService:clearCombatQueue()
    for i = #self.queue, 1, -1 do
        local job = self.queue[i]
        if not job.burn and (job.type == "ability" or job.type == "nuke" or job.type == "disc" or job.type == "aa") then
            self.queuedKeys[job.key] = nil
            table.remove(self.queue, i)
        end
    end
end

function CastService:clearQueue()
    self.queue            = {}
    self.queuedKeys       = {}
    self.currentlyInFlight = nil
end

function CastService:interruptCasting()
    if mq.TLO.Me.Casting() and mq.TLO.Target.ID() == State.assist.targetId then
        mq.cmd('/interrupt')
    end
end

return CastService