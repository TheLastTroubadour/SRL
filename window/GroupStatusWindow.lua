local mq    = require 'mq'
local ImGui = require 'ImGui'

local GroupStatusWindow = {}
GroupStatusWindow.visible     = false
GroupStatusWindow.statusService = nil

local function hpColor(pct)
    if not pct then return 0.5, 0.5, 0.5, 1.0 end
    if pct >= 70 then return 0.2, 0.8, 0.2, 1.0
    elseif pct >= 40 then return 0.9, 0.7, 0.1, 1.0
    else return 0.9, 0.2, 0.2, 1.0 end
end

local function drawMemberRow(name, hp, mana, targetName, casting, dead)
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

local function drawContent(statusService)
    if not statusService then
        ImGui.TextColored(0.9, 0.6, 0.1, 1.0, "Waiting for status data...")
        return
    end

    -- ImGuiTableFlags: RowBg=64, BordersInnerV=512
    -- ImGuiTableColumnFlags: WidthFixed=2, WidthStretch=1
    if not ImGui.BeginTable("GroupStatusTable", 5, 64 + 512) then return end

    ImGui.TableSetupColumn("Name",    2,  72)
    ImGui.TableSetupColumn("HP",      2,  45)
    ImGui.TableSetupColumn("Mana",    2,  45)
    ImGui.TableSetupColumn("Target",  2,  80)
    ImGui.TableSetupColumn("Casting", 2, 144)
    ImGui.TableHeadersRow()

    for _, entry in ipairs(statusService:getAll()) do
        drawMemberRow(entry.name, entry.hp, entry.mana, entry.target, entry.casting, entry.dead)
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

    ImGui.SetNextWindowSize(460, 220, 8) -- ImGuiCond_FirstUseEver = 8
    local show = ImGui.Begin("Group Status")

    if show then
        local ok, err = pcall(drawContent, self.statusService)
        if not ok then
            ImGui.TextColored(0.9, 0.2, 0.2, 1.0, "Error: " .. tostring(err))
        end
    end

    ImGui.End()
end

return GroupStatusWindow
