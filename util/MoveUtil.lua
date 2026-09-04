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

-- Navigate to raw coordinates (e.g. a fixed camp point, not tied to a spawn).
-- Returns false if no path exists so the caller can abort/warn instead of hanging.
function MoveUtil.navToLoc(x, y, z, dist)
    dist = dist or 5
    local locStr = string.format('locxyz %s %s %s', x, y, z)
    if not mq.TLO.Navigation.PathExists(locStr)() then
        return false
    end
    mq.cmdf('/nav %s dist=%d', locStr, dist)
    return true
end

-- 2D distance from the player's current position to a raw {x=, y=} point.
function MoveUtil.distanceToLoc(x, y)
    local dx = mq.TLO.Me.X() - x
    local dy = mq.TLO.Me.Y() - y
    return math.sqrt(dx * dx + dy * dy)
end

-- Real walkable path length to a raw {x=, y=, z=} point, not straight-line
-- distance -- accounts for walls/elevation/detours the same way distanceToLoc
-- can't (see findPullTarget's reasoning for picking path length over radial
-- distance). Returns nil if no path exists at all (unreachable/no mesh).
function MoveUtil.pathLengthToLoc(x, y, z)
    local locStr = string.format('locxyz %s %s %s', x, y, z)
    local len = mq.TLO.Navigation.PathLength(locStr)()
    if not len or len <= 0 then return nil end
    return len
end

-- Resolves a configured stick distance value, supporting the special
-- "maxmelee" string (live target's actual max melee range, floored, minus a
-- 1-yard buffer) alongside plain numeric distances.
function MoveUtil.resolveStickDist(dist, fallback)
    fallback = fallback or 10
    if tostring(dist):lower() == 'maxmelee' then
        return math.floor((mq.TLO.Target.MaxMeleeTo() or 15) - 1)
    end
    return tonumber(dist) or fallback
end

return MoveUtil
