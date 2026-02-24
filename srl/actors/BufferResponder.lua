local mq = require('mq')

local BufferResponder = {}
BufferResponder.__index = BufferResponder

function BufferResponder:new(bus)
    local self = setmetatable({}, BufferResponder)
    self.bus = bus
    self:register()
    return self
end

function BufferResponder:register()
    self.bus:on('buff_status_request', function(sender, data)
        self:handleRequest(sender, data)
    end)
end

function BufferResponder:handleRequest(sender, data)
    local spell = data.spell
    local buff = mq.TLO.Me.Buff[spell]

    local hasBuff = buff() ~= nil
    local duration = hasBuff and buff.Duration.TotalSeconds() or 0
    local myId = mq.TLO.Me.ID()

    self.bus:reply(sender, data.id, {
        name = mq.TLO.Me.Name(),
        hasBuff = hasBuff,
        duration = duration,
        characterId = myId
    })
end

return BufferResponder