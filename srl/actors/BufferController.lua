local mq = require('mq')
local TableUtil = require 'srl/util/TableUtil'

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
    self.bus:on('buff_status_request', function(sender, data)
        print("Should be doing something")
        self:handleRequest(sender, data)
    end)
end

function BufferController:checkBuff(spell, targetName)
    local id = tostring(math.random(100000,999999))

    self.pending[id] = {
        spell = spell,
        target = name
    }

    local prom = self.bus:request(targetName, 'buff_status_request', {
        spell = spell
    }):next(function(reply)
        print('Reply2', reply)
        self:evaluate(reply)
    end)
    :catch(function()
        print("Buffed has timed out")
    end)
    print("Prom: ", prom)
    print(TableUtil.table_print(prom))
    return prom
end

function BufferController:evaluate(reply)
    print("Eval", reply)
    if not reply.hasBuff or reply.duration < 120 then
        self:castBuff(reply.name, reply.spell)
    end
end

function BufferController:castBuff(target, spell)
    if mq.gettime() - self.lastCast < self.castThrottle then return end
    if not mq.TLO.Me.SpellReady(spell)() then return end
    --Queue?
    CastUtil.srl_cast(spellName, gem, target)

    self.lastCast = mq.gettime()
end

function BufferController:handleRequest(sender, data)
    local spell = data.spell
    local buff = mq.TLO.Me.Buff[spell]

    local hasBuff = buff() ~= nil
    local duration = hasBuff and buff.Duration.TotalSeconds() or 0

    self.bus:reply(sender, data.id, {
        name = mq.TLO.Me.Name(),
        hasBuff = hasBuff,
        duration = duration,
        mana = mq.TLO.Me.PctMana()
    })
end


return BufferController