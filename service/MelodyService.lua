local mq = require 'mq'

local MelodyService = {}
MelodyService.__index = MelodyService

local IDLE_THRESHOLD_MS = 5000  -- fallback: re-issue if not singing for this long (tune as needed)

function MelodyService:new(config)
    local self = setmetatable({}, MelodyService)
    self.config      = config
    self.active      = nil    -- name of currently playing melody
    self.lastSongTime = 0
    self.interrupted = false
    return self
end

-- Activates a named melody by issuing /queuemelody with its gem list.
-- YAML example:
--   Bard:
--     Melodies:
--       dps:
--         - 1
--         - 2
--         - 3
--         - 4
--       invis:
--         - 5
--         - 6
function MelodyService:play(name)
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' then return end

    local melodies = self.config:get('Bard.Melodies') or {}
    local gems = melodies[name]
    if not gems or #gems == 0 then
        print(string.format('[MelodyService] No melody named "%s"', tostring(name)))
        return
    end
    mq.cmd('/stopsong')
    self.active      = name
    self.interrupted = false
    self.lastSongTime = mq.gettime()
    if #gems == 1 then
        mq.cmdf('/cast %s', gems[1])
    else
        mq.cmdf('/queuemelody %s', table.concat(gems, ' '))
    end
end

function MelodyService:stop()
    self.active      = nil
    self.interrupted = false
    mq.cmd('/stopsong')
end

-- Call each main loop tick. Detects stun/fear interrupts and re-issues the
-- melody once safe, with a fallback for other interrupts (silence, etc.).
function MelodyService:tick(ctx)
    if not self.active then return end
    if ctx.myClass ~= 'BRD' then return end
    if ctx.dead or ctx.sitting then return end

    if ctx.stunned or ctx.feared ~= nil then
        self.interrupted = true
        return
    end

    if ctx.casting ~= nil then
        self.lastSongTime = mq.gettime()
        self.interrupted  = false
        return
    end

    local idleMs = mq.gettime() - self.lastSongTime
    if self.interrupted or idleMs > IDLE_THRESHOLD_MS then
        self:play(self.active)
    end
end

return MelodyService
