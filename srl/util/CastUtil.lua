
local mq = require 'mq'
local Logging = require 'srl/core/write'
local target = require 'srl/service/TargetService'

cast_util_export = {}

function cast_util_export:checkIfCastingIsReady(spell)
    Logging.Debug("Attack.checkIfCastingIsReady Start")

    Logging.Debug("checks Spell -- " ..tostring(spell==nil) .. "--- Casting " ..tostring(mq.TLO.Me.Casting() == true));
    Logging.Debug("Ready ---" .. tostring(mq.TLO.Cast.Ready(spell)() == false))
    if(spell == nil) then return false end

    if(mq.TLO.Me.Casting() == true) then
        return false
    end

    if(mq.TLO.Cast.Ready(spell)() == false) then
        return false
    end

    Logging.Debug("Returning True")
    Logging.Debug("Attack.checkIfCastingIsReady End")
    return true
end



return cast_util_export