-- GuildMate: Addon entry point
-- This file loads FIRST (see GuildMate.toc).
-- Creates the AceAddon object; all other files grab it via GetAddon().

local GM = LibStub("AceAddon-3.0"):NewAddon("GuildMate",
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceComm-3.0"
)

GM.version = "0.1.0"
GM.L = LibStub("AceLocale-3.0"):GetLocale("GuildMate")

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function GM:OnInitialize()
    -- Merge SavedVariables with defaults
    self.DB:Init()

    -- Register addon message prefix for guild-wide sync (max 16 chars)
    self:RegisterComm("GuildMate")

    -- Register modules into the sidebar (order = display order)
    self.MainFrame:RegisterModule(
        "donations",
        "Donations",
        "Interface\\Icons\\INV_Misc_Coin_01",
        self.Donations)

    -- Minimap button
    self:_CreateMinimapButton()

    -- Register in Interface → Options → AddOns
    self:_CreateOptionsPanel()

    -- Slash commands
    self:RegisterChatCommand("guildmate", "SlashCommand")
    self:RegisterChatCommand("gm", "SlashCommand")
end

function GM:OnEnable()
    self.Events:Register()
    -- GUILD_ROSTER_UPDATE fires automatically; no manual request needed in TBC Anniversary.
end

function GM:OnDisable()
    -- Nothing to tear down; AceEvent handles deregistration automatically
end

-- ── Slash command handler ─────────────────────────────────────────────────────

