-- GuildMate: Donation tracking core
-- Parses guild bank money-log transactions and accumulates per-member totals.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Utils = GM.Utils

local Donations = {}
GM.Donations = Donations

-- ── Addon presence tracking ──────────────────────────────────────────────────

-- Tracks who has GuildMate installed.
-- Persisted in SavedVariables so we remember even across sessions.
-- [memberKey] = versionString   e.g. "Thrall-Sulfuras" = "0.1.0"

function Donations:GetAddonUsers()
    if not GM.DB.sv.addonUsers then GM.DB.sv.addonUsers = {} end
    return GM.DB.sv.addonUsers
end

function Donations:SetAddonUser(memberKey, version)
    if not GM.DB.sv.addonUsers then GM.DB.sv.addonUsers = {} end
    GM.DB.sv.addonUsers[memberKey] = version
end

-- Session-local set of members whose goal-met milestone was already announced.
-- Keyed by "memberKey|periodKey" to avoid re-announcing on every bank scan.
local _announcedMilestones = {}

-- ── Roster cache ──────────────────────────────────────────────────────────────

-- [memberKey] = { name, realm, rankIndex, classFilename, online }
local _roster = {}

function Donations:OnRosterUpdate()
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

-- ── Guild-wide sync ───────────────────────────────────────────────────────────

-- Broadcast all known donation totals for the current and previous period to
-- every online guild member.  Called after every bank scan so any member who
-- opens the bank pushes their knowledge to all officers, regardless of rank.
function Donations:BroadcastKnownTotals()
    local goal       = GM.DB:GetActiveGoal()
    local periodType = goal and goal.period or "weekly"
    local prevOffset = (periodType == "weekly") and (7 * 86400) or (32 * 86400)

    local periods = {
        Utils.PeriodKey(time(), periodType),
        Utils.PeriodKey(time() - prevOffset, periodType),
    }

    for memberKey, _ in pairs(GM.DB.sv.donations) do
        for _, periodKey in ipairs(periods) do
            local total = GM.DB:GetDonated(memberKey, periodKey)
            if total > 0 then
                GM:SendCommMessage("GuildMate",
                    string.format("DONATION_TOTAL|%s|%s|%d", memberKey, periodKey, total),
                    "GUILD")
            end
        end
    end
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

    local goal       = GM.DB:GetActiveGoal()
    local realm      = GetRealmName and GetRealmName() or "Unknown"
    local periodType = goal and goal.period or "weekly"

    -- Pass 1: sum all deposits from the log, grouped by member+period.
    -- The log holds up to 25 entries. We sum everything visible rather than
    -- deduplicating by fingerprint, because identical deposits (same player,
    -- same amount, same hour) produce the same fingerprint and get lost.
    -- totals[memberKey][periodKey] = copperFromLog
    local totals = {}

    for i = 1, 25 do
        local txType, name, amount, year, month, day, hour = getMoneyTx(i)
        if not txType then break end

        if txType == "deposit" and name and amount and amount > 0
           and year ~= nil and month ~= nil and day ~= nil and hour ~= nil then

            local approxTs  = time() - (year * 365 * 86400) - (month * 30 * 86400)
                                     - (day * 86400) - (math.floor(hour) * 3600)
            local periodKey = Utils.PeriodKey(approxTs, periodType)
            local memberKey = Utils.MemberKey(name, realm)

            if not totals[memberKey] then totals[memberKey] = {} end
            totals[memberKey][periodKey] = (totals[memberKey][periodKey] or 0) + amount
        end
    end

    -- Pass 2: max-merge log totals into the DB (never decrease, only increase).
    -- This is idempotent — safe to call on every bank open / money update.
    local changed = false

    for memberKey, periods in pairs(totals) do
        for periodKey, logTotal in pairs(periods) do
            local prevTotal = GM.DB:GetDonated(memberKey, periodKey)

            if logTotal > prevTotal then
                GM.DB:SetDonationTotal(memberKey, periodKey, logTotal)
                changed = true

                GM:SendCommMessage("GuildMate",
                    string.format("DONATION_TOTAL|%s|%s|%d", memberKey, periodKey, logTotal),
                    "GUILD")

                -- Announce in guild chat when an online member just met the goal
                if goal and GM.DB:GetSetting("goalMetAnnounce")
                   and prevTotal < goal.goldAmount
                   and logTotal >= goal.goldAmount then
                    local milestoneKey = memberKey .. "|" .. periodKey
                    local rosterInfo = _roster[memberKey]
                    if rosterInfo and rosterInfo.online
                       and not _announcedMilestones[milestoneKey] then
                        _announcedMilestones[milestoneKey] = true
                        local name = rosterInfo.name or memberKey:match("^(.+)-[^-]+$") or memberKey
                        SendChatMessage(
                            string.format(GM.L["GOAL_MET_ANNOUNCE"],
                                name, goal.period, Utils.FormatMoneyShort(goal.goldAmount)),
                            "GUILD")
                    end
                end
            end
        end
    end

    if changed then
        GM.MainFrame:RefreshActiveView()
    end

    -- Always broadcast all known totals after a bank scan, regardless of whether
    -- new transactions were found.  Any guild member who opens the bank will push
    -- their full knowledge to every online officer — not just newly-found entries.
    Donations:BroadcastKnownTotals()
