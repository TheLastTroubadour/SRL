--Macro Created to be full bot scenario for all classes in EQ
mq = require "mq";
Attack = require 'srl/Attack'
Init = require "srl/Setup";
Movement = require 'srl/Movement'
Target = require 'srl/Target'
Logging = require 'Write'
IniHelper = require "srl/ini/BaseIni"
Buff = require "srl/Buff"
TableUtil = require 'srl/util/TableUtil'
StringUtil = require 'srl/util/StringUtil'

-- MAIN MACRO LOOP
local function mainLoop()
    Logging.Debug("Main Loop Start")
    Init.setup();
    while true do
        Logging.Debug("Main While loop Start")
        mq.doevents();
        --each class is going to be different going to need to abstract eventually
        Movement.check_follow()
        Attack.check_assist()
        Buff.check_buff()
        mq.delay(2000)
        Logging.Debug("Main While loop ")
    end
end

mainLoop();