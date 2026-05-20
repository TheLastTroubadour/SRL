local mq = require 'mq'

local LootService = {}
LootService.__index = LootService

function LootService:new()
    local self = setmetatable({}, LootService)
    self.lastCheck      = 0
    self.pendingConfirm = false
    self.confirmExpiry  = 0
    return self
end

function LootService:update()
    local now = mq.gettime()
    if now - self.lastCheck < 1000 then return end
    self.lastCheck = now

    -- Only auto-confirm if we just clicked a loot button (prevents accepting unrelated dialogs)
    if self.pendingConfirm and now <= self.confirmExpiry then
        local confirm = mq.TLO.Window('ConfirmationDialogBox')
        if confirm() and confirm.Open() then
            mq.cmd('/notify ConfirmationDialogBox CD_Yes_Button leftmouseup')
            self.pendingConfirm = false
            return
        end
    else
        self.pendingConfirm = false
    end

    local count = mq.TLO.AdvLoot.PCount() or 0
    if count > 0 then
        mq.cmd('/notify AdvancedLootWnd ADLW_LootBtnTemplate leftmouseup')
        self.pendingConfirm = true
        self.confirmExpiry  = now + 4000
    end
end

return LootService
