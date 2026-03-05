local Logging = require 'srl/core/Write'
local InviteService = require 'srl.service.InviteService'

local setup_export = {}

function setup_export.setup()
    Logging.Debug("Setup.setup Start")
    InviteService:init()

    Logging.Debug("Setup.setup End")
end

return setup_export