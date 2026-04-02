local mq         = require 'mq'
local ImGui      = require 'ImGui'
local yaml       = require 'lyaml'
local Schema     = require 'config.EditorSchema'
local SpellCache = require 'util.SpellCache'

local ConfigEditorWindow = {}
ConfigEditorWindow.__index     = ConfigEditorWindow
ConfigEditorWindow.visible     = false
ConfigEditorWindow.config      = nil

-- ============================================================
-- Tab state
-- ============================================================

local charTab = {
    editTable       = nil,   -- deep copy of parsed char YAML
    rawBuf          = '',    -- raw text fallback
    rawMode         = false, -- toggle between structured / raw
    dirty           = false,
    loaded          = false,
    selectedSection = nil,   -- key of the section shown in the right pane
}

local settingsTab = {
    rawBuf = '',
    dirty  = false,
    loaded = false,
}

-- ============================================================
-- Utilities
-- ============================================================

local function deepCopy(orig)
    if type(orig) ~= 'table' then return orig end
    local copy = {}
    for k, v in pairs(orig) do copy[k] = deepCopy(v) end
    return copy
end

local function isArray(t)
    if type(t) ~= 'table' then return false end
    return #t > 0 or next(t) == nil
end

local function charFilePath()
    return ConfigEditorWindow.config.path .. ConfigEditorWindow.config.fileName
end

local function settingsFilePath()
    return mq.configDir .. '\\srl\\config\\settings.yaml'
end

local function readFile(path)
    local f = io.open(path, 'r')
    if not f then return '' end
    local s = f:read('*a')
    f:close()
    return s
end

local function writeFile(path, text)
    local f = io.open(path, 'w')
    if not f then return false end
    f:write(text)
    f:close()
    return true
end

-- Serialize back to YAML (loses inline comments; tradeoff for structured editing)
local function tableToYaml(tbl)
    local ok, result = pcall(function() return yaml.dump({tbl}) end)
    if not ok then return nil, result end
    return result
end

-- ============================================================
-- Field widgets
-- ============================================================
-- Autocomplete
-- ============================================================

-- Track which autocomplete field is showing suggestions
local acOpenId = nil

