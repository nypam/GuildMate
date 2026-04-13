-- GuildMate: Member donation view
-- Personal status panel — raw WoW frames, no AceGUI.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Utils = GM.Utils

local MemberView = {}
GM.MemberView = MemberView

local _showGuildLogs = false

-- ── Render ───────────────────────────────────────────────────────────────────

function MemberView:Render()
    local parent = GM.MainFrame:ClearContent()
    local L = Utils.LayoutBuilder(parent)

    local playerName = UnitName("player") or "Unknown"
    local realm      = GetRealmName and GetRealmName() or "Unknown"
    local memberKey  = Utils.MemberKey(playerName, realm)

    local goal      = GM.DB:GetActiveGoal()

    -- Does the goal apply to this player's rank? If not, we still render the
    -- goal card in grey so reroll / alt ranks can see what the main goal is,
    -- but we skip the personal progress (they're not expected to donate).
    local goalApplies = true
    if goal then
        local _, _, playerRankIndex = GetGuildInfo("player")
        if playerRankIndex and goal.targetRanks and not goal.targetRanks[playerRankIndex] then
            goalApplies = false
        end
    end

    local periodKey = goal and Utils.PeriodKey(time(), goal.period) or nil
    -- Use effective-donated so previous-period overpayments carry forward to
    -- cover the current period (e.g. paying 4 weeks at once covers the next
    -- 3 weeks too).
    local donated   = (goal and periodKey and goalApplies) and GM.DB:GetEffectiveDonated(memberKey, periodKey, goal) or 0
    local actualDonated = (goal and periodKey and goalApplies) and GM.DB:GetDonated(memberKey, periodKey) or 0
    local rawFrac   = (goal and goal.goldAmount > 0 and goalApplies) and (donated / goal.goldAmount) or 0
    local frac      = math.min(1, rawFrac)
    -- Grey palette when the goal is informational-only (doesn't apply to us).
    local color     = goalApplies and Utils.StatusColor(frac) or { 0.55, 0.55, 0.55 }
    local periodsAhead = (goal and goal.goldAmount > 0 and rawFrac >= 1 and goalApplies)
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
        local bc = color

        local function PaintBorder(bg)
            local function Edge(p1, r1, p2, r2, w, h)
                local t = bg:CreateTexture(nil, "BORDER")
                t:SetPoint(p1, bg, r1)
                t:SetPoint(p2, bg, r2)
                if w then t:SetWidth(w) end
                if h then t:SetHeight(h) end
                t:SetColorTexture(bc[1], bc[2], bc[3], 0.6)
            end
            Edge("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, 1)
            Edge("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, 1)
            Edge("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", 1, nil)
            Edge("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", 1, nil)
        end

        -- ── Container 1: Goal info + progress bar ────────────────────────────
        local card1Start = L:GetY()
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

        -- Decide what the bar represents:
        --  - When the goal applies: personal donated / goal amount.
        --  - When it doesn't: guild-wide progress — members who have met the
        --    goal / total members in the target ranks. Same visual, greyed.
        local barFrac, barLabel
        if goalApplies then
            barFrac = frac
            local pct = math.floor(frac * 100)
            barLabel = string.format("%s / %s  (%d%%)",
                Utils.FormatMoneyShort(donated),
                Utils.FormatMoneyShort(goal.goldAmount), pct)
        else
            local roster = GM.Donations and GM.Donations:GetRoster() or {}
            local total, met = 0, 0
            for key, info in pairs(roster) do
                if goal.targetRanks and goal.targetRanks[info.rankIndex] then
                    total = total + 1
                    if GM.DB:GetEffectiveDonated(key, periodKey, goal) >= goal.goldAmount then
                        met = met + 1
                    end
                end
            end
            barFrac = (total > 0) and (met / total) or 0
            local pct = math.floor(barFrac * 100)
            barLabel = string.format("%d / %d members met  (%d%%)", met, total, pct)
        end

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
        barText:SetText(barLabel)
        barText:SetTextColor(1, 1, 1, 1)

        barRow:SetScript("OnSizeChanged", function(_, w)
            fill:SetWidth(math.max(1, w * barFrac))
        end)

        -- When the goal doesn't apply, append a grey "Applies to: ..." line
        -- so the user understands who the goal is for.
        if not goalApplies then
            local rankNames = {}
            if goal.targetRanks then
                for i = 0, 9 do
                    if goal.targetRanks[i] and GuildControlGetRankName then
                        local rn = GuildControlGetRankName(i + 1)
                        if rn and rn ~= "" then rankNames[#rankNames + 1] = rn end
                    end
                end
            end
            L:AddSpacer(4)
            local rankList = #rankNames > 0 and table.concat(rankNames, ", ") or "\226\128\148"
            L:AddText("|cff888888" .. string.format(GM.L["GOAL_APPLIES_TO"] or "Applies to: %s", rankList) .. "|r", 11)
        end

        L:AddSpacer(PAD)
        L:SetMargins(0, 0)

        -- Paint container 1 background (no border — border goes on parent)
        local card1H = L:GetY() - card1Start
        local card1Bg = CreateFrame("Frame", nil, parent)
        card1Bg:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -card1Start)
        card1Bg:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        card1Bg:SetHeight(card1H)
        card1Bg:SetFrameLevel(parent:GetFrameLevel())
        Utils.SetFrameColor(card1Bg, color[1], color[2], color[3], 0.08)

        -- ── Container 2: Goal status (edge-to-edge, stronger tint) ──────────
        local summaryRow = L:AddFrame(28)
        Utils.SetFrameColor(summaryRow, color[1], color[2], color[3], 0.18)

        -- Left: summary text
        local summaryFs = summaryRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        summaryFs:SetPoint("LEFT", summaryRow, "LEFT", 10, 0)
        summaryFs:SetJustifyH("LEFT")

        if not goalApplies then
            -- Informational — no personal progress to report.
            summaryFs:SetText("|cffaaaaaa" .. GM.L["GOAL_NOT_APPLICABLE"] .. "|r")
        elseif frac >= 1.0 then
            local pw = goal.period == "monthly" and GM.L["MONTH_FULL"] or GM.L["WEEK_FULL"]
            -- When the current period is being covered by carryover (player
            -- didn't actually donate this period), show the credit message.
            if actualDonated == 0 and donated >= goal.goldAmount then
                local creditPeriods = math.floor(donated / goal.goldAmount)
                summaryFs:SetText(string.format(
                    "|cff5fba47Goal covered|r by credit  (%s remaining, %d %s%s)",
                    Utils.FormatMoneyShort(donated),
                    creditPeriods, pw, creditPeriods > 1 and "s" or ""))
            elseif periodsAhead > 0 then
                summaryFs:SetText(string.format(GM.L["GOAL_MET_AHEAD"],
                    Utils.FormatMoneyShort(donated), periodsAhead, pw, periodsAhead > 1 and "s" or ""))
            else
                summaryFs:SetText(string.format(GM.L["GOAL_MET"], Utils.FormatMoneyShort(donated)))
            end
        else
            local remaining = math.max(0, goal.goldAmount - donated)
            local pct = math.floor(frac * 100)
            summaryFs:SetText(string.format(GM.L["DONATED_REMAINING"],
                Utils.FormatMoneyShort(donated),
                Utils.FormatMoneyShort(remaining), pct))
        end

        -- Right: last deposit (only meaningful when the goal applies to us)
        if goalApplies then
            local rec = GM.DB.sv.donations[memberKey]
            if rec and rec.lastDeposit and rec.lastDeposit > 0 then
                local lastFs = summaryRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                lastFs:SetPoint("RIGHT", summaryRow, "RIGHT", -10, 0)
                lastFs:SetJustifyH("RIGHT")
                lastFs:SetText("|cffaaaaaa" .. string.format(GM.L["LAST_DEPOSIT"], date("%b %d at %H:%M", rec.lastDeposit)) .. "|r")
            end
        end

        -- Parent border wrapping both containers
        local outerBg = CreateFrame("Frame", nil, parent)
        outerBg:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -card1Start)
        outerBg:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        outerBg:SetHeight(L:GetY() - card1Start)
        outerBg:SetFrameLevel(parent:GetFrameLevel())
        PaintBorder(outerBg)
    else
        -- No active goal at all
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

    -- Build a combined timeline: real past periods + previous empty + future covered
    local historyRows = {}  -- { periodKey, amount, covered }
    local goalAmt = goal and goal.goldAmount or 0
    local periodType = goal and goal.period or "weekly"
    local periodOffset = (periodType == "weekly") and (7 * 86400) or (30 * 86400)

    -- Collect real donation periods
    local rec = GM.DB.sv.donations[memberKey]
    local knownPeriods = {}
    if rec and rec.records then
        for pk in pairs(rec.records) do
            local amt = GM.DB:GetDonated(memberKey, pk)
            if amt > 0 then
                historyRows[#historyRows + 1] = { periodKey = pk, amount = amt, covered = false }
                knownPeriods[pk] = true
            end
        end
    end

    -- Add previous periods (up to 4 back) even if empty — so you see the gap
    if goal then
        for i = 1, 4 do
            local pastTs = time() - (i * periodOffset)
            local pastPk = Utils.PeriodKey(pastTs, periodType)
            if not knownPeriods[pastPk] then
                historyRows[#historyRows + 1] = { periodKey = pastPk, amount = 0, covered = false }
                knownPeriods[pastPk] = true
            end
        end
    end

    -- Mark periods as "covered by carryover" using the same logic as the
    -- current-period status: walk all real records up through the current
    -- period, accumulating surplus and depleting it for any gap.
    -- A period with 0 actual donation is "covered" if surplus >= goal at
    -- that point. Includes the current period and a few future periods if
    -- the credit reaches that far.
    if goal and goalAmt > 0 then
        local sortedKnown = {}
        for pk in pairs(knownPeriods) do sortedKnown[#sortedKnown + 1] = pk end
        table.sort(sortedKnown)

        -- Determine how far forward to project (where the surplus runs out).
        local surplus = 0
        local prevOrd = nil
        local function _Ord(pk)
            local y, w = pk:match("^(%d+)%-W(%d+)$")
            if y then return tonumber(y) * 53 + tonumber(w) end
            local y2, m = pk:match("^(%d+)%-(%d+)$")
            if y2 then return tonumber(y2) * 12 + tonumber(m) end
            return 0
        end

        for _, pk in ipairs(sortedKnown) do
            local ord = _Ord(pk)
            if prevOrd then
                local missed = ord - prevOrd - 1
                surplus = math.max(0, surplus - missed * goalAmt)
            end
            local amt = GM.DB:GetDonated(memberKey, pk)
            -- If this period has no actual donation but surplus covers goal,
            -- mark it "covered" in the timeline.
            if amt == 0 and surplus >= goalAmt then
                for _, hr in ipairs(historyRows) do
                    if hr.periodKey == pk then hr.covered = true; break end
                end
            end
            surplus = math.max(0, surplus + amt - goalAmt)
            prevOrd = ord
        end

        -- Project surplus forward into future periods until it depletes.
        if periodKey and surplus >= goalAmt then
            local currentOrd = _Ord(periodKey)
            -- If our last record is before current, deplete first to current.
            if prevOrd and prevOrd < currentOrd then
                local gap = currentOrd - prevOrd
                surplus = math.max(0, surplus - gap * goalAmt)
                if surplus >= goalAmt and not knownPeriods[periodKey] then
                    historyRows[#historyRows + 1] = { periodKey = periodKey, amount = 0, covered = true }
                    knownPeriods[periodKey] = true
                end
            end
            -- Then walk forward.
            local i = 1
            while surplus >= goalAmt and i <= 12 do
                surplus = surplus - goalAmt
                local futureTs = time() + (i * periodOffset)
                local futurePk = Utils.PeriodKey(futureTs, periodType)
                if not knownPeriods[futurePk] then
                    historyRows[#historyRows + 1] = { periodKey = futurePk, amount = 0, covered = true }
                    knownPeriods[futurePk] = true
                end
                i = i + 1
            end
        end
    end

    -- Sort: most recent / future first
    table.sort(historyRows, function(a, b) return a.periodKey > b.periodKey end)

    if #historyRows == 0 then
        L:AddText("|cffaaaaaa" .. GM.L["NO_HISTORY"] .. "|r", 12)
    else
        local ROW_H = 28
        local shown = 0
        for _, hr in ipairs(historyRows) do
            if shown >= 10 then break end
            shown = shown + 1

            local hfrac
            if hr.covered then
                hfrac = 1
            else
                hfrac = (goalAmt > 0) and math.min(1, hr.amount / goalAmt) or (hr.amount > 0 and 1 or 0)
            end
            local hcolor = Utils.StatusColor(hfrac)
            local isCurrent = (periodKey and hr.periodKey == periodKey)

            local row = L:AddFrame(isCurrent and ROW_H + 4 or ROW_H)
            row:EnableMouse(true)

            -- Background — current week gets a brighter, tinted background
            local bgR, bgG, bgB, bgA
            if isCurrent then
                bgR, bgG, bgB, bgA = hcolor[1], hcolor[2], hcolor[3], 0.15
            else
                bgR, bgG, bgB, bgA = 0.12, 0.12, 0.12, 0.3
            end
            local bgTex = row:CreateTexture(nil, "BACKGROUND")
            bgTex:SetAllPoints()
            bgTex:SetTexture("Interface\\Buttons\\WHITE8X8")
            bgTex:SetVertexColor(bgR, bgG, bgB, bgA)

            -- Hover
            row:SetScript("OnEnter", function() bgTex:SetVertexColor(bgR * 1.3, bgG * 1.3, bgB * 1.3, bgA + 0.15) end)
            row:SetScript("OnLeave", function() bgTex:SetVertexColor(bgR, bgG, bgB, bgA) end)

            -- Left accent bar for current period
            if isCurrent then
                local accent = row:CreateTexture(nil, "BORDER")
                accent:SetWidth(3)
                accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
                accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
                accent:SetTexture("Interface\\Buttons\\WHITE8X8")
                accent:SetVertexColor(hcolor[1], hcolor[2], hcolor[3], 0.8)
            end

            -- Colour square
            local square = row:CreateTexture(nil, "OVERLAY")
            square:SetSize(8, 8)
            square:SetPoint("LEFT", row, "LEFT", 8, 0)
            square:SetTexture("Interface\\Buttons\\WHITE8X8")
            square:SetVertexColor(hcolor[1], hcolor[2], hcolor[3], 1)

            -- Period label
            local periodFs = row:CreateFontString(nil, "OVERLAY", isCurrent and "GameFontHighlight" or "GameFontNormal")
            periodFs:SetPoint("LEFT", row, "LEFT", 24, 0)
            periodFs:SetWidth(150)
            periodFs:SetJustifyH("LEFT")
            if hr.covered then
                periodFs:SetText("|cff5fba47" .. Utils.PeriodLabel(hr.periodKey) .. "|r")
            elseif isCurrent then
                periodFs:SetText("|cffffffff" .. Utils.PeriodLabel(hr.periodKey) .. "  (current)|r")
            else
                periodFs:SetText(Utils.PeriodLabel(hr.periodKey))
            end

            -- Amount text
            local amtFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            amtFs:SetPoint("LEFT", row, "LEFT", 176, 0)
            amtFs:SetWidth(120)
            amtFs:SetJustifyH("LEFT")
            if hr.covered then
                amtFs:SetText("|cff5fba47(covered)|r")
            else
                local aheadCount = (goalAmt > 0 and hr.amount >= goalAmt)
                    and math.floor(hr.amount / goalAmt) - 1 or 0
                local amtText = Utils.FormatMoneyShort(hr.amount)
                if aheadCount > 0 then
                    local pw = periodType == "monthly" and GM.L["MONTH_FULL"] or GM.L["WEEK_FULL"]
                    amtText = amtText .. "  |cff5fba47+" .. aheadCount .. pw .. "|r"
                end
                amtFs:SetText(amtText)
            end

            -- Progress bar (right side)
            if goalAmt > 0 then
                local barFrame = CreateFrame("Frame", nil, row)
                barFrame:SetHeight(10)
                barFrame:SetPoint("LEFT", row, "LEFT", 300, 0)
                barFrame:SetPoint("RIGHT", row, "RIGHT", -8, 0)

                local track = barFrame:CreateTexture(nil, "BACKGROUND")
                track:SetAllPoints()
                track:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
                track:SetVertexColor(0.1, 0.1, 0.1, 0.8)

                local fill = barFrame:CreateTexture(nil, "BORDER")
                fill:SetPoint("TOPLEFT")
                fill:SetPoint("BOTTOMLEFT")
                fill:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
                fill:SetVertexColor(hcolor[1], hcolor[2], hcolor[3], 0.85)
                fill:SetWidth(1)

                local pct = math.floor(hfrac * 100)
                local pctFs = barFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                pctFs:SetPoint("CENTER")
                pctFs:SetText(pct .. "%")
                pctFs:SetTextColor(1, 1, 1, 0.9)

                barFrame:SetScript("OnSizeChanged", function(_, w)
                    fill:SetWidth(math.max(1, w * hfrac))
                end)
            end
        end
    end

    -- ── Guild Donation Logs (toggle) ────────────────────────────────────────
    L:AddSpacer(14)

    local toggleRow = L:AddRow(22)

    -- Title (left)
    local toggleTitle = toggleRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toggleTitle:SetPoint("LEFT", toggleRow, "LEFT", 0, 0)
    toggleTitle:SetText("|cffcccccc" .. GM.L["GUILD_DONATION_LOGS"] .. "|r")

    -- Show/Hide button (right)
    local toggleBtn = CreateFrame("Button", nil, toggleRow, "UIPanelButtonTemplate")
    toggleBtn:SetSize(60, 20)
    toggleBtn:SetPoint("RIGHT", toggleRow, "RIGHT", 0, 0)
    toggleBtn:SetText(_showGuildLogs and "Hide" or "Show")
    toggleBtn:SetScript("OnClick", function()
        PlaySound(856)
        _showGuildLogs = not _showGuildLogs
        MemberView:Render()
    end)

    if not _showGuildLogs then
        L:Finish()
        return
    end

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
