-- GuildMate: Donation tracking core
-- Parses guild bank money-log transactions and accumulates per-member totals.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Utils = GM.Utils

local Donations = {}
GM.Donations = Donations

-- ── Roster cache ──────────────────────────────────────────────────────────────

-- [memberKey] = { name, realm, rankIndex, classFilename, online }
local _roster = {}

function Donations:OnRosterUpdate()
    -- Good moment to evict expired fingerprints (runs at most once per session)
    if not Donations._prunedThisSession then
        GM.DB:PruneSeenTransactions()
        Donations._prunedThisSession = true
    end
    wipe(_roster)
    local realm = GetRealmName and GetRealmName() or "Unknown"
    local count = GetNumGuildMembers()
    for i = 1, count do
        local name, _, rankIndex, _, _, _, _, _, online, _, classFilename = GetGuildRosterInfo(i)
        if name then
            -- GetGuildRosterInfo may return "Name-Realm" for cross-realm; split if needed
            local pname, prealm = name:match("^(.+)-(.+)$")
            pname  = pname  or name
            prealm = prealm or realm
            local key = Utils.MemberKey(pname, prealm)
            _roster[key] = {
                name          = pname,
                realm         = prealm,
                rankIndex     = rankIndex,
                classFilename = classFilename or "WARRIOR",
                online        = online,
            }
            GM.DB:SetMemberRank(key, rankIndex)
        end
    end
end

-- Returns a snapshot of the roster (read-only)
function Donations:GetRoster()
    return _roster
end

-- ── Transaction log parsing ───────────────────────────────────────────────────

function Donations:ProcessTransactionLog()
    -- TBC Anniversary API: GetGuildBankMoneyTransaction(index) for money log.
    -- (GetGuildBankTransactionInfo does not exist in this build.)
    local getMoneyTx = _G["GetGuildBankMoneyTransaction"]

    if not getMoneyTx then
        GM:Print("|cff4A90D9GuildMate debug:|r GetGuildBankMoneyTransaction is nil — bank not open yet?")
        return
    end

    local goal    = GM.DB:GetActiveGoal()
    local realm   = GetRealmName and GetRealmName() or "Unknown"
    local changed = false

    -- GetNumGuildBankMoneyTransactions() returns 0 even when data exists in TBC Anniversary.
    -- Just iterate up to 25 and break on nil — same as the raw log cap.
    GM:Print("|cff4A90D9GuildMate debug:|r ProcessTransactionLog running.")

    for i = 1, 25 do
        -- Money transaction signature: txType, name, amount, year, month, day, hour
        -- year/month/day/hour are how-long-ago offsets; 0 = just now.
        local txType, name, amount, year, month, day, hour = getMoneyTx(i)

        if not txType then break end

        if txType == "deposit" and name and amount and amount > 0
           and year ~= nil and month ~= nil and day ~= nil and hour ~= nil then

            local fp = string.format("%s|%d|%d|%d|%d|%d",
                name, amount, year, month, day, math.floor(hour))

            if not GM.DB:HasSeenTransaction(fp) then
                GM.DB:MarkTransactionSeen(fp)

                local approxTs  = time() - (year * 365 * 86400) - (month * 30 * 86400)
                                         - (day * 86400) - (math.floor(hour) * 3600)
                local periodType = goal and goal.period or "weekly"
                local periodKey  = Utils.PeriodKey(approxTs, periodType)
                local memberKey  = Utils.MemberKey(name, realm)

                local newTotal = GM.DB:AddDonation(memberKey, periodKey, amount)
                changed = true

                GM:SendCommMessage("GuildMate",
                    string.format("DONATION_TOTAL|%s|%s|%d", memberKey, periodKey, newTotal),
                    "GUILD")

                GM:Print(string.format("|cff4A90D9GuildMate:|r Recorded %s deposit by %s (%s)",
                    Utils.FormatMoney(amount), name, Utils.PeriodLabel(periodKey)))
            end
        end
    end

    if changed then
        GM.MainFrame:RefreshActiveView()
    end
end

-- ── Comm handler ─────────────────────────────────────────────────────────────

function Donations:OnCommReceived(message)
    -- DONATION_TOTAL carries the sender's known running total for a member+period.
    -- We take max(ours, theirs) — safe to receive multiple times.
    local cmd, memberKey, periodKey, totalStr = message:match("^(%w+)|(.+)|(.+)|(%d+)$")

    if cmd == "DONATION_TOTAL" then
        local total = tonumber(totalStr)
        if memberKey and periodKey and total then
            GM.DB:SetDonationTotal(memberKey, periodKey, total)
            GM.MainFrame:RefreshActiveView()
        end
    elseif cmd == "GOAL_UPDATE" then
        -- Future: deserialise and store updated goal from officer
    end
end

-- ── Reminder helpers ──────────────────────────────────────────────────────────

-- Whisper everyone in the target rank list who hasn't met the goal this period
function Donations:RemindIncomplete()
    local goal = GM.DB:GetActiveGoal()
    if not goal then
        GM:Print("No active donation goal set.")
        return
    end

    local periodKey = Utils.PeriodKey(time(), goal.period)
    local msg = GM.DB:GetSetting("reminderMessage")

    local count = 0
    for key, info in pairs(_roster) do
        if goal.targetRanks[info.rankIndex] then
            local donated = GM.DB:GetDonated(key, periodKey)
            if donated < goal.goldAmount then
                local whisper = msg
                whisper = whisper:gsub("%%s", info.name)
                whisper = whisper:gsub("%%g", Utils.FormatMoneyShort(goal.goldAmount))
                whisper = whisper:gsub("%%p", goal.period)
                whisper = whisper:gsub("%%d", Utils.FormatMoneyShort(donated))
                SendChatMessage(whisper, "WHISPER", nil, info.name)
                count = count + 1
            end
        end
    end

    GM:Print(string.format("|cff4A90D9GuildMate:|r Sent reminders to %d member(s).", count))
end

-- Post a progress summary to the configured channel
function Donations:AnnounceProgress()
    local goal = GM.DB:GetActiveGoal()
    if not goal then return end

    local periodKey = Utils.PeriodKey(time(), goal.period)
    local total, met = 0, 0

    for key, info in pairs(_roster) do
        if goal.targetRanks[info.rankIndex] then
            total = total + 1
            local donated = GM.DB:GetDonated(key, periodKey)
            if donated >= goal.goldAmount then met = met + 1 end
        end
    end

    local channel = GM.DB:GetSetting("announceChannel")
    if channel == "OFF" then return end

    local text = string.format(
        "[GuildMate] Donation progress (%s): %d / %d members have met the %s goal.",
        Utils.PeriodLabel(periodKey), met, total, Utils.FormatMoneyShort(goal.goldAmount))

    SendChatMessage(text, channel)
end

-- ── Module render entry point (called by MainFrame) ───────────────────────────

function Donations:Render(container)
    -- Delegate to OfficerView or MemberView depending on player rank.
    -- GM.debugOfficer = true forces OfficerView regardless of rank (toggle with /gm debug).
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex == nil then rankIndex = 99 end  -- not in guild

    if GM.debugOfficer or GM.DB:IsOfficerRank(rankIndex) then
        if GM.OfficerView then
            GM.OfficerView:Render(container)
        end
    else
        if GM.MemberView then
            GM.MemberView:Render(container)
        end
    end
end
