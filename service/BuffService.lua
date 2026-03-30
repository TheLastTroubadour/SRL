local mq = require 'mq'
local TableUtil = require 'util.TableUtil'
local StringUtil = require 'util.StringUtil'
local Job = require 'model.Job'
local State = require 'core.State'
local MAX_NEXT_CHECK_MS = 30 * 60 * 1000  -- 30 minutes

local BuffService = {}
BuffService.__index = BuffService

function BuffService:new(bus, scheduler, combatService, castService, config)
    local self = setmetatable({}, BuffService)

    self.config = config
    self.policy = {
        selfBuffs = self:getBuffInformationForKey('Buffs.SelfBuff'),
        combatBuffs = self:getBuffInformationForKey('Buffs.CombatBuff'),
        botBuffs = self:getBuffInformationForKey('Buffs.BotBuff')
    }

    self.scheduler = scheduler
    self.combatService = combatService
    self.castService = castService
    self.explicitRequests = {}
    self.bus = bus
    self.requested = {}     -- target:spell currently polling
    self.cooldowns = {}     -- suppression timer
    self.nextCheck = {}   -- key → timestamp when next poll allowed

    return self
end

local function key(target, spellName)
    return target .. ":" .. spellName
end

function BuffService:pollIfDue(target, spell)

    local k = key(target, spell)
    local now = mq.gettime()
    if not now then return nil end

    --supression active (per target:spell)
    if self.cooldowns[k] and now < self.cooldowns[k] then
        return nil
    end

    -- Spell-level suppression: prevents same spell being polled for multiple targets
    -- simultaneously (e.g. group buffs listed under charactersToBuff)
    local spellKey = 'spell:' .. spell
    if self.cooldowns[spellKey] and now < self.cooldowns[spellKey] then
        return nil
    end

    local spawn = mq.TLO.Spawn('pc =' .. target)

    -- Not in zone
    if not spawn() then
        self.nextCheck[k] = now + 60000
        return nil
    end

    -- Dead — reset timer so we rebuff immediately after they res
    if spawn.Dead() then
        self.nextCheck[k] = now + 5000
        return nil
    end

    -- Not time yet
    if self.nextCheck[k] and now < self.nextCheck[k] then
        return nil
    end

    -- Already polling (clear stale lock after 10s in case the coroutine died)
    if self.requested[k] then
        if now < self.requested[k] + 10000 then
            return nil
        end
        self.requested[k] = nil
    end

    local dist = spawn.Distance()
    if not dist then
        self.nextCheck[k] = now + 60000
        return nil
    end

    -- Out of range
    local spellRange = self:getSpellRange(spell)
    if spellRange > 0 and dist > spellRange then
        self.nextCheck[k] = now + 5000
        return nil
    end

    self.requested[k] = now
    --Prevent Immediate repoll
    self.nextCheck[k] = now + 2000

    return self.bus:request(
            target,
            "buff_status_request",
            { spell = spell,
            },
            2000
    )
end

function BuffService:getSpellRange(spellName)
    local ae = tonumber(mq.TLO.Spell(spellName).AERange()) or 0
    if ae > 0 then return ae end
    return tonumber(mq.TLO.Spell(spellName).Range()) or 0
end

function BuffService:update(ctx)
    if ctx and ctx.dead then return end
    if ctx and ctx.invis then return end

    local inCombat = (ctx and ctx.numberOfAggresiveInXTar and ctx.numberOfAggresiveInXTar > 0)
                  or self.combatService:isInCombat()
                  or (State.assist.targetId ~= nil)

    -- Combat buffs only in combat
    if inCombat then
        self:processCategory("combatBuffs", true)
    end

    -- Self/bot buffs: always process (alwaysCheck entries fire in combat too)
    self:processCategory("selfBuffs", inCombat)
    self:processCategory("botBuffs", inCombat)

end

