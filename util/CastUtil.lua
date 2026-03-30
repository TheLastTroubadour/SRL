
local mq = require 'mq'
local Logging = require 'core.Write'
local target = require 'service.TargetService'

cast_util_export = {}

function cast_util_export:checkIfCastingIsReady(spell)
    Logging.Debug("Attack.checkIfCastingIsReady Start")

    Logging.Debug("checks Spell -- " ..tostring(spell==nil) .. "--- Casting " ..tostring(mq.TLO.Me.Casting() == true));
    Logging.Debug("Ready ---" .. tostring(mq.TLO.Me.SpellReady(spell)() == false))
    if(spell == nil) then return false end

    if(mq.TLO.Me.Casting() == true) then
        return false
    end

    if(mq.TLO.Me.SpellReady(spell)() == false) then
        return false
    end

    Logging.Debug("Returning True")
    Logging.Debug("Attack.checkIfCastingIsReady End")
    return true
end



return cast_util_export