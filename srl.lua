--Macro Created to be full bot scenario for all classes in EQ
local mq = require "mq";
local init = require "srl/Setup"
local Logging = require 'srl/core/Write'
local Bus = require 'srl/core/Bus'
local BufferController = require 'srl/controller/BufferController'
local Scheduler = require 'srl/core/Scheduler'
local BuffService = require 'srl/service/BuffService'
local CombatService = require 'srl/service/CombatService'
local CastService = require 'srl/service/CastService'
local BindService = require 'srl/service/BindService'
local CombatController = require 'srl/controller/CombatController'
local CommandBus = require 'srl/core/CommandBus'
-- MAIN MACRO LOOP
local function mainLoop()
    Logging.Debug("Main Loop Start")
    init.setup();

    local scheduler = Scheduler:new()
    local castService = CastService:new(scheduler)
    local busService = Bus:new(mq.TLO.Me.Name())
    castService:setBus(busService)
    BufferController:new(busService)
    local combatService = CombatService:new(castService)
    BindService:new(combatService)
    castService.combatService = combatService
    local combatController = CombatController:new(combatService)
    local buffService = BuffService:new(busService, scheduler, combatService, castService)
    CommandBus:init()
    CommandBus:register('Assist', function(payload)
        combatController:assist(payload)
    end)

    while true do
        Logging.Debug("Main While loop Start")
        --order matters
        --Process network replies and resolve promises
        busService:update()
        --resume any coroutines waiting on await
        scheduler:run()

        buffService:update()
        combatService:update()
        mq.delay(10)

        Logging.Debug("Main While loop End")
    end
end

mainLoop();