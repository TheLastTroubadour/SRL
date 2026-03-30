local mq = require('mq')
local TableUtil = require 'util.TableUtil'
local StringUtil = require 'util.StringUtil'
local BufferController = {}
BufferController.__index = BufferController

function BufferController:new(bus)
    local self = setmetatable({}, BufferController)
    self.bus  = bus
    self.pendingCasts = {}
    self:register()
    return self
end

function BufferController:register()
    self.bus.actor:on('buff_status_request', function(sender, data)
        self:handleRequest(sender, data)
    end)

    -- When any SRL bot confirms a buff landed, check if we also received it
    -- (handles group spells) and broadcast back to all bots.
    self.bus.actor:on('buff_cast', function(sender, data)
        local d = data and data.data
        if not d or not d.spellName then return end
        table.insert(self.pendingCasts, {
            spellName  = d.spellName,
            casterName = d.casterName,
            checkAt    = mq.gettime() + 600,  -- short settle delay
        })
    end)
end

-- Called each tick from init.lua main loop.
function BufferController:update()
    local now = mq.gettime()
    for i = #self.pendingCasts, 1, -1 do
        local p = self.pendingCasts[i]
        if now < p.checkAt then goto continue end
        table.remove(self.pendingCasts, i)

        local spellName = p.spellName
        local buff = mq.TLO.Me.Buff('=' .. spellName)
        local hasBuff = buff() ~= nil
        local duration = hasBuff and (buff.Duration.TotalSeconds() or 0) or 0

        if not hasBuff then
            local song = mq.TLO.Me.Song('=' .. spellName)
            hasBuff = song() ~= nil
            duration = hasBuff and (song.Duration.TotalSeconds() or 0) or 0
        end

        if hasBuff and duration > 0 then
            self.bus.actor:broadcast('buff_received', {
                targetName = mq.TLO.Me.Name(),
                spellName  = spellName,
                duration   = duration,
                casterName = p.casterName,
                sender     = mq.TLO.Me.Name(),
            })
        end

        ::continue::
    end
end

function BufferController:handleRequest(sender, data)
    local spell = data.data.spell
    local characterId = mq.TLO.Me.ID()

    local buff = mq.TLO.Me.Buff('=' .. spell)
    local hasBuff = buff() ~= nil
    local duration = hasBuff and (buff.Duration.TotalSeconds() or 0) or 0

    -- Fall back to song window (bard songs, short-duration buffs)
    if not hasBuff then
        local song = mq.TLO.Me.Song('=' .. spell)
        hasBuff = song() ~= nil
        duration = hasBuff and (song.Duration.TotalSeconds() or 0) or 0
    end

    -- Treat blocked buffs as present so the caster stops trying
    if not hasBuff and mq.TLO.Me.BlockedBuff('=' .. spell)() then
        hasBuff = true
        duration = 99999
    end

    local payload = {}
    payload.id = data.data.id
    payload.name = mq.TLO.Me.Name()
    payload.hasBuff = hasBuff
    payload.duration = duration
    payload.characterId = characterId
    payload.spellName = spell
    payload.generation = data.data.generation

    self.bus:reply(data.sender, payload)
end


return BufferController