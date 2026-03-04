local mq = require("mq")
local yaml = require("lyaml")
local LFS = require 'lfs'
local TableUtil = require 'srl.util.TableUtil'
local Class = require 'srl.config.defaults.Class'
local Role = require 'srl.config.defaults.Role'
local Defaults = require 'srl.config.defaults.Base'
local RoleService = require 'srl.service.RoleService'

local ConfigService = {}
ConfigService.__index = ConfigService

-------------------------------------------------
-- Constructor
-------------------------------------------------

function ConfigService:new(eventBus)

    local self = setmetatable({}, ConfigService)

    self.eventBus = eventBus

    self.roleOrder = {}

    self.resolved = {}

    self.watchFiles = {}

    self.schema = nil

    self.characterName = mq.TLO.Me.Name()
    self.comments = require 'srl.config.defaults.Comment'
    self.path = mq.TLO.Lua.Dir() .. "\\srl\\config\\bot_yaml\\"
    self.fileName = self.characterName .. "_" .. mq.TLO.EverQuest.Server() .. ".yaml"

    return self
end

local function ensureDirectory(path)
    local attr = LFS.attributes(path)
    if not attr then
        LFS.mkdir(path)
    end
end
-------------------------------------------------
-- Deep Merge
-------------------------------------------------

local function deepMerge(dest, src)

    for k,v in pairs(src) do

        if type(v) == "table" then

            if type(dest[k]) ~= "table" then
                dest[k] = {}
            end

            deepMerge(dest[k], v)

        else
            dest[k] = v
        end

    end

end

-------------------------------------------------
-- YAML Ordered Writer
-------------------------------------------------

local function writeYamlTable(file, tbl, comments, indent)

    indent = indent or 0

    local spacing = string.rep(" ", indent)

    for key,value in pairs(tbl) do

        local comment = comments and comments[key]

        --------------------------------
        -- Print comment
        --------------------------------

        if type(comment) == "string" then
            file:write(spacing.."# "..comment.."\n")
        end

        --------------------------------
        -- Nested table
        --------------------------------

        if type(value) == "table" then

            file:write(spacing..key..":\n")

            local childComments = type(comment) == "table" and comment or nil

            writeYamlTable(
                    file,
                    value,
                    childComments,
                    indent + 2
            )

        else

            file:write(spacing..key..": "..tostring(value).."\n")

        end

    end

end

-------------------------------------------------
-- File Timestamp
-------------------------------------------------

local function fileModified(path)

    local p = io.popen('stat -c %Y "'..path..'"')

    if not p then return 0 end

    local t = tonumber(p:read("*a")) or 0

    p:close()

    return t
end

-------------------------------------------------
-- Watch File
-------------------------------------------------

function ConfigService:watch(path)

    self.watchFiles[path] = fileModified(path)

end

-------------------------------------------------
-- Load Character YAML
-------------------------------------------------

function ConfigService:loadCharacterYaml()

    local path = self.path .. self.fileName

    local file = io.open(path,"r")

    if not file then
        print("Load Character Yaml failed")
        return
    end


    self.resolved = yaml.load(file:read("*a")) or {}

    file:close()

    self:watch(path)

end

-------------------------------------------------
-- Generate YAML First Run
-------------------------------------------------

function ConfigService:generateCharacterYaml()


    local path = self.path .. self.fileName

    local readOnly = io.open(path, 'r')

    if readOnly then
        readOnly:close()
        return
    else
        ensureDirectory(self.path)
    end

        print("Generating character config")

        local merged = {}

        --------------------------------
        -- defaults
        --------------------------------

        deepMerge(merged, Defaults)

        --------------------------------
        -- roles
        --------------------------------

        local roles = RoleService:getRoles()

        for _, v in pairs(roles) do
            if Role[v] then
                deepMerge(merged, Role[v])
            end

        end

        --class
        local classShortName = mq.TLO.Me.Class.ShortName()
        if Class[classShortName] then
            deepMerge(merged, Class[classShortName])
        end

        --------------------------------
        -- write yaml
        --------------------------------
        local f = io.open(path,"w")

        f:write("# Character Configuration\n")
        --------------------------------
        -- write config
        --------------------------------

        writeYamlTable(
                f,
                merged,
                self.comments,
                0
        )

        f:close()

        self.resolved = merged

    end

-------------------------------------------------
-- Runtime Override
-------------------------------------------------

function ConfigService:setRuntime(path,value)

    local node = self.layers.runtime

    local parts = {}

    for p in self.path:gmatch("[^%.]+") do
        table.insert(parts,p)
    end

    for i=1,#parts-1 do

        local part = parts[i]

        node[part] = node[part] or {}

        node = node[part]

    end

    node[parts[#parts]] = value

end

-------------------------------------------------
-- Build Final Config
-------------------------------------------------

function ConfigService:build()

    if self.schema then
        self:validate()
    end

end

-------------------------------------------------
-- Dot Path Access
-------------------------------------------------

function ConfigService:get(path)

    local node = self.resolved

    for key in string.gmatch(path, "[^.]+") do
        node = node[key]
        if not node then
            return nil
        end
    end
    return node
end

-------------------------------------------------
-- Schema Validation
-------------------------------------------------

function ConfigService:setSchema(schema)

    self.schema = schema

end

function ConfigService:validate()

    local errors = {}

    for path,rules in pairs(self.schema) do

        local value = self:get(path)

        if rules.required and value == nil then
            table.insert(errors,"Missing config: "..path)
        end

        if value ~= nil then

            if rules.type == "number" and type(value) ~= "number" then
                table.insert(errors,path.." must be number")
            end

            if rules.type == "string" and type(value) ~= "string" then
                table.insert(errors,path.." must be string")
            end

        end

    end

    if #errors > 0 then

        print("CONFIG VALIDATION FAILED")

        for _,e in ipairs(errors) do
            print(e)
        end

        error("Invalid Config")

    end

end

-------------------------------------------------
-- YAML Patch
-------------------------------------------------

function ConfigService:patchYamlValue(key,value)

    local path = self.path .. self.characterName..".yaml"

    local lines = {}

    for line in io.lines(path) do
        table.insert(lines,line)
    end

    local replaced = false

    for i,line in ipairs(lines) do

        if line:match("^"..key..":") then

            lines[i] = key..": "..tostring(value)

            replaced = true

        end

    end

    if not replaced then
        table.insert(lines,key..": "..tostring(value))
    end

    local file = io.open(path,"w")

    for _,l in ipairs(lines) do
        file:write(l.."\n")
    end

    file:close()

end

-------------------------------------------------
-- Reload Check
-------------------------------------------------

function ConfigService:update()

    local changed = false

    for path,last in pairs(self.watchFiles) do

        local modified = fileModified(path)

        if modified > last then

            print("Config changed:",path)

            self.watchFiles[path] = modified

            changed = true

        end

    end

    if changed then
        self:reload()
    end

end

-------------------------------------------------
-- Reload
-------------------------------------------------

function ConfigService:reload()

    print("Reloading config")

    self:loadCharacterYaml(self.characterName)

    self:build()

    if self.eventBus then
        self.eventBus:emit("config.changed",self.resolved)
    end

end

return ConfigService