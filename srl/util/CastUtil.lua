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

    Logging.Debug("Attack.checkIfCastingIsReady End")
    return true
end

function cast_util_export.srl_cast(spellName, gem, spellTarget)
    local isSpellReady = checkIfCastingIsReady(spellName)
    if(isSpellReady == true) then
        print(("Spell name %s Gem %s Target %s"):format(spellName, gem, spellTarget))
        Target.get_target_by_id(spellTarget)
        --param gems
        mq.cmdf("/bc Casting " .. spellName)
        mq.cmdf("/casting \"%s\"|%s", spellName, gem)
        return
    end
end

return cast_util_export