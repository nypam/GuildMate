-- GuildMate: Member donation view
-- Personal status panel shown to non-officer guild members.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local AceGUI = LibStub("AceGUI-3.0")
local Utils  = GM.Utils

local MemberView = {}
GM.MemberView = MemberView

-- ── Visual constants ──────────────────────────────────────────────────────────

-- ── Render ────────────────────────────────────────────────────────────────────

function MemberView:Render(container)
    local outerContainer = container
    container:ReleaseChildren()
    container:SetLayout("Fill")

    -- Wrap in scroll frame so content never clips
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    container:AddChild(scroll)

    -- Redirect all rendering into the scroll frame
    container = scroll

    local playerName = UnitName("player") or "Unknown"
    local realm      = GetRealmName and GetRealmName() or "Unknown"
    local memberKey  = Utils.MemberKey(playerName, realm)

    local goal      = GM.DB:GetActiveGoal()
    local periodKey = goal and Utils.PeriodKey(time(), goal.period) or nil
    local donated   = (goal and periodKey) and GM.DB:GetDonated(memberKey, periodKey) or 0
    local frac      = (goal and goal.goldAmount > 0) and math.min(1, donated / goal.goldAmount) or 0
    local color     = Utils.StatusColor(frac)

    -- ── Title row with settings button ────────────────────────────────────────
    local headerGroup = AceGUI:Create("SimpleGroup")
    headerGroup:SetLayout("Flow")
    headerGroup:SetFullWidth(true)
    container:AddChild(headerGroup)

    local title = AceGUI:Create("Label")
    title:SetText("|cff4A90D9YOUR DONATION STATUS|r")
    title:SetFont(Utils.Font(GameFontHighlight, 16))
    title:SetRelativeWidth(0.9)
    headerGroup:AddChild(title)

    local settingsBtn = AceGUI:Create("Button")
    settingsBtn:SetText("⚙")
    settingsBtn:SetWidth(38)
    settingsBtn:SetCallback("OnClick", function()
        PlaySound(856)
        GM.SettingsView:Render(outerContainer, function()
            MemberView:Render(outerContainer)
        end)
    end)
    headerGroup:AddChild(settingsBtn)

    self:_AddSpacer(container, 8)

    -- ── Status card ───────────────────────────────────────────────────────────
    local card = AceGUI:Create("InlineGroup")
    card:SetTitle("")
    card:SetLayout("List")
    card:SetFullWidth(true)
    container:AddChild(card)

    Utils.SetFrameColor(card.frame, color[1], color[2], color[3], 0.12, card)

    if goal then
        -- Goal headline
        local goalLine = AceGUI:Create("Label")
        goalLine:SetText(string.format(
            "|cffd4af37%s goal:|r  %s per member",
            goal.period:gsub("^%l", string.upper),
            Utils.FormatMoneyShort(goal.goldAmount)))
        goalLine:SetFont(Utils.Font(GameFontHighlight, 14))
        goalLine:SetFullWidth(true)
        card:AddChild(goalLine)

        -- Period + time remaining
        local secsLeft = Utils.SecondsRemainingInPeriod(goal.period)
        local daysLeft = math.floor(secsLeft / 86400)
        local periodLine = AceGUI:Create("Label")
        periodLine:SetText(string.format("|cffaaaaaa%s  ·  %d day%s remaining|r",
            Utils.PeriodLabel(periodKey), daysLeft, daysLeft == 1 and "" or "s"))
        periodLine:SetFullWidth(true)
        card:AddChild(periodLine)

        self:_AddSpacer(card, 6)

        -- Progress bar
        local pct = math.floor(frac * 100)
        local barText = string.format("%s / %s  (%d%%)",
            Utils.FormatMoneyShort(donated),
            Utils.FormatMoneyShort(goal.goldAmount), pct)
        local barWidget = Utils.CreateProgressBar(barText, frac, color[1], color[2], color[3])
        card:AddChild(barWidget)

        -- Numeric summary
        local amtLine = AceGUI:Create("Label")
        local remaining = math.max(0, goal.goldAmount - donated)
        if frac >= 1.0 then
            amtLine:SetText("|cff5fba47✔  Goal met!|r  You donated " ..
                Utils.FormatMoneyShort(donated))
        else
            amtLine:SetText(string.format(
                "%s donated  ·  |cffd9a400%s remaining|r  (%d%%)",
                Utils.FormatMoneyShort(donated),
                Utils.FormatMoneyShort(remaining), pct))
        end
        amtLine:SetFullWidth(true)
        card:AddChild(amtLine)

        self:_AddSpacer(card, 4)

        -- Last deposit
        local rec = GM.DB.sv.donations[memberKey]
        if rec and rec.lastDeposit and rec.lastDeposit > 0 then
            local lastLine = AceGUI:Create("Label")
            lastLine:SetText("|cffaaaaaaLast deposit:  " ..
                date("%b %d at %H:%M", rec.lastDeposit) .. "|r")
            lastLine:SetFullWidth(true)
            card:AddChild(lastLine)
        end

        -- Hint for members
        self:_AddSpacer(card, 4)
        local hint = AceGUI:Create("Label")
        hint:SetText("|cffaaaaaa💡  Deposits you make to the guild bank are tracked automatically.|r")
        hint:SetFullWidth(true)
        card:AddChild(hint)
    else
        -- No active goal
        local noGoal = AceGUI:Create("Label")
        noGoal:SetText("|cffaaaaaaNo donation goal has been set by an officer yet.|r")
        noGoal:SetFullWidth(true)
        card:AddChild(noGoal)
    end

    -- ── History ───────────────────────────────────────────────────────────────
    self:_AddSpacer(container, 14)

    local histTitle = AceGUI:Create("Label")
    histTitle:SetText("|cffccccccHISTORY|r")
    histTitle:SetFont(Utils.Font(GameFontHighlight, 12))
    histTitle:SetFullWidth(true)
    container:AddChild(histTitle)

    local rec = GM.DB.sv.donations[memberKey]
    if rec and rec.records then
        -- Sort period keys descending
        local periods = {}
        for k in pairs(rec.records) do periods[#periods + 1] = k end
        table.sort(periods, function(a, b) return a > b end)

        -- Show up to 6 recent periods
        local shown = 0
        for _, pk in ipairs(periods) do
            if shown >= 6 then break end
            shown = shown + 1

            local amt      = rec.records[pk]
            local goalAmt  = goal and goal.goldAmount or 0
            local hfrac    = (goalAmt > 0) and math.min(1, amt / goalAmt) or 1
            local hcolor   = Utils.StatusColor(hfrac)
            local hcolorHex = string.format("|cff%02x%02x%02x", hcolor[1]*255, hcolor[2]*255, hcolor[3]*255)

            local row = AceGUI:Create("SimpleGroup")
            row:SetLayout("Flow")
            row:SetFullWidth(true)
            row:SetHeight(26)
            container:AddChild(row)

            Utils.SetFrameColor(row.frame, hcolor[1], hcolor[2], hcolor[3], 0.20, row)

            local iconLbl = AceGUI:Create("Label")
            iconLbl:SetText(hcolorHex .. "●|r")
            iconLbl:SetWidth(22)
            row:AddChild(iconLbl)

            local periodLbl = AceGUI:Create("Label")
            periodLbl:SetText(Utils.PeriodLabel(pk))
            periodLbl:SetWidth(200)
            row:AddChild(periodLbl)

            local amtLbl = AceGUI:Create("Label")
            amtLbl:SetText(Utils.FormatMoneyShort(amt))
            amtLbl:SetRelativeWidth(1.0)
            row:AddChild(amtLbl)
        end

        if #periods == 0 then
            local empty = AceGUI:Create("Label")
            empty:SetText("|cffaaaaaaNo donation history yet.|r")
            empty:SetFullWidth(true)
            container:AddChild(empty)
        end
    else
        local empty = AceGUI:Create("Label")
        empty:SetText("|cffaaaaaaNo donation history yet.|r")
        empty:SetFullWidth(true)
        container:AddChild(empty)
    end
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

function MemberView:_AddSpacer(container, height)
    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    spacer:SetHeight(height or 8)
    container:AddChild(spacer)
end