local function renderAutocomplete(item, field, uid, searchFn)
    local widgetId = field.key .. '_' .. uid
    local cur      = tostring(item[field.key] or '')
    local changed  = false

    ImGui.SetNextItemWidth(180)
    local new = ImGui.InputText('##inp_' .. widgetId, cur)
    local inputActive = ImGui.IsItemActive()

    if new ~= cur then
        item[field.key] = new
        cur = new
        changed = true
    end

    -- Track which field wants suggestions open
    if inputActive then
        acOpenId = widgetId
    end

    -- Show inline suggestion list when this field is active and has 2+ chars
    local showList = acOpenId == widgetId and #cur >= 2
    if showList then
        local matches = searchFn(cur)
        if #matches > 0 then
            local listH = math.min(#matches * 20 + 6, 162)
            if ImGui.BeginChild('##aclist_' .. widgetId, 186, listH, true) then
                local listHovered = ImGui.IsWindowHovered()
                for _, match in ipairs(matches) do
                    if ImGui.Selectable(match .. '##acsel_' .. widgetId) then
                        item[field.key] = match
                        changed  = true
                        acOpenId = nil
                    end
                end
                -- Hide list when neither the input nor the suggestion list has focus
                if not inputActive and not listHovered then
                    acOpenId = nil
                end
            end
            ImGui.EndChild()
        else
            -- No matches — clear so the empty list doesn't linger
            if not inputActive then acOpenId = nil end
        end
    end

    return changed
end

-- ============================================================

-- Returns the new value and changed bool
local function renderField(item, field, uid)
    local v = item[field.key]
    local changed = false

    local labelColor = field.required and {0.9, 0.9, 0.4, 1.0} or nil

    if labelColor then
        ImGui.TextColored(labelColor[1], labelColor[2], labelColor[3], labelColor[4], field.label .. '*')
    else
        ImGui.Text(field.label)
    end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(180)

    if field.ftype == 'subobject' then
        -- Render a nested object's fields inline under a sub-header
        ImGui.Separator()
        if type(v) ~= 'table' then
            -- Create the sub-object on first edit
            if ImGui.Button('Configure ' .. field.label .. '##new_' .. field.key .. uid) then
                item[field.key] = {}
                changed = true
            end
        else
            ImGui.TextColored(0.5, 0.8, 1.0, 1.0, field.label)
            ImGui.Indent(12)
            for _, subField in ipairs(field.fields or {}) do
                local fc = renderField(v, subField, uid .. '_' .. field.key)
                if fc then changed = true end
            end
            ImGui.Unindent(12)
        end
        ImGui.Separator()
        return changed
    end

    if field.ftype == 'string_list' then
        -- Label above, not inline (list takes multiple rows)
        ImGui.Separator()
        ImGui.Text(field.label .. ':')
        local list = v
        if type(list) ~= 'table' then
            list = {}
            item[field.key] = list
        end
        local toRemove = nil
        ImGui.Indent(12)
        for i, entry in ipairs(list) do
            ImGui.SetNextItemWidth(160)
            local new = ImGui.InputText('##sli_' .. field.key .. uid .. '_' .. i, tostring(entry))
            if new ~= entry then list[i] = new; changed = true end
            ImGui.SameLine()
            if ImGui.SmallButton('X##slrm_' .. field.key .. uid .. '_' .. i) then
                toRemove = i; changed = true
            end
        end
        if toRemove then table.remove(list, toRemove) end
        if ImGui.SmallButton('+ Add##sladd_' .. field.key .. uid) then
            table.insert(list, '')
            changed = true
        end
        ImGui.Unindent(12)
        ImGui.Separator()
        return changed
    end

    if field.ftype == 'bool' then
        local cur = v == true
        local new = ImGui.Checkbox('##' .. field.key .. uid, cur)
        if new ~= cur then item[field.key] = new; changed = true end

    elseif field.ftype == 'number' then
        local cur = tonumber(v) or 0
        local new = ImGui.InputInt('##' .. field.key .. uid, cur)
        if new ~= cur then item[field.key] = new; changed = true end

    elseif field.ftype == 'enum' then
        local opts = field.options or {}
        local cur  = tostring(v or opts[1] or '')
        if ImGui.BeginCombo('##' .. field.key .. uid, cur) then
            for _, opt in ipairs(opts) do
                if ImGui.Selectable(opt, opt == cur) then
                    item[field.key] = opt; changed = true
                end
            end
            ImGui.EndCombo()
        end

    elseif field.ftype == 'spell_name' then
        local fc = renderAutocomplete(item, field, uid,
            function(q) return SpellCache.searchSpells(q) end)
        if fc then changed = true end

    elseif field.ftype == 'ability_name' then
        local fc = renderAutocomplete(item, field, uid,
            function(q) return SpellCache.searchAbilities(q) end)
        if fc then changed = true end

    else -- string / fallback
        local cur = tostring(v or '')
        local new = ImGui.InputText('##' .. field.key .. uid, cur)
        if new ~= cur then item[field.key] = new; changed = true end
    end

    return changed
end

-- ============================================================
-- Array renderer (flat list of items)
-- ============================================================

local function renderArray(arr, schema, uid, changed)
    local toRemove = nil
    for i, item in ipairs(arr) do
        local itemLabel = tostring(item[schema.labelKey] or i)
        local nodeId    = '##item_' .. uid .. '_' .. i

        -- Collapse header per item
        local open = ImGui.CollapsingHeader(itemLabel .. nodeId)

        -- Remove button on the same line
        ImGui.SameLine()
        ImGui.SetCursorPosX(ImGui.GetCursorPosX())
        if ImGui.SmallButton('X##rm_' .. uid .. '_' .. i) then
            toRemove = i
            changed  = true
        end

        if open then
            ImGui.Indent(12)
            for _, field in ipairs(schema.fields) do
                local fc = renderField(item, field, uid .. '_' .. i)
                if fc then changed = true end
            end
            ImGui.Unindent(12)
        end
    end

    if toRemove then
        table.remove(arr, toRemove)
    end

    if ImGui.Button('+ Add##' .. uid) then
        table.insert(arr, deepCopy(schema.default or {}))
        changed = true
    end

    return changed
end

-- ============================================================
-- KV renderer
-- ============================================================

local function renderKV(tbl, fields, uid, changed)
    for _, field in ipairs(fields) do
        local always = field.ftype == 'bool' or field.ftype == 'subobject' or field.ftype == 'string_list'
        if tbl[field.key] ~= nil or always then
            local fc = renderField(tbl, field, uid .. '_kv')
            if fc then changed = true end
        end
    end
    return changed
end

-- ============================================================
-- Named-set renderer  (tbl.Main = {...}, tbl.Cold = {...})
-- ============================================================

local function renderNamedSets(tbl, schema, uid, changed)
    -- Determine which set keys to show
    local keys = schema.setNames and deepCopy(schema.setNames) or {}
    -- Also show any extra keys present in the table that aren't in kvFields
    local kvKeys = {}
    if schema.kvFields then
        for _, f in ipairs(schema.kvFields) do kvKeys[f.key] = true end
    end
    local seen = {}
    for _, k in ipairs(keys) do seen[k] = true end
    for k, v in pairs(tbl) do
        if not seen[k] and not kvKeys[k] and type(v) == 'table' then
            table.insert(keys, k)
            seen[k] = true
        end
    end

    -- Render any kv fields that live at the section level (e.g. Debuff.DebuffTargetsOnXTarEnabled)
    if schema.kvFields then
        changed = renderKV(tbl, schema.kvFields, uid, changed)
        ImGui.Separator()
    end

    for _, setName in ipairs(keys) do
        local setArr = tbl[setName]
        if setArr == nil then
            -- Empty set: offer to add it
            if ImGui.CollapsingHeader(setName .. ' (empty)##' .. uid .. '_' .. setName) then
                if ImGui.Button('+ Add first item##' .. uid .. '_' .. setName) then
                    tbl[setName] = { deepCopy(schema.default or {}) }
                    changed = true
                end
            end
        elseif type(setArr) == 'table' and isArray(setArr) then
            if ImGui.CollapsingHeader(setName .. '##' .. uid .. '_' .. setName) then
                ImGui.Indent(8)
                changed = renderArray(setArr, schema, uid .. '_' .. setName, changed)
                ImGui.Unindent(8)
            end
        elseif type(setArr) == 'table' then
            -- nested named sets (e.g. Debuff.DebuffOnAssist.Main)
            if ImGui.CollapsingHeader(setName .. '##' .. uid .. '_' .. setName) then
                ImGui.Indent(8)
                local innerKeys = {}
                for k, v in pairs(setArr) do
                    if type(v) == 'table' then table.insert(innerKeys, k) end
                end
                table.sort(innerKeys)
                for _, innerKey in ipairs(innerKeys) do
                    local innerArr = setArr[innerKey]
                    if type(innerArr) == 'table' and isArray(innerArr) then
                        if ImGui.CollapsingHeader(innerKey .. '##' .. uid .. '_' .. setName .. '_' .. innerKey) then
                            ImGui.Indent(8)
                            changed = renderArray(innerArr, schema, uid .. '_' .. setName .. '_' .. innerKey, changed)
                            ImGui.Unindent(8)
                        end
                    end
                end
                if ImGui.Button('+ Add Set##ns_' .. uid .. '_' .. setName) then
                    -- prompt handled below via a simple InputText popup approach
                end
                ImGui.Unindent(8)
            end
        end
    end

    -- Button to add a new named set
    ImGui.Spacing()
    if ImGui.Button('+ New Set##' .. uid) then
        tbl['NewSet'] = {}
        changed = true
    end

    return changed
end

-- ============================================================
-- Section dispatcher
-- ============================================================

local function renderSection(key, tbl, schema, uid, changed)
    if tbl == nil then
        -- Section absent: offer to create it
        ImGui.TextDisabled('(not configured)')
        return changed
    end

    if schema.type == 'kv' then
        changed = renderKV(tbl, schema.fields, uid, changed)

    elseif schema.type == 'array' then
        if type(tbl) ~= 'table' then
            ImGui.TextDisabled('(empty)')
            if ImGui.Button('+ Add first item##' .. uid) then
                -- Replace scalar with an array
                -- Caller must handle this; we signal via dirty only
            end
        else
            changed = renderArray(tbl, schema, uid, changed)
        end

    elseif schema.type == 'named_sets' then
        changed = renderNamedSets(tbl, schema, uid, changed)

    elseif schema.type == 'mixed' then
        -- kv fields at top level
        if schema.kvFields then
            changed = renderKV(tbl, schema.kvFields, uid, changed)
            ImGui.Separator()
        end
        -- sub-array
        if schema.arrayKey then
            local arr = tbl[schema.arrayKey]
            if arr == nil then arr = {} tbl[schema.arrayKey] = arr end
            local subSchema = {
                labelKey = schema.labelKey,
                fields   = schema.fields,
                default  = schema.default,
            }
            changed = renderArray(arr, subSchema, uid .. '_' .. schema.arrayKey, changed)
        end
    end

    return changed
end

-- ============================================================
-- Generic fallback renderer (unknown sections)
-- ============================================================

local function renderGeneric(key, val, uid, depth, changed)
    depth = depth or 0
    local indent = depth * 12

    if type(val) == 'table' then
        if ImGui.CollapsingHeader(key .. '##gen_' .. uid) then
            ImGui.Indent(indent + 8)
            if isArray(val) then
                for i, item in ipairs(val) do
                    if type(item) == 'table' then
                        if ImGui.CollapsingHeader(tostring(i) .. '##gen_' .. uid .. '_' .. i) then
                            ImGui.Indent(8)
                            for k2, v2 in pairs(item) do
                                if type(v2) ~= 'table' then
                                    local f = { key = k2, label = k2, ftype = type(v2) == 'boolean' and 'bool' or type(v2) == 'number' and 'number' or 'string' }
                                    local fc = renderField(item, f, uid .. '_' .. i .. '_' .. k2)
                                    if fc then changed = true end
                                end
                            end
                            ImGui.Unindent(8)
                        end
                    else
                        ImGui.Text(tostring(i) .. ': ' .. tostring(item))
                    end
                end
            else
                for k2, v2 in pairs(val) do
                    changed = renderGeneric(k2, v2, uid .. '_' .. k2, depth + 1, changed)
                end
            end
            ImGui.Unindent(indent + 8)
        end
    elseif type(val) == 'boolean' then
        local f = { key = key, label = key, ftype = 'bool' }
        -- We need a parent table; use a wrapper trick via ImGui.Text + SameLine
        ImGui.Text(key .. ':')
        ImGui.SameLine()
        ImGui.Text(tostring(val))
    elseif type(val) == 'number' then
        ImGui.Text(key .. ': ' .. tostring(val))
    else
        ImGui.Text(key .. ': ' .. tostring(val or ''))
    end
    return changed
end

-- ============================================================
-- Character tab
-- ============================================================

local function loadCharTab()
    local path = charFilePath()
    local text = readFile(path)
    charTab.rawBuf = text
    local ok, parsed = pcall(function() return yaml.load(text) end)
    charTab.editTable       = (ok and type(parsed) == 'table') and deepCopy(parsed) or nil
    charTab.dirty           = false
    charTab.loaded          = true
    charTab.selectedSection = nil  -- will default to first section on next draw
end

local function drawCharTab()
    if not charTab.loaded then loadCharTab() end

    local avail_x, avail_y = ImGui.GetContentRegionAvail()

    -- Mode toggle
    if charTab.rawMode then
        if ImGui.Button('Structured View') then charTab.rawMode = false end
    else
        if ImGui.Button('Raw Edit') then
            -- sync raw buf from current editTable
            if charTab.editTable then
                local text, err = tableToYaml(charTab.editTable)
                charTab.rawBuf = text or ('# Error: ' .. tostring(err))
            end
            charTab.rawMode = true
        end
    end

    ImGui.SameLine()
    ImGui.BeginDisabled(not charTab.dirty)
    if ImGui.Button('Apply##char') then
        local text
        if charTab.rawMode then
            text = charTab.rawBuf
        else
            local err
            text, err = tableToYaml(charTab.editTable)
            if not text then
                print('[SRL] ConfigEditor: serialize error: ' .. tostring(err))
                ImGui.EndDisabled()
                return
            end
            -- Prepend comment header
            text = '# Character Configuration\n' .. text
        end
        if writeFile(charFilePath(), text) then
            charTab.dirty = false
            ConfigEditorWindow.config:reload()
            print('[SRL] ConfigEditor: saved and reloaded ' .. charFilePath())
        else
            print('[SRL] ConfigEditor: ERROR writing ' .. charFilePath())
        end
    end
    ImGui.EndDisabled()

    ImGui.SameLine()
    if ImGui.Button('Revert##char') then
        charTab.loaded = false
        loadCharTab()
    end

    if charTab.dirty then
        ImGui.SameLine()
        ImGui.TextColored(0.9, 0.7, 0.1, 1.0, 'Unsaved changes')
    end

    ImGui.Separator()

    -- ── Raw mode ──────────────────────────────────────────────────────
    if charTab.rawMode then
        local editorH = avail_y - 68
        local newText = ImGui.InputTextMultiline('##rawchar', charTab.rawBuf, avail_x, editorH)
        if newText ~= charTab.rawBuf then
            charTab.rawBuf = newText
            charTab.dirty  = true
        end
        return
    end

    -- ── Structured mode ───────────────────────────────────────────────
    if not charTab.editTable then
        ImGui.TextColored(0.9, 0.2, 0.2, 1.0, 'Failed to parse YAML. Use Raw Edit.')
        return
    end

    local tbl     = charTab.editTable
    local changed = false

    -- Build ordered section list (known sections present in the file, then unknowns)
    local sectionList = {}  -- { key, label, schema|nil }
    local shown = {}
    for _, key in ipairs(Schema.order) do
        local schema = Schema.sections[key]
        if schema and tbl[key] ~= nil then
            shown[key] = true
            table.insert(sectionList, { key = key, label = schema.label, schema = schema })
        end
    end
    for k in pairs(tbl) do
        if not shown[k] and k ~= '_version' then
            table.insert(sectionList, { key = k, label = k, schema = nil })
        end
    end

    -- Default selection to first section
    if not charTab.selectedSection and #sectionList > 0 then
        charTab.selectedSection = sectionList[1].key
    end

    local paneH = avail_y - 68

    -- ── Left pane: section list ───────────────────────────────────────
    if not ImGui.BeginChild('##seclist', 150, paneH, true) then
        ImGui.EndChild()
    else
        for _, entry in ipairs(sectionList) do
            local selected = charTab.selectedSection == entry.key
            if ImGui.Selectable(entry.label .. '##sl_' .. entry.key, selected) then
                charTab.selectedSection = entry.key
            end
        end
        ImGui.EndChild()
    end

    ImGui.SameLine()

    -- ── Right pane: selected section content ─────────────────────────
    if not ImGui.BeginChild('##seccontent', 0, paneH, true) then
        ImGui.EndChild()
    else
        local sel = charTab.selectedSection
        if sel then
            -- Find the entry
            local selEntry
            for _, e in ipairs(sectionList) do
                if e.key == sel then selEntry = e; break end
            end

            if selEntry then
                ImGui.TextColored(0.5, 0.8, 1.0, 1.0, selEntry.label)
                ImGui.Separator()
                if selEntry.schema then
                    changed = renderSection(sel, tbl[sel], selEntry.schema, sel, changed)
                else
                    changed = renderGeneric(sel, tbl[sel], 'other_' .. sel, 0, changed)
                end
            end
        else
            ImGui.TextDisabled('Select a section on the left.')
        end
        ImGui.EndChild()
    end

    if changed then charTab.dirty = true end
end

-- ============================================================
-- Settings tab (raw text only)
-- ============================================================

local function loadSettingsTab()
    settingsTab.rawBuf = readFile(settingsFilePath())
    settingsTab.dirty  = false
    settingsTab.loaded = true
end

local function drawSettingsTab()
    if not settingsTab.loaded then loadSettingsTab() end

    local avail_x, avail_y = ImGui.GetContentRegionAvail()

    ImGui.BeginDisabled(not settingsTab.dirty)
    if ImGui.Button('Apply##settings') then
        if writeFile(settingsFilePath(), settingsTab.rawBuf) then
            settingsTab.dirty = false
            ConfigEditorWindow.config:reload()
            print('[SRL] ConfigEditor: saved settings.yaml')
        else
            print('[SRL] ConfigEditor: ERROR writing settings.yaml')
        end
    end
    ImGui.EndDisabled()

    ImGui.SameLine()
    if ImGui.Button('Revert##settings') then
        settingsTab.loaded = false
        loadSettingsTab()
    end

    if settingsTab.dirty then
        ImGui.SameLine()
        ImGui.TextColored(0.9, 0.7, 0.1, 1.0, 'Unsaved changes')
    end

    ImGui.Separator()

    local editorH = avail_y - 60
    local newText = ImGui.InputTextMultiline('##rawsettings', settingsTab.rawBuf, avail_x, editorH)
    if newText ~= settingsTab.rawBuf then
        settingsTab.rawBuf = newText
        settingsTab.dirty  = true
    end
end

-- ============================================================
-- Public API
-- ============================================================

function ConfigEditorWindow:setConfig(cfg)
    self.config    = cfg
    charTab.loaded    = false
    settingsTab.loaded = false
end

function ConfigEditorWindow:toggle()
    self.visible = not self.visible
    if self.visible then
        charTab.loaded     = false
        settingsTab.loaded = false
        SpellCache.reset() -- rebuild in case spells changed since last open
    end
end

function ConfigEditorWindow:draw()
    if not self.visible then return end
    if not self.config  then return end

    ImGui.SetNextWindowSize(860, 680, 8) -- ImGuiCond_FirstUseEver
    self.visible, _ = ImGui.Begin('SRL Config Editor', self.visible, 0)
    if not self.visible then ImGui.End(); return end

    local ok, err = pcall(function()
        if ImGui.BeginTabBar('ConfigEditorTabs') then

            if ImGui.BeginTabItem('Character' .. (charTab.dirty and '  *' or '') .. '##chartab') then
                local draw_ok, draw_err = pcall(drawCharTab)
                if not draw_ok then
                    ImGui.TextColored(0.9, 0.2, 0.2, 1.0, 'Error: ' .. tostring(draw_err))
                end
                ImGui.EndTabItem()
            end

            if ImGui.BeginTabItem('Settings' .. (settingsTab.dirty and '  *' or '') .. '##settingstab') then
                local draw_ok, draw_err = pcall(drawSettingsTab)
                if not draw_ok then
                    ImGui.TextColored(0.9, 0.2, 0.2, 1.0, 'Error: ' .. tostring(draw_err))
                end
                ImGui.EndTabItem()
            end

            ImGui.EndTabBar()
        end
    end)
    if not ok then
        ImGui.TextColored(0.9, 0.2, 0.2, 1.0, 'Window error: ' .. tostring(err))
    end

    ImGui.End()
end

return ConfigEditorWindow
