-- GuildMate: Officer donation view
-- Renders the full member roster with donation status for officers/GL.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local AceGUI = LibStub("AceGUI-3.0")
local Utils  = GM.Utils

local OfficerView = {}
GM.OfficerView = OfficerView

-- ── Visual constants ──────────────────────────────────────────────────────────

local COLOR_ACCENT  = { 0.055, 0.306, 0.576 }
local FILL_OPACITY  = 0.30
local HOVER_MULT    = 1.25

-- ── Render ────────────────────────────────────────────────────────────────────

function OfficerView:Render(container)
    container:ReleaseChildren()
    container:SetLayout("Fill")

    -- Wrap everything in a scroll frame so content never clips
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    container:AddChild(scroll)

    local goal      = GM.DB:GetActiveGoal()
    local periodKey = goal and Utils.PeriodKey(time(), goal.period) or nil

    -- ── Header bar ────────────────────────────────────────────────────────────
    self:_RenderHeader(scroll, container, periodKey)

    -- ── Goal card ─────────────────────────────────────────────────────────────
    if goal then
        self:_RenderGoalCard(scroll, container, goal, periodKey)
    else
        self:_RenderNoGoal(scroll)
    end

    -- ── Member roster ─────────────────────────────────────────────────────────
    self:_RenderRoster(scroll, goal, periodKey)

    -- ── Action bar ────────────────────────────────────────────────────────────
    self:_RenderActionBar(scroll, goal)
end

-- ── Header ────────────────────────────────────────────────────────────────────

function OfficerView:_RenderHeader(container, outerContainer, periodKey)
    local headerGroup = AceGUI:Create("SimpleGroup")
    headerGroup:SetLayout("Flow")
    headerGroup:SetFullWidth(true)
    headerGroup:SetHeight(36)
    container:AddChild(headerGroup)

    local title = AceGUI:Create("Label")
    title:SetText("|cff4A90D9DONATIONS|r  " ..
        (periodKey and ("|cffaaaaaa" .. Utils.PeriodLabel(periodKey) .. "|r") or ""))
    title:SetFont(Utils.Font(GameFontHighlight, 16))
    title:SetRelativeWidth(0.7)
    headerGroup:AddChild(title)

    -- "New Goal" button top-right
    local newGoalBtn = AceGUI:Create("Button")
    newGoalBtn:SetText("+ New Goal")
    newGoalBtn:SetWidth(110)
    newGoalBtn:SetCallback("OnClick", function()
        PlaySound(856)
        GM.GoalEditor:Open(outerContainer,
            nil,
            function() OfficerView:Render(outerContainer) end,
            function() OfficerView:Render(outerContainer) end)
    end)
    headerGroup:AddChild(newGoalBtn)

    -- Settings button
    local settingsBtn = AceGUI:Create("Button")
    settingsBtn:SetText("⚙")
    settingsBtn:SetWidth(38)
    settingsBtn:SetCallback("OnClick", function()
        PlaySound(856)
        GM.SettingsView:Render(outerContainer, function()
            OfficerView:Render(outerContainer)
        end)
    end)
    headerGroup:AddChild(settingsBtn)
end

-- ── Goal card ─────────────────────────────────────────────────────────────────

