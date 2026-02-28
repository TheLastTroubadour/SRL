local mq = require('mq')
local TableUtil = require 'srl/util/TableUtil'
local StringUtil = require 'srl/util/StringUtil'
local BufferController = {}
BufferController.__index = BufferController

function BufferController:new(bus)
    local self = setmetatable({}, BufferController)
    self.bus = bus
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
    payload.iniSpellLine = data.data.iniSpellLine

    self.bus:reply(sender, payload)
end


return BufferController