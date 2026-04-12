-- GuildMate: Debug view
-- DB inspector with table sizes, tree browser, comm stats, and purge tools.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Utils = GM.Utils

local DebugView = {}
GM.DebugView = DebugView

-- ── State ────────────────────────────────────────────────────────────────────

local _browsingTable = nil    -- DB key currently being browsed, or nil for summary
local _expandedPaths = {}     -- set of expanded tree paths
local _browseSearch = ""
local MAX_ROWS = 100

-- Comm stats are initialized in GuildMate.lua (GM._commStats)

-- ── Size estimation ─────────────────────────────────────────────────────────

local function EstimateBytes(val, depth)
    depth = depth or 0
    if depth > 10 then return 4 end
    if val == nil then return 0 end
    local t = type(val)
    if t == "string" then return #val + 8
    elseif t == "number" then return 8
    elseif t == "boolean" then return 4
    elseif t == "table" then
        local sum = 40
        for k, v in pairs(val) do
            sum = sum + EstimateBytes(k, depth + 1) + EstimateBytes(v, depth + 1) + 16
        end
        return sum
    end
    return 8
end

local function FormatBytes(bytes)
    if bytes < 1024 then return string.format("%d B", bytes) end
    return string.format("%.1f KB", bytes / 1024)
end

local function CountKeys(tbl)
    if type(tbl) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

-- ── DB table definitions ────────────────────────────────────────────────────

local DB_TABLES = {
    { key = "goals",          label = "Goals" },
    { key = "donations",      label = "Donations" },
    { key = "professions",    label = "Professions" },
    { key = "recipes2",       label = "Recipes" },
    { key = "addonUsers",     label = "Addon Users" },
    { key = "settings",       label = "Settings" },
}

-- ── Render: Summary ─────────────────────────────────────────────────────────