end

-- ── Goal broadcast ───────────────────────────────────────────────────────────

-- Serialize targetRanks ({[0]=true,[2]=true}) → "0,2"
local function _SerializeRanks(targetRanks)
    local parts = {}
    for idx in pairs(targetRanks) do
        if targetRanks[idx] then
            parts[#parts + 1] = tostring(idx)
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- Deserialize "0,2" → {[0]=true,[2]=true}
local function _DeserializeRanks(str)
    local ranks = {}
    for idx in str:gmatch("(%d+)") do
        ranks[tonumber(idx)] = true
    end
    return ranks
end

-- Broadcast the active goal to the guild so all clients can store it.
-- Called when a goal is created and on officer login.
function Donations:BroadcastGoal(goal)
    if not goal then return end
    local ranks = _SerializeRanks(goal.targetRanks)
    local msg = string.format("GOAL_UPDATE|%d|%d|%s|%s|%s|%d",
        goal.id, goal.goldAmount, goal.period,
        goal.createdBy or "Unknown", ranks, goal.startEpoch or 0)
    GM:SendCommMessage("GuildMate", msg, "GUILD")
end

-- ── Comm handler ─────────────────────────────────────────────────────────────

function Donations:OnCommReceived(message, _channel, sender)
    local cmd = message:match("^(%w+)")

    if cmd == "DONATION_TOTAL" then
        -- DONATION_TOTAL|memberKey|periodKey|total
        local _, memberKey, periodKey, totalStr = message:match("^(%w+)|(.+)|(.+)|(%d+)$")
        local total = tonumber(totalStr)
        if memberKey and periodKey and total then
            GM.DB:SetDonationTotal(memberKey, periodKey, total)
            -- Debounce: a bulk sync sends many messages at once; only redraw once
            -- they've all landed rather than once per message.
            if not Donations._refreshPending then
                Donations._refreshPending = true
                C_Timer.After(0.5, function()
                    Donations._refreshPending = false
                    GM.MainFrame:RefreshActiveView()
                end)
            end
        end

    elseif cmd == "HELLO" then
        -- HELLO|version  — sender has GuildMate installed
        local _, version = message:match("^(%w+)|(.+)$")
        if version and sender then
            local realm = GetRealmName and GetRealmName() or "Unknown"
            local sn, sr = sender:match("^(.+)-(.+)$")
            sn = sn or sender
            sr = sr or realm
            Donations:SetAddonUser(Utils.MemberKey(sn, sr), version)

            -- New member just came online — share our goal and donation data
            -- so they don't have to wait for the next bank open or officer login.
            C_Timer.After(2, function()
                local goal = GM.DB:GetActiveGoal()
                if goal and Donations.BroadcastGoal then
                    Donations:BroadcastGoal(goal)
                end
                if Donations.BroadcastKnownTotals then
                    Donations:BroadcastKnownTotals()
                end
            end)
        end

    elseif cmd == "GOAL_UPDATE" then
        -- GOAL_UPDATE|id|goldAmount|period|createdBy|ranks|startEpoch
        -- createdBy may contain hyphens/special chars, so use [^|]+ for it
        local _, idStr, amountStr, period, createdBy, ranksStr, epochStr =
            message:match("^(%w+)|(%d+)|(%d+)|([^|]+)|([^|]+)|([^|]+)|(%d+)$")

        -- Debug: log what we received (remove after fixing)
        GM:Print(string.format("|cff4A90D9GuildMate debug:|r GOAL_UPDATE received: id=%s amt=%s period=%s createdBy=%s ranks=%s epoch=%s",
            tostring(idStr), tostring(amountStr), tostring(period),
            tostring(createdBy), tostring(ranksStr), tostring(epochStr)))

        local id        = tonumber(idStr)
        local amount    = tonumber(amountStr)
        local epoch     = tonumber(epochStr)

        if id and amount and period then
            local existing = GM.DB:GetActiveGoal()
            -- Accept if we have no goal, or the incoming goal is newer
            if not existing or (epoch and epoch > (existing.startEpoch or 0))
                            or (id and id > (existing.id or 0)) then
                local goal = {
                    id          = id,
                    goldAmount  = amount,
                    period      = period,
                    targetRanks = _DeserializeRanks(ranksStr or ""),
                    active      = true,
                    createdBy   = createdBy or "Unknown",
                    startEpoch  = epoch or 0,
                }
                GM.DB:DeactivateAllGoals()
                GM.DB:SaveGoal(goal)
                GM.MainFrame:RefreshActiveView()
            end
        end
    end
end

-- ── Reminder helpers ──────────────────────────────────────────────────────────

-- Whisper all online members in the target rank list who haven't met the goal
function Donations:RemindIncomplete()
    local goal = GM.DB:GetActiveGoal()
    if not goal then
        GM:Print(GM.L["NO_ACTIVE_GOAL"])
        return
    end

    local periodKey = Utils.PeriodKey(time(), goal.period)
    local playerName = UnitName("player") or ""

    local count = 0
    for key, info in pairs(_roster) do
        if info.online and goal.targetRanks[info.rankIndex]
           and info.name ~= playerName then
            local donated = GM.DB:GetDonated(key, periodKey)
            if donated < goal.goldAmount then
                local remaining = goal.goldAmount - donated
                local whisper = string.format(GM.L["WHISPER_TEMPLATE"],
                    info.name, goal.period,
                    Utils.FormatMoneyShort(goal.goldAmount),
                    Utils.FormatMoneyShort(donated),
                    Utils.FormatMoneyShort(remaining))
                SendChatMessage(whisper, "WHISPER", nil, info.name)
                count = count + 1
            end
        end
    end

    GM:Print(string.format(GM.L["SENT_REMINDERS"], count))
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

    local text = string.format(GM.L["ANNOUNCE_FORMAT"],
        Utils.PeriodLabel(periodKey), met, total, Utils.FormatMoneyShort(goal.goldAmount))

    SendChatMessage(text, channel)
end

-- ── Module render entry point (called by MainFrame) ───────────────────────────

function Donations:Render()
    -- Delegate to OfficerView or MemberView depending on player rank.
    -- GM.debugOfficer = true forces OfficerView regardless of rank (toggle with /gm debug).
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex == nil then rankIndex = 99 end  -- not in guild

    if GM.debugOfficer or GM.DB:IsOfficerRank(rankIndex) then
        if GM.OfficerView then
            GM.OfficerView:Render()
        end
    else
        if GM.MemberView then
            GM.MemberView:Render()
        end
    end
end
