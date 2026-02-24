local mq = require('mq')
local TableUtil = require 'srl/util/TableUtil'
local StringUtil = require 'srl/util/StringUtil'
local CastUtil = require 'srl/util/CastUtil'

local BufferController = {}
BufferController.__index = BufferController

function BufferController:new(bus)
    local self = setmetatable({}, BufferController)
    self.bus = bus
    self.pending = {}
    self.castThrottle = 600
    self.lastCast = 0
    self:register()
    return self
end

function BufferController:register()
    self.bus.actor:on("buff_reply", function(sender, data)
        local id = data.data.id
        if self.bus.pending[id] then
            self.bus.pending[id]:resolve(data)
            self.bus.pending[id] = nil
        end
    end)

    self.bus.actor:on('buff_status_request', function(sender, data)
        self:handleRequest(sender, data)
    end)
end

function BufferController:checkBuff(spell, targetName, spellData)

    Srl.scheduler.spawn(function()
        local reply =self.bus:request(targetName, 'buff_status_request', {
            spell = spell
        }):await()

        self:evaluate(reply, spellData)

    end)
end

function BufferController:evaluate(reply, spellData)
    self:castBuff(reply, spellData)
end

function BufferController:castBuff(reply, spellData)
    if mq.gettime() - self.lastCast < self.castThrottle then return end
    local duration = reply.data.duration
    local characterToBuffId = reply.data.characterId
    local spellToCastName = reply.data.spellName

    --In ticks
    if(tonumber(duration) < 30) then
        local gemNumber = StringUtil.getValueByName(spellData, "/Gem")
        CastUtil.srl_cast(spellToCastName, gemNumber, characterToBuffId)
    end

    if not mq.TLO.Me.SpellReady(spell)() then return end
    --Queue?
    CastUtil.srl_cast(spellName, gem, target)

    self.lastCast = mq.gettime()
end

function BufferController:handleRequest(sender, data)
    local spell = data.data.spell
    local buff = mq.TLO.Me.Buff(spell)
    local characterId = mq.TLO.Me.ID()
    local hasBuff = buff() ~= nil
    local duration = hasBuff and buff.Duration.TotalSeconds() or 0
    local payload = {}

    payload.id = data.data.id
    payload.name = mq.TLO.Me.Name()
    payload.hasBuff = hasBuff
    payload.duration = duration
    payload.characterId = characterId
    payload.spellName = spell

    self.bus:reply(sender, payload)
end


return BufferController