function OfficerView:_RenderGoalCard(container, outerContainer, goal, periodKey)
    local card = AceGUI:Create("InlineGroup")
    card:SetTitle("")
    card:SetLayout("List")
    card:SetFullWidth(true)
    container:AddChild(card)

    Utils.SetFrameColor(card.frame, COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3], 0.12)

    -- Goal summary line
    local numRanks   = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    local rankNames  = {}
    for i = 0, numRanks - 1 do
        if goal.targetRanks[i] then
            rankNames[#rankNames + 1] = GuildControlGetRankName and GuildControlGetRankName(i) or ("Rank "..i)
        end
    end

    local summaryLine = AceGUI:Create("Label")
    summaryLine:SetText(string.format(
        "|cffd4af37%s|r per member  ·  %s  ·  Ranks: %s",
        Utils.FormatMoneyShort(goal.goldAmount),
        goal.period:gsub("^%l", string.upper),
        #rankNames > 0 and table.concat(rankNames, ", ") or "None"))
    summaryLine:SetFullWidth(true)
    card:AddChild(summaryLine)

    -- Time remaining
    local secsLeft = Utils.SecondsRemainingInPeriod(goal.period)
    local daysLeft = math.floor(secsLeft / 86400)
    local timeLabel = AceGUI:Create("Label")
    timeLabel:SetText(string.format("|cffaaaaaa%s · %d day%s remaining|r",
        Utils.PeriodLabel(periodKey), daysLeft, daysLeft == 1 and "" or "s"))
    timeLabel:SetFullWidth(true)
    card:AddChild(timeLabel)

    -- Overall progress bar (members who met goal / total targeted)
    local roster   = GM.Donations:GetRoster()
    local total, met = 0, 0
    for key, info in pairs(roster) do
        if goal.targetRanks[info.rankIndex] then
            total = total + 1
            local donated = GM.DB:GetDonated(key, periodKey)
            if donated >= goal.goldAmount then met = met + 1 end
        end
    end

    local progLabel = AceGUI:Create("Label")
    local frac = total > 0 and (met / total) or 0
    local pct  = math.floor(frac * 100)
    progLabel:SetText(string.format(
        "%d / %d members met goal  |cffaaaaaa(%d%%)|r", met, total, pct))
    progLabel:SetFullWidth(true)
    card:AddChild(progLabel)

    local editBtn = AceGUI:Create("Button")
    editBtn:SetText("Edit Goal")
    editBtn:SetWidth(100)
    editBtn:SetCallback("OnClick", function()
        PlaySound(856)
        GM.GoalEditor:Open(outerContainer, goal,
            function() OfficerView:Render(outerContainer) end,
            function() OfficerView:Render(outerContainer) end)
    end)
    card:AddChild(editBtn)
end

function OfficerView:_RenderNoGoal(container)
    local notice = AceGUI:Create("Label")
    notice:SetText("|cffaaaaaa No active donation goal. Click |r|cffffd700+ New Goal|r|cffaaaaaa to create one.|r")
    notice:SetFullWidth(true)
    container:AddChild(notice)
end

-- ── Roster ────────────────────────────────────────────────────────────────────

function OfficerView:_RenderRoster(container, goal, periodKey)
    -- Section header
    local hdr = AceGUI:Create("Label")
    hdr:SetText("|cffccccccMEMBER STATUS|r")
    hdr:SetFullWidth(true)
    hdr:SetFont(Utils.Font(GameFontHighlight, 12))
    container:AddChild(hdr)

    -- Build sorted member list
    local roster = GM.Donations:GetRoster()
    local rows = {}
    for key, info in pairs(roster) do
        local donated = (goal and periodKey) and GM.DB:GetDonated(key, periodKey) or 0
        local frac    = (goal and goal.goldAmount > 0) and (donated / goal.goldAmount) or 0
        local inScope = (not goal) or goal.targetRanks[info.rankIndex]
        if inScope then
            rows[#rows + 1] = {
                key           = key,
                name          = info.name,
                rankIndex     = info.rankIndex,
                classFilename = info.classFilename,
                online        = info.online,
                donated       = donated,
                goalAmount    = goal and goal.goldAmount or 0,
                frac          = frac,
            }
        end
    end

    -- Sort: not-donated first, then partial, then met; alpha within groups
    table.sort(rows, function(a, b)
        local ag = a.frac >= 1 and 2 or (a.frac > 0 and 1 or 0)
        local bg = b.frac >= 1 and 2 or (b.frac > 0 and 1 or 0)
        if ag ~= bg then return ag < bg end
        return a.name < b.name
    end)

    if #rows == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetText("|cffaaaaaa No members found. Open the guild panel to refresh the roster.|r")
        empty:SetFullWidth(true)
        container:AddChild(empty)
        return
    end

    for _, row in ipairs(rows) do
        self:_RenderMemberRow(container, row)
    end
end

function OfficerView:_RenderMemberRow(container, row)
    local color = Utils.StatusColor(row.frac)
    local icon  = Utils.StatusIcon(row.frac)
    local pct   = math.min(100, math.floor(row.frac * 100))

    -- Row container
    local rowGroup = AceGUI:Create("SimpleGroup")
    rowGroup:SetLayout("Flow")
    rowGroup:SetFullWidth(true)
    rowGroup:SetHeight(38)
    container:AddChild(rowGroup)

    -- Row background with status colour (texture-based, no BackdropTemplate needed)
    Utils.SetFrameColor(rowGroup.frame, color[1], color[2], color[3], FILL_OPACITY)

    -- Hover highlight: update the texture colour directly
    rowGroup.frame:EnableMouse(true)
    rowGroup.frame:SetScript("OnEnter", function(f)
        Utils.SetFrameColor(f, color[1], color[2], color[3], FILL_OPACITY * HOVER_MULT)
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(row.name, 1, 1, 1)
        if row.goalAmount > 0 then
            GameTooltip:AddLine(string.format("Donated: %s / %s  (%d%%)",
                Utils.FormatMoneyShort(row.donated),
                Utils.FormatMoneyShort(row.goalAmount), pct), 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    rowGroup.frame:SetScript("OnLeave", function(f)
        Utils.SetFrameColor(f, color[1], color[2], color[3], FILL_OPACITY)
        GameTooltip:Hide()
    end)

    -- Status icon
    local statusLabel = AceGUI:Create("Label")
    statusLabel:SetText(icon)
    statusLabel:SetWidth(24)
    rowGroup:AddChild(statusLabel)

    -- Class icon + name
    local nameLabel = AceGUI:Create("Label")
    local classColor = Utils.ClassColor(row.classFilename)
    local colorHex = string.format("|cff%02x%02x%02x",
        classColor[1] * 255, classColor[2] * 255, classColor[3] * 255)
    local onlineStr = row.online and "" or " |cffaaaaaa(offline)|r"
    nameLabel:SetText(colorHex .. Utils.Truncate(row.name, 16) .. "|r" .. onlineStr)
    nameLabel:SetWidth(160)
    rowGroup:AddChild(nameLabel)

    -- Rank name
    local rankName = (GuildControlGetRankName and GuildControlGetRankName(row.rankIndex))
        or ("Rank " .. row.rankIndex)
    local rankLabel = AceGUI:Create("Label")
    rankLabel:SetText("|cffaaaaaa" .. Utils.Truncate(rankName, 14) .. "|r")
    rankLabel:SetWidth(120)
    rowGroup:AddChild(rankLabel)

    -- Amount donated / goal
    local amtLabel = AceGUI:Create("Label")
    if row.goalAmount > 0 then
        amtLabel:SetText(string.format("%s / %s",
            Utils.FormatMoneyShort(row.donated),
            Utils.FormatMoneyShort(row.goalAmount)))
    else
        amtLabel:SetText(Utils.FormatMoneyShort(row.donated))
    end
    amtLabel:SetWidth(140)
    rowGroup:AddChild(amtLabel)

    -- Progress bar (inline, right side)
    if row.goalAmount > 0 then
        local barLabel = AceGUI:Create("Label")
        local filled  = math.floor(pct / 10)       -- 0-10 filled blocks
        local empty   = 10 - filled
        local barStr  = "|cff" ..
            string.format("%02x%02x%02x", color[1]*255, color[2]*255, color[3]*255) ..
            string.rep("█", filled) .. "|r" ..
            "|cff333333" .. string.rep("░", empty) .. "|r"
        barLabel:SetText(barStr .. "  " .. pct .. "%")
        barLabel:SetRelativeWidth(1.0)
        rowGroup:AddChild(barLabel)
    end
end

-- ── Action bar ────────────────────────────────────────────────────────────────

function OfficerView:_RenderActionBar(container, goal)
    local barGroup = AceGUI:Create("SimpleGroup")
    barGroup:SetLayout("Flow")
    barGroup:SetFullWidth(true)
    container:AddChild(barGroup)

    -- Count incomplete members for button label
    local incompleteCount = 0
    if goal then
        local periodKey = Utils.PeriodKey(time(), goal.period)
        for key, info in pairs(GM.Donations:GetRoster()) do
            if goal.targetRanks[info.rankIndex] then
                local donated = GM.DB:GetDonated(key, periodKey)
                if donated < goal.goldAmount then
                    incompleteCount = incompleteCount + 1
                end
            end
        end
    end

    local remindBtn = AceGUI:Create("Button")
    remindBtn:SetText(string.format("Remind Incomplete (%d)", incompleteCount))
    remindBtn:SetWidth(200)
    remindBtn:SetDisabled(not goal or incompleteCount == 0)
    remindBtn:SetCallback("OnClick", function()
        PlaySound(856)
        GM.Donations:RemindIncomplete()
    end)
    barGroup:AddChild(remindBtn)

    local announceBtn = AceGUI:Create("Button")
    announceBtn:SetText("Announce to Guild")
    announceBtn:SetWidth(170)
    announceBtn:SetDisabled(not goal)
    announceBtn:SetCallback("OnClick", function()
        PlaySound(856)
        GM.Donations:AnnounceProgress()
    end)
    barGroup:AddChild(announceBtn)
end
