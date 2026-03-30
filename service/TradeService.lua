local mq = require 'mq'

local TradeService = {}
TradeService.__index = TradeService

function TradeService:new(config, trustService)
    local self = setmetatable({}, TradeService)
    self.config       = config
    self.trustService = trustService
    return self
end

function TradeService:update()
    -- Do NOT automate the foreground client
    if mq.TLO.EverQuest.Foreground() then return end

    -- Auto-accept trades from trusted players
    if mq.TLO.Window("TradeWnd").Open() then
        local tradeBtn  = mq.TLO.Window("TradeWnd").Child("TRDW_Trade_Button")
        local otherName = mq.TLO.Window("TradeWnd").Child("TRDW_OtherName").Text()
        if self.trustService:isTrusted(otherName) and tradeBtn.Enabled() then
            mq.cmd("/notify TradeWnd TRDW_Trade_Button leftmouseup")
        end
    end

    -- Auto-accept shared task invitations from trusted players
    if mq.TLO.Window("ConfirmationDialogBox").Open() then
        local text = mq.TLO.Window("ConfirmationDialogBox").Child("CD_TextOutput").Text() or ''
        local sharer = text:match("^(.+) has asked you to join the shared task")
        if sharer and self.trustService:isTrusted(sharer) then
            mq.cmd("/notify ConfirmationDialogBox CD_Yes_Button leftmouseup")
        end
    end
end

return TradeService