function DebugView:Render()
    if _browsingTable then
        self:_RenderBrowser()
        return
    end

    local parent = GM.MainFrame:ClearContent()
    local L = Utils.LayoutBuilder(parent)

    L:AddText("|cffffffffDEBUG|r  |cffaaaaaa— Database Inspector|r", 16, GameFontHighlight)
    L:AddSpacer(10)

    -- Column headers
    local headerRow = L:AddFrame(18)
    local function Header(x, w, text)
        local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", headerRow, "LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetText("|cff888888" .. text .. "|r")
    end
    Header(0, 160, "Table")
    Header(170, 60, "Rows")
    Header(240, 80, "Est. Size")
    Header(410, 140, "Last Update")

    L:AddSpacer(4)

    local totalBytes = 0

    for _, def in ipairs(DB_TABLES) do
        local tbl = GM.DB.sv[def.key]
        local rows = CountKeys(tbl)
        local bytes = EstimateBytes(tbl)
        totalBytes = totalBytes + bytes

        local row = L:AddFrame(28)
        row:EnableMouse(true)

        local bgTex = row:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints()
        bgTex:SetTexture("Interface\\Buttons\\WHITE8X8")
        bgTex:SetVertexColor(0.12, 0.12, 0.12, 0.3)

        row:SetScript("OnEnter", function() bgTex:SetVertexColor(0.18, 0.18, 0.18, 0.5) end)
        row:SetScript("OnLeave", function() bgTex:SetVertexColor(0.12, 0.12, 0.12, 0.3) end)

        -- Table name
        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFs:SetPoint("LEFT", row, "LEFT", 4, 0)
        nameFs:SetWidth(160)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetText(def.label)

        -- Row count
        local countFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        countFs:SetPoint("LEFT", row, "LEFT", 170, 0)
        countFs:SetWidth(60)
        countFs:SetJustifyH("LEFT")
        countFs:SetText("|cffaaaaaa" .. rows .. "|r")

        -- Size
        local sizeFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sizeFs:SetPoint("LEFT", row, "LEFT", 240, 0)
        sizeFs:SetWidth(80)
        sizeFs:SetJustifyH("LEFT")
        sizeFs:SetText("|cffaaaaaa" .. FormatBytes(bytes) .. "|r")

        -- Browse button
        local browseBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        browseBtn:SetSize(60, 20)
        browseBtn:SetPoint("LEFT", row, "LEFT", 340, 0)
        browseBtn:SetText("Browse")
        local tableKey = def.key
        browseBtn:SetScript("OnClick", function()
            PlaySound(856)
            _browsingTable = tableKey
            _expandedPaths = {}
            _browseSearch = ""
            DebugView:Render()
        end)

        -- Last update
        local updateFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        updateFs:SetPoint("LEFT", row, "LEFT", 410, 0)
        updateFs:SetWidth(160)
        updateFs:SetJustifyH("LEFT")
        local lastTs = GM._lastUpdates and GM._lastUpdates[def.key]
        if lastTs then
            local ago = time() - lastTs
            local agoStr
            if ago < 60 then agoStr = ago .. "s ago"
            elseif ago < 3600 then agoStr = math.floor(ago / 60) .. "m ago"
            elseif ago < 86400 then agoStr = math.floor(ago / 3600) .. "h ago"
            else agoStr = math.floor(ago / 86400) .. "d ago" end
            updateFs:SetText("|cff5fba47" .. agoStr .. "|r  |cffaaaaaa" .. date("%H:%M:%S", lastTs) .. "|r")
        else
            updateFs:SetText("|cff666666—|r")
        end
    end

    -- Total
    L:AddSpacer(6)
    L:AddText("|cffaaaaaa Total estimated size: |r|cffffffff" .. FormatBytes(totalBytes) .. "|r", 12)

    -- ── Comm stats ──────────────────────────────────────────────────────────
    L:AddSpacer(14)
    L:AddText("|cffccccccCOMM STATS|r  |cffaaaaaa(this session)|r", 12, GameFontHighlight)
    L:AddSpacer(4)

    local cs = GM._commStats
    local statsRow = L:AddFrame(50)
    Utils.SetFrameColor(statsRow, 0.08, 0.08, 0.08, 0.5)

    local function StatText(x, y, text)
        local fs = statsRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", statsRow, "TOPLEFT", x, y)
        fs:SetText(text)
    end
    StatText(8,  -6,  "|cffaaaaaaSent:|r  " .. cs.sent .. " messages  (" .. FormatBytes(cs.bytesSent) .. ")")
    StatText(8,  -22, "|cffaaaaaaReceived:|r  " .. cs.received .. " messages  (" .. FormatBytes(cs.bytesReceived) .. ")")

    -- Refresh button (updates timestamps + feed)
    local refreshBtn = CreateFrame("Button", nil, statsRow, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 20)
    refreshBtn:SetPoint("TOPRIGHT", statsRow, "TOPRIGHT", -6, -6)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        PlaySound(856)
        DebugView:Render()
    end)

    -- ── Live comm feed ──────────────────────────────────────────────────────
    L:AddSpacer(14)
    L:AddText("|cffccccccLIVE COMM FEED|r  |cffaaaaaa(last " .. (GM._commHistoryMax or 50) .. " messages)|r", 12, GameFontHighlight)
    L:AddSpacer(4)

    local history = GM._commHistory or {}
    if #history == 0 then
        L:AddText("|cffaaaaaaNo messages yet. Waiting for comm activity...|r", 11)
    else
        -- Column headers
        local feedHeader = L:AddFrame(16)
        local function FeedHeader(x, w, text)
            local fs = feedHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("LEFT", feedHeader, "LEFT", x, 0)
            fs:SetWidth(w)
            fs:SetJustifyH("LEFT")
            fs:SetText("|cff666666" .. text .. "|r")
        end
        FeedHeader(4,   50, "Time")
        FeedHeader(60,  40, "Dir")
        FeedHeader(110, 120, "Command")
        FeedHeader(235, 120, "Sender")
        FeedHeader(360,  60, "Bytes")

        for i, evt in ipairs(history) do
            if i > 50 then break end

            local row = L:AddFrame(18)
            row:EnableMouse(true)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            bg:SetVertexColor(0.10, 0.10, 0.10, i % 2 == 0 and 0.15 or 0.25)

            local evtPreview = evt.preview or ""
            row:SetScript("OnEnter", function()
                bg:SetVertexColor(0.18, 0.22, 0.30, 0.5)
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(evt.cmd, 1, 1, 1)
                GameTooltip:AddLine(date("%Y-%m-%d %H:%M:%S", evt.timestamp), 0.7, 0.7, 0.7)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(evtPreview, 0.8, 0.8, 1, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function()
                bg:SetVertexColor(0.10, 0.10, 0.10, i % 2 == 0 and 0.15 or 0.25)
                GameTooltip:Hide()
            end)

            -- Time
            local timeFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            timeFs:SetPoint("LEFT", row, "LEFT", 4, 0)
            timeFs:SetWidth(50)
            timeFs:SetJustifyH("LEFT")
            timeFs:SetText("|cffaaaaaa" .. date("%H:%M:%S", evt.timestamp) .. "|r")

            -- Direction (colored square badge + label, vertically centered)
            local isIn = (evt.dir == "in")
            local badgeR, badgeG, badgeB = 0.37, 0.73, 0.28  -- green for in
            local labelColor = "|cff5fba47"
            local labelText = "in"
            if not isIn then
                badgeR, badgeG, badgeB = 0.85, 0.64, 0.00     -- orange for out
                labelColor = "|cffd9a400"
                labelText = "out"
            end

            local badge = CreateFrame("Frame", nil, row)
            badge:SetSize(14, 14)
            badge:SetPoint("LEFT", row, "LEFT", 60, 0)

            local badgeBg = badge:CreateTexture(nil, "BACKGROUND")
            badgeBg:SetAllPoints()
            badgeBg:SetTexture("Interface\\Buttons\\WHITE8X8")
            badgeBg:SetVertexColor(badgeR, badgeG, badgeB, 0.85)

            -- Fully-white triangle drawn from stacked 1-px WHITE8X8 strips.
            -- Avoids greyscale artifacts from Blizzard's shaded arrow assets
            -- (ChatFrameExpandArrow + SetDesaturated still renders mid-tones).
            local TRI_H = 6     -- triangle height in pixels
            local stepW = 2     -- each line is 2px wider than the previous
            for row_i = 0, TRI_H - 1 do
                -- For "in" (down arrow): wide on top, narrow on bottom.
                -- For "out" (up arrow): narrow on top, wide on bottom.
                local fromTop = isIn and row_i or (TRI_H - 1 - row_i)
                local strip = badge:CreateTexture(nil, "OVERLAY")
                strip:SetTexture("Interface\\Buttons\\WHITE8X8")
                strip:SetVertexColor(1, 1, 1, 1)
                local w = (TRI_H - fromTop) * stepW
                strip:SetSize(w, 1)
                -- Anchor each strip to badge center, offset vertically by row.
                -- Triangle occupies y = -(TRI_H/2-0.5) .. +(TRI_H/2-0.5) from center.
                local yOffset = (TRI_H / 2 - 0.5) - row_i
                strip:SetPoint("CENTER", badge, "CENTER", 0, yOffset)
            end

            local dirFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dirFs:SetPoint("LEFT", badge, "RIGHT", 4, 0)
            dirFs:SetText(labelColor .. labelText .. "|r")

            -- Command
            local cmdFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            cmdFs:SetPoint("LEFT", row, "LEFT", 110, 0)
            cmdFs:SetWidth(120)
            cmdFs:SetJustifyH("LEFT")
            cmdFs:SetText("|cffffffff" .. evt.cmd .. "|r")

            -- Sender
            local senderFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            senderFs:SetPoint("LEFT", row, "LEFT", 235, 0)
            senderFs:SetWidth(120)
            senderFs:SetJustifyH("LEFT")
            local senderName = evt.sender:match("^(.+)-[^-]+$") or evt.sender
            senderFs:SetText("|cffaaaaaa" .. senderName .. "|r")

            -- Bytes
            local bytesFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            bytesFs:SetPoint("LEFT", row, "LEFT", 360, 0)
            bytesFs:SetWidth(60)
            bytesFs:SetJustifyH("LEFT")
            bytesFs:SetText("|cff888888" .. evt.bytes .. "B|r")
        end
    end

    -- ── Action buttons (only visible in debug officer mode) ────────────────
    if not GM.debugOfficer then
        L:Finish()
        return
    end

    L:AddSpacer(14)
    L:AddText("|cffccccccACTIONS|r  |cffff4444(destructive — /gm debug ON)|r", 12, GameFontHighlight)
    L:AddSpacer(4)

    local actionRow = L:AddRow(30)

    -- Purge Ex-Members
    local purgeBtn = CreateFrame("Button", nil, actionRow, "UIPanelButtonTemplate")
    purgeBtn:SetSize(140, 24)
    purgeBtn:SetPoint("LEFT", actionRow, "LEFT", 0, 0)
    purgeBtn:SetText("Purge Ex-Members")
    purgeBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Purge Ex-Members")
        GameTooltip:AddLine("Remove profession and recipe data for members no longer in the guild.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Donation history is preserved (never deleted).", 0.4, 0.8, 0.4, true)
        GameTooltip:Show()
    end)
    purgeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    purgeBtn:SetScript("OnClick", function()
        PlaySound(856)
        if not purgeBtn._confirmPending then
            purgeBtn._confirmPending = true
            purgeBtn:SetText("|cffff4444Confirm?|r")
            C_Timer.After(3, function()
                purgeBtn._confirmPending = false
                purgeBtn:SetText("Purge Ex-Members")
            end)
        else
            purgeBtn._confirmPending = false
            local roster = GM.Donations and GM.Donations:GetRoster() or {}
            if next(roster) then
                -- NEVER delete donation history — it's sacred.
                -- Only prune professions and recipe crafter lists.
                if GM.Professions and GM.Professions.PruneStaleData then
                    GM.Professions:PruneStaleData(roster)
                end
                -- Prune addonUsers too
                if GM.DB.sv.addonUsers then
                    for key in pairs(GM.DB.sv.addonUsers) do
                        if not roster[key] then
                            GM.DB.sv.addonUsers[key] = nil
                        end
                    end
                end
            end
            GM:Print("|cff4A90D9GuildMate:|r Purged profession/recipe data for ex-members. |cff5fba47Donation history preserved.|r")
            DebugView:Render()
        end
    end)

    -- Clear Recipes
    local clearRecBtn = CreateFrame("Button", nil, actionRow, "UIPanelButtonTemplate")
    clearRecBtn:SetSize(110, 24)
    clearRecBtn:SetPoint("LEFT", purgeBtn, "RIGHT", 6, 0)
    clearRecBtn:SetText("Clear Recipes")
    clearRecBtn:SetScript("OnClick", function()
        PlaySound(856)
        if not clearRecBtn._confirmPending then
            clearRecBtn._confirmPending = true
            clearRecBtn:SetText("|cffff4444Confirm?|r")
            C_Timer.After(3, function()
                clearRecBtn._confirmPending = false
                clearRecBtn:SetText("Clear Recipes")
            end)
        else
            clearRecBtn._confirmPending = false
            GM.DB.sv.recipes2 = {}
            GM:Print("|cff4A90D9GuildMate:|r Recipes cleared. They will repopulate as members open tradeskill windows.")
            DebugView:Render()
        end
    end)

    -- Rescan Bank
    local rescanBtn = CreateFrame("Button", nil, actionRow, "UIPanelButtonTemplate")
    rescanBtn:SetSize(110, 24)
    rescanBtn:SetPoint("LEFT", clearRecBtn, "RIGHT", 6, 0)
    rescanBtn:SetText("Rescan Bank")
    rescanBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Rescan Guild Bank")
        GameTooltip:AddLine("Wipe donation events from the last 3 days and re-read the bank log.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Guild bank must be open. Older history is preserved.", 1, 0.8, 0.3, true)
        GameTooltip:Show()
    end)
    rescanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rescanBtn:SetScript("OnClick", function()
        PlaySound(856)
        if not rescanBtn._confirmPending then
            rescanBtn._confirmPending = true
            rescanBtn:SetText("|cffff4444Confirm?|r")
            C_Timer.After(3, function()
                rescanBtn._confirmPending = false
                rescanBtn:SetText("Rescan Bank")
            end)
        else
            rescanBtn._confirmPending = false
            if not _G["GuildBankFrame"] or not GuildBankFrame:IsShown() then
                GM:Print("|cffcc3333GuildMate:|r Guild bank must be open to rescan.")
            else
                GM.Donations:RescanRecent(3)
                GM:Print("|cff5fba47GuildMate:|r Recent events rescanned from bank log.")
                DebugView:Render()
            end
        end
    end)

    -- Reset All
    local resetBtn = CreateFrame("Button", nil, actionRow, "UIPanelButtonTemplate")
    resetBtn:SetSize(80, 24)
    resetBtn:SetPoint("LEFT", rescanBtn, "RIGHT", 6, 0)
    resetBtn:SetText("Reset All")
    resetBtn:SetScript("OnClick", function()
        PlaySound(856)
        if not resetBtn._confirmPending then
            resetBtn._confirmPending = 1
            resetBtn:SetText("|cffff4444Click 2x|r")
            C_Timer.After(3, function()
                resetBtn._confirmPending = false
                resetBtn:SetText("Reset All")
            end)
        elseif resetBtn._confirmPending == 1 then
            resetBtn._confirmPending = 2
            resetBtn:SetText("|cffff0000CONFIRM|r")
            C_Timer.After(3, function()
                resetBtn._confirmPending = false
                resetBtn:SetText("Reset All")
            end)
        else
            resetBtn._confirmPending = false
            -- Backup donations before wiping
            GM.DB:BackupDonations("manual-reset-all")
            local backups = GM.DB.sv.donationBackups
            GuildMateDB = nil
            GM.DB:Init()
            -- Restore the backup list
            GM.DB.sv.donationBackups = backups
            GM:Print("|cffff4444GuildMate:|r Database reset. |cff5fba47Donation history backed up — use /gm restore to recover.|r")
            DebugView:Render()
        end
    end)

    L:Finish()
