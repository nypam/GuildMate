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

    -- Prune stale data: remove members no longer in guild
    if next(_roster) then
        local addonUsers = GM.DB.sv.addonUsers
        if addonUsers then
            for key in pairs(addonUsers) do
                if not _roster[key] then
                    addonUsers[key] = nil
                end
            end
        end

        -- Prune profession/recipe data for ex-members
        if GM.Professions and GM.Professions.PruneStaleData then
            GM.Professions:PruneStaleData(_roster)
        end
    end
end

-- Returns a snapshot of the roster (read-only)
function Donations:GetRoster()
    return _roster
end

-- Wipe recent donation events (last N days) and re-scan the bank.
-- Older events are preserved. Backs up to donationBackups first.
-- Requires the guild bank to be open.
function Donations:RescanRecent(days)
    if GM.DB._readOnly then
        if GM.Print then GM:Print("|cffcc3333GuildMate:|r read-only mode, rescan skipped.") end
        return
    end
    days = days or 3
    local cutoff = time() - (days * 86400)

    -- Backup first
    GM.DB:BackupDonations("pre-rescan-" .. days .. "d")

    -- Remove recent events from the log
    local oldLog = GM.DB.sv.donationLog or {}
    local keptLog = {}
    local keptSeen = {}
    local removedPeriods = {}

    for _, e in ipairs(oldLog) do
        local ts = e.timestamp or 0
        if ts < cutoff or e.synthetic then
            keptLog[#keptLog + 1] = e
            keptSeen[e.id] = true
        else
            -- Track which member+period combos were affected
            removedPeriods[e.memberKey] = removedPeriods[e.memberKey] or {}
            removedPeriods[e.memberKey][e.periodKey] = true
        end
    end

    GM.DB.sv.donationLog = keptLog
    GM.DB.sv.donationLogSeen = keptSeen

    -- Recompute totals for affected member+period combos from remaining log
    for mk, periods in pairs(removedPeriods) do
        for pk in pairs(periods) do
            local sum = 0
            for _, e in ipairs(keptLog) do
                if e.memberKey == mk and e.periodKey == pk then
                    sum = sum + (e.amount or 0)
                end
            end
            local rec = GM.DB.sv.donations[mk]
            if rec and rec.records then
                if sum > 0 then
                    rec.records[pk] = sum
                else
                    rec.records[pk] = nil
                end
            end
        end
    end

    -- Now re-scan the bank (requires bank to be open)
    self:ProcessTransactionLog()
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

    -- Batch all totals into one message instead of N individual messages.
    -- Format: DONATION_BATCH|memberKey:periodKey:total,memberKey:periodKey:total,...
    -- Only include members currently in the guild roster.
    local hasRoster = next(_roster) ~= nil
    local parts = {}

    for memberKey, _ in pairs(GM.DB.sv.donations) do
        -- Skip ex-members (only filter if roster is populated)
        if hasRoster and not _roster[memberKey] then
            -- skip
        else
            for _, periodKey in ipairs(periods) do
                local total = GM.DB:GetDonated(memberKey, periodKey)
                if total > 0 then
                    parts[#parts + 1] = memberKey .. ":" .. periodKey .. ":" .. total
                end
            end
        end
    end

    if #parts > 0 then
        local msg = "DONATION_BATCH|" .. table.concat(parts, ",")
        GM:SendCommMessage("GuildMate", msg, "GUILD")
    end
end

-- Broadcast recent donation events from the log (to new clients).
-- Default: last 60 days. Only real events (not synthetic).
function Donations:BroadcastDonationLog(sinceDays)
    local since = time() - ((sinceDays or 60) * 86400)
    local log = GM.DB:GetDonationLog({ since = since })

    local parts = {}
    local hasRoster = next(_roster) ~= nil

    for _, e in ipairs(log) do
        if e.synthetic then
            -- Skip synthetic events (can't reconstruct real timestamp)
        elseif hasRoster and not _roster[e.memberKey] then
            -- Skip ex-members
        else
            parts[#parts + 1] = string.format("%s:%d:%d:%s:%s",
                e.memberKey, e.timestamp or 0, e.amount, e.periodKey, e.id)
        end
    end

    if #parts > 0 then
        local msg = "DEPOSIT_BATCH|" .. table.concat(parts, ",")
        GM:SendCommMessage("GuildMate", msg, "GUILD")
    end
end

-- ── Transaction log parsing ───────────────────────────────────────────────────

function Donations:ProcessTransactionLog()
    if GM.DB._readOnly then return end
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

    -- Build a snapshot of current bank log entries, then reconcile with DB.
    -- This approach correctly handles duplicate same-amount deposits by
    -- matching the set of log entries, not by time proximity.
    local logEntries = {}  -- { memberKey, amount, approxTs, hour, periodKey }

    for i = 1, 25 do
        local txType, name, amount, year, month, day, hour = getMoneyTx(i)
        if not txType then break end

        if txType == "deposit" and name and amount and amount > 0
           and year ~= nil and month ~= nil and day ~= nil and hour ~= nil then

            local approxTs  = time() - (year * 365 * 86400) - (month * 30 * 86400)
                                     - (day * 86400) - (math.floor(hour) * 3600)
            local periodKey = Utils.PeriodKey(approxTs, periodType)
            local memberKey = Utils.MemberKey(name, realm)

            logEntries[#logEntries + 1] = {
                memberKey = memberKey,
                amount    = amount,
                approxTs  = approxTs,
                hour      = math.floor(hour),
                periodKey = periodKey,
                idx       = i,
            }
        end
    end

    -- Count how many times each (memberKey, amount) pair appears in the log.
    -- The DB should contain exactly the same count of matching events in the
    -- approximate time range (within ~2 days of now). If DB has FEWER, we
    -- need to add the missing ones. If DB has MORE, something else filled in.
    local logCounts = {}  -- [memberKey][amount] = count in current scan
    for _, e in ipairs(logEntries) do
        logCounts[e.memberKey] = logCounts[e.memberKey] or {}
        logCounts[e.memberKey][e.amount] = (logCounts[e.memberKey][e.amount] or 0) + 1
    end

    -- Count DB events for same (memberKey, amount) in the last 3 days
    -- (covers the full 25-entry log window).
    local dbCutoff = time() - (3 * 86400)
    local dbCounts = {}
    for _, ev in ipairs(GM.DB.sv.donationLog or {}) do
        if not ev.synthetic and ev.timestamp and ev.timestamp >= dbCutoff then
            dbCounts[ev.memberKey] = dbCounts[ev.memberKey] or {}
            dbCounts[ev.memberKey][ev.amount] = (dbCounts[ev.memberKey][ev.amount] or 0) + 1
        end
    end

    -- For each log entry, determine if it's already covered by the DB.
    -- We group by (memberKey, amount) and add `logCount - dbCount` new events.
    local addedPairs = {}  -- track how many we've added per pair this scan
    local newEvents = {}
    local changed = false

    for _, e in ipairs(logEntries) do
        local mk, amt = e.memberKey, e.amount
        local logN = logCounts[mk][amt] or 0
        local dbN  = (dbCounts[mk] and dbCounts[mk][amt]) or 0
        local addedN = (addedPairs[mk] and addedPairs[mk][amt]) or 0

        -- We want to add (logN - dbN) new events total for this pair.
        -- Skip this entry if we've already added enough.
        if addedN + dbN < logN then
            -- Unique ID using timestamp + index to avoid collisions within pair
            local eventId = string.format("%s|%d|%d|%d",
                mk, amt, e.approxTs, e.idx)

            if not GM.DB:HasDonationEvent(eventId) then
                local event = {
                    id        = eventId,
                    timestamp = e.approxTs,
                    memberKey = mk,
                    amount    = amt,
                    periodKey = e.periodKey,
                }
                if GM.DB:AddDonationEvent(event) then
                    newEvents[#newEvents + 1] = event
                    changed = true
                    addedPairs[mk] = addedPairs[mk] or {}
                    addedPairs[mk][amt] = (addedPairs[mk][amt] or 0) + 1
                end
            end
        end
    end

    -- For each new event, broadcast via DEPOSIT (new clients) and update
    -- aggregated totals (old clients will receive via DONATION_BATCH below).
    for _, event in ipairs(newEvents) do
        -- New: DEPOSIT message with full event data
        local msg = string.format("DEPOSIT|%s|%d|%d|%s|%s",
            event.memberKey, event.timestamp, event.amount,
            event.periodKey, event.id)
        GM:SendCommMessage("GuildMate", msg, "GUILD")

        -- Goal-met announcement
        if goal and GM.DB:GetSetting("goalMetAnnounce") then
            local newTotal = GM.DB:GetDonated(event.memberKey, event.periodKey)
            local prevTotal = newTotal - event.amount
            if prevTotal < goal.goldAmount and newTotal >= goal.goldAmount then
                local milestoneKey = event.memberKey .. "|" .. event.periodKey
                local rosterInfo = _roster[event.memberKey]
                if rosterInfo and rosterInfo.online
                   and not _announcedMilestones[milestoneKey] then
                    _announcedMilestones[milestoneKey] = true
                    local dname = rosterInfo.name or event.memberKey:match("^(.+)-[^-]+$") or event.memberKey
                    SendChatMessage(
                        string.format(GM.L["GOAL_MET_ANNOUNCE"],
                            dname, goal.period, Utils.FormatMoneyShort(goal.goldAmount)),
                        "GUILD")
                end
            end
        end
    end

    if changed then
        GM.MainFrame:RefreshActiveView()
        -- Only broadcast aggregated totals when we actually added events.
        -- Otherwise every bank open would fire a full DONATION_BATCH blast
        -- to the guild — pure noise when nothing changed.
        Donations:BroadcastKnownTotals()
    end
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
    -- Simple format: GOAL|id|amount|period|ranks|epoch
    -- Dropped createdBy to avoid special character parsing issues
    local msg = string.format("GOAL|%d|%d|%s|%s|%d",
        goal.id, goal.goldAmount, goal.period,
        ranks, goal.startEpoch or 0)
    GM:SendCommMessage("GuildMate", msg, "GUILD")
end

-- ── Comm handler ─────────────────────────────────────────────────────────────

function Donations:OnCommReceived(message, _channel, sender)
    local cmd = message:match("^([%w_]+)")

    -- Note: version gating is centralized in GM:OnCommReceived. By the time
    -- we get here, either this is HELLO or the sender is compatible.
    -- Read-only mode: we still process HELLO (to learn versions) but skip
    -- any data message that would mutate the DB.
    if GM.DB._readOnly and cmd ~= "HELLO" then return end

    if cmd == "DEPOSIT" then
        -- DEPOSIT|memberKey|timestamp|amount|periodKey|eventId
        local _, mk, tsStr, amtStr, pk, eventId = message:match("^([%w_]+)|([^|]+)|(%d+)|(%d+)|([^|]+)|(.+)$")
        local ts = tonumber(tsStr)
        local amt = tonumber(amtStr)
        if mk and ts and amt and pk and eventId and not GM.DB:HasDonationEvent(eventId) then
            GM.DB:AddDonationEvent({
                id        = eventId,
                timestamp = ts,
                memberKey = mk,
                amount    = amt,
                periodKey = pk,
            })
            if not Donations._refreshPending then
                Donations._refreshPending = true
                C_Timer.After(0.5, function()
                    Donations._refreshPending = false
                    GM.MainFrame:RefreshActiveView()
                end)
            end
        end

    elseif cmd == "DEPOSIT_BATCH" then
        -- DEPOSIT_BATCH|mk:ts:amt:pk:id,mk:ts:amt:pk:id,...
        local _, batchStr = message:match("^([%w_]+)|(.+)$")
        if batchStr then
            for entry in batchStr:gmatch("[^,]+") do
                local mk, tsStr, amtStr, pk, eventId = entry:match("^([^:]+):(%d+):(%d+):([%d%-W]+):(.+)$")
                local ts = tonumber(tsStr)
                local amt = tonumber(amtStr)
                if mk and ts and amt and pk and eventId and not GM.DB:HasDonationEvent(eventId) then
                    GM.DB:AddDonationEvent({
                        id        = eventId,
                        timestamp = ts,
                        memberKey = mk,
                        amount    = amt,
                        periodKey = pk,
                    })
                end
            end
            if not Donations._refreshPending then
                Donations._refreshPending = true
                C_Timer.After(0.5, function()
                    Donations._refreshPending = false
                    GM.MainFrame:RefreshActiveView()
                end)
            end
        end

    elseif cmd == "DONATION_BATCH" then
        -- DONATION_BATCH|memberKey:periodKey:total,memberKey:periodKey:total,...
        local _, batchStr = message:match("^([%w_]+)|(.+)$")
        if batchStr then
            for entry in batchStr:gmatch("[^,]+") do
                local mk, pk, totalStr = entry:match("^(.+):([%d%-W]+):(%d+)$")
                local total = tonumber(totalStr)
                if mk and pk and total then
                    GM.DB:SetDonationTotal(mk, pk, total)
                end
            end
            -- Debounce refresh
            if not Donations._refreshPending then
                Donations._refreshPending = true
                C_Timer.After(0.5, function()
                    Donations._refreshPending = false
                    GM.MainFrame:RefreshActiveView()
                end)
            end
        end

    elseif cmd == "DONATION_TOTAL" then
        -- Legacy single-message format from pre-v0.4.1 clients. Old clients
        -- spam this every few seconds per member. We still honor the data
        -- (via SetDonationTotal → max-merge, no synthetic) but aggressively
        -- debounce the UI refresh to prevent layout thrash.
        local _, memberKey, periodKey, totalStr = message:match("^([%w_]+)|([^|]+)|([^|]+)|(%d+)$")
        local total = tonumber(totalStr)
        if memberKey and periodKey and total then
            GM.DB:SetDonationTotal(memberKey, periodKey, total)
            if not Donations._refreshPending then
                Donations._refreshPending = true
                C_Timer.After(2, function()
                    Donations._refreshPending = false
                    GM.MainFrame:RefreshActiveView()
                end)
            end
        end

    elseif cmd == "HELLO" then
        -- HELLO|version  — sender has GuildMate installed.
        -- We ONLY record the version. Data broadcasts happen on real events
        -- (bank scans, goal edits, tradeskill opens), NOT on every HELLO.
        -- The old "welcome dump" pattern caused 5-50KB cascades per login
        -- which saturated comm in busy guilds. Fresh clients bootstrap via
        -- explicit /gm sync instead.
        local _, version = message:match("^(%w+)|(.+)$")
        if version and sender then
            local realm = GetRealmName and GetRealmName() or "Unknown"
            local sn, sr = sender:match("^(.+)-(.+)$")
            sn = sn or sender
            sr = sr or realm
            local senderKey = Utils.MemberKey(sn, sr)
            local wasKnown = GM.DB.sv.addonUsers and GM.DB.sv.addonUsers[senderKey] ~= nil
            Donations:SetAddonUser(senderKey, version)

            -- Handshake reply: send our HELLO back to a previously-unknown
            -- sender so they learn our version. Guild-wide debounced (10s)
            -- so concurrent new-sender bursts only produce one reply.
            if not wasKnown then
                local lastSent = GM._lastHelloSentAt or 0
                local now = GetTime()
                if (now - lastSent) > 10 then
                    GM._lastHelloSentAt = now
                    C_Timer.After(1, function()
                        GM:SendCommMessage("GuildMate",
                            "HELLO|" .. (GM.version or "0.0.0"), "GUILD")
                    end)
                end
            end
        end

    elseif cmd == "GOAL" or cmd == "GOAL_UPDATE" then
        -- New format: GOAL|id|amount|period|ranks|epoch
        -- Old format: GOAL_UPDATE|id|amount|period|createdBy|ranks|epoch
        local idStr, amountStr, period, ranksStr, epochStr

        if cmd == "GOAL" then
            _, idStr, amountStr, period, ranksStr, epochStr =
                message:match("^([%w_]+)|(%d+)|(%d+)|(%w+)|([^|]+)|(%d+)$")
        else
            -- Legacy: skip createdBy field
            local _, _id, _amt, _per, _cb, _rk, _ep =
                message:match("^([%w_]+)|(%d+)|(%d+)|([^|]+)|([^|]+)|([^|]+)|(%d+)$")
            idStr, amountStr, period, ranksStr, epochStr = _id, _amt, _per, _rk, _ep
        end

        local id     = tonumber(idStr)
        local amount = tonumber(amountStr)
        local epoch  = tonumber(epochStr)

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
                    createdBy   = "Unknown",
                    startEpoch  = epoch or 0,
                }
                GM.DB:DeactivateAllGoals()
                GM.DB:SaveGoal(goal)
                GM.MainFrame:RefreshActiveView()
                GM:Print("|cff4A90D9GuildMate:|r Received donation goal: " ..
                    Utils.FormatMoneyShort(amount) .. " " .. period)
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
