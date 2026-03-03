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
local Config = require 'srl.config.Config'
local Base = require 'srl.config.defaults.Base'
local Class = require 'srl.config.defaults.Class'
local Role = require 'srl.config.defaults.Role'
local RoleService = require 'srl.service.RoleService'
local PackageMan = require('mq/PackageMan')
local TableUtil = require 'srl.util.TableUtil'
local FollowController = require 'srl.controller.FollowController'
local FollowService = require 'srl.service.FollowService'
PackageMan.Require('lyaml')
PackageMan.Require('luafilesystem', 'lfs')

local function merge(a, b)
    for k, v in pairs(b) do
        if type(v) == "table" then
            a[k] = a[k] or {}
            merge(a[k], v)
        else
            a[k] = v
        end
    end
end

local function buildDefaults()
    local class = mq.TLO.Me.Class.ShortName()
    local defaults = {}

    -- 1️⃣ Base
    merge(defaults, Base)

    -- 2️⃣ Class
    if Class[class] then
        merge(defaults, Class[class])
    end

    -- 3️⃣ Multiple Roles
    local roles = RoleService:getRoles()

    for _, role in ipairs(roles) do
        if Role[role] then
            merge(defaults, Roles[role])
        end
    end

    return defaults
end

-- MAIN MACRO LOOP
local function mainLoop()
    Logging.Debug("Main Loop Start")
    init.setup();

    local config = Config:new(Base)
    config:Load()

    local layeredDefaults = buildDefaults(config.data)
    config.defaults = layeredDefaults
    config:Load()

    local scheduler = Scheduler:new()
    local castService = CastService:new(scheduler)
    local busService = Bus:new("SRL")
    castService:setBus(busService)
    BufferController:new(busService)
    local combatService = CombatService:new(castService, config)
    BindService:new(combatService)
    castService.combatService = combatService
    local combatController = CombatController:new(combatService)
    local buffService = BuffService:new(busService, scheduler, combatService, castService, config)
    CommandBus:init()
    CommandBus:register('Assist', function(payload)
        combatController:assist(payload)
    end)

    local followService = FollowService:new()
    local followController = FollowController:new(followService)

    CommandBus:register('Follow', function(payload)
        followController:follow(payload)
    end)

    CommandBus:register('Stop', function(payload)
        followController:stop()
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
        mq.delay(100)

        Logging.Debug("Main While loop End")
    end
end



mainLoop();