function GM:SlashCommand(input)
    input = input and input:trim():lower() or ""

    if input == "" or input == "show" then
        self.MainFrame:Toggle()
    elseif input == "donations" then
        self.MainFrame:Show()
        -- TODO: Switch sidebar to donations tab
    elseif input == "testbank" then
        -- Open the guild bank, then type this to force-scan
        self:Print("GuildBankFrame exists: " .. tostring(_G["GuildBankFrame"] ~= nil))
        if _G["GuildBankFrame"] then
            self:Print("IsShown: " .. tostring(GuildBankFrame:IsShown()))
            self:Print("_gmHooked: " .. tostring(GuildBankFrame._gmHooked))
        end
        self:Print("_bankOpen: " .. tostring(GM.Events._bankOpen))
        GM.Events._bankOpen = true
        -- Request fresh log data before processing
        local moneyTab = (GUILD_BANK_MAX_TABS or 6) + 1
        if QueryGuildBankLog then
            QueryGuildBankLog(moneyTab)
            self:Print("QueryGuildBankLog(" .. moneyTab .. ") called.")
        else
            self:Print("QueryGuildBankLog not available.")
        end
        -- Process immediately + delayed retry
        GM.Donations:ProcessTransactionLog()
        C_Timer.After(2, function() GM.Donations:ProcessTransactionLog() end)
    elseif input == "debug" then
        self.debugOfficer = not self.debugOfficer
        self:Print(self.debugOfficer and GM.L["DEBUG_OFFICER_ON"] or GM.L["DEBUG_OFFICER_OFF"])
        self.MainFrame:RefreshActiveView()
    elseif input == "scanlog" then
        local out = {}

        -- All GetGuildBank* globals
        local fns = {}
        for k, v in pairs(_G) do
            if type(k) == "string" and k:find("GuildBank") and type(v) == "function" then
                fns[#fns+1] = k
            end
        end
        table.sort(fns)
        out[#out+1] = "=== GuildBank functions ==="
        for _, k in ipairs(fns) do out[#out+1] = k end

        -- Money transaction count (no tab arg needed)
        if type(_G["GetNumGuildBankMoneyTransactions"]) == "function" then
            out[#out+1] = "GetNumGuildBankMoneyTransactions() = " .. tostring(GetNumGuildBankMoneyTransactions())
        end

        -- Dump first money transaction
        if type(_G["GetGuildBankMoneyTransaction"]) == "function" then
            out[#out+1] = "=== GetGuildBankMoneyTransaction(1) ==="
            local a,b,c,d,e,f,g = GetGuildBankMoneyTransaction(1)
            out[#out+1] = table.concat({tostring(a),tostring(b),tostring(c),tostring(d),tostring(e),tostring(f),tostring(g)}, " | ")
        end

        -- Save to SavedVariables and print path
        GuildMateDB.debugScan = out
        self:Print("|cff4A90D9GuildMate:|r Scan saved. Do /reload then open:")
        self:Print("|cffffd700WTF/Account/<name>/SavedVariables/GuildMate.lua|r")
        self:Print("Look for debugScan = { ... } near the top.")
    elseif input == "help" then
        self:Print(GM.L["CMD_HELP_HEADER"])
        self:Print(GM.L["CMD_HELP_TOGGLE"])
        self:Print(GM.L["CMD_HELP_DONATIONS"])
        self:Print(GM.L["CMD_HELP_DEBUG"])
        self:Print(GM.L["CMD_HELP_SCANLOG"])
        self:Print(GM.L["CMD_HELP_HELP"])
    else
        self:Print(GM.L["CMD_UNKNOWN"])
    end
end

-- ── Interface Options panel ───────────────────────────────────────────────────
-- Registers GuildMate in ESC → Interface → AddOns so users can find it.
-- TBC Anniversary uses the old InterfaceOptions_AddCategory API.

function GM:_CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "GuildMate"

    -- Build content when the panel is first shown
    local built = false
    panel:SetScript("OnShow", function(self)
        if built then return end
        built = true

        local y = -16   -- running Y offset from top
        local LEFT = 16
        local RIGHT_MARGIN = -16

        -- ── About section ────────────────────────────────────────────────────
        local title = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", LEFT, y)
        title:SetText("|cff4A90D9Guild|rMate")

        local ver = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
        ver:SetText("|cffaaaaaav" .. (GM.version or "0.1.0") .. "  ·  TBC Anniversary|r")
        y = y - 38

        local desc = self:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", LEFT, y)
        desc:SetPoint("RIGHT", self, "RIGHT", RIGHT_MARGIN, 0)
        desc:SetJustifyH("LEFT")
        desc:SetText(
            "|cff4A90D9GuildMate|r helps guild leaders and officers track member donations " ..
            "to the guild bank.\n\n" ..
            "|cffd4af37How it works:|r Officers set a gold donation goal (weekly or monthly) " ..
            "for selected ranks. When any guild member opens the guild bank, the addon reads " ..
            "the last 25 money transactions and records deposits automatically. Totals sync " ..
            "across all guild members who have the addon installed.\n\n" ..
            "Officers see the full roster with colour-coded donation status, and can send " ..
            "reminders or announcements. Members see their own progress and history.\n\n" ..
            "Use |cffffd700/gm|r to open the main window, or click the minimap button.")

        -- Open GuildMate button — anchored below the description with spacing
        local openBtn = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
        openBtn:SetSize(160, 24)
        openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)
        openBtn:SetText("Open GuildMate")
        openBtn:SetScript("OnClick", function()
            PlaySound(856)
            GM.MainFrame:Show()
        end)

        -- ── Divider ──────────────────────────────────────────────────────────
        local divider = self:CreateTexture(nil, "ARTWORK")
        divider:SetHeight(1)
        divider:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -10)
        divider:SetPoint("RIGHT", self, "RIGHT", RIGHT_MARGIN, 0)
        divider:SetColorTexture(0.3, 0.3, 0.3, 0.6)

        -- ── Settings section ─────────────────────────────────────────────────
        -- Anchor everything below the divider using relative points so the
        -- layout adapts to the description text height automatically.

        local settingsTitle = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        settingsTitle:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -10)
        settingsTitle:SetText("|cffd4af37Settings|r")

        -- Use y-offset tracking relative to settingsTitle from here
        local lastWidget = settingsTitle
        local function Below(gap) return "TOPLEFT", lastWidget, "BOTTOMLEFT", 0, -(gap or 6) end

        -- Login Reminder
        local remindCb = CreateFrame("CheckButton", nil, self, "InterfaceOptionsCheckButtonTemplate")
        remindCb:SetPoint(Below(8))
        remindCb:SetChecked(GM.DB:GetSetting("reminderEnabled"))
        remindCb.Text:SetText("Show a reminder on login if I haven't met the donation goal")
        remindCb:SetScript("OnClick", function(cb)
            GM.DB:SetSetting("reminderEnabled", cb:GetChecked())
            PlaySound(856)
        end)
        lastWidget = remindCb

        -- Goal Met Announcement
        local goalMetCb = CreateFrame("CheckButton", nil, self, "InterfaceOptionsCheckButtonTemplate")
        goalMetCb:SetPoint(Below(4))
        goalMetCb:SetChecked(GM.DB:GetSetting("goalMetAnnounce"))
        goalMetCb.Text:SetText("Announce in guild chat when a member meets the donation goal")
        goalMetCb:SetScript("OnClick", function(cb)
            GM.DB:SetSetting("goalMetAnnounce", cb:GetChecked())
            PlaySound(856)
        end)
        lastWidget = goalMetCb

        -- ── Officer-only settings ────────────────────────────────────────────
        local _, _, playerRankIndex = GetGuildInfo("player")
        local isOfficer = GM.debugOfficer or GM.DB:IsOfficerRank(playerRankIndex or 99)

        if isOfficer then
            local officerTitle = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            officerTitle:SetPoint(Below(12))
            officerTitle:SetText("|cffd4af37Goal Management|r")
            lastWidget = officerTitle

            -- Goal Management Ranks
            local rankDesc = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rankDesc:SetPoint(Below(4))
            rankDesc:SetText("|cffaaaaaaRanks that can create, edit and delete donation goals:|r")
            lastWidget = rankDesc

            local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
            for i = 0, numRanks - 1 do
                local rankName = (GuildControlGetRankName and GuildControlGetRankName(i + 1)) or ("Rank " .. i)
                local cb = CreateFrame("CheckButton", nil, self, "InterfaceOptionsCheckButtonTemplate")
                cb:SetPoint(Below(0))
                cb:SetChecked(GM.DB:IsOfficerRank(i))
                cb.Text:SetText(rankName)
                if i == 0 then
                    cb:Disable()
                    cb.Text:SetTextColor(0.5, 0.5, 0.5)
                else
                    local idx = i
                    cb:SetScript("OnClick", function(self)
                        GM.DB.sv.settings.officerRanks[idx] = self:GetChecked() or nil
                        PlaySound(856)
                    end)
                end
                lastWidget = cb
            end

            -- Announce Channel
            local chanLabel = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            chanLabel:SetPoint(Below(10))
            chanLabel:SetText("|cffaaaaaaAnnounce progress to:|r")
            lastWidget = chanLabel

            local channels = {
                { value = "GUILD",   label = "Guild Chat"   },
                { value = "OFFICER", label = "Officer Chat"  },
                { value = "OFF",     label = "Off"           },
            }
            local currentChan = GM.DB:GetSetting("announceChannel") or "GUILD"
            local chanBtns = {}

            for _, ch in ipairs(channels) do
                local cb = CreateFrame("CheckButton", nil, self, "InterfaceOptionsCheckButtonTemplate")
                cb:SetPoint(Below(0))
                cb:SetChecked(currentChan == ch.value)
                cb.Text:SetText(ch.label)
                local chValue = ch.value
                cb:SetScript("OnClick", function()
                    GM.DB:SetSetting("announceChannel", chValue)
                    for _, other in ipairs(chanBtns) do
                        other:SetChecked(other == cb)
                    end
                    PlaySound(856)
                end)
                chanBtns[#chanBtns + 1] = cb
                lastWidget = cb
            end
        end

        -- ── Footer note ──────────────────────────────────────────────────────
        local note = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        note:SetPoint(Below(12))
        note:SetText("|cffaaaaaa Settings are saved automatically.|r")
    end)

    -- Register with the Interface Options system
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name, panel.name)
        cat.ID = panel.name
        Settings.RegisterAddOnCategory(cat)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    self._optionsPanel = panel
end

-- ── Minimap button ────────────────────────────────────────────────────────────

function GM:_CreateMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1")
    local LDBIcon = LibStub("LibDBIcon-1.0")

    local broker = LDB:NewDataObject("GuildMate", {
        type  = "launcher",
        label = "GuildMate",
        icon  = "Interface\\Icons\\INV_Misc_Note_06",
        OnClick = function(_, button)
            if button == "LeftButton" then
                GM.MainFrame:Toggle()
            elseif button == "RightButton" then
                -- Future: open settings directly
                GM.MainFrame:Toggle()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine(GM.L["ADDON_TITLE"])
            tt:AddLine(GM.L["MINIMAP_LEFT_CLICK"], 1, 1, 1)
        end,
    })

    -- minimapData must be a SavedVariable sub-table for LibDBIcon
    local db = GM.DB.sv.settings
    if not db.minimapData then
        db.minimapData = { hide = false, minimapPos = db.minimapPos or 45 }
    end

    LDBIcon:Register("GuildMate", broker, db.minimapData)
end

-- ── Addon message handler (AceComm) ──────────────────────────────────────────

function GM:OnCommReceived(prefix, message, channel, sender)
    if prefix ~= "GuildMate" then return end
    if sender == UnitName("player") then return end  -- ignore our own messages

    if GM.Donations and GM.Donations.OnCommReceived then
        GM.Donations:OnCommReceived(message, channel, sender)
    end
end
