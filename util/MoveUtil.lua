local mq    = require 'mq'
local Target = require 'service.TargetService'

local MoveUtil = {}

-- Navigate to a spawn by ID.
-- Uses /nav if a path exists in the loaded mesh; falls back to /stick loose otherwise.
-- dist: stick distance used for both the fallback and as the nav stop distance (default 5)
function MoveUtil.navOrStick(targetId, dist)
    dist = dist or 5
    if mq.TLO.Navigation.PathExists('id ' .. tostring(targetId))() then
        mq.cmdf('/nav id %s dist=%d', targetId, dist)
    else
        Target:getTargetById(targetId)
        local uw = mq.TLO.Me.FeetWet() and ' uw' or ''
        mq.cmdf('/stick %d loose%s', dist, uw)
    end
end

return MoveUtil
