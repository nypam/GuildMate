-- GuildMate: Addon entry point
-- This file loads FIRST (see GuildMate.toc).
-- Creates the AceAddon object; all other files grab it via GetAddon().

local GM = LibStub("AceAddon-3.0"):NewAddon("GuildMate",
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceComm-3.0"
)

GM.version = "0.1.0"

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
        self:Print("|cff4A90D9GuildMate:|r Officer view override: " ..
            (self.debugOfficer and "|cff5fba47ON|r" or "|cffcc3333OFF|r"))
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
        self:Print("|cff4A90D9GuildMate|r commands:")
        self:Print("  /gm             — Toggle main window")
        self:Print("  /gm donations   — Open Donations panel")
        self:Print("  /gm debug       — Toggle officer view override (testing)")
        self:Print("  /gm scanlog     — Dump raw bank log (open guild bank first)")
        self:Print("  /gm help        — Show this help")
    else
        self:Print("Unknown command. Type |cffffd700/gm help|r for a list.")
    end
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
            tt:AddLine("|cff4A90D9Guild|rMate")
            tt:AddLine("|cffaaaaaa Left-click|r to toggle", 1, 1, 1)
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
