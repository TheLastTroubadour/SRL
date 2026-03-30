local mq    = require 'mq'
local ImGui = require 'ImGui'

local GroupStatusWindow = {}
GroupStatusWindow.visible = true

local function hpColor(pct)
    if not pct then return 0.5, 0.5, 0.5, 1.0 end
    if pct >= 70 then return 0.2, 0.8, 0.2, 1.0
    elseif pct >= 40 then return 0.9, 0.7, 0.1, 1.0
    else return 0.9, 0.2, 0.2, 1.0 end
end

local function drawMemberRow(name, hp, mana, targetName, casting, dead)
    -- Name (red if dead)
    if dead then
        ImGui.TextColored(0.6, 0.1, 0.1, 1.0, string.format("%-14s", name))
    else
        ImGui.Text(string.format("%-14s", name))
    end
    ImGui.SameLine()

    -- HP (color coded)
    local hpStr = hp and string.format("%3d%%", hp) or " ?? "
    local r, g, b, a = hpColor(hp)
    ImGui.TextColored(r, g, b, a, hpStr)
    ImGui.SameLine()

    -- Mana (blue) or dashes if no mana resource
    local manaStr = mana and string.format("%3d%%", mana) or "  - "
    if mana then
        ImGui.TextColored(0.2, 0.4, 0.9, 1.0, manaStr)
    else
        ImGui.Text(manaStr)
    end
    ImGui.SameLine()

    -- Target
    ImGui.Text(string.format("%-22s", targetName or ""))
    ImGui.SameLine()

    -- Casting
    if casting and casting ~= "" then
        ImGui.TextColored(0.9, 0.9, 0.2, 1.0, casting)
    else
        ImGui.Text("")
    end
end

function GroupStatusWindow:toggle()
    self.visible = not self.visible
end

local function drawContent()
    local myMaxMana = mq.TLO.Me.MaxMana() or 0
    drawMemberRow(
        mq.TLO.Me.CleanName() or "Me",
        mq.TLO.Me.PctHPs(),
        myMaxMana > 0 and mq.TLO.Me.PctMana() or nil,
        mq.TLO.Target.CleanName() or "",
        mq.TLO.Me.Casting() or "",
        mq.TLO.Me.Dead()
    )

    local members = mq.TLO.Group.Members() or 0
    for i = 1, members do
        local m = mq.TLO.Group.Member(i)
        if m() then
            local name    = m.CleanName() or "?"
            local maxMana = m.MaxMana() or 0
            local casting    = ""
            local targetName = ""
            local spawn = mq.TLO.Spawn('pc =' .. name)
            if spawn() then
                casting = spawn.Casting() or ""
                local tgt = spawn.Target
                if tgt and tgt() then targetName = tgt.CleanName() or "" end
            end

            drawMemberRow(
                name,
                m.PctHPs(),
                maxMana > 0 and m.PctMana() or nil,
                targetName,
                casting,
                m.Dead()
            )
        end
    end
end

function GroupStatusWindow:draw()
    if not self.visible then return end

    ImGui.SetNextWindowSize(680, 220, ImGuiCond_FirstUseEver)
    local open = true
    local show = ImGui.Begin("Group Status", open)

    if show then
        self.visible = ImGui.Checkbox("Show", self.visible)
        ImGui.SameLine()
        ImGui.Text(string.format("  %-14s %-10s %-10s %-22s %s",
            "Name", "HP", "Mana", "Target", "Casting"))
        ImGui.Separator()

        local ok, err = pcall(drawContent)
        if not ok then
            ImGui.TextColored(0.9, 0.2, 0.2, 1.0, "Error: " .. tostring(err))
        end
    end

    if not ImGui.End() then
        self.visible = false
    end
end

return GroupStatusWindow
