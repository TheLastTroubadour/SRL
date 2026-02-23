--Macro Created to be full bot scenario for all classes in EQ
local mq = require "mq";
local heal = require 'srl/Heal'
local attack = require 'srl/Attack'
local init = require "srl/Setup";
local movement = require 'srl/Movement'
local Logging = require 'Write'
local buff = require "srl/Buff"

-- MAIN MACRO LOOP
local function mainLoop()
    Logging.Debug("Main Loop Start")
    init.setup();
    while true do
        Logging.Debug("Main While loop Start")
        mq.doevents();
        --each class is going to be different going to need to abstract eventually
        heal.check_healing()
        movement.check_follow()
        attack.check_assist()
        buff.check_buff()
        BUS:update()
        Logging.Debug("Main While loop End")
        mq.delay(2000)
    end
end

mainLoop();