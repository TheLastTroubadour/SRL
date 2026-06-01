local mq    = require 'mq'
local ImGui = require 'ImGui'

local GroupStatusWindow = {}
GroupStatusWindow.visible       = false
GroupStatusWindow.statusService = nil
GroupStatusWindow.showExpView   = false
GroupStatusWindow.expSortKey    = nil   -- nil = default (class order)
GroupStatusWindow.expSortAsc    = true

local EXP_COLS = {
    { label = 'Name',     key = 'name',      width = 72 },
    { label = 'EXP%',     key = 'pctExp',    width = 60 },
    { label = 'AA EXP%',  key = 'pctAAExp',  width = 65 },
    { label = 'Unspent',  key = 'aaUnspent',  width = 55 },
    { label = 'Assigned', key = 'aaAssigned', width = 65 },
    { label = 'Total AA', key = 'aaTotal',    width = 65 },
}

local function hpColor(pct)
    if not pct then return 0.5, 0.5, 0.5, 1.0 end
    if pct >= 70 then return 0.2, 0.8, 0.2, 1.0
    elseif pct >= 40 then return 0.9, 0.7, 0.1, 1.0
    else return 0.9, 0.2, 0.2, 1.0 end
end

local function drawMemberRow(name, hp, mana, endurance, targetName, casting, dead)
    ImGui.TableNextRow()

    -- Name
    ImGui.TableNextColumn()
    if dead then
        ImGui.TextColored(0.6, 0.1, 0.1, 1.0, name)
    else
        ImGui.Text(name)
    end

    -- HP
    ImGui.TableNextColumn()
    local hpStr = hp and string.format("%d%%", hp) or "??"
    local r, g, b, a = hpColor(hp)
    ImGui.TextColored(r, g, b, a, hpStr)

    -- Mana
    ImGui.TableNextColumn()
    local manaStr = mana and string.format("%d%%", mana) or "-"
    if mana then
        ImGui.TextColored(0.2, 0.4, 0.9, 1.0, manaStr)
    else
        ImGui.Text(manaStr)
    end

    -- Endurance
    ImGui.TableNextColumn()
    local endStr = endurance and string.format("%d%%", endurance) or "-"
    if endurance then
        ImGui.TextColored(0.8, 0.5, 0.1, 1.0, endStr)
    else
        ImGui.Text(endStr)
    end

    -- Target
    ImGui.TableNextColumn()
    ImGui.Text(targetName or "")

    -- Casting
    ImGui.TableNextColumn()
    if casting and casting ~= "" then
        ImGui.TextColored(0.9, 0.9, 0.2, 1.0, casting)
    else
        ImGui.Text("")
    end
end

local function drawExpTable(statusService)
    if not statusService then
        ImGui.TextColored(0.9, 0.6, 0.1, 1.0, "Waiting for status data...")
        return
    end

    -- ImGuiTableFlags: RowBg=64, BordersInnerV=512
    if not ImGui.BeginTable("ExpTable", #EXP_COLS, 64 + 512) then return end

    -- ImGuiTableColumnFlags: WidthFixed=2
    for _, col in ipairs(EXP_COLS) do
        ImGui.TableSetupColumn('', 2, col.width)
    end

    -- Clickable header row — each button toggles ASC/DESC for that column
    ImGui.TableNextRow()
    for i, col in ipairs(EXP_COLS) do
        ImGui.TableSetColumnIndex(i - 1)
        local lbl = col.label
        if GroupStatusWindow.expSortKey == col.key then
            lbl = lbl .. (GroupStatusWindow.expSortAsc and ' ^' or ' v')
        end
        if ImGui.SmallButton(lbl) then
            if GroupStatusWindow.expSortKey == col.key then
                GroupStatusWindow.expSortAsc = not GroupStatusWindow.expSortAsc
            else
                GroupStatusWindow.expSortKey = col.key
                GroupStatusWindow.expSortAsc = true
            end
        end
    end

    -- Sort entries
    local entries = statusService:getAll()
    local sortKey = GroupStatusWindow.expSortKey
    local sortAsc = GroupStatusWindow.expSortAsc
    if sortKey then
        table.sort(entries, function(a, b)
            local av = a[sortKey] or (sortKey == 'name' and '' or 0)
            local bv = b[sortKey] or (sortKey == 'name' and '' or 0)
            if sortAsc then return av < bv else return av > bv end
        end)
    end

    for _, entry in ipairs(entries) do
        ImGui.TableNextRow()

        ImGui.TableNextColumn()
        if entry.dead then
            ImGui.TextColored(0.6, 0.1, 0.1, 1.0, entry.name)
        else
            ImGui.Text(entry.name)
        end

        ImGui.TableNextColumn()
        ImGui.Text(entry.pctExp and string.format('%.2f%%', entry.pctExp) or '-')

        ImGui.TableNextColumn()
        ImGui.Text(entry.pctAAExp and string.format('%.2f%%', entry.pctAAExp) or '-')

        ImGui.TableNextColumn()
        ImGui.Text(entry.aaUnspent and tostring(entry.aaUnspent) or '-')

        ImGui.TableNextColumn()
        ImGui.Text(entry.aaAssigned and tostring(entry.aaAssigned) or '-')

        ImGui.TableNextColumn()
        ImGui.Text(entry.aaTotal and tostring(entry.aaTotal) or '-')
    end

    ImGui.EndTable()
end

local function drawContent(statusService)
    if not statusService then
        ImGui.TextColored(0.9, 0.6, 0.1, 1.0, "Waiting for status data...")
        return
    end

    -- ImGuiTableFlags: RowBg=64, BordersInnerV=512
    -- ImGuiTableColumnFlags: WidthFixed=2, WidthStretch=1
    if not ImGui.BeginTable("GroupStatusTable", 6, 64 + 512) then return end

    ImGui.TableSetupColumn("Name",      2,  72)
    ImGui.TableSetupColumn("HP",        2,  45)
    ImGui.TableSetupColumn("Mana",      2,  45)
    ImGui.TableSetupColumn("End",       2,  45)
    ImGui.TableSetupColumn("Target",    2,  80)
    ImGui.TableSetupColumn("Casting",   2, 144)
    ImGui.TableHeadersRow()

    for _, entry in ipairs(statusService:getAll()) do
        drawMemberRow(entry.name, entry.hp, entry.mana, entry.endurance, entry.target, entry.casting, entry.dead)
    end

    ImGui.EndTable()
end

function GroupStatusWindow:setStatusService(svc)
    self.statusService = svc
end

function GroupStatusWindow:toggle()
    self.visible = not self.visible
end

function GroupStatusWindow:draw()
    if not self.visible then return end

    ImGui.SetNextWindowSize(510, 220, 8) -- ImGuiCond_FirstUseEver = 8
    local show = ImGui.Begin("Character Status")

    if show then
        -- Toggle button: switches between group status and EXP/AA views
        local label = self.showExpView and '[ Group ]' or '[ XP/AA ]'
        if ImGui.SmallButton(label) then
            self.showExpView = not self.showExpView
        end
        ImGui.Separator()

        if self.showExpView then
            local ok, err = pcall(drawExpTable, self.statusService)
            if not ok then
                ImGui.TextColored(0.9, 0.2, 0.2, 1.0, "Error: " .. tostring(err))
            end
        else
            local ok, err = pcall(drawContent, self.statusService)
            if not ok then
                ImGui.TextColored(0.9, 0.2, 0.2, 1.0, "Error: " .. tostring(err))
            end
        end
    end

    ImGui.End()
end

return GroupStatusWindow
