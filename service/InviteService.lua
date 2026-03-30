local mq = require('mq')

local InviteService = {}

function InviteService:setup(trustService)
    self.trustService = trustService
end

function InviteService:handleRaidInvite(inviter)
    if self.raidInviteLock then return end
    if not mq.TLO.Raid.Invited() then return end
    if not self.trustService:isTrusted(inviter) then return end

    self.raidInviteLock = true
    if mq.TLO.Window('ConfirmationDialogBox').Open() then
        mq.cmd('/notify ConfirmationDialogBox CD_Yes_Button leftmouseup')
    end
    self.raidInviteLock = false
end

function InviteService:handleGroupInvite(inviter)
    if mq.TLO.Me.Grouped() then return end

    if not self.trustService:isTrusted(inviter) then
        return
    end

    mq.cmd('/invite')
end

return InviteService