function BuffService:processCategory(category, inCombat)


    local spells = self.policy[category]
    if not spells then
        return
    end
    if #spells == 0 then
        return
    end

    for _, buff in ipairs(spells) do
        -- Gate long buffs during combat unless alwaysCheck is set
        if (category == "botBuffs" or category == "selfBuffs") and inCombat and not buff.alwaysCheck then
            if not self.explicitRequests[(buff.targetName or '') .. ":" .. (buff.spell or buff.name or '')] then
                goto continue
            end
        end

        buff.category = category

        local p = self:pollIfDue(buff.targetName, buff.buffName or buff.name)
        if p then
            self:handlePollPromise(buff.targetName, buff, p)
        end

        :: continue ::
    end
end

function BuffService:getBuffInformationForKey(key)
    local values = self.config:get(key)
    local jobList = {}
    if values then
        for _, v in ipairs(values) do
            local spellName = v.spell
            local gem = v.gem or 8
            local jobType = v.type or 'buff'
            local buffName = v.buffName or spellName
            if jobType == 'item' and not v.buffName then
                local clickySpell = mq.TLO.FindItem('=' .. spellName).Clicky.Spell.Name()
                if clickySpell then buffName = clickySpell end
            end
            if (v.charactersToBuff) then
                for _, character in ipairs(v.charactersToBuff) do
                    --TODO need to fix IniLine and don't need generation for buffs and add conditions instead of iniLine
                    local targetId = mq.TLO.Spawn('pc = ' .. character).ID()
                    local job = Job:new(targetId, character, spellName, jobType, 0, gem)
                    job.alwaysCheck = v.alwaysCheck or false
                    job.buffName = buffName
                    table.insert(jobList, job)
                end
            else
                local characterId = mq.TLO.Me.ID()
                local job = Job:new(characterId, mq.TLO.Me.Name(), spellName, jobType, 0, gem)
                job.alwaysCheck = v.alwaysCheck or false
                job.buffName = buffName
                table.insert(jobList, job)
            end
        end
    end

    return jobList
end

function BuffService:handlePollPromise(target, buffEntry, promise)

    self.scheduler:spawn(function()

        local reply, err = promise:await()

        local k = key(target, buffEntry.name)
        local now = mq.gettime()

        self.requested[k] = nil


        -- If promise failed (timeout)
        if not reply then
            -- Retry soon but not instantly
            self.nextCheck[k] = now + 5000
            return
        end

        local inCombat = self.combatService:isInCombat()
        ------------------------------------------------
        -- 1️⃣ Buff does NOT exist → cast it
        ------------------------------------------------
        if not reply.data.hasBuff then

            -- If long group buff and in combat and not explicit → skip
            if buffEntry.category == 'botBuffs'
                    and inCombat
                    and not buffEntry.alwaysCheck
                    and not self.explicitRequests[k]
            then
                self.nextCheck[k] = now + 5000
                return
            end


            -- Suppress immediate re-poll (per target:spell)
            self.cooldowns[k] = now + 5000

            -- Spell-level cooldown: brief window to let buff_received propagate
            -- before other targets are polled for the same spell
            local spellKey = 'spell:' .. (buffEntry.buffName or buffEntry.name)
            self.cooldowns[spellKey] = now + 3000

            if self.castService:isQueued(buffEntry) then
                --Currently queued
                return
            end

            -- Refresh targetId — it changes when a character zones
            local freshSpawn = mq.TLO.Spawn('pc =' .. target)
            if not freshSpawn() then
                self.nextCheck[k] = now + 10000
                return
            end
            buffEntry.targetId = freshSpawn.ID()
            buffEntry.key = buffEntry.name .. ':' .. tostring(buffEntry.targetId)

            -- Enqueue cast
            self.castService:enqueue(buffEntry)

            -- Retry check later
            self.nextCheck[k] = now + 10000
        end

        ------------------------------------------------
        -- 2️⃣ Buff exists → check duration
        ------------------------------------------------
        if (reply.data.hasBuff) then
            local refreshWindow = (mq.TLO.Spell(buffEntry.name).Duration.TotalSeconds() or 0) * .1
            local duration = reply.data.duration or 0

            --within 10% of the original cast time
            if duration <= refreshWindow then

                -- Same combat gating logic
                if inCombat
                        and not self.explicitRequests[k]
                then
                    self.nextCheck[k] = now + 5000
                    return
                end

                self.cooldowns[k] = now + 3000

                local spellKey = 'spell:' .. (buffEntry.buffName or buffEntry.name)
                self.cooldowns[spellKey] = now + 3000

                if self.castService:isQueued(buffEntry) then
                    --Currently queued
                    return
                end

                local freshSpawn2 = mq.TLO.Spawn('pc =' .. target)
                if not freshSpawn2() then
                    self.nextCheck[k] = now + 10000
                    return
                end
                buffEntry.targetId = freshSpawn2.ID()
                buffEntry.key = buffEntry.name .. ':' .. tostring(buffEntry.targetId)

                self.castService:enqueue(buffEntry)

                local spellDuration = mq.TLO.Spell(buffEntry.name).Duration.TotalSeconds() or 0
                self.nextCheck[k] = now + math.max(10000, spellDuration * 0.8 * 1000)
            else
                ------------------------------------------------
                -- 3️⃣ Buff healthy → schedule next expiration check
                ------------------------------------------------
                local ms = math.min(duration * 0.8 * 1000, MAX_NEXT_CHECK_MS)
                self.nextCheck[k] = now + ms
            end
        end



        -- Clear explicit request if fulfilled
        if self.explicitRequests[k] then
            self.explicitRequests[k] = nil
        end

    end)
