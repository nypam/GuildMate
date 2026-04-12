-- GuildMate: Addon entry point
-- This file loads FIRST (see GuildMate.toc).
-- Creates the AceAddon object; all other files grab it via GetAddon().

local GM = LibStub("AceAddon-3.0"):NewAddon("GuildMate",
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceComm-3.0"
)

do
    local v = (GetAddOnMetadata or C_AddOns and C_AddOns.GetAddOnMetadata or function() end)("GuildMate", "Version")
    if not v or v:find("project%-version") then v = "0.4.5-dev" end
    GM.version = v
end
GM.L = LibStub("AceLocale-3.0"):GetLocale("GuildMate")

-- Minimum version we will accept data messages from. Bump this when we make
-- incompatible wire-format changes so older clients can't corrupt the DB.
-- HELLO is always accepted (so we can discover old clients' versions and
-- report them). Data messages (PROF_UPDATE, RECIPE_UPDATE, DONATION_*, etc.)
-- from senders below this version are dropped.
GM.MIN_COMPAT_VERSION = "0.4.5"

-- Parse "1.2.3" / "1.2.3-dev" / "v0.4.4" into a comparable integer key.
-- Ignores trailing -suffix; missing components default to 0.
local function _VersionKey(v)
    if type(v) ~= "string" or v == "" then return 0 end
    v = v:gsub("^v", ""):gsub("%-.*$", "")
    local a, b, c = v:match("^(%d+)%.?(%d*)%.?(%d*)")
    return (tonumber(a) or 0) * 1000000 + (tonumber(b) or 0) * 1000 + (tonumber(c) or 0)
end
GM._VersionKey = _VersionKey

