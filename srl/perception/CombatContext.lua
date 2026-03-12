local mq = require 'mq'
local RoleService = require 'srl.service.RoleService'
local State = require 'srl.core.State'
local Context = {}

function Context:build(state)

    local ctx = {}

    ctx.mana = mq.TLO.Me.PctMana()
    ctx.hp = mq.TLO.Me.PctHPs()
    ctx.moving = mq.TLO.Me.Moving()

    ctx.roles = RoleService:getRoles()

    ctx.targetId = State.combat.targetId

    if ctx.targetId then
        local spawn = mq.TLO.Spawn(ctx.targetId)

        if spawn() then
            ctx.targetDistance = spawn.Distance()
            ctx.targetHP = spawn.PctHPs()
        end
    end

    ctx.inCombat = State.combat.inCombat

    return ctx

end

return Context