local mq = require('mq')

local InviteService = {}

function InviteService:handleRaidInvite(inviter)

    if mq.TLO.Me.Raided() then return end

    if not self:isDanNetPeer(inviter) then
        print("Raid invite ignored (not a DanNet peer)")
        return
    end

    --mq.cmd('/raidinvite accept')

end

function InviteService:handleRezOffer(resurrector)

    if not self:isDanNetPeer(resurrector) then
        print("Rez offer ignored (not a DanNet peer): " .. tostring(resurrector))
        return
    end

    mq.cmd('/accept')

end

function InviteService:handleGroupInvite(inviter)

    if mq.TLO.Me.Grouped() then return end

    if not self:isDanNetPeer(inviter) then
        return
    end

    mq.cmd('/invite')

end

function InviteService:isDanNetPeer(name)

    if mq.TLO.DanNet(name) then
        return true
    end

    return false
end

return InviteService