-- Returns true if we should accept a data message from the given sender.
-- Policy:
--   - Self: always accepted.
--   - Known sender (we've seen their HELLO): accept iff their version is
--     >= MIN_COMPAT_VERSION.
--   - Unknown sender: REJECT. We can't verify their version, so we fire
--     an opportunistic HELLO to discover it and drop this message. The
--     sender will re-broadcast on their next real event (bank open, etc.)
--     once they've recorded our HELLO and replied with theirs. This is
--     stricter than the old accept-on-unknown policy but prevents a
--     single outdated client from polluting the guild's data.
function GM:IsSenderCompatible(sender)
    if not sender then return false end

    -- Always trust self
    local me = UnitName("player") or ""
    local rawSender = sender:match("^(.+)-[^-]+$") or sender
    if rawSender == me then return true end

    local addonUsers = self.DB and self.DB.sv and self.DB.sv.addonUsers
    if not addonUsers then
        self:_OpportunisticHello()
        return false
    end

    local realm = GetRealmName and GetRealmName() or "Unknown"
    local sn, sr = sender:match("^(.+)-(.+)$")
    sn = sn or sender
    sr = sr or realm
    local mk = self.Utils.MemberKey(sn, sr)

    local theirVersion = addonUsers[mk]
    if not theirVersion then
        -- Unknown sender: announce ourselves and drop this message.
        self:_OpportunisticHello()
        return false
    end
    return _VersionKey(theirVersion) >= _VersionKey(self.MIN_COMPAT_VERSION)
end

-- Send our HELLO to the guild so unknown senders learn who we are. Debounced
-- to 10s to avoid spamming if multiple unknown senders hit us back-to-back
-- (which is common right after a DB flush).
function GM:_OpportunisticHello()
    local lastSent = self._lastHelloSentAt or 0
    local now = GetTime()
    if (now - lastSent) < 10 then return end
    self._lastHelloSentAt = now
    C_Timer.After(1, function()
        GM:SendCommMessage("GuildMate",
            "HELLO|" .. (GM.version or "0.0.0"), "GUILD")
    end)
end

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

    local function profModule(profName)
        return { Render = function() GM.ProfessionView:RenderProfession(profName) end }
    end

    self.MainFrame:RegisterModule(
        "professions",
        "Professions",
        "Interface\\Icons\\Trade_Engineering",
        { Render = function() GM.ProfessionView:RenderOverview() end },
        {
            -- Primary Crafting
            { id = "prof_alchemy",        label = "Alchemy",        icon = "Interface\\Icons\\Trade_Alchemy",         module = profModule("Alchemy") },
            { id = "prof_blacksmithing",  label = "Blacksmithing",  icon = "Interface\\Icons\\Trade_BlackSmithing",   module = profModule("Blacksmithing") },
            { id = "prof_enchanting",     label = "Enchanting",     icon = "Interface\\Icons\\Trade_Engraving",       module = profModule("Enchanting") },
            { id = "prof_engineering",    label = "Engineering",    icon = "Interface\\Icons\\Trade_Engineering",     module = profModule("Engineering") },
            { id = "prof_jewelcrafting",  label = "Jewelcrafting",  icon = "Interface\\Icons\\INV_Misc_Gem_01",       module = profModule("Jewelcrafting") },
            { id = "prof_leatherworking", label = "Leatherworking", icon = "Interface\\Icons\\Trade_LeatherWorking",  module = profModule("Leatherworking") },
            { id = "prof_tailoring",      label = "Tailoring",       icon = "Interface\\Icons\\Trade_Tailoring",        module = profModule("Tailoring") },
            -- Primary Gathering
            { id = "prof_herbalism",      label = "Herbalism",      icon = "Interface\\Icons\\Trade_Herbalism",       module = profModule("Herbalism") },
            { id = "prof_mining",         label = "Mining",          icon = "Interface\\Icons\\Trade_Mining",           module = profModule("Mining") },
            { id = "prof_skinning",       label = "Skinning",        icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",  module = profModule("Skinning") },
            -- Secondary
            { id = "prof_cooking",        label = "Cooking",         icon = "Interface\\Icons\\INV_Misc_Food_15",       module = profModule("Cooking") },
            { id = "prof_firstaid",       label = "First Aid",       icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", module = profModule("First Aid") },
            { id = "prof_fishing",        label = "Fishing",         icon = "Interface\\Icons\\Trade_Fishing",          module = profModule("Fishing") },
        })

    self.MainFrame:RegisterModule(
        "requests",
        "Requests",
        "Interface\\Icons\\INV_Scroll_03",
        { Render = function() GM.MainFrame:_ShowComingSoon("Requests") end },
        {
            { id = "req_gold",  label = "Gold",  icon = "Interface\\Icons\\INV_Misc_Coin_01", module = { Render = function() GM.MainFrame:_ShowComingSoon("Gold Requests") end } },
            { id = "req_craft", label = "Craft", icon = "Interface\\Icons\\Trade_BlackSmithing", module = { Render = function() GM.MainFrame:_ShowComingSoon("Craft Requests") end } },
        })

    self.MainFrame:RegisterModule(
        "debug",
        "Debug",
        "Interface\\Icons\\INV_Misc_Gear_01",
        { Render = function()
            if GM.DebugView then
                GM.DebugView:Render()
            else
                GM.MainFrame:_ShowComingSoon("Debug (load error)")
            end
        end })

    -- Minimap button
    self:_CreateMinimapButton()

    -- Register in Interface → Options → AddOns
    self:_CreateOptionsPanel()

    -- Slash commands
    self:RegisterChatCommand("guildmate", "SlashCommand")
    self:RegisterChatCommand("gm", "SlashCommand")
end

-- Init comm stats early (before any SendCommMessage call)
GM._commStats = { sent = 0, received = 0, bytesSent = 0, bytesReceived = 0 }

-- Rolling buffer of recent comm events for the Debug view
GM._commHistory = {}   -- { { dir, cmd, sender, bytes, timestamp, preview }, ... }
GM._commHistoryMax = 50

-- Last-update timestamps per DB table (when data last changed via comm)
GM._lastUpdates = {}   -- { [tableName] = timestamp }

local function _RecordCommEvent(dir, message, sender)
    local cmd = message and message:match("^([%w_]+)") or "?"
    local preview = message or ""
    if #preview > 120 then preview = preview:sub(1, 117) .. "..." end

    table.insert(GM._commHistory, 1, {
        dir       = dir,
        cmd       = cmd,
        sender    = sender or "?",
        bytes     = message and #message or 0,
        timestamp = time(),
        preview   = preview,
    })
    while #GM._commHistory > GM._commHistoryMax do
        table.remove(GM._commHistory)
    end

    -- Track last update for the table this command affects
    if cmd == "DONATION_BATCH" or cmd == "DONATION_TOTAL"
       or cmd == "DEPOSIT" or cmd == "DEPOSIT_BATCH" then
        GM._lastUpdates.donations = time()
    elseif cmd == "PROF_UPDATE" then
        GM._lastUpdates.professions = time()
    elseif cmd == "RECIPE_UPDATE" then
        GM._lastUpdates.recipes2 = time()
    elseif cmd == "GOAL" or cmd == "GOAL_UPDATE" then
        GM._lastUpdates.goals = time()
    elseif cmd == "HELLO" then
        GM._lastUpdates.addonUsers = time()
    end
end
GM._RecordCommEvent = _RecordCommEvent

function GM:OnEnable()
    self.Events:Register()

    -- Wrap SendCommMessage to track outgoing comm stats + history
    local origSend = self.SendCommMessage
    self.SendCommMessage = function(self, prefix, message, ...)
        if prefix == "GuildMate" and self._commStats then
            self._commStats.sent = self._commStats.sent + 1
            self._commStats.bytesSent = self._commStats.bytesSent + #message
            if GM._RecordCommEvent then
                GM._RecordCommEvent("out", message, UnitName("player") or "?")
            end
        end
        return origSend(self, prefix, message, ...)
    end
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

    elseif input == "backup" then
        GM.DB:BackupDonations("manual")
        self:Print("|cff4A90D9GuildMate:|r Donation history backed up.")

    elseif input == "backups" or input == "listbackups" then
        local list = GM.DB:ListDonationBackups()
        if #list == 0 then
            self:Print("|cff4A90D9GuildMate:|r No backups yet.")
        else
            self:Print("|cff4A90D9GuildMate backups:|r")
            for _, b in ipairs(list) do
                self:Print(string.format("  [%d]  %s  %d members  (%s)",
                    b.slot, date("%Y-%m-%d %H:%M", b.timestamp), b.count, b.reason))
            end
            self:Print("|cffaaaaaaUse /gm restore <slot> to restore a backup|r")
        end

    elseif input:match("^restore") then
        local slot = tonumber(input:match("^restore%s+(%d+)$")) or 1
        local ok, ts, reason = GM.DB:RestoreDonations(slot)
        if ok then
            self:Print(string.format("|cff5fba47GuildMate:|r Restored backup from %s (%s)",
                date("%Y-%m-%d %H:%M", ts), reason))
            self.MainFrame:RefreshActiveView()
        else
            self:Print("|cffcc3333GuildMate:|r Backup slot " .. slot .. " does not exist.")
        end

    elseif input:match("^rescan") then
        local days = tonumber(input:match("^rescan%s+(%d+)$")) or 3
        if not _G["GuildBankFrame"] or not GuildBankFrame:IsShown() then
            self:Print("|cffcc3333GuildMate:|r Guild bank must be open to rescan.")
        else
            GM.Donations:RescanRecent(days)
            self:Print(string.format("|cff5fba47GuildMate:|r Rescanned last %d day(s) from bank log.", days))
            self.MainFrame:RefreshActiveView()
        end
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
    elseif input == "commtest" then
        if self._commDebug then
            self._commDebug = false
            self:Print("|cff4A90D9GuildMate:|r Comm debug |cffcc3333OFF|r")
        else
            self._commDebug = true
            self:Print("|cff4A90D9GuildMate:|r Comm debug |cff5fba47ON|r. Sending PING to guild...")
            GM:SendCommMessage("GuildMate", "PING|" .. (UnitName("player") or "?"), "GUILD")
            self:Print("Waiting for responses... (type /gm commtest again to turn off)")
        end

    elseif input == "sync" then
        self:Print("|cff4A90D9GuildMate:|r Sending sync request to guild...")

        -- Broadcast HELLO so others share their data back
        GM:SendCommMessage("GuildMate", "HELLO|" .. (GM.version or "0.0.0"), "GUILD")

        -- Broadcast our own data
        local goal = GM.DB:GetActiveGoal()
        if goal and GM.Donations and GM.Donations.BroadcastGoal then
            GM.Donations:BroadcastGoal(goal)
            self:Print("  → Goal broadcasted: " .. GM.Utils.FormatMoneyShort(goal.goldAmount) .. " " .. goal.period)
        else
            self:Print("  → No active goal to broadcast")
        end

        if GM.Donations and GM.Donations.BroadcastKnownTotals then
            GM.Donations:BroadcastKnownTotals()
            self:Print("  → Donation totals broadcasted (aggregated, for older clients)")
        end

        if GM.Donations and GM.Donations.BroadcastDonationLog then
            GM.Donations:BroadcastDonationLog(60)
            self:Print("  → Donation events broadcasted (last 60 days)")
        end

        if GM.Professions and GM.Professions.ScanSelf then
            GM.Professions:ScanSelf()
            self:Print("  → Professions broadcasted")
        end

        if GM.Professions and GM.Professions.BroadcastRecipes and GM.DB.sv.recipes2 then
            local myName = UnitName("player") or "Unknown"
            local myRealm = GetRealmName and GetRealmName() or "Unknown"
            local myKey = GM.Utils.MemberKey(myName, myRealm)
            local recipeCount = 0
            for profName in pairs(GM.DB.sv.recipes2) do
                GM.Professions:BroadcastRecipes(myKey, profName)
                recipeCount = recipeCount + 1
            end
            self:Print("  → Recipes broadcasted (" .. recipeCount .. " professions)")
        end

        self:Print("|cff5fba47Sync complete.|r Other online members will receive your data shortly.")

    elseif input == "status" then
        -- Debug: show what's in the local DB
        local goal = GM.DB:GetActiveGoal()
        self:Print("|cff4A90D9GuildMate status:|r")
        if goal then
            self:Print("  Goal: " .. GM.Utils.FormatMoneyShort(goal.goldAmount) .. " " .. goal.period .. " (id=" .. goal.id .. ")")
        else
            self:Print("  Goal: |cffcc3333NONE|r")
        end

        local donationCount = 0
        if GM.DB.sv.donations then
            for _ in pairs(GM.DB.sv.donations) do donationCount = donationCount + 1 end
        end
        self:Print("  Donation records: " .. donationCount)

        local profCount = 0
        if GM.DB.sv.professions then
            for _ in pairs(GM.DB.sv.professions) do profCount = profCount + 1 end
        end
        self:Print("  Profession records: " .. profCount)

        local recipeProfs = 0
        if GM.DB.sv.recipes2 then
            for _ in pairs(GM.DB.sv.recipes2) do recipeProfs = recipeProfs + 1 end
        end
        self:Print("  Recipe professions: " .. recipeProfs)

        local addonUsers = GM.Donations and GM.Donations:GetAddonUsers() or {}
        local addonCount = 0
        for _ in pairs(addonUsers) do addonCount = addonCount + 1 end
        self:Print("  Addon users known: " .. addonCount)

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
        title:SetText(GM.L["ADDON_TITLE"])

        local ver = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
        ver:SetText("|cffaaaaaav" .. (GM.version or "0.1.0") .. "  ·  TBC Anniversary|r")
        y = y - 38

        local desc = self:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", LEFT, y)
        desc:SetPoint("RIGHT", self, "RIGHT", RIGHT_MARGIN, 0)
        desc:SetJustifyH("LEFT")
        desc:SetText(GM.L["OPTIONS_DESC"])

        -- Open GuildMate button — anchored below the description with spacing
        local openBtn = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
        openBtn:SetSize(160, 24)
        openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)
        openBtn:SetText(GM.L["OPEN_GUILDMATE"])
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
        remindCb.Text:SetText(GM.L["LOGIN_REMINDER_DESC"])
        remindCb:SetScript("OnClick", function(cb)
            GM.DB:SetSetting("reminderEnabled", cb:GetChecked())
            PlaySound(856)
        end)
        lastWidget = remindCb

        -- Goal Met Announcement
        local goalMetCb = CreateFrame("CheckButton", nil, self, "InterfaceOptionsCheckButtonTemplate")
        goalMetCb:SetPoint(Below(4))
        goalMetCb:SetChecked(GM.DB:GetSetting("goalMetAnnounce"))
        goalMetCb.Text:SetText(GM.L["GOAL_MET_DESC"])
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
            officerTitle:SetText("|cffd4af37" .. GM.L["GOAL_MANAGEMENT"] .. "|r")
            lastWidget = officerTitle

            -- Goal Management Ranks
            local rankDesc = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rankDesc:SetPoint(Below(4))
            rankDesc:SetText("|cffaaaaaa" .. GM.L["GOAL_MGMT_DESC"] .. "|r")
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
            chanLabel:SetText("|cffaaaaaa" .. GM.L["ANNOUNCE_CHANNEL_DESC"] .. "|r")
            lastWidget = chanLabel

            local channels = {
                { value = "GUILD",   label = "GUILD_CHAT"   },
                { value = "OFFICER", label = "OFFICER_CHAT"  },
                { value = "OFF",     label = "OFF"           },
            }
            local currentChan = GM.DB:GetSetting("announceChannel") or "GUILD"
            local chanBtns = {}

            for _, ch in ipairs(channels) do
                local cb = CreateFrame("CheckButton", nil, self, "InterfaceOptionsCheckButtonTemplate")
                cb:SetPoint(Below(0))
                cb:SetChecked(currentChan == ch.value)
                cb.Text:SetText(GM.L[ch.label])
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
        note:SetText("|cffaaaaaa" .. GM.L["SETTINGS_AUTO_SAVE"] .. "|r")
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

    -- Track comm stats
    self._commStats.received = self._commStats.received + 1
    self._commStats.bytesReceived = self._commStats.bytesReceived + #message

    -- Record in history buffer for the Debug view
    _RecordCommEvent("in", message, sender)

    -- Comm debug logging
    if self._commDebug then
        local dbgCmd = message and message:match("^([%w_]+)") or "?"
        self:Print(string.format("|cff888888[comm in]|r %s from %s (%d bytes)", dbgCmd, tostring(sender), #message))
    end

    -- PING/PONG for comm testing
    local cmd = message and message:match("^([%w_]+)")
    if cmd == "PING" then
        GM:SendCommMessage("GuildMate", "PONG|" .. (UnitName("player") or "?"), "GUILD")
        return
    elseif cmd == "PONG" then
        local _, who = message:match("^(%w+)|(.+)$")
        self:Print("|cff5fba47[comm]|r PONG received from " .. tostring(who or sender))
        return
    end

    -- Version gate: HELLO is always allowed (so we can learn the sender's
    -- version). Every other message requires the sender's tracked version
    -- to be >= MIN_COMPAT_VERSION. Without this, an outdated client on a
    -- guildie's alt can flood our DB with stale-format messages.
    if cmd ~= "HELLO" and not self:IsSenderCompatible(sender) then
        if self._commDebug then
            self:Print("|cffcc3333[comm]|r dropped " .. tostring(cmd) .. " from outdated/unknown sender " .. tostring(sender))
        end
        return
    end

    -- Per-sender rate limit: cap how many messages of each command type we
    -- accept from a single sender in a sliding window. Runaway old clients
    -- (e.g. ones that spam DONATION_TOTAL every second) still get rejected
    -- even if their version technically passes the gate.
    --
    -- Caps chosen generously enough not to affect normal operation:
    --   DONATION_TOTAL / DONATION_BATCH / DEPOSIT / DEPOSIT_BATCH: 6 / 60s
    --   RECIPE_UPDATE / PROF_UPDATE: 3 / 60s
    --   GOAL / GOAL_UPDATE: 4 / 60s
    --   Everything else: no per-sender cap
    if cmd and sender then
        local now = GetTime()
        self._rateLimits = self._rateLimits or {}
        local caps = {
            DONATION_TOTAL = 6, DONATION_BATCH = 6,
            DEPOSIT = 20, DEPOSIT_BATCH = 4,
            RECIPE_UPDATE = 3, PROF_UPDATE = 3,
            GOAL = 4, GOAL_UPDATE = 4,
        }
        local cap = caps[cmd]
        if cap then
            local bucketKey = sender .. ":" .. cmd
            local bucket = self._rateLimits[bucketKey]
            if not bucket or (now - bucket.start) > 60 then
                bucket = { start = now, count = 0 }
                self._rateLimits[bucketKey] = bucket
            end
            bucket.count = bucket.count + 1
            if bucket.count > cap then
                if self._commDebug then
                    self:Print(string.format(
                        "|cffcc3333[comm]|r rate-limited %s from %s (%d > %d/60s)",
                        cmd, tostring(sender), bucket.count, cap))
                end
                return
            end
        end
    end

    if GM.Donations and GM.Donations.OnCommReceived then
        GM.Donations:OnCommReceived(message, channel, sender)
    end
    if GM.Professions and GM.Professions.OnCommReceived then
        GM.Professions:OnCommReceived(message, channel, sender)
    end
end
