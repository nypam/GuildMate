-- GuildMate: Central event hub
-- All WoW event registrations live here; handlers are dispatched to modules.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Events = {}
GM.Events = Events

-- Called from GM:OnEnable()
function Events:Register()
    -- Guild roster refreshed
    GM:RegisterEvent("GUILD_ROSTER_UPDATE", Events.OnGuildRosterUpdate)

    -- Player just logged in / UI loaded
    GM:RegisterEvent("PLAYER_LOGIN", Events.OnPlayerLogin)

    -- GuildBankFrame is created at an unpredictable time (demand-loaded before our addon
    -- can hook GuildBankFrame_LoadUI). Poll every second until the frame appears, then
    -- hook OnShow/OnHide once and stop polling.
    local _pollCount = 0
    local function _PollForBankFrame()
        if _G["GuildBankFrame"] then
            if not GuildBankFrame._gmHooked then
                GuildBankFrame._gmHooked = true
                GuildBankFrame:HookScript("OnShow", Events.OnGuildBankOpened)
                GuildBankFrame:HookScript("OnHide", Events.OnGuildBankClosed)
            end
            -- If bank is already open when we find the frame, trigger immediately
            if GuildBankFrame:IsShown() and not GM.Events._bankOpen then
                Events.OnGuildBankOpened()
            end
        elseif _pollCount < 7200 then  -- give up after 2 hours (won't reach this)
            _pollCount = _pollCount + 1
            C_Timer.After(1, _PollForBankFrame)
        end
    end
    C_Timer.After(1, _PollForBankFrame)

    -- Money balance changed while bank is open → request fresh log
    pcall(function()
        GM:RegisterEvent("GUILDBANK_UPDATE_MONEY", Events.OnGuildBankMoneyUpdate)
    end)

    -- Log data arrived from the server → now safe to read transactions
    pcall(function()
        GM:RegisterEvent("GUILD_BANK_LOG_UPDATE", Events.OnGuildBankLogUpdate)
    end)
end

-- ── Handlers ─────────────────────────────────────────────────────────────────

function Events.OnPlayerLogin()
    -- GUILD_ROSTER_UPDATE fires automatically on login in TBC Anniversary.

    -- Re-broadcast the active goal so other guild members pick it up.
    -- Delay 8s to let roster/comm settle before sending.
    C_Timer.After(8, function()
        local _, _, playerRankIndex = GetGuildInfo("player")
        if not GM.DB:IsOfficerRank(playerRankIndex or 99) then return end

        local goal = GM.DB:GetActiveGoal()
        if goal and GM.Donations then
            GM.Donations:BroadcastGoal(goal)
        end
    end)

    -- Auto-remind: show a local reminder if this player hasn't met the goal.
    -- Delay 10s so guild info and goal sync have time to settle.
    C_Timer.After(10, function()
        if not GM.DB:GetSetting("reminderEnabled") then return end

        local goal = GM.DB:GetActiveGoal()
        if not goal then return end

        local playerName = UnitName("player") or ""
        local realm      = GetRealmName and GetRealmName() or ""
        local playerKey  = GM.Utils.MemberKey(playerName, realm)
        local periodKey  = GM.Utils.PeriodKey(time(), goal.period)
        local donated    = GM.DB:GetDonated(playerKey, periodKey)

        if donated < goal.goldAmount then
            local remaining = goal.goldAmount - donated
            GM:Print(string.format(
                "|cffd9a400Reminder:|r You still need to donate %s to meet the %s goal of %s.",
                GM.Utils.FormatMoneyShort(remaining),
                goal.period,
                GM.Utils.FormatMoneyShort(goal.goldAmount)))
        end
    end)
end

function Events.OnGuildRosterUpdate()
    if GM.Donations and GM.Donations.OnRosterUpdate then
        GM.Donations:OnRosterUpdate()
    end
    if GM.MainFrame then
        GM.MainFrame:RefreshActiveView()
    end
end

-- Request the money log from the server. The money tab is one past the item tabs.
local function _RequestMoneyLog()
    local moneyTab = (GUILD_BANK_MAX_TABS or 6) + 1
    if QueryGuildBankLog then
        QueryGuildBankLog(moneyTab)
    end
end

-- Try to read the log. Called from events and timer fallbacks.
local function _TryProcessLog()
    if GM.Events._bankOpen and GM.Donations and GM.Donations.ProcessTransactionLog then
        GM.Donations:ProcessTransactionLog()
    end
end

function Events.OnGuildBankOpened()
    if GM.Events._bankOpen then return end  -- guard against double-trigger
    GM.Events._bankOpen = true
    -- Ask the server to send money log data
    _RequestMoneyLog()
    -- Timer fallback: GUILD_BANK_LOG_UPDATE may not fire in TBC Anniversary
    C_Timer.After(1, _TryProcessLog)
    C_Timer.After(3, _TryProcessLog)
end

function Events.OnGuildBankClosed()
    GM.Events._bankOpen = false
end

function Events.OnGuildBankMoneyUpdate()
    if GM.Events._bankOpen then
        _RequestMoneyLog()
        -- Timer fallback in case the log update event doesn't fire
        C_Timer.After(1, _TryProcessLog)
        C_Timer.After(3, _TryProcessLog)
    end
end

function Events.OnGuildBankLogUpdate()
    _TryProcessLog()
end