end

-- ── Render: Browser ─────────────────────────────────────────────────────────

function DebugView:_RenderBrowser()
    local parent = GM.MainFrame:ClearContent()
    local L = Utils.LayoutBuilder(parent)

    local tbl = GM.DB.sv[_browsingTable]
    local label = _browsingTable

    -- Header
    local headerRow = L:AddRow(32)

    local backBtn = CreateFrame("Button", nil, headerRow, "UIPanelButtonTemplate")
    backBtn:SetSize(60, 22)
    backBtn:SetPoint("LEFT", headerRow, "LEFT", 0, 0)
    backBtn:SetText("Back")
    backBtn:SetScript("OnClick", function()
        PlaySound(856)
        _browsingTable = nil
        DebugView:Render()
    end)

    local titleFs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetFont(Utils.Font(GameFontHighlight, 16))
    titleFs:SetPoint("LEFT", backBtn, "RIGHT", 10, 0)
    titleFs:SetText("|cffffffffDEBUG|r  |cffaaaaaa— " .. label .. "|r")

    -- Search
    local searchBox = CreateFrame("EditBox", "GuildMateDebugSearchBox", headerRow, "InputBoxTemplate")
    searchBox:SetSize(140, 20)
    searchBox:SetPoint("RIGHT", headerRow, "RIGHT", -6, 0)
    searchBox:SetTextInsets(4, 4, 0, 0)
    searchBox:SetAutoFocus(false)
    searchBox:EnableMouse(true)
    searchBox:SetText(_browseSearch)
    searchBox:SetCursorPosition(0)

    local searchLabel = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("RIGHT", searchBox, "LEFT", -8, 0)
    searchLabel:SetText("|cffaaaaaaFilter:|r")

    local searchTimer = nil
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        _browseSearch = self:GetText():lower()
        if searchTimer then searchTimer:Cancel() end
        searchTimer = C_Timer.NewTimer(0.3, function()
            searchTimer = nil
            DebugView:_RenderBrowser()
            C_Timer.After(0, function()
                local box = _G["GuildMateDebugSearchBox"]
                if box then
                    box:SetFocus()
                    box:SetCursorPosition(#box:GetText())
                end
            end)
        end)
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        _browseSearch = ""
        self:SetText("")
        self:ClearFocus()
        DebugView:_RenderBrowser()
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    L:AddSpacer(8)

    -- Info
    local bytes = EstimateBytes(tbl)
    local rows = CountKeys(tbl)
    L:AddText("|cffaaaaaa" .. rows .. " entries  ·  " .. FormatBytes(bytes) .. "|r", 11)
    L:AddSpacer(4)

    if type(tbl) ~= "table" then
        L:AddText("|cffaaaaaa" .. tostring(tbl) .. "|r", 12)
        L:Finish()
        return
    end

    -- Render tree
    local rendered = 0
    self:_RenderTree(L, parent, tbl, "", 0, rendered)

    L:Finish()
end

-- ── Tree renderer ───────────────────────────────────────────────────────────

function DebugView:_RenderTree(L, parent, tbl, path, depth, rendered)
    if type(tbl) ~= "table" then return rendered end
    if rendered > MAX_ROWS then return rendered end

    -- Sort keys
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return tostring(a) < tostring(b)
    end)

    for _, k in ipairs(keys) do
        if rendered > MAX_ROWS then
            L:AddText("|cffaaaaaa... " .. (#keys - rendered) .. " more entries (limit reached)|r", 11)
            return rendered
        end

        local keyStr = tostring(k)
        local val = tbl[k]
        local fullPath = path == "" and keyStr or (path .. "." .. keyStr)

        -- Apply search filter at top level
        local shouldRender = true
        if depth == 0 and _browseSearch ~= "" then
            if not keyStr:lower():find(_browseSearch, 1, true) then
                local childMatch = false
                if type(val) == "table" then
                    for ck in pairs(val) do
                        if tostring(ck):lower():find(_browseSearch, 1, true) then
                            childMatch = true
                            break
                        end
                    end
                end
                if not childMatch then
                    shouldRender = false
                end
            end
        end

        if shouldRender then
            rendered = rendered + 1
            local indent = depth * 16
            local isTable = type(val) == "table"
            local isExpanded = _expandedPaths[fullPath]

            local row = L:AddFrame(22)
            row:EnableMouse(true)

            local bgTex = row:CreateTexture(nil, "BACKGROUND")
            bgTex:SetAllPoints()
            bgTex:SetTexture("Interface\\Buttons\\WHITE8X8")
            bgTex:SetVertexColor(0.10, 0.10, 0.10, depth % 2 == 0 and 0.2 or 0.1)

            row:SetScript("OnEnter", function() bgTex:SetVertexColor(0.15, 0.15, 0.15, 0.4) end)
            row:SetScript("OnLeave", function() bgTex:SetVertexColor(0.10, 0.10, 0.10, depth % 2 == 0 and 0.2 or 0.1) end)

            if isTable then
                local fp = fullPath
                row:SetScript("OnMouseUp", function()
                    PlaySound(856)
                    local scrollPos = GM.MainFrame:GetScrollPosition()
                    _expandedPaths[fp] = not _expandedPaths[fp]
                    DebugView:_RenderBrowser()
                    GM.MainFrame:SetScrollPosition(scrollPos)
                end)

                local arrow = isExpanded and "▼ " or "▶ "
                local subCount = CountKeys(val)
                local subSize = EstimateBytes(val)

                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetPoint("LEFT", row, "LEFT", 4 + indent, 0)
                fs:SetText("|cffd4af37" .. arrow .. keyStr .. "|r  |cff888888[" .. subCount .. " entries, " .. FormatBytes(subSize) .. "]|r")
            else
                local valStr = tostring(val)
                if #valStr > 80 then valStr = valStr:sub(1, 77) .. "..." end

                local keyFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                keyFs:SetPoint("LEFT", row, "LEFT", 4 + indent, 0)
                keyFs:SetWidth(200 - indent)
                keyFs:SetJustifyH("LEFT")
                keyFs:SetText("|cffaaaaaa" .. keyStr .. "|r")

                local valFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                valFs:SetPoint("LEFT", row, "LEFT", 210, 0)
                valFs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                valFs:SetJustifyH("LEFT")

                local valColor = "ffffff"
                if type(val) == "number" then valColor = "5fba47"
                elseif type(val) == "boolean" then valColor = "d9a400"
                elseif type(val) == "string" then valColor = "4A90D9" end
                valFs:SetText("|cff" .. valColor .. valStr .. "|r")
            end

            if isTable and isExpanded then
                rendered = self:_RenderTree(L, parent, val, fullPath, depth + 1, rendered)
            end
        end
    end

    return rendered
end
