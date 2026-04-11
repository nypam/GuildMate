-- GuildMate: Member donation view
-- Personal status panel — raw WoW frames, no AceGUI.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Utils = GM.Utils

local MemberView = {}
GM.MemberView = MemberView

-- ── Render ───────────────────────────────────────────────────────────────────

function MemberView:Render()
    local parent = GM.MainFrame:ClearContent()
    local L = Utils.LayoutBuilder(parent)

    local playerName = UnitName("player") or "Unknown"
    local realm      = GetRealmName and GetRealmName() or "Unknown"
    local memberKey  = Utils.MemberKey(playerName, realm)

    local goal      = GM.DB:GetActiveGoal()
    local periodKey = goal and Utils.PeriodKey(time(), goal.period) or nil
    local donated   = (goal and periodKey) and GM.DB:GetDonated(memberKey, periodKey) or 0
    local rawFrac   = (goal and goal.goldAmount > 0) and (donated / goal.goldAmount) or 0
    local frac      = math.min(1, rawFrac)
    local color     = Utils.StatusColor(frac)
    local periodsAhead = (goal and goal.goldAmount > 0 and rawFrac >= 1)
        and math.floor(donated / goal.goldAmount) - 1 or 0

    -- ── Header ───────────────────────────────────────────────────────────────
    local headerRow = L:AddRow(32)

    local titleFs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetFont(Utils.Font(GameFontHighlight, 16))
    titleFs:SetPoint("LEFT", headerRow, "LEFT", 0, 0)
    titleFs:SetText("|cffffffff" .. GM.L["YOUR_DONATION_STATUS"] .. "|r")

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
        GM.SettingsView:Render(function() MemberView:Render() end)
    end)
    settingsBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText(GM.L["SETTINGS"])
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    L:AddSpacer(8)

    -- ── Status card ──────────────────────────────────────────────────────────
    if goal then
        local PAD = 10
        local cardStartY = L:GetY()
        L:SetMargins(PAD, PAD)
        L:AddSpacer(PAD)

        -- Goal headline
        local periodWord = goal.period == "monthly" and GM.L["MONTHLY"] or GM.L["WEEKLY"]
        L:AddText(string.format(GM.L["GOAL_HEADLINE"], periodWord,
            Utils.FormatMoneyShort(goal.goldAmount)), 14)

        -- Period + time remaining
        local secsLeft = Utils.SecondsRemainingInPeriod(goal.period)
        local daysLeft = math.floor(secsLeft / 86400)
        L:AddText("|cffaaaaaa" .. string.format(GM.L["PERIOD_REMAINING"],
            Utils.PeriodLabel(periodKey), daysLeft, daysLeft == 1 and "" or "s", "") .. "|r", 11)

        L:AddSpacer(8)

        -- Progress bar
        local pct = math.floor(frac * 100)
        local barRow = L:AddFrame(18)

        local track = barRow:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
        track:SetVertexColor(0.12, 0.12, 0.12, 0.9)

        local fill = barRow:CreateTexture(nil, "BORDER")
        fill:SetPoint("TOPLEFT")
        fill:SetPoint("BOTTOMLEFT")
        fill:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
        fill:SetVertexColor(color[1], color[2], color[3], 0.85)
        fill:SetWidth(1)

        local barText = barRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        barText:SetPoint("LEFT", barRow, "LEFT", 6, 0)
        barText:SetText(string.format("%s / %s  (%d%%)",
            Utils.FormatMoneyShort(donated),
            Utils.FormatMoneyShort(goal.goldAmount), pct))
        barText:SetTextColor(1, 1, 1, 1)

        barRow:SetScript("OnSizeChanged", function(_, w)
            fill:SetWidth(math.max(1, w * frac))
        end)

        L:AddSpacer(8)

        -- Summary
        local remaining = math.max(0, goal.goldAmount - donated)
        if frac >= 1.0 then
            local pw = goal.period == "monthly" and GM.L["MONTH_FULL"] or GM.L["WEEK_FULL"]
            if periodsAhead > 0 then
                L:AddText(string.format(GM.L["GOAL_MET_AHEAD"],
                    Utils.FormatMoneyShort(donated), periodsAhead, pw, periodsAhead > 1 and "s" or ""), 12)
            else
                L:AddText(string.format(GM.L["GOAL_MET"], Utils.FormatMoneyShort(donated)), 12)
            end
        else
            L:AddText(string.format(GM.L["DONATED_REMAINING"],
                Utils.FormatMoneyShort(donated),
                Utils.FormatMoneyShort(remaining), pct), 12)
        end

        -- Last deposit
        local rec = GM.DB.sv.donations[memberKey]
        if rec and rec.lastDeposit and rec.lastDeposit > 0 then
            L:AddText("|cffaaaaaa" .. string.format(GM.L["LAST_DEPOSIT"], date("%b %d at %H:%M", rec.lastDeposit)) .. "|r", 11)
        end

        -- Hint
        L:AddText("|cffaaaaaa" .. GM.L["AUTO_TRACK_HINT"] .. "|r", 11)

        L:AddSpacer(PAD)
        L:SetMargins(0, 0)

        -- Paint card background + border with status colour
        local cardH = L:GetY() - cardStartY
        local cardBg = CreateFrame("Frame", nil, parent)
        cardBg:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -cardStartY)
        cardBg:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        cardBg:SetHeight(cardH)
        cardBg:SetFrameLevel(parent:GetFrameLevel())
        Utils.SetFrameColor(cardBg, color[1], color[2], color[3], 0.10)

        -- Border in status colour
        local bc = color
        local function Edge(p1, r1, p2, r2, w, h)
            local t = cardBg:CreateTexture(nil, "BORDER")
            t:SetPoint(p1, cardBg, r1)
            t:SetPoint(p2, cardBg, r2)
            if w then t:SetWidth(w) end
            if h then t:SetHeight(h) end
            t:SetColorTexture(bc[1], bc[2], bc[3], 0.6)
        end
        Edge("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, 1)
        Edge("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, 1)
        Edge("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", 1, nil)
        Edge("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", 1, nil)
    else
        local noGoalRow = L:AddFrame(40)
        Utils.SetFrameColor(noGoalRow, 0.15, 0.15, 0.15, 0.3)
        local fs = noGoalRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", noGoalRow, "LEFT", 10, 0)
        fs:SetText("|cffaaaaaa" .. GM.L["NO_GOAL_SET"] .. "|r")
    end

    -- ── History ──────────────────────────────────────────────────────────────
    L:AddSpacer(14)
    L:AddText("|cffcccccc" .. GM.L["HISTORY"] .. "|r", 12, GameFontHighlight)
    L:AddSpacer(4)

    local rec = GM.DB.sv.donations[memberKey]
    if rec and rec.records then
        local periods = {}
        for k in pairs(rec.records) do periods[#periods + 1] = k end
        table.sort(periods, function(a, b) return a > b end)

        local shown = 0
        for _, pk in ipairs(periods) do
            if shown >= 6 then break end
            shown = shown + 1

            local amt     = GM.DB:GetDonated(memberKey, pk)
            local goalAmt = goal and goal.goldAmount or 0
            local hfrac   = (goalAmt > 0) and math.min(1, amt / goalAmt) or 1
            local hcolor  = Utils.StatusColor(hfrac)

            local row = L:AddFrame(28)
            Utils.SetFrameColor(row, hcolor[1], hcolor[2], hcolor[3], 0.20)

            local colorHex = string.format("|cff%02x%02x%02x", hcolor[1]*255, hcolor[2]*255, hcolor[3]*255)
            local dotFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            dotFs:SetPoint("LEFT", row, "LEFT", 6, 0)
            dotFs:SetText(colorHex .. "●|r")

            local periodFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            periodFs:SetPoint("LEFT", row, "LEFT", 26, 0)
            periodFs:SetText(Utils.PeriodLabel(pk))

            local amtFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            amtFs:SetPoint("LEFT", row, "LEFT", 230, 0)
            amtFs:SetText(Utils.FormatMoneyShort(amt))
        end

        if #periods == 0 then
            L:AddText("|cffaaaaaa" .. GM.L["NO_HISTORY"] .. "|r", 12)
        end
    else
        L:AddText("|cffaaaaaa" .. GM.L["NO_HISTORY"] .. "|r", 12)
    end

    -- ── Guild Donation Logs ──────────────────────────────────────────────────
    L:AddSpacer(14)
    L:AddText("|cffcccccc" .. GM.L["GUILD_DONATION_LOGS"] .. "|r", 12, GameFontHighlight)
    L:AddSpacer(4)

    -- Collect all donations across all members and periods
    local allEntries = {}
    local roster = GM.Donations:GetRoster()

    for mk, mRec in pairs(GM.DB.sv.donations) do
        if mRec and mRec.records then
            local info = roster[mk]
            local eName = info and info.name or mk
            local eClass = info and info.classFilename or "WARRIOR"

            for pk, val in pairs(mRec.records) do
                local amt
                if type(val) == "table" then
                    amt = math.max(val.own or 0, val.synced or 0)
                else
                    amt = val
                end
                if amt > 0 then
                    allEntries[#allEntries + 1] = {
                        name          = eName,
                        classFilename = eClass,
                        periodKey     = pk,
                        amount        = amt,
                    }
                end
            end
        end
    end

    -- Sort: most recent period first, then by name
    table.sort(allEntries, function(a, b)
        if a.periodKey ~= b.periodKey then return a.periodKey > b.periodKey end
        return a.name < b.name
    end)

    if #allEntries == 0 then
        L:AddText("|cffaaaaaa" .. GM.L["NO_GUILD_RECORDS"] .. "|r", 12)
    else
        local lastPeriod = nil
        for _, entry in ipairs(allEntries) do
            if entry.periodKey ~= lastPeriod then
                lastPeriod = entry.periodKey
                L:AddSpacer(4)
                L:AddText("|cffd4af37" .. Utils.PeriodLabel(entry.periodKey) .. "|r", 12)
                L:AddSpacer(2)
            end

            local logRow = L:AddFrame(24)
            logRow:EnableMouse(true)

            local logBg = logRow:CreateTexture(nil, "BACKGROUND")
            logBg:SetAllPoints()
            logBg:SetTexture("Interface\\Buttons\\WHITE8X8")
            logBg:SetVertexColor(0.15, 0.15, 0.15, 0.2)

            logRow:SetScript("OnEnter", function() logBg:SetVertexColor(0.2, 0.2, 0.2, 0.4) end)
            logRow:SetScript("OnLeave", function() logBg:SetVertexColor(0.15, 0.15, 0.15, 0.2) end)

            local classColor = Utils.ClassColor(entry.classFilename)
            local classHex = string.format("|cff%02x%02x%02x",
                classColor[1] * 255, classColor[2] * 255, classColor[3] * 255)

            local nameFs = logRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameFs:SetPoint("LEFT", logRow, "LEFT", 8, 0)
            nameFs:SetWidth(180)
            nameFs:SetJustifyH("LEFT")
            nameFs:SetText(classHex .. entry.name .. "|r")

            local amtFs = logRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            amtFs:SetPoint("LEFT", logRow, "LEFT", 200, 0)
            amtFs:SetWidth(120)
            amtFs:SetJustifyH("LEFT")
            amtFs:SetText("|cffd4af37" .. Utils.FormatMoneyShort(entry.amount) .. "|r")
        end
    end

    L:Finish()
end
