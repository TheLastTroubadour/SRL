local mq = require 'mq'
local Logging = require 'Write'

local basic_export = {}

local function acceptInvite(line, chatSender)
    Logging.Debug("Basic.acceptInvite Start");
    --If character is in DanNet accept invite
    mq.cmd("/invite");
    Logging.Debug("Basic.acceptInvite End");
end

function basic_export.registerEvents()
    mq.event('acceptInvite1', '#1# invites you to join a group.', acceptInvite);
end

return basic_export