end

-- Called when any bot broadcasts that they received a buff.
-- Every bot that could cast this spell suppresses its nextCheck so nobody
-- double-casts the same buff on that target.
function BuffService:onBuffReceived(targetName, spellName, duration)
    local k = key(targetName, spellName)
    local now = mq.gettime()
    local ms = math.min(math.max(30000, duration * 0.8 * 1000), MAX_NEXT_CHECK_MS)
    self.nextCheck[k] = now + ms
end

function BuffService:reset()
    self.cooldowns  = {}
    self.nextCheck  = {}
    self.requested  = {}
end

function BuffService:resetForTarget(targetName)
    local prefix = targetName:lower() .. ':'
    for k in pairs(self.cooldowns) do
        if k:lower():sub(1, #prefix) == prefix then self.cooldowns[k] = nil end
    end
    for k in pairs(self.nextCheck) do
        if k:lower():sub(1, #prefix) == prefix then self.nextCheck[k] = nil end
    end
    for k in pairs(self.requested) do
        if k:lower():sub(1, #prefix) == prefix then self.requested[k] = nil end
    end
    -- Add explicit requests so combat doesn't block rebuffing after death/rez
    for _, category in ipairs({'selfBuffs', 'botBuffs', 'combatBuffs'}) do
        local spells = self.policy[category] or {}
        for _, buff in ipairs(spells) do
            if (buff.targetName or ''):lower() == targetName:lower() then
                local spell = buff.spell or buff.name or ''
                self.explicitRequests[buff.targetName .. ':' .. spell] = true
            end
        end
    end
end

function BuffService:setTakeHoldCooldownOnJob(job)
    local k = key(job.targetName, job.name)
    local now = mq.gettime()
    local spellDuration = (mq.TLO.Spell(job.name).Duration.TotalSeconds() or 0) * 1000
    -- Schedule next check at 80% of spell duration, floor 30s, cap 10min
    local cooldown = spellDuration > 0
        and math.min(spellDuration * 0.8, 10 * 60 * 1000)
        or  (10 * 60 * 1000)
    self.nextCheck[k] = now + math.max(30000, cooldown)
end

return BuffService