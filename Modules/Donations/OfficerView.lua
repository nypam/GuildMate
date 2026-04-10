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

-- Roster filter state (persists across re-renders within the session)
local _filters = { paid = true, partial = true, unpaid = true }

-- ── Render ────────────────────────────────────────────────────────────────────

function OfficerView:Render(container)
    container:ReleaseChildren()
    container:SetLayout("List")

    local goal      = GM.DB:GetActiveGoal()
    local periodKey = goal and Utils.PeriodKey(time(), goal.period) or nil

    -- ── Header bar ────────────────────────────────────────────────────────────
    self:_RenderHeader(container, container, periodKey)

    -- ── Goal card ─────────────────────────────────────────────────────────────
    if goal then
        self:_RenderGoalCard(container, container, goal, periodKey)
    else
        self:_RenderNoGoal(container)
    end

    -- ── Action bar (above roster so it's always visible) ────────────────────
    self:_RenderActionBar(container, goal)

    -- ── Member roster (fills remaining height) ────────────────────────────────
    -- Calculate how much vertical space the top elements used, then give
    -- the roster box the rest. Defer one frame so AceGUI has laid out.
    self:_RenderRoster(container, container, goal, periodKey)

    C_Timer.After(0, function()
        if not container.frame then return end
        local containerHeight = container.frame:GetHeight()
        local rosterFrame = self._rosterBox and self._rosterBox.frame
        if rosterFrame then
            local top = rosterFrame:GetTop()
            local bottom = container.frame:GetBottom()
            if top and bottom and top > bottom then
                self._rosterBox:SetHeight(top - bottom - 4)
            end
        end
    end)
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

    Utils.SetFrameColor(card.frame, COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3], 0.12, card)

    -- Goal summary line
    local numRanks   = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    local rankNames  = {}
    for i = 0, numRanks - 1 do
        if goal.targetRanks[i] then
            rankNames[#rankNames + 1] = GuildControlGetRankName and GuildControlGetRankName(i + 1) or ("Rank "..i)
        end
    end

    local summaryLine = AceGUI:Create("Label")
    summaryLine:SetText(string.format(
        "|cffd4af37%s|r per member  ·  %s  ·  Ranks: %s",
        Utils.FormatMoneyShort(goal.goldAmount),
        goal.period:gsub("^%l", string.upper),
        #rankNames > 0 and table.concat(rankNames, ", ") or "None"))
    summaryLine:SetFullWidth(true)
    summaryLine:SetHeight(20)
    card:AddChild(summaryLine)

    -- Time remaining
    local secsLeft = Utils.SecondsRemainingInPeriod(goal.period)
    local daysLeft = math.floor(secsLeft / 86400)
    local timeLabel = AceGUI:Create("Label")
    timeLabel:SetText(string.format("|cffaaaaaa%s · %d day%s remaining|r",
        Utils.PeriodLabel(periodKey), daysLeft, daysLeft == 1 and "" or "s"))
    timeLabel:SetFullWidth(true)
    timeLabel:SetHeight(20)
    card:AddChild(timeLabel)

    self:_AddSpacer(card, 4)

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

    local frac = total > 0 and (met / total) or 0
    local pct  = math.floor(frac * 100)
    local goalColor = Utils.StatusColor(frac)

    local barText = string.format("%d / %d members met goal  (%d%%)", met, total, pct)
    local barWidget = Utils.CreateProgressBar(barText, frac, goalColor[1], goalColor[2], goalColor[3])
    card:AddChild(barWidget)

    self:_AddSpacer(card, 4)

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

function OfficerView:_RenderRoster(outerContainer, container, goal, periodKey)
    -- Wrap the roster in an InlineGroup (same style as the goal card)
    local rosterBox = AceGUI:Create("InlineGroup")
    rosterBox:SetTitle("|cffccccccMEMBER STATUS|r")
    rosterBox:SetLayout("Fill")
    rosterBox:SetFullWidth(true)
    container:AddChild(rosterBox)
    self._rosterBox = rosterBox

    -- Scrollable content inside the roster box
    local rosterScroll = AceGUI:Create("ScrollFrame")
    rosterScroll:SetLayout("List")
    rosterScroll:SetFullWidth(true)
    rosterScroll:SetFullHeight(true)
    rosterBox:AddChild(rosterScroll)

    -- Filter checkboxes
    local filterGroup = AceGUI:Create("SimpleGroup")
    filterGroup:SetLayout("Flow")
    filterGroup:SetFullWidth(true)
    rosterScroll:AddChild(filterGroup)

    local filterDefs = {
        { key = "unpaid",  label = "|cff8e0e13Unpaid|r",          color = {0.557, 0.055, 0.075} },
        { key = "partial", label = "|cffd9a400Partially Paid|r",  color = {0.851, 0.608, 0.0}   },
        { key = "paid",    label = "|cff5fba47Paid|r",            color = {0.373, 0.729, 0.275} },
    }

    for _, def in ipairs(filterDefs) do
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(def.label)
        cb:SetValue(_filters[def.key])
        cb:SetWidth(140)
        local filterKey = def.key
        cb:SetCallback("OnValueChanged", function(_, _, val)
            _filters[filterKey] = val
            -- Re-render the whole view to apply the filter
            OfficerView:Render(outerContainer)
        end)
        filterGroup:AddChild(cb)
    end

    self:_AddSpacer(rosterScroll, 4)

    -- Build sorted member list
    local roster = GM.Donations:GetRoster()
    local rows = {}
    for key, info in pairs(roster) do
        local donated = (goal and periodKey) and GM.DB:GetDonated(key, periodKey) or 0
        local frac    = (goal and goal.goldAmount > 0) and (donated / goal.goldAmount) or 0
        local inScope = (not goal) or goal.targetRanks[info.rankIndex]

        -- Apply filter
        local status
        if frac >= 1 then status = "paid"
        elseif frac > 0 then status = "partial"
        else status = "unpaid"
        end

        if inScope and _filters[status] then
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
        empty:SetText("|cffaaaaaa No members match the current filter.|r")
        empty:SetFullWidth(true)
        rosterScroll:AddChild(empty)
        return
    end

    for _, row in ipairs(rows) do
        self:_RenderMemberRow(rosterScroll, row)
    end
end

function OfficerView:_RenderMemberRow(container, row)
    local color = Utils.StatusColor(row.frac)
    local pct   = math.min(100, math.floor(row.frac * 100))

    -- Row container
    local rowGroup = AceGUI:Create("SimpleGroup")
    rowGroup:SetLayout("Flow")
    rowGroup:SetFullWidth(true)
    rowGroup:SetHeight(34)
    container:AddChild(rowGroup)

    local f = rowGroup.frame

    -- All custom textures go on a child frame so they're destroyed on release
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(f)
    overlay:EnableMouse(true)

    -- Subtle row background
    local bgTex = overlay:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    bgTex:SetVertexColor(0.15, 0.15, 0.15, 0.3)

    -- Hover highlight
    overlay:SetScript("OnEnter", function()
        bgTex:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        GameTooltip:SetOwner(overlay, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(row.name, 1, 1, 1)
        if row.goalAmount > 0 then
            GameTooltip:AddLine(string.format("Donated: %s / %s  (%d%%)",
                Utils.FormatMoneyShort(row.donated),
                Utils.FormatMoneyShort(row.goalAmount), pct), 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    overlay:SetScript("OnLeave", function()
        bgTex:SetVertexColor(0.15, 0.15, 0.15, 0.3)
        GameTooltip:Hide()
    end)

    -- Clean up the overlay when AceGUI recycles this widget
    local origOnRelease = rowGroup.OnRelease
    rowGroup.OnRelease = function(self)
        overlay:Hide()
        overlay:SetParent(nil)
        if origOnRelease then origOnRelease(self) end
    end

    -- ── Left side: Name (status) ──────────────────────────────────────────────
    local classColor = Utils.ClassColor(row.classFilename)
    local nameLabel = AceGUI:Create("Label")
    local classHex = string.format("|cff%02x%02x%02x",
        classColor[1] * 255, classColor[2] * 255, classColor[3] * 255)
    local onlineStr = row.online and "" or " |cffaaaaaa(offline)|r"
    nameLabel:SetText(classHex .. Utils.Truncate(row.name, 14) .. "|r" .. onlineStr)
    nameLabel:SetRelativeWidth(0.25)
    rowGroup:AddChild(nameLabel)

    -- ── Rank ──────────────────────────────────────────────────────────────────
    local rankName = (GuildControlGetRankName and GuildControlGetRankName(row.rankIndex + 1))
        or ("Rank " .. row.rankIndex)
    local rankLabel = AceGUI:Create("Label")
    rankLabel:SetText("|cffaaaaaa" .. Utils.Truncate(rankName, 10) .. "|r")
    rankLabel:SetRelativeWidth(0.15)
    rowGroup:AddChild(rankLabel)

    -- ── Donated / Target ──────────────────────────────────────────────────────
    local amtLabel = AceGUI:Create("Label")
    if row.goalAmount > 0 then
        amtLabel:SetText(string.format("%s / %s",
            Utils.FormatMoneyShort(row.donated),
            Utils.FormatMoneyShort(row.goalAmount)))
    else
        amtLabel:SetText(Utils.FormatMoneyShort(row.donated))
    end
    amtLabel:SetRelativeWidth(0.18)
    rowGroup:AddChild(amtLabel)

    -- ── Progress bar (fills remaining right side) ─────────────────────────────
    if row.goalAmount > 0 then
        local barLabel = AceGUI:Create("Label")
        barLabel:SetText(" ")
        barLabel:SetRelativeWidth(0.42)
        barLabel:SetHeight(18)
        rowGroup:AddChild(barLabel)

        local bf = barLabel.frame

        -- Bar container on a child frame for clean recycling
        local barOverlay = CreateFrame("Frame", nil, bf)
        barOverlay:SetPoint("TOPLEFT", bf, "TOPLEFT", 2, -2)
        barOverlay:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -2, 2)

        -- Dark track
        local track = barOverlay:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
        track:SetVertexColor(0.12, 0.12, 0.12, 0.9)

        -- Coloured fill
        local fill = barOverlay:CreateTexture(nil, "BORDER")
        fill:SetPoint("TOPLEFT", barOverlay, "TOPLEFT", 0, 0)
        fill:SetPoint("BOTTOMLEFT", barOverlay, "BOTTOMLEFT", 0, 0)
        fill:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
        fill:SetVertexColor(color[1], color[2], color[3], 0.85)
        fill:SetWidth(1)

        -- Percentage text centered in bar
        local pctText = barOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pctText:SetPoint("CENTER")
        pctText:SetText(pct .. "%")
        pctText:SetTextColor(1, 1, 1, 1)

        -- Update fill width when sized
        barOverlay:SetScript("OnSizeChanged", function(self, width)
            fill:SetWidth(math.max(1, width * math.min(1, row.frac)))
        end)

        -- Clean up bar overlay on release
        local origBarRelease = barLabel.OnRelease
        barLabel.OnRelease = function(self)
            barOverlay:Hide()
            barOverlay:SetParent(nil)
            if origBarRelease then origBarRelease(self) end
        end
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

    local exportBtn = AceGUI:Create("Button")
    exportBtn:SetText("Export CSV")
    exportBtn:SetWidth(120)
    exportBtn:SetCallback("OnClick", function()
        PlaySound(856)
        OfficerView:_ShowExportWindow(goal)
    end)
    barGroup:AddChild(exportBtn)
end

-- ── CSV Export ────────────────────────────────────────────────────────────────

function OfficerView:_ShowExportWindow(goal)
    local roster = GM.Donations:GetRoster()
    local periodType = goal and goal.period or "weekly"

    -- Collect all period keys across all members
    local allPeriods = {}
    local periodSet  = {}
    for memberKey in pairs(GM.DB.sv.donations) do
        local rec = GM.DB.sv.donations[memberKey]
        if rec and rec.records then
            for pk in pairs(rec.records) do
                if not periodSet[pk] then
                    periodSet[pk] = true
                    allPeriods[#allPeriods + 1] = pk
                end
            end
        end
    end
    table.sort(allPeriods)

    -- Build CSV header
    local lines = {}
    local header = "Name,Rank,Online"
    for _, pk in ipairs(allPeriods) do
        header = header .. "," .. pk
    end
    header = header .. ",Total"
    lines[#lines + 1] = header

    -- Build sorted member list
    local members = {}
    for memberKey in pairs(GM.DB.sv.donations) do
        members[#members + 1] = memberKey
    end
    table.sort(members)

    -- Build CSV rows
    for _, memberKey in ipairs(members) do
        local rec  = GM.DB.sv.donations[memberKey]
        local info = roster[memberKey]
        local name = memberKey
        local rankName = ""
        local online   = ""

        if info then
            name     = info.name or memberKey
            rankName = (GuildControlGetRankName and GuildControlGetRankName(info.rankIndex + 1)) or ""
            online   = info.online and "Yes" or "No"
        end

        local row   = name .. "," .. rankName .. "," .. online
        local total = 0

        for _, pk in ipairs(allPeriods) do
            local amt = (rec and rec.records and rec.records[pk]) or 0
            total = total + amt
            -- Convert copper to gold with 2 decimal places
            row = row .. "," .. string.format("%.2f", amt / 10000)
        end

        row = row .. "," .. string.format("%.2f", total / 10000)
        lines[#lines + 1] = row
    end

    local csv = table.concat(lines, "\n")

    -- Show in a copy-paste AceGUI window
    local exportFrame = AceGUI:Create("Frame")
    exportFrame:SetTitle("GuildMate — Export CSV")
    exportFrame:SetWidth(600)
    exportFrame:SetHeight(400)
    exportFrame:SetLayout("Fill")
    exportFrame:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end)

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel("Select all (Ctrl+A) and copy (Ctrl+C):")
    editBox:SetText(csv)
    editBox:SetFullWidth(true)
    editBox:SetFullHeight(true)
    editBox:DisableButton(true)
    exportFrame:AddChild(editBox)

    -- Auto-select all text for easy copying
    C_Timer.After(0.1, function()
        if editBox.editBox then
            editBox.editBox:SetFocus()
            editBox.editBox:HighlightText()
        end
    end)
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

function OfficerView:_AddSpacer(container, height)
    local sp = AceGUI:Create("Label")
    sp:SetText(" ")
    sp:SetFullWidth(true)
    sp:SetHeight(height or 8)
    container:AddChild(sp)
end
