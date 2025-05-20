cast_util_export = {}

local function checkIfCastingIsReady(spell)
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

function cast_util_export.srl_cast(spellName, gem, spellTarget)
    Logging.Debug("Cast Util Export SRL Cast Start")
    local isSpellReady = checkIfCastingIsReady(spellName)
    Logging.Debug(("Is spell ready %s --- %s "):format(spellName, isSpellReady))
    if(isSpellReady == true) then
        Target.get_target_by_id(spellTarget)
        --param gems
        mq.cmdf("/bc Casting " .. spellName)
        mq.cmdf("/casting \"%s\"|%s", spellName, gem)
        return
    end
    Logging.Debug("Cast Util Export SRL Cast End")
end

return cast_util_export