local mq = require 'mq'
local TableUtil = require 'srl/util/TableUtil'
local StringUtil = require 'srl/util/StringUtil'
local CastUtil = require 'srl/util/CastUtil'

local BuffService = {}
BuffService.__index = BuffService

function BuffService:new(bus)
    local self = setmetatable({}, BuffService)

    self.bus = bus
    self.requested = {}     -- target:spell currently polling
    self.queue = {}         -- cast queue
    self.active = nil       -- current cast
    self.cooldowns = {}     -- suppression timer
    self.nextCheck = {}   -- key → timestamp when next poll allowed

    return self
end

local function key(target, spell)
    return target .. ":" .. spell
end

function BuffService:poll(target, spell, iniSpellLine)

    local k = key(target, spell)
    local now = mq.gettime()

    -- Don't poll if not time yet
    if self.nextCheck[k] and now < self.nextCheck[k] then
        return
    end

    -- Prevent duplicate in-flight requests
    if self.requested[k] then return end
    self.requested[k] = true


    scheduler:spawn(function()
        local reply = self.bus
                          :request(target, "buff_status_request", { spell = spell })
                          :await()

        self.requested[k] = nil

        if not reply then return end

        return reply


    end)
end

function BuffService:enqueue(target, spell, iniSpellLine)

    local k = key(target, spell)

    -- Prevent duplicate queue entries
    for _,job in ipairs(self.queue) do
        if job.key == k then return end
    end

    table.insert(self.queue, {
        key = k,
        target = target,
        spell = spell,
        iniData = iniSpellLine
    })
end

function BuffService:update()
    if self.active then return end
    if #self.queue == 0 then return end

    local job = table.remove(self.queue, 1)
    self.active = job

    scheduler:spawn(function()

        self:castBuff(job.target, job.spell, job.iniData)

        -- Suppress re-poll for 10 seconds
        self.cooldowns[job.key] = mq.gettime() + 10000

        self.active = nil

    end)
end

function BuffService:castBuff(target, spellName, spellData)
    local spawnSearch = 'pc ' .. target
    local characterToBuffId = mq.TLO.Spawn(spawnSearch).ID
    local gemNumber = StringUtil.getValueByName(spellData, "/Gem")

    CastUtil.srl_cast(spellName, gemNumber, characterToBuffId)

    self.lastCast = mq.gettime()
end

return BuffService