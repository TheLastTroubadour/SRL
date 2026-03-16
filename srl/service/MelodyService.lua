local mq = require 'mq'

local MelodyService = {}
MelodyService.__index = MelodyService

function MelodyService:new(config)
    local self = setmetatable({}, MelodyService)
    self.config = config
    self.active = nil  -- name of currently playing melody
    return self
end

-- Activates a named melody by issuing /twist with its gem list.
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
    self.active = name
    mq.cmdf('/twist %s', table.concat(gems, ' '))
end

function MelodyService:stop()
    self.active = nil
    mq.cmd('/twist off')
end

return MelodyService
