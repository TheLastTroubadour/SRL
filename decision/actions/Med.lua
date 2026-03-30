local mq    = require 'mq'
local State = require 'core.State'

local Med = {}
Med.__index = Med
Med.name = 'Med'

function Med:new()
    return setmetatable({}, Med)
end

function Med:score(ctx)
    if not State.caster.medMode then return 0 end
    if State.follow.active then return 0 end
    if ctx.inCombat then return 0 end
    if mq.TLO.Me.Sitting() then return 0 end
    return 1
end

function Med:execute(ctx)
    mq.cmd('/sit')
end

return Med
