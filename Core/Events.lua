-- GuildMate: Central event hub
-- All WoW event registrations live here; handlers are dispatched to modules.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Events = {}
GM.Events = Events

-- How long (seconds) to wait after the bank opens before reading transaction data.
local LOG_READ_DELAY = 0.5

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

    -- Money balance changed while bank is open → re-read log
    pcall(function()
        GM:RegisterEvent("GUILDBANK_UPDATE_MONEY", Events.OnGuildBankMoneyUpdate)
    end)
end

-- ── Handlers ─────────────────────────────────────────────────────────────────

function Events.OnPlayerLogin()
    -- GUILD_ROSTER_UPDATE fires automatically on login in TBC Anniversary.

    -- Auto-remind: whisper members who haven't donated this period.
    C_Timer.After(5, function()
        if not GM.DB:GetSetting("reminderEnabled") then return end

        local goal = GM.DB:GetActiveGoal()
        if not goal then return end

        local periodKey  = GM.Utils.PeriodKey(time(), goal.period)
        local playerName = UnitName("player") or ""
        local realm      = GetRealmName and GetRealmName() or ""
        local playerKey  = GM.Utils.MemberKey(playerName, realm)

        -- Only officers send reminders
        local _, _, playerRankIndex = GetGuildInfo("player")
        if not GM.DB:IsOfficerRank(playerRankIndex or 99) then return end

        local msg = GM.DB:GetSetting("reminderMessage") or
            "Hi %s! Don't forget the %p guild donation goal of %g. You've donated %d so far."

        local roster = GM.Donations and GM.Donations:GetRoster()
        if not roster then return end

        for key, info in pairs(roster) do
            if goal.targetRanks[info.rankIndex] and key ~= playerKey then
                local donated = GM.DB:GetDonated(key, periodKey)
                if donated < goal.goldAmount and info.online then
                    local text = msg
                    text = text:gsub("%%s", info.name)
                    text = text:gsub("%%g", GM.Utils.FormatMoneyShort(goal.goldAmount))
                    text = text:gsub("%%p", goal.period)
                    text = text:gsub("%%d", GM.Utils.FormatMoneyShort(donated))
                    SendChatMessage(text, "WHISPER", nil, info.name)
                end
            end
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

function Events.OnGuildBankOpened()
    if GM.Events._bankOpen then return end  -- guard against double-trigger
    GM.Events._bankOpen = true
    C_Timer.After(LOG_READ_DELAY, function()
        if GM.Events._bankOpen and GM.Donations and GM.Donations.ProcessTransactionLog then
            GM.Donations:ProcessTransactionLog()
        end
    end)
end

function Events.OnGuildBankClosed()
    GM.Events._bankOpen = false
end

function Events.OnGuildBankMoneyUpdate()
    if GM.Events._bankOpen then
        C_Timer.After(LOG_READ_DELAY, function()
            if GM.Events._bankOpen and GM.Donations and GM.Donations.ProcessTransactionLog then
                GM.Donations:ProcessTransactionLog()
            end
        end)
    end
end
