local TradeService = {}
local mq = require 'mq'

function TradeService:update()
-- Do NOT automate the foreground client
    if mq.TLO.EverQuest.Foreground() then
        return
    end

    if not mq.TLO.Window("TradeWnd").Open() then
        return
    end

    local tradeBtn = mq.TLO.Window("TradeWnd").Child("TRDW_Trade_Button")
    local otherName = mq.TLO.Window("TradeWnd").Child("TRDW_OtherName").Text()

    if otherName and mq.TLO.DanNet(otherName) then
        if tradeBtn.Enabled() then
            mq.cmd("/notify TradeWnd TRDW_Trade_Button leftmouseup")
        end

    end
end

return TradeService