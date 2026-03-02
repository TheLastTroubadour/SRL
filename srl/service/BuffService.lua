local mq = require 'mq'
local TableUtil = require 'srl/util/TableUtil'
local StringUtil = require 'srl/util/StringUtil'
local CastUtil = require 'srl/util/CastUtil'
local Job = require 'srl/model/Job'
local IniHelper = require 'srl/ini/IniHelper'
local BuffService = {}
BuffService.__index = BuffService

local SPELL = "spell"
local Ability = "ability"
local AA = "aa"

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
    self.queue = {}         -- cast queue
    self.cooldowns = {}     -- suppression timer
    self.nextCheck = {}   -- key → timestamp when next poll allowed

    return self
end

local function key(target, spell)
    return target .. ":" .. spell
end

function BuffService:pollIfDue(target, spell, iniSpellLine)


    local k = key(target, spell)
    local now = mq.gettime()

    --supression active
    if self.cooldowns[k] and now > self.cooldowns[k] then
        return nil
    end

    -- Not time yet
    if self.nextCheck[k] and now > self.nextCheck[k] then
        return nil
    end

    -- Already polling
    if self.requested[k] == true then
        return nil
    end
    self.requested[k] = true

    return self.bus:request(
            target,
            "buff_status_request",
            { spell = spell,
              iniSpellLine = iniSpellLine },
            2000
    )
end

function BuffService:update()
    local inCombat = self.combatService:isInCombat()

    -- Always check self buffs (but gated)

    -- Combat buffs only in combat
    if inCombat then
        self:processCategory("combatBuffs", true)
    end

    -- Group buffs only out of combat unless explicit
    if not inCombat then
        self:processCategory("selfBuffs", inCombat)
        self:processCategory("botBuffs", inCombat)
    end
end

function BuffService:processCategory(category, inCombat)


    local spells = self.policy[category]
    if not spells then return end
    if #spells == 0 then return end

    for _,buff in ipairs(spells) do
        -- Gate long buffs during combat
        if category == "botBuffs" and inCombat then
            if not self.explicitRequests[buff.target .. ":" .. buff.spell] then
                goto continue
            end
        end

        buff.category = category

        local p = self:pollIfDue(buff.target, buff.spell, buff.iniLine)
        if p then
            self:handlePollPromise(buff.target, buff, p)
        end

        ::continue::
    end
end

function BuffService:getBuffInformationForKey(key)
    local values = self.config:Get(key)
    local jobList = {}
    for _, v in ipairs(values) do
        local spellName = v.spell
        local gem = v.gem or 8
        if(v.charactersToBuff) then
            for _, character in ipairs(v.charactersToBuff) do
                --TODO need to fix IniLine and don't need generation for buffs and add conditions instead of iniLine
                local job = Job:new(character, spellName, 'spell', 0, {}, gem)
                table.insert(jobList, job)
            end
        else
            local character = mq.TLO.Me.Name()
            local job = Job:new(character, spellName, 'spell', 0, {}, gem)
            table.insert(jobList, job)
        end
    end

    return jobList
end

function BuffService:handlePollPromise(target, buffEntry, promise)

    self.scheduler:spawn(function()

        local reply, err = promise:await()

        local k = key(target, buffEntry.spell)
        local now = mq.gettime()

        if reply then
            self.requested[k] = nil
        end

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
                    and not self.explicitRequests[k]
            then
                self.nextCheck[k] = now + 5000
                return
            end

            -- Suppress immediate re-poll
            self.cooldowns[k] = now + 30000

            print("Queueing")
            -- Enqueue cast
            self.castService:enqueue(buffEntry)

            -- Retry check later
            self.nextCheck[k] = now + 5000
            return
        end

        ------------------------------------------------
        -- 2️⃣ Buff exists → check duration
        ------------------------------------------------
        local refreshWindow = mq.TLO.Spell(buffEntry.spell).Duration.TotalSeconds() * .1
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

            self.castService:enqueue(buffEntry)

            self.nextCheck[k] = now + 5000
            return
        end

        ------------------------------------------------
        -- 3️⃣ Buff healthy → schedule next expiration check
        ------------------------------------------------
        self.nextCheck[k] = now + (duration * .8 * 1000)

        -- Clear explicit request if fulfilled
        if self.explicitRequests[k] then
            self.explicitRequests[k] = nil
        end

    end)
end

return BuffService