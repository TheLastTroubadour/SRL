local mq = require("mq")
local yaml = require("lyaml")
local LFS = require 'lfs'
local TableUtil = require 'util.TableUtil'
local Class = require 'config.defaults.Class'
local Role = require 'config.defaults.Role'
local Defaults = require 'config.defaults.Base'
local RoleService = require 'service.RoleService'

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
    self.comments = require 'config.defaults.Comment'
    self.path = mq.configDir .. "\\srl\\config\\"
    self.fileName = self.characterName .. "_" .. mq.TLO.EverQuest.Server() .. ".yaml"

    return self
end

local function ensureDirectory(path)
    -- LFS.mkdir only creates one level; build each segment so nested dirs work
    local current = ''
    for segment in path:gmatch('[^\\]+') do
        current = current == '' and segment or (current .. '\\' .. segment)
        if not LFS.attributes(current) then
            LFS.mkdir(current)
        end
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
    local attr = LFS.attributes(path)
    return attr and attr.modification or 0
end

-------------------------------------------------
-- Watch File
-------------------------------------------------

function ConfigService:watch(path)

    self.watchFiles[path] = fileModified(path)

end

-------------------------------------------------
-- Load Global Settings YAML
-------------------------------------------------

function ConfigService:loadGlobalSettings()

    local path = mq.configDir .. "\\srl\\config\\settings.yaml"

    local file = io.open(path, "r")

    if not file then
        return
    end

    local globalSettings = yaml.load(file:read("*a")) or {}
    file:close()

    deepMerge(self.resolved, globalSettings)

    self:watch(path)

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

    local content = file:read("*a")
    file:close()
    local ok, result = pcall(yaml.load, content)
    if not ok then
        error(string.format('[SRL] YAML error in %s:\n%s', path, tostring(result)))
    end
    local charSettings = result or {}

    -- Start from global settings, then overlay character settings on top
    self.resolved = {}
    self:loadGlobalSettings()
    deepMerge(self.resolved, charSettings)

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
-- Patch Character YAML
-- Updates a dot-path in both the in-memory resolved table and the raw
-- character YAML file, so the change survives a reload.
-------------------------------------------------

function ConfigService:patchCharacterYaml(dotPath, value)
    local keys = {}
    for key in dotPath:gmatch('[^.]+') do table.insert(keys, key) end

    -- Update in-memory resolved
    local node = self.resolved
    for i = 1, #keys - 1 do
        local k = keys[i]
        if type(node[k]) ~= 'table' then node[k] = {} end
        node = node[k]
    end
    local lastKey = keys[#keys]
    if type(value) == 'table' then
        if type(node[lastKey]) ~= 'table' then node[lastKey] = {} end
        deepMerge(node[lastKey], value)
    else
        node[lastKey] = value
    end

    -- Load raw character YAML (not merged with globals)
    local path = self.path .. self.fileName
    local file = io.open(path, 'r')
    local raw = {}
    if file then
        raw = yaml.load(file:read('*a')) or {}
        file:close()
    end

    -- Apply same patch to raw
    local rawNode = raw
    for i = 1, #keys - 1 do
        local k = keys[i]
        if type(rawNode[k]) ~= 'table' then rawNode[k] = {} end
        rawNode = rawNode[k]
    end
    if type(value) == 'table' then
        if type(rawNode[lastKey]) ~= 'table' then rawNode[lastKey] = {} end
        deepMerge(rawNode[lastKey], value)
    else
        rawNode[lastKey] = value
    end

    -- Write back using yaml.dump so lyaml properly handles all types
    -- (booleans, integer-keyed sequences, etc.) it parsed
    local f = io.open(path, 'w')
    if not f then
        print('[SRL] Config: failed to write ' .. path)
        return
    end
    f:write('# Character Configuration\n')
    f:write(yaml.dump({raw}))
    f:close()
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