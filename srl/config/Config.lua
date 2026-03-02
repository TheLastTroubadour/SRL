local mq = require('mq')
local yaml = require('lyaml')
local TableUtil = require 'srl.util.TableUtil'
local Config = {}
local LFS = require 'lfs'
local VERSION = 1

Config.__index = Config
local migrations = {}

---------------------------------------------------
-- Constructor
-------------------------------------------------
function Config:new(defaults)
    local obj = setmetatable({}, self)

    obj.defaults = defaults or {}
    obj.data = {}
    obj.file = nil
    obj.loaded = false

    return obj
end

-------------------------------------------------
-- File path (per character + server)
-------------------------------------------------
function Config:buildFile()
    local name = mq.TLO.Me.Name() or "Unknown"
    local server = mq.TLO.EverQuest.Server() or "Unknown"

    return string.format(
            "%s\\srl\\config\\bot_yaml\\%s_%s.yaml",
            mq.TLO.Lua.Dir(),
            name,
            server
    )
end

-------------------------------------------------
-- Deep merge (IMPORTANT)
-------------------------------------------------
local function mergeDefaults(defaults, data)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(data[k]) ~= "table" then
                data[k] = {}
            end
            mergeDefaults(v, data[k])
        elseif data[k] == nil then
            data[k] = v
        end
    end
end

-------------------------------------------------
-- Ensure directory exists
-------------------------------------------------
local function ensureDirectory(path)
    local attr = LFS.attributes(path)
    if not attr then
        LFS.mkdir(path)
        end
end

-------------------------------------------------
-- Load
-------------------------------------------------
function Config:Load()
    if self.loaded then
        return
    end

    self.file = self:buildFile()
    ensureDirectory(mq.TLO.Lua.Dir() .. "\\srl\\config\\bot_yaml")

    local f = io.open(self.file, "r")

    if f then
        local content = f:read("*a")
        f:close()
        self.data = yaml.load(content) or {}
    else
        self.data = {}
    end

    -- merge defaults safely
    mergeDefaults(self.defaults, self.data)
    self:runMigrations()

    self:Save() -- ensure new defaults persist
    self.loaded = true
end

function Config:runMigrations()
    local fileVersion = self.data._version or 1

    if(Config._version) then
        if fileVersion < Config._version then
            for v = fileVersion + 1, Config.VERSION do
                if migrations[v] then
                    migrations[v](self.data)
                end
            end

            self.data._version = Config.VERSION
        end
    end
end


-------------------------------------------------
-- Save
-------------------------------------------------
function Config:Save()
    local f = io.open(self.file, "w")
    if not f then
        return
    end
    f:write(yaml.dump({self.data}))
    f:close()
end

-------------------------------------------------
-- Get (dot path supported)
-------------------------------------------------
function Config:Get(path)
    local node = self.data
    for key in string.gmatch(path, "[^.]+") do
        node = node[key]
        if not node then
            return nil
        end
    end
    return node
end

-------------------------------------------------
-- Set
-------------------------------------------------
function Config:Set(path, value)
    local node = self.data
    local keys = {}

    for key in string.gmatch(path, "[^.]+") do
        table.insert(keys, key)
    end

    for i = 1, #keys - 1 do
        node = node[keys[i]]
        if not node then
            return
        end
    end

    node[keys[#keys]] = value
end

-------------------------------------------------
-- Migration: 1 → 2
-------------------------------------------------
migrations[2] = function(data)
    -- Example: rename combat.assistType → combat.assist.type

    if data.combat and data.combat.assistType then
        data.combat.assist = data.combat.assist or {}
        data.combat.assist.type = data.combat.assistType
        data.combat.assistType = nil
    end
end

-------------------------------------------------
-- Migration: 2 → 3
-------------------------------------------------
migrations[3] = function(data)
    -- Example: add assist.percent if missing
    data.combat = data.combat or {}
    data.combat.assist = data.combat.assist or {}

    if data.combat.assist.percent == nil then
        data.combat.assist.percent = 99
    end
end

return Config