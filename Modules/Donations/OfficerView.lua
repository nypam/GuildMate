-- GuildMate: Officer donation view
-- Full member roster with donation status — raw WoW frames, no AceGUI.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Utils = GM.Utils

local OfficerView = {}
GM.OfficerView = OfficerView

-- ── Visual constants ─────────────────────────────────────────────────────────

local ROW_HEIGHT    = 32
local CONTAINER_PAD = 10
local BORDER_COLOR  = { 0.3, 0.3, 0.3, 0.4 }
local CONTAINER_BG  = { 0.055, 0.306, 0.576, 0.12 }

-- Paint a bordered container background on `parent` spanning from startY to current L:GetY()
local function _PaintContainer(L, parent, startY)
    local h = L:GetY() - startY
    local bg = CreateFrame("Frame", nil, parent)
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -startY)
    bg:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    bg:SetHeight(h)
    bg:SetFrameLevel(parent:GetFrameLevel())
    Utils.SetFrameColor(bg, CONTAINER_BG[1], CONTAINER_BG[2], CONTAINER_BG[3], CONTAINER_BG[4])

    local function Edge(p1, r1, p2, r2, w, h)
        local t = bg:CreateTexture(nil, "BORDER")
        t:SetPoint(p1, bg, r1)
        t:SetPoint(p2, bg, r2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        t:SetColorTexture(BORDER_COLOR[1], BORDER_COLOR[2], BORDER_COLOR[3], BORDER_COLOR[4])
    end
    Edge("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, 1)
    Edge("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, 1)
    Edge("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", 1, nil)
    Edge("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", 1, nil)

    return bg
end

-- Roster filter state (persists within session)
local _filters = { paid = true, partial = true, unpaid = true }
local _searchText = ""
local _activeTab = "roster"  -- "roster" or "logs"

-- ── Render ───────────────────────────────────────────────────────────────────

function OfficerView:Render()
    local parent = GM.MainFrame:ClearContent()
    local L = Utils.LayoutBuilder(parent)

    local goal      = GM.DB:GetActiveGoal()
    local periodKey = goal and Utils.PeriodKey(time(), goal.period) or nil

    -- ── Header row ───────────────────────────────────────────────────────────
    local headerRow = L:AddRow(24)

    local titleFs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetFont(Utils.Font(GameFontHighlight, 16))
    titleFs:SetPoint("LEFT", headerRow, "LEFT", 0, 0)
    titleFs:SetText("|cffffffff" .. GM.L["DONATIONS"] .. "|r")

    local settingsBtn = CreateFrame("Button", nil, headerRow, "UIPanelButtonTemplate")
    settingsBtn:SetSize(30, 24)
    settingsBtn:SetPoint("RIGHT", headerRow, "RIGHT", 0, 0)
    settingsBtn:SetText("")
    local cogIcon = settingsBtn:CreateTexture(nil, "OVERLAY")
    cogIcon:SetSize(16, 16)
    cogIcon:SetPoint("CENTER")
    cogIcon:SetTexture("Interface\\Scenarios\\ScenarioIcon-Interact")
    settingsBtn:SetScript("OnClick", function()
        PlaySound(856)
        GM.SettingsView:Render(function() OfficerView:Render() end)
    end)
    settingsBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText(GM.L["SETTINGS"])
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local newGoalBtn = CreateFrame("Button", nil, headerRow, "UIPanelButtonTemplate")
    newGoalBtn:SetSize(110, 24)
    newGoalBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
    newGoalBtn:SetText(GM.L["NEW_GOAL"])
    newGoalBtn:SetScript("OnClick", function()
        PlaySound(856)
        GM.GoalEditor:Open(nil,
            function() OfficerView:Render() end,
            function() OfficerView:Render() end)
    end)

    -- Addon user count
    local addonUsers = GM.Donations:GetAddonUsers()
    local addonCount = 0
    for _ in pairs(addonUsers) do addonCount = addonCount + 1 end
    if addonCount > 0 then
        local addonFs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        addonFs:SetPoint("RIGHT", newGoalBtn, "LEFT", -10, 0)
        addonFs:SetText("|TInterface\\Icons\\INV_Misc_Orb_03:12:12|t |cffaaaaaa" .. string.format(GM.L["MEMBERS_WITH_ADDON"], addonCount, addonCount == 1 and "" or "s") .. "|r")
    end

    -- Period line (below title)
    if periodKey then
        L:AddText("|cffaaaaaa" .. Utils.PeriodLabel(periodKey) .. "|r", 11)
    end

    -- ── Goal card ────────────────────────────────────────────────────────────
    if goal then
        self:_RenderGoalCard(L, parent, goal, periodKey)
    else
        L:AddSpacer(4)
        L:AddText("|cffaaaaaa" .. GM.L["NO_GOAL"] .. "|r", 12)
    end

    L:AddSpacer(8)

    -- ── Tools container ──────────────────────────────────────────────────────
    local toolsStartY = L:GetY()
    L:SetMargins(CONTAINER_PAD, CONTAINER_PAD)
    L:AddSpacer(CONTAINER_PAD)
    L:AddText("|cffcccccc" .. GM.L["TOOLS"] .. "|r", 12, GameFontHighlight)
    L:AddSpacer(4)
    self:_RenderActionBar(L, parent, goal)
    L:AddSpacer(CONTAINER_PAD)
    L:SetMargins(0, 0)
    _PaintContainer(L, parent, toolsStartY)

    L:AddSpacer(8)

    -- ── Container with tabs inside ─────────────────────────────────────────
    local contentStartY = L:GetY()
    L:SetMargins(CONTAINER_PAD, CONTAINER_PAD)
    L:AddSpacer(CONTAINER_PAD)

    -- Tab bar
    local tabRow = L:AddRow(28)

    local function MakeTab(text, tabKey, xOff)
        local isActive = (_activeTab == tabKey)
        local btn = CreateFrame("Button", nil, tabRow)
        btn:SetHeight(26)
        btn:SetPoint("LEFT", tabRow, "LEFT", xOff, 0)

        -- Background
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        if isActive then
            bg:SetVertexColor(0.2, 0.35, 0.5, 0.6)
        else
            bg:SetVertexColor(0.15, 0.15, 0.15, 0.4)
        end

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        if isActive then
            label:SetText("|cffffffff" .. text .. "|r")
        else
            label:SetText("|cff888888" .. text .. "|r")
        end
        btn:SetWidth(label:GetStringWidth() + 20)

        -- Bottom accent line for active tab
        if isActive then
            local accent = btn:CreateTexture(nil, "OVERLAY")
            accent:SetHeight(2)
            accent:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
            accent:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
            accent:SetColorTexture(0.29, 0.56, 0.85, 1)
        end

        -- Hover
        btn:SetScript("OnEnter", function()
            if not isActive then bg:SetVertexColor(0.2, 0.2, 0.2, 0.5) end
        end)
        btn:SetScript("OnLeave", function()
            if not isActive then bg:SetVertexColor(0.15, 0.15, 0.15, 0.4) end
        end)

        btn:SetScript("OnClick", function()
            PlaySound(856)
            _activeTab = tabKey
            OfficerView:Render()
        end)

        return btn
    end

    MakeTab(GM.L["MEMBER_STATUS_TAB"], "roster", 0)
    MakeTab(GM.L["LOGS"], "logs", 130)

    L:AddSpacer(8)

    -- Tab content
    if _activeTab == "roster" then
        self:_RenderRosterTab(L, parent, goal, periodKey)
    else
        self:_RenderLogsTab(L, parent)
    end

    L:AddSpacer(CONTAINER_PAD)
    L:SetMargins(0, 0)
    _PaintContainer(L, parent, contentStartY)

    L:Finish()
end

-- ── Roster tab ───────────────────────────────────────────────────────────────

function OfficerView:_RenderRosterTab(L, parent, goal, periodKey)
    -- Filters
    local filterRow = L:AddRow(26)
    local filterDefs = {
        { key = "unpaid",  label = GM.L["FILTER_UNPAID"],   color = {0.557, 0.055, 0.075} },
        { key = "partial", label = GM.L["FILTER_PARTIAL"], color = {0.851, 0.608, 0.0}   },
        { key = "paid",    label = GM.L["FILTER_PAID"],    color = {0.373, 0.729, 0.275} },
    }
    local fx = 0
    for _, def in ipairs(filterDefs) do
        local cb = CreateFrame("CheckButton", nil, filterRow, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("LEFT", filterRow, "LEFT", fx, 0)
        cb:SetChecked(_filters[def.key])
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        local colorHex = string.format("|cff%02x%02x%02x", def.color[1]*255, def.color[2]*255, def.color[3]*255)
        lbl:SetText(colorHex .. def.label .. "|r")
        local fk = def.key
        cb:SetScript("OnClick", function(self)
            _filters[fk] = self:GetChecked()
            OfficerView:Render()
        end)
        fx = fx + 130
    end

    -- Search field
    local searchBox = CreateFrame("EditBox", "GuildMateSearchBox", filterRow, "InputBoxTemplate")
    searchBox:SetSize(140, 20)
    searchBox:SetPoint("RIGHT", filterRow, "RIGHT", -6, 0)
    searchBox:SetTextInsets(4, 4, 0, 0)
    searchBox:SetAutoFocus(false)
    searchBox:EnableMouse(true)
    searchBox:SetText(_searchText)
    searchBox:SetCursorPosition(0)

    local searchLabel = filterRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("RIGHT", searchBox, "LEFT", -8, 0)
    searchLabel:SetText("|cffaaaaaa" .. GM.L["SEARCH"] .. "|r")

    local searchTimer = nil
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        _searchText = self:GetText():lower()
        if searchTimer then searchTimer:Cancel() end
        searchTimer = C_Timer.NewTimer(0.3, function()
            searchTimer = nil
            OfficerView:Render()
            C_Timer.After(0, function()
                local box = _G["GuildMateSearchBox"]
                if box then
                    box:SetFocus()
                    box:SetCursorPosition(#box:GetText())
                end
            end)
        end)
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        _searchText = ""
        self:SetText("")
        self:ClearFocus()
        OfficerView:Render()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    L:AddSpacer(4)

    -- Build sorted member list
    local roster = GM.Donations:GetRoster()
    local rows = {}
    for key, info in pairs(roster) do
        local donated = (goal and periodKey) and GM.DB:GetDonated(key, periodKey) or 0
        local frac    = (goal and goal.goldAmount > 0) and (donated / goal.goldAmount) or 0
        local inScope = (not goal) or goal.targetRanks[info.rankIndex]

        local status
        if frac >= 1 then status = "paid"
        elseif frac > 0 then status = "partial"
        else status = "unpaid" end

        local matchesSearch = (_searchText == "") or info.name:lower():find(_searchText, 1, true)

        if inScope and _filters[status] and matchesSearch then
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

    table.sort(rows, function(a, b)
        local ag = a.frac >= 1 and 2 or (a.frac > 0 and 1 or 0)
        local bg = b.frac >= 1 and 2 or (b.frac > 0 and 1 or 0)
        if ag ~= bg then return ag < bg end
        return a.name < b.name
    end)

    if #rows == 0 then
        L:AddText("|cffaaaaaa" .. GM.L["NO_MEMBERS_MATCH"] .. "|r", 12)
    else
        for _, row in ipairs(rows) do
            self:_RenderMemberRow(L, parent, row)
        end
    end
end

-- ── Logs tab ─────────────────────────────────────────────────────────────────

local _logSearchText = ""

function OfficerView:_RenderLogsTab(L, parent)
    -- Search field
    local searchRow = L:AddRow(26)

    local logSearchBox = CreateFrame("EditBox", "GuildMateLogSearchBox", searchRow, "InputBoxTemplate")
    logSearchBox:SetSize(160, 20)
    logSearchBox:SetPoint("RIGHT", searchRow, "RIGHT", -6, 0)
    logSearchBox:SetTextInsets(4, 4, 0, 0)
    logSearchBox:SetAutoFocus(false)
    logSearchBox:EnableMouse(true)
    logSearchBox:SetText(_logSearchText)
    logSearchBox:SetCursorPosition(0)

    local logSearchLabel = searchRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    logSearchLabel:SetPoint("RIGHT", logSearchBox, "LEFT", -8, 0)
    logSearchLabel:SetText("|cffaaaaaaSearch:|r")

    local logSearchTimer = nil
    logSearchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        _logSearchText = self:GetText():lower()
        if logSearchTimer then logSearchTimer:Cancel() end
        logSearchTimer = C_Timer.NewTimer(0.3, function()
            logSearchTimer = nil
            OfficerView:Render()
            C_Timer.After(0, function()
                local box = _G["GuildMateLogSearchBox"]
                if box then
                    box:SetFocus()
                    box:SetCursorPosition(#box:GetText())
                end
            end)
        end)
    end)
    logSearchBox:SetScript("OnEscapePressed", function(self)
        _logSearchText = ""
        self:SetText("")
        self:ClearFocus()
        OfficerView:Render()
    end)
    logSearchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    L:AddSpacer(6)

    -- Collect all donations across all members and periods into a flat list
    local entries = {}
    local roster = GM.Donations:GetRoster()

    for memberKey, rec in pairs(GM.DB.sv.donations) do
        if rec and rec.records then
            local info = roster[memberKey]
            local name = info and info.name or memberKey
            local classFilename = info and info.classFilename or "WARRIOR"

            for periodKey, val in pairs(rec.records) do
                local amt
                if type(val) == "table" then
                    amt = math.max(val.own or 0, val.synced or 0)
                else
                    amt = val
                end
                local matchesSearch = (_logSearchText == "") or name:lower():find(_logSearchText, 1, true)
                if amt > 0 and matchesSearch then
                    entries[#entries + 1] = {
                        name          = name,
                        memberKey     = memberKey,
                        classFilename = classFilename,
                        periodKey     = periodKey,
                        amount        = amt,
                    }
                end
            end
        end
    end

    -- Sort: most recent period first, then by name within period
    table.sort(entries, function(a, b)
        if a.periodKey ~= b.periodKey then return a.periodKey > b.periodKey end
        return a.name < b.name
    end)

    if #entries == 0 then
        L:AddText("|cffaaaaaa" .. GM.L["NO_DONATION_RECORDS"] .. "|r", 12)
        return
    end

    -- Render grouped by period
    local lastPeriod = nil
    for _, entry in ipairs(entries) do
        -- Period header
        if entry.periodKey ~= lastPeriod then
            lastPeriod = entry.periodKey
            L:AddSpacer(4)
            L:AddText("|cffd4af37" .. Utils.PeriodLabel(entry.periodKey) .. "|r", 12)
            L:AddSpacer(2)
        end

        -- Entry row
        local rowFrame = L:AddFrame(24)
        rowFrame:EnableMouse(true)

        local bgTex = rowFrame:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints()
        bgTex:SetTexture("Interface\\Buttons\\WHITE8X8")
        bgTex:SetVertexColor(0.15, 0.15, 0.15, 0.2)

        rowFrame:SetScript("OnEnter", function()
            bgTex:SetVertexColor(0.2, 0.2, 0.2, 0.4)
        end)
        rowFrame:SetScript("OnLeave", function()
            bgTex:SetVertexColor(0.15, 0.15, 0.15, 0.2)
        end)

        -- Class-coloured name
        local classColor = Utils.ClassColor(entry.classFilename)
        local classHex = string.format("|cff%02x%02x%02x",
            classColor[1] * 255, classColor[2] * 255, classColor[3] * 255)

        local nameFs = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFs:SetPoint("LEFT", rowFrame, "LEFT", 8, 0)
        nameFs:SetWidth(180)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetText(classHex .. entry.name .. "|r")

        -- Amount (gold coloured)
        local amtFs = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        amtFs:SetPoint("LEFT", rowFrame, "LEFT", 200, 0)
        amtFs:SetWidth(120)
        amtFs:SetJustifyH("LEFT")
        amtFs:SetText("|cffd4af37" .. Utils.FormatMoneyShort(entry.amount) .. "|r")
    end
end

-- ── Goal card ────────────────────────────────────────────────────────────────

function OfficerView:_RenderGoalCard(L, parent, goal, periodKey)
    local cardStartY = L:GetY()
    L:SetMargins(CONTAINER_PAD, CONTAINER_PAD)
    L:AddSpacer(CONTAINER_PAD)

    -- Goal amount + period
    local periodWord = goal.period == "monthly" and GM.L["MONTHLY"] or GM.L["WEEKLY"]
    L:AddText(string.format(GM.L["GOAL_PER_MEMBER"],
        Utils.FormatMoneyShort(goal.goldAmount), periodWord), 12)

    -- Ranks on a separate line
    local numRanks  = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    local rankNames = {}
    for i = 0, numRanks - 1 do
        if goal.targetRanks[i] then
            rankNames[#rankNames + 1] = GuildControlGetRankName and GuildControlGetRankName(i + 1) or ("Rank "..i)
        end
    end
    L:AddText("|cffaaaaaa" .. string.format(GM.L["RANKS_LABEL"],
        #rankNames > 0 and table.concat(rankNames, ", ") or GM.L["RANKS_NONE"]) .. "|r", 11)

    -- Time remaining
    local secsLeft = Utils.SecondsRemainingInPeriod(goal.period)
    local daysLeft = math.floor(secsLeft / 86400)
    L:AddText("|cffaaaaaa" .. string.format(GM.L["DAYS_REMAINING"],
        daysLeft, daysLeft == 1 and "" or "s") .. "|r", 11)

    -- Space before progress bar
    L:AddSpacer(10)

    -- Overall progress
    local roster = GM.Donations:GetRoster()
    local total, met, totalDonated = 0, 0, 0
    for key, info in pairs(roster) do
        if goal.targetRanks[info.rankIndex] then
            total = total + 1
            local donated = GM.DB:GetDonated(key, periodKey)
            totalDonated = totalDonated + donated
            if donated >= goal.goldAmount then met = met + 1 end
        end
    end
    local frac = total > 0 and (met / total) or 0
    local goalColor = Utils.StatusColor(frac)

    -- Progress bar
    local barRow = L:AddFrame(16)
    local track = barRow:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
    track:SetVertexColor(0.12, 0.12, 0.12, 0.9)

    local fill = barRow:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
    fill:SetVertexColor(goalColor[1], goalColor[2], goalColor[3], 0.85)
    fill:SetWidth(1)

    local barText = barRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    barText:SetPoint("LEFT", barRow, "LEFT", 6, 0)
    barText:SetText(string.format(GM.L["MEMBERS_MET_GOAL"], met, total, math.floor(frac * 100)))
    barText:SetTextColor(1, 1, 1, 1)

    barRow:SetScript("OnSizeChanged", function(_, w)
        fill:SetWidth(math.max(1, w * math.min(1, frac)))
    end)

    -- Space after progress bar
    L:AddSpacer(10)

    -- Total collected this period
    local collectTarget = total * goal.goldAmount
    local collectPct = collectTarget > 0 and math.floor(totalDonated / collectTarget * 100) or 0
    L:AddText(string.format("|cffaaaaaa" .. GM.L["COLLECTED_THIS_PERIOD"] .. "|r  |cffd4af37%s|r / %s  |cffaaaaaa(%d%%)|r",
        Utils.FormatMoneyShort(totalDonated),
        Utils.FormatMoneyShort(collectTarget),
        collectPct), 11)

    L:AddSpacer(CONTAINER_PAD)
    L:SetMargins(0, 0)

    local cardBg = _PaintContainer(L, parent, cardStartY)

    -- Edit Goal button (top-right of card)
    local editBtn = CreateFrame("Button", nil, cardBg, "UIPanelButtonTemplate")
    editBtn:SetSize(90, 22)
    editBtn:SetPoint("TOPRIGHT", cardBg, "TOPRIGHT", -8, -6)
    editBtn:SetText(GM.L["EDIT_GOAL"])
    editBtn:SetScript("OnClick", function()
        PlaySound(856)
        GM.GoalEditor:Open(goal,
            function() OfficerView:Render() end,
            function() OfficerView:Render() end)
    end)

    -- Force Goal button (Guild Master only — pushes goal to all members)
    local _, _, playerRankIndex = GetGuildInfo("player")
    local forceBtn = nil
    if playerRankIndex == 0 or GM.debugOfficer then
        forceBtn = CreateFrame("Button", nil, cardBg, "UIPanelButtonTemplate")
        forceBtn:SetSize(90, 22)
        forceBtn:SetPoint("RIGHT", editBtn, "LEFT", -4, 0)
        forceBtn:SetText("Force Goal")
        forceBtn:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetText("Force Goal Sync")
            GameTooltip:AddLine("Broadcast the active goal to all online guild members.", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Use this if members don't see the goal.", 1, 0.8, 0.3)
            GameTooltip:Show()
        end)
        forceBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        forceBtn:SetScript("OnClick", function()
            PlaySound(856)
            GM.Donations:BroadcastGoal(goal)
            GM.Donations:BroadcastKnownTotals()
            GM:Print("|cff4A90D9GuildMate:|r Goal and donation data broadcasted to guild.")
        end)
    end

    -- Delete Goal button (cross icon inside a standard button)
    local deleteAnchor = (playerRankIndex == 0 or GM.debugOfficer) and forceBtn or editBtn
    local deleteBtn = CreateFrame("Button", nil, cardBg, "UIPanelButtonTemplate")
    deleteBtn:SetSize(30, 22)
    deleteBtn:SetPoint("RIGHT", deleteAnchor, "LEFT", -4, 0)
    deleteBtn:SetText("")

    local delIcon = deleteBtn:CreateTexture(nil, "OVERLAY")
    delIcon:SetSize(14, 14)
    delIcon:SetPoint("CENTER")
    delIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady")

    deleteBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText(GM.L["DELETE_GOAL"])
        GameTooltip:AddLine(GM.L["DELETE_GOAL_HINT"], 1, 0.5, 0.5)
        GameTooltip:Show()
    end)
    deleteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    deleteBtn:SetScript("OnClick", function()
        PlaySound(856)
        -- Confirmation: require a second click within 3 seconds
        if not deleteBtn._confirmPending then
            deleteBtn._confirmPending = true
            delIcon:SetVertexColor(1, 0.3, 0.3)
            GM:Print(GM.L["DELETE_CONFIRM"])
            C_Timer.After(3, function()
                deleteBtn._confirmPending = false
                if delIcon then delIcon:SetVertexColor(1, 1, 1) end
            end)
        else
            deleteBtn._confirmPending = false
            GM.DB:DeactivateAllGoals()
            GM:Print(GM.L["GOAL_DELETED"])
            OfficerView:Render()
        end
    end)
end

-- ── Action bar ───────────────────────────────────────────────────────────────

function OfficerView:_RenderActionBar(L, parent, goal)
    local row = L:AddRow(30)

    local incompleteCount = 0
    if goal then
        local periodKey = Utils.PeriodKey(time(), goal.period)
        for key, info in pairs(GM.Donations:GetRoster()) do
            if goal.targetRanks[info.rankIndex] then
                if GM.DB:GetDonated(key, periodKey) < goal.goldAmount then
                    incompleteCount = incompleteCount + 1
                end
            end
        end
    end

    local rx = 0
    local function ActionBtn(text, width, onClick, disabled)
        local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btn:SetSize(width, 26)
        btn:SetPoint("LEFT", row, "LEFT", rx, 0)
        btn:SetText(text)
        if disabled then btn:Disable() end
        btn:SetScript("OnClick", function() PlaySound(856); onClick() end)
        rx = rx + width + 6
        return btn
    end

    ActionBtn(string.format(GM.L["REMIND_INCOMPLETE"], incompleteCount), 200,
        function() GM.Donations:RemindIncomplete() end,
        not goal or incompleteCount == 0)

    ActionBtn(GM.L["ANNOUNCE_TO_GUILD"], 160,
        function() GM.Donations:AnnounceProgress() end,
        not goal)

    ActionBtn(GM.L["EXPORT_CSV"], 110,
        function() OfficerView:_ShowExportWindow(goal) end,
        false)
end

-- ── Member row ───────────────────────────────────────────────────────────────

function OfficerView:_RenderMemberRow(L, parent, row)
    local color = Utils.StatusColor(math.min(1, row.frac))
    local pct   = math.min(100, math.floor(row.frac * 100))
    local periodsAhead = (row.goalAmount > 0 and row.frac >= 1)
        and math.floor(row.donated / row.goalAmount) - 1 or 0

    local rowFrame = L:AddFrame(ROW_HEIGHT)
    rowFrame:EnableMouse(true)

    -- Background
    local bgTex = rowFrame:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    bgTex:SetVertexColor(0.15, 0.15, 0.15, 0.3)

    -- Hover
    rowFrame:SetScript("OnEnter", function()
        bgTex:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(row.name, 1, 1, 1)
        if row.goalAmount > 0 then
            GameTooltip:AddLine(string.format(GM.L["DONATED_TOOLTIP"],
                Utils.FormatMoneyShort(row.donated),
                Utils.FormatMoneyShort(row.goalAmount), pct), 0.8, 0.8, 0.8)
            if periodsAhead > 0 then
                local pw = (GM.DB:GetActiveGoal() and GM.DB:GetActiveGoal().period == "monthly") and GM.L["MONTH_FULL"] or GM.L["WEEK_FULL"]
                GameTooltip:AddLine(string.format(GM.L["AHEAD_TOOLTIP"], periodsAhead, pw, periodsAhead > 1 and "s" or ""), 0.4, 0.8, 0.4)
            end
        end
        GameTooltip:Show()
    end)
    rowFrame:SetScript("OnLeave", function()
        bgTex:SetVertexColor(0.15, 0.15, 0.15, 0.3)
        GameTooltip:Hide()
    end)

    -- Helper: vertically centred text
    local function RowText(xOff, width, text)
        local fs = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", rowFrame, "LEFT", xOff, 0)
        fs:SetWidth(width)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("MIDDLE")
        fs:SetText(text)
        return fs
    end

    -- Addon indicator (green square = has GuildMate, red = doesn't)
    local addonUsers = GM.Donations:GetAddonUsers()
    local hasAddon = addonUsers[row.key]
    local addonSquare = rowFrame:CreateTexture(nil, "OVERLAY")
    addonSquare:SetSize(8, 8)
    addonSquare:SetPoint("LEFT", rowFrame, "LEFT", 8, 0)
    addonSquare:SetTexture("Interface\\Buttons\\WHITE8X8")
    if hasAddon then
        addonSquare:SetVertexColor(0.2, 0.8, 0.2, 1)   -- green
    else
        addonSquare:SetVertexColor(0.7, 0.15, 0.15, 1)  -- red
    end

    -- Name (shifted right to make room for the square)
    local classColor = Utils.ClassColor(row.classFilename)
    local classHex = string.format("|cff%02x%02x%02x",
        classColor[1] * 255, classColor[2] * 255, classColor[3] * 255)
    local onlineStr = row.online and "" or " |cffaaaaaa(offline)|r"
    RowText(24, 156, classHex .. Utils.Truncate(row.name, 14) .. "|r" .. onlineStr)

    -- Rank
    local rankName = (GuildControlGetRankName and GuildControlGetRankName(row.rankIndex + 1))
        or ("Rank " .. row.rankIndex)
    RowText(180, 96, "|cffaaaaaa" .. Utils.Truncate(rankName, 10) .. "|r")

    -- Amount + ahead indicator
    local amtStr
    if row.goalAmount > 0 then
        amtStr = string.format("%s / %s",
            Utils.FormatMoneyShort(row.donated),
            Utils.FormatMoneyShort(row.goalAmount))
        if periodsAhead > 0 then
            local pw = (GM.DB:GetActiveGoal() and GM.DB:GetActiveGoal().period == "monthly") and GM.L["MONTH_SHORT"] or GM.L["WEEK_SHORT"]
            amtStr = amtStr .. "  |cff5fba47" .. string.format(GM.L["AHEAD_SHORT"], periodsAhead, pw) .. "|r"
        end
    else
        amtStr = Utils.FormatMoneyShort(row.donated)
    end
    RowText(280, 150, amtStr)

    -- Progress bar
    if row.goalAmount > 0 then
        local barFrame = CreateFrame("Frame", nil, rowFrame)
        barFrame:SetPoint("LEFT", rowFrame, "LEFT", 404, 0)
        barFrame:SetPoint("RIGHT", rowFrame, "RIGHT", -80, 0)
        barFrame:SetHeight(14)

        local track = barFrame:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
        track:SetVertexColor(0.12, 0.12, 0.12, 0.9)

        local fill = barFrame:CreateTexture(nil, "BORDER")
        fill:SetPoint("TOPLEFT")
        fill:SetPoint("BOTTOMLEFT")
        fill:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
        fill:SetVertexColor(color[1], color[2], color[3], 0.85)
        fill:SetWidth(1)

        local pctText = barFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pctText:SetPoint("CENTER")
        pctText:SetText(pct .. "%")
        pctText:SetTextColor(1, 1, 1, 1)

        barFrame:SetScript("OnSizeChanged", function(_, w)
            fill:SetWidth(math.max(1, w * math.min(1, row.frac)))
        end)
    end

    -- Whisper reminder button
    if row.goalAmount > 0 and row.frac < 1 and row.online then
        local whisperBtn = CreateFrame("Button", nil, rowFrame)
        whisperBtn:SetSize(22, 22)
        whisperBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -20, 0)

        local btnIcon = whisperBtn:CreateTexture(nil, "ARTWORK")
        btnIcon:SetAllPoints()
        btnIcon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
        whisperBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")

        whisperBtn:SetScript("OnClick", function()
            PlaySound(856)
            local goal = GM.DB:GetActiveGoal()
            if not goal then return end
            local remaining = goal.goldAmount - row.donated
            SendChatMessage(string.format(GM.L["WHISPER_TEMPLATE"],
                row.name, goal.period,
                Utils.FormatMoneyShort(goal.goldAmount),
                Utils.FormatMoneyShort(row.donated),
                Utils.FormatMoneyShort(remaining)),
                "WHISPER", nil, row.name)
            GM:Print(string.format(GM.L["REMINDER_SENT"], row.name))
        end)

        whisperBtn:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(string.format(GM.L["WHISPER_REMINDER_TIP"], row.name), 1, 1, 1)
            GameTooltip:Show()
        end)
        whisperBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
end

-- ── CSV Export ────────────────────────────────────────────────────────────────

function OfficerView:_ShowExportWindow(goal)
    local roster = GM.Donations:GetRoster()

    -- CSV escape: wrap in quotes if value contains comma, quote, or newline
    local function esc(s)
        s = tostring(s or "")
        if s:find('[,"\r\n]') then
            return '"' .. s:gsub('"', '""') .. '"'
        end
        return s
    end

    -- Build CSV from the event log (one line per deposit)
    local lines = { "Date,Time,Player,Realm,Rank,Amount (g),PeriodKey,EventId,Synthetic" }

    local log = GM.DB:GetDonationLog() or {}

    -- Sort by timestamp descending (newest first); synthetic events (ts=0) at bottom
    table.sort(log, function(a, b)
        local ta = a.timestamp or 0
        local tb = b.timestamp or 0
        if ta == 0 and tb ~= 0 then return false end
        if tb == 0 and ta ~= 0 then return true end
        return ta > tb
    end)

    for _, e in ipairs(log) do
        local info = roster[e.memberKey]
        local playerName = info and info.name or (e.memberKey:match("^(.+)-[^-]+$") or e.memberKey)
        local realm = e.memberKey:match("^.+-([^-]+)$") or ""
        local rank = info and (GuildControlGetRankName and GuildControlGetRankName(info.rankIndex + 1) or "") or ""
        local dateStr, timeStr
        if e.timestamp and e.timestamp > 0 then
            dateStr = date("%Y-%m-%d", e.timestamp)
            timeStr = date("%H:%M:%S", e.timestamp)
        else
            dateStr = ""
            timeStr = ""
        end
        local gold = string.format("%.2f", (e.amount or 0) / 10000)
        local synth = e.synthetic and "Yes" or "No"

        lines[#lines + 1] = table.concat({
            esc(dateStr), esc(timeStr), esc(playerName), esc(realm), esc(rank),
            gold, esc(e.periodKey), esc(e.id), synth,
        }, ",")
    end

    -- Fallback: if the event log is empty, export aggregated data for backward compat
    if #lines == 1 then
        lines[#lines + 1] = "-- No event log data. Showing aggregated donations: --"
        lines[#lines + 1] = "Player,Realm,Rank,Period,Amount (g)"
        for mk, rec in pairs(GM.DB.sv.donations or {}) do
            local info = roster[mk]
            local playerName = info and info.name or (mk:match("^(.+)-[^-]+$") or mk)
            local realm = mk:match("^.+-([^-]+)$") or ""
            local rank = info and (GuildControlGetRankName and GuildControlGetRankName(info.rankIndex + 1) or "") or ""
            if rec.records then
                for pk, amt in pairs(rec.records) do
                    if type(amt) == "table" then
                        amt = math.max(amt.own or 0, amt.synced or 0)
                    end
                    if amt > 0 then
                        lines[#lines + 1] = table.concat({
                            esc(playerName), esc(realm), esc(rank), esc(pk),
                            string.format("%.2f", amt / 10000),
                        }, ",")
                    end
                end
            end
        end
    end

    local csv = table.concat(lines, "\n")

    -- Export popup window (raw frame)
    local ef = CreateFrame("Frame", "GuildMateExportFrame", UIParent)
    ef:SetSize(600, 400)
    ef:SetPoint("CENTER")
    ef:SetFrameStrata("FULLSCREEN_DIALOG")
    ef:SetMovable(true)
    ef:EnableMouse(true)
    Utils.SetFrameColor(ef, 0.06, 0.06, 0.06, 0.98)

    local efTitle = ef:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    efTitle:SetPoint("TOP", ef, "TOP", 0, -8)
    efTitle:SetText(GM.L["EXPORT_TITLE"])

    local efClose = CreateFrame("Button", nil, ef, "UIPanelCloseButton")
    efClose:SetPoint("TOPRIGHT", ef, "TOPRIGHT", 4, 4)
    efClose:SetScript("OnClick", function() ef:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, ef, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", ef, "TOPLEFT", 12, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", ef, "BOTTOMRIGHT", -30, 12)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetText(csv)
    scrollFrame:SetScrollChild(editBox)

    C_Timer.After(0.1, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    ef:Show()
end
