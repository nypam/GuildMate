-- GuildMate: Database layer
-- Defines the SavedVariables schema and provides clean accessors.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local DB = {}
GM.DB = DB

-- ── Schema version — bump when migration logic changes ──────────────────────
local SCHEMA_VERSION = 6

-- Default schema — merged with any existing SavedVariables on load
DB.defaults = {
    version = SCHEMA_VERSION,

    -- Active and past donation goals, keyed by a numeric id
    goals = {},

    -- Per-member donation records, keyed by "Name-Realm"
    -- [periodKey] = copperTotal (plain number, max-merged)
    -- Kept for backward compatibility with older addon versions.
    -- Source of truth for new clients is donationLog (below).
    donations = {},

    -- Event log: one entry per deposit, chronological.
    -- { id, timestamp, memberKey, amount, periodKey, synthetic? }
    -- `id` is a stable fingerprint for dedup across reloads and sync.
    -- `synthetic=true` means the timestamp is approximated (from old data).
    donationLog = {},

    -- Set of seen event IDs for fast dedup (avoids scanning log every time)
    -- [id] = true
    donationLogSeen = {},

    -- Per-member profession data
    professions = {},

    -- Per-profession recipe data, keyed by spellID string
    recipes2 = {},

    -- Who has the addon installed (persisted)
    addonUsers = {},

    -- Addon-wide settings
    settings = {
        officerRanks = { [0] = true, [1] = true },
        reminderEnabled = true,
        reminderMessage = "Hi %s! Don't forget the %p guild donation goal of %g. You've donated %d so far.",
        announceChannel = "GUILD",
        goalMetAnnounce = true,
        windowWidth  = 900,
        windowHeight = 550,
        windowX      = nil,
        windowY      = nil,
        minimapPos   = 45,
    },
}

-- Called from guildMate.lua:OnInitialize after GuildMateDB is available
function DB:Init()
    GuildMateDB = GuildMateDB or {}
    self:_Migrate(GuildMateDB)
    self.sv = GuildMateDB

    -- Heal any double-counting introduced by the old SetDonationTotal behavior.
    -- Backs up first so the user can always /gm restore if needed.
    if self.sv.donationLog and #self.sv.donationLog > 0 then
        local hasSynthetics = false
        for _, e in ipairs(self.sv.donationLog) do
            if e.synthetic then hasSynthetics = true; break end
        end
        if hasSynthetics then
            self:BackupDonations("pre-synthetic-cleanup")
            local removed = self:CleanupSyntheticDonations()
            if removed > 0 then
                -- Defer the chat print until the addon is fully initialized.
                C_Timer.After(3, function()
                    if GM and GM.Print then
                        GM:Print("|cff4A90D9GuildMate:|r healed " .. removed ..
                            " duplicate donation entr" ..
                            (removed == 1 and "y" or "ies") ..
                            ". Backup saved; use |cffffd700/gm restore|r to undo.")
                    end
                end)
            end
        end
    end
end

-- Snapshot donations to a rolling backup slot.
-- Called before any destructive operation. Keeps the last 5 backups.
function DB:BackupDonations(reason)
    if not self.sv.donations then return end
    if not self.sv.donationBackups then self.sv.donationBackups = {} end

    local backup = {
        timestamp = time(),
        reason    = reason or "manual",
        donations = self:_DeepCopy(self.sv.donations),
    }

    table.insert(self.sv.donationBackups, 1, backup)

    -- Keep only last 5
    while #self.sv.donationBackups > 5 do
        table.remove(self.sv.donationBackups)
    end
end

-- Restore donations from a backup slot (1 = most recent, 5 = oldest).
-- Returns true on success, false if slot doesn't exist.
function DB:RestoreDonations(slot)
    slot = slot or 1
    if not self.sv.donationBackups or not self.sv.donationBackups[slot] then
        return false
    end
    local backup = self.sv.donationBackups[slot]
    self.sv.donations = self:_DeepCopy(backup.donations)
    return true, backup.timestamp, backup.reason
end

-- List all backups: returns array of { timestamp, reason, entryCount }
function DB:ListDonationBackups()
    local list = {}
    if not self.sv.donationBackups then return list end
    for i, b in ipairs(self.sv.donationBackups) do
        local count = 0
        for _ in pairs(b.donations or {}) do count = count + 1 end
        list[#list + 1] = {
            slot      = i,
            timestamp = b.timestamp,
            reason    = b.reason,
            count     = count,
        }
    end
    return list
end

-- Merge defaults + run migrations
function DB:_Migrate(sv)
    -- Merge top-level defaults
    for k, v in pairs(self.defaults) do
        if sv[k] == nil then
            sv[k] = (type(v) == "table") and self:_DeepCopy(v) or v
        end
    end

    -- Merge nested settings defaults
    if sv.settings then
        for k, v in pairs(self.defaults.settings) do
            if sv.settings[k] == nil then
                sv.settings[k] = (type(v) == "table") and self:_DeepCopy(v) or v
            end
        end
    end

    -- ── Schema v2 migrations ─────────────────────────────────────────────────
    if (sv.version or 1) < 2 then
        -- Auto-backup donations before any migration that touches them
        if sv.donations and next(sv.donations) then
            sv.donationBackups = sv.donationBackups or {}
            table.insert(sv.donationBackups, 1, {
                timestamp = time(),
                reason    = "pre-v2-migration",
                donations = self:_DeepCopy(sv.donations),
            })
            while #sv.donationBackups > 5 do table.remove(sv.donationBackups) end
        end

        -- Delete dead tables from older versions
        sv.seenTransactions = nil
        sv.debugScan = nil
        sv.recipes = nil  -- replaced by recipes2

        -- Migrate donation records from {own, synced} to plain numbers
        if sv.donations then
            for _, rec in pairs(sv.donations) do
                if rec.records then
                    for pk, val in pairs(rec.records) do
                        if type(val) == "table" then
                            rec.records[pk] = math.max(val.own or 0, val.synced or 0)
                        end
                    end
                end
            end
        end

        sv.version = 2
    end

    -- ── Schema v3: fix double-counting from pre-log aggregates ──────────────
    -- Previous version made AddDonationEvent additive, causing events to be
    -- double-counted on top of existing aggregated donations from v1/v2.
    -- This recomputes every period total as max(event sum, original aggregate).
    if (sv.version or 1) < 3 then
        -- Backup first
        if sv.donations and next(sv.donations) then
            sv.donationBackups = sv.donationBackups or {}
            table.insert(sv.donationBackups, 1, {
                timestamp = time(),
                reason    = "pre-v3-migration",
                donations = self:_DeepCopy(sv.donations),
            })
            while #sv.donationBackups > 5 do table.remove(sv.donationBackups) end
        end

        -- Compute log sums per (member, period)
        local logSums = {}
        for _, e in ipairs(sv.donationLog or {}) do
            logSums[e.memberKey] = logSums[e.memberKey] or {}
            local ps = logSums[e.memberKey]
            ps[e.periodKey] = (ps[e.periodKey] or 0) + (e.amount or 0)
        end

        -- For each stored donation, cap it at max(log sum, original value before double-counting).
        -- We don't know the "original", but we know: if logSum > current, current was under-counted
        -- (shouldn't happen). If logSum < current, the excess might be pre-log data OR double-count.
        -- Strategy: if current > 2 * logSum and logSum > 0, assume double-count and use logSum.
        -- Otherwise preserve current (safer — keeps pre-log data).
        if sv.donations then
            for mk, rec in pairs(sv.donations) do
                if rec.records then
                    local ps = logSums[mk] or {}
                    for pk, val in pairs(rec.records) do
                        if type(val) == "table" then
                            val = math.max(val.own or 0, val.synced or 0)
                        end
                        local logSum = ps[pk] or 0
                        if logSum > 0 and val > logSum then
                            -- Likely double-counted. Use log sum as truth.
                            rec.records[pk] = logSum
                        else
                            rec.records[pk] = val
                        end
                    end
                end
            end
        end

        sv.version = 3
    end

    -- ── Schema v4: rebuild event log with stable absolute-time fingerprints ──
    -- Old fingerprints used relative time offsets (year/month/day/hour-ago from
    -- WoW's bank API) which shift as time passes, creating duplicate events.
    -- New fingerprints use absolute hour buckets.
    if (sv.version or 1) < 4 then
        -- Backup
        if sv.donations and next(sv.donations) then
            sv.donationBackups = sv.donationBackups or {}
            table.insert(sv.donationBackups, 1, {
                timestamp = time(),
                reason    = "pre-v4-migration",
                donations = self:_DeepCopy(sv.donations),
            })
            while #sv.donationBackups > 5 do table.remove(sv.donationBackups) end
        end

        -- Rebuild donationLog with new-format IDs, deduping at the same time.
        -- Group existing events by (memberKey, amount, hour bucket) — the new
        -- fingerprint — and keep only one per bucket.
        local newLog = {}
        local newSeen = {}

        for _, e in ipairs(sv.donationLog or {}) do
            if e.synthetic then
                -- Preserve synthetic events with their old IDs
                if not newSeen[e.id] then
                    newLog[#newLog + 1] = e
                    newSeen[e.id] = true
                end
            else
                local ts = e.timestamp or 0
                if ts > 0 then
                    local hourBucket = math.floor(ts / 3600)
                    local newId = string.format("%s|%d|%d",
                        e.memberKey, e.amount or 0, hourBucket)
                    if not newSeen[newId] then
                        e.id = newId
                        newLog[#newLog + 1] = e
                        newSeen[newId] = true
                    end
                    -- else: duplicate event, drop it
                else
                    -- No timestamp (shouldn't happen for non-synthetic), keep as-is
                    if not newSeen[e.id] then
                        newLog[#newLog + 1] = e
                        newSeen[e.id] = true
                    end
                end
            end
        end

        sv.donationLog = newLog
        sv.donationLogSeen = newSeen

        -- Recompute aggregated donation totals from the deduplicated log
        if sv.donations then
            -- Compute log sums
            local logSums = {}
            for _, e in ipairs(sv.donationLog) do
                logSums[e.memberKey] = logSums[e.memberKey] or {}
                local ps = logSums[e.memberKey]
                ps[e.periodKey] = (ps[e.periodKey] or 0) + (e.amount or 0)
            end

            for mk, rec in pairs(sv.donations) do
                if rec.records then
                    local ps = logSums[mk] or {}
                    for pk, val in pairs(rec.records) do
                        if type(val) == "table" then
                            val = math.max(val.own or 0, val.synced or 0)
                        end
                        local logSum = ps[pk] or 0
                        -- Trust the log if we have it; otherwise preserve existing value
                        if logSum > 0 then
                            rec.records[pk] = logSum
                        else
                            rec.records[pk] = val
                        end
                    end
                end
            end
        end

        sv.version = 4
    end

    -- ── Schema v5: rebuild log with 6-hour buckets (WoW fuzzy timestamps) ───
    -- The 1-hour bucket from v4 is still too precise — WoW's "X hours ago"
    -- drifts by ±1 hour causing same deposits to land in adjacent buckets.
    -- Quantize to 6-hour windows to absorb that drift.
    if (sv.version or 1) < 5 then
        if sv.donations and next(sv.donations) then
            sv.donationBackups = sv.donationBackups or {}
            table.insert(sv.donationBackups, 1, {
                timestamp = time(),
                reason    = "pre-v5-migration",
                donations = self:_DeepCopy(sv.donations),
            })
            while #sv.donationBackups > 5 do table.remove(sv.donationBackups) end
        end

        local newLog = {}
        local newSeen = {}

        for _, e in ipairs(sv.donationLog or {}) do
            if e.synthetic then
                if not newSeen[e.id] then
                    newLog[#newLog + 1] = e
                    newSeen[e.id] = true
                end
            else
                local ts = e.timestamp or 0
                if ts > 0 then
                    local sixHourBucket = math.floor(ts / (6 * 3600))
                    local newId = string.format("%s|%d|%d",
                        e.memberKey, e.amount or 0, sixHourBucket)
                    if not newSeen[newId] then
                        e.id = newId
                        newLog[#newLog + 1] = e
                        newSeen[newId] = true
                    end
                else
                    if not newSeen[e.id] then
                        newLog[#newLog + 1] = e
                        newSeen[e.id] = true
                    end
                end
            end
        end

        sv.donationLog = newLog
        sv.donationLogSeen = newSeen

        -- Recompute aggregated totals from clean log
        if sv.donations then
            local logSums = {}
            for _, e in ipairs(sv.donationLog) do
                logSums[e.memberKey] = logSums[e.memberKey] or {}
                local ps = logSums[e.memberKey]
                ps[e.periodKey] = (ps[e.periodKey] or 0) + (e.amount or 0)
            end

            for mk, rec in pairs(sv.donations) do
                if rec.records then
                    local ps = logSums[mk] or {}
                    for pk, val in pairs(rec.records) do
                        if type(val) == "table" then
                            val = math.max(val.own or 0, val.synced or 0)
                        end
                        local logSum = ps[pk] or 0
                        if logSum > 0 then
                            rec.records[pk] = logSum
                        else
                            rec.records[pk] = val
                        end
                    end
                end
            end
        end

        sv.version = 5
    end

    -- ── Schema v6: proximity-based dedup for donation log ───────────────────
    -- Previous bucket-based approaches either created phantom duplicates
    -- (hour bucket too precise) or merged legitimate separate deposits
    -- (6-hour bucket too coarse). The new approach keeps all events with
    -- their real timestamps and uses a ±2h proximity check at scan time.
    -- This migration rebuilds the log by merging events that are likely
    -- duplicates (same member+amount within 2 hours).
    if (sv.version or 1) < 6 then
        if sv.donations and next(sv.donations) then
            sv.donationBackups = sv.donationBackups or {}
            table.insert(sv.donationBackups, 1, {
                timestamp = time(),
                reason    = "pre-v6-migration",
                donations = self:_DeepCopy(sv.donations),
            })
            while #sv.donationBackups > 5 do table.remove(sv.donationBackups) end
        end

        local DRIFT = 2 * 3600
        local kept = {}  -- final log
        local newSeen = {}

        -- Sort by timestamp so we process chronologically
        local sorted = {}
        for _, e in ipairs(sv.donationLog or {}) do
            sorted[#sorted + 1] = e
        end
        table.sort(sorted, function(a, b)
            return (a.timestamp or 0) < (b.timestamp or 0)
        end)

        for _, e in ipairs(sorted) do
            if e.synthetic then
                if not newSeen[e.id] then
                    kept[#kept + 1] = e
                    newSeen[e.id] = true
                end
            else
                local ts = e.timestamp or 0
                -- Regenerate ID with the new format
                local newId = string.format("%s|%d|%d",
                    e.memberKey, e.amount or 0, ts)

                -- Check if we already kept a close match
                local dup = false
                for _, k in ipairs(kept) do
                    if not k.synthetic
                       and k.memberKey == e.memberKey
                       and k.amount == e.amount
                       and k.timestamp
                       and math.abs(k.timestamp - ts) < DRIFT then
                        dup = true
                        break
                    end
                end

                if not dup then
                    e.id = newId
                    kept[#kept + 1] = e
                    newSeen[newId] = true
                end
            end
        end

        sv.donationLog = kept
        sv.donationLogSeen = newSeen

        -- Recompute aggregated totals from the cleaned log
        if sv.donations then
            local logSums = {}
            for _, e in ipairs(sv.donationLog) do
                logSums[e.memberKey] = logSums[e.memberKey] or {}
                local ps = logSums[e.memberKey]
                ps[e.periodKey] = (ps[e.periodKey] or 0) + (e.amount or 0)
            end

            for mk, rec in pairs(sv.donations) do
                if rec.records then
                    local ps = logSums[mk] or {}
                    for pk, val in pairs(rec.records) do
                        if type(val) == "table" then
                            val = math.max(val.own or 0, val.synced or 0)
                        end
                        local logSum = ps[pk] or 0
                        if logSum > 0 then
                            rec.records[pk] = logSum
                        else
                            rec.records[pk] = val
                        end
                    end
                end
            end
        end

        sv.version = SCHEMA_VERSION
    end
end

function DB:_DeepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = (type(v) == "table") and self:_DeepCopy(v) or v
    end
    return copy
end

-- ── Settings helpers ─────────────────────────────────────────────────────────

function DB:GetSetting(key)
    return self.sv.settings[key]
end

function DB:SetSetting(key, value)
    self.sv.settings[key] = value
end

function DB:IsOfficerRank(rankIndex)
    if rankIndex == 0 then return true end
    return self.sv.settings.officerRanks[rankIndex] == true
end

-- ── Goal helpers ─────────────────────────────────────────────────────────────

function DB:NextGoalId()
    local maxId = 0
    for id in pairs(self.sv.goals) do
        if id > maxId then maxId = id end
    end
    return maxId + 1
end

function DB:SaveGoal(goal)
    self.sv.goals[goal.id] = goal
end

function DB:GetActiveGoal()
    for _, goal in pairs(self.sv.goals) do
        if goal.active then return goal end
    end
    return nil
end

function DB:DeactivateAllGoals()
    for _, goal in pairs(self.sv.goals) do
        goal.active = false
    end
end

-- ── Donation record helpers ──────────────────────────────────────────────────

-- Returns (or creates) the donation record for a member key ("Name-Realm")
function DB:GetMemberRecord(memberKey)
    if not self.sv.donations[memberKey] then
        self.sv.donations[memberKey] = {
            records     = {},   -- [periodKey] = copperTotal (plain number)
            lastDeposit = 0,
            rankIndex   = -1,
        }
    end
    return self.sv.donations[memberKey]
end

-- Donated copper for a member in a specific period (0 if none).
function DB:GetDonated(memberKey, periodKey)
    local rec = self.sv.donations[memberKey]
    if not rec then return 0 end
    local r = rec.records[periodKey]
    if not r then return 0 end
    -- Handle legacy {own, synced} tables from pre-v2 data
    if type(r) == "table" then return math.max(r.own or 0, r.synced or 0) end
    return r
end

-- Update a member's rank index (called on roster refresh)
function DB:SetMemberRank(memberKey, rankIndex)
    local rec = self:GetMemberRecord(memberKey)
    rec.rankIndex = rankIndex
end

-- ── Donation event log ──────────────────────────────────────────────────────

-- Add a deposit event to the log. Returns true if added (new), false if dup.
-- id is a stable fingerprint. The aggregated donations[periodKey] total is
-- recomputed by summing all events for that member+period, so we stay
-- consistent even if some events were imported from pre-log aggregates.
function DB:AddDonationEvent(event)
    if not event or not event.id then return false end

    self.sv.donationLogSeen = self.sv.donationLogSeen or {}
    if self.sv.donationLogSeen[event.id] then return false end

    self.sv.donationLog = self.sv.donationLog or {}
    self.sv.donationLog[#self.sv.donationLog + 1] = event
    self.sv.donationLogSeen[event.id] = true

    -- Recompute the aggregated total from the log (idempotent, not additive)
    self:_RecomputePeriodTotal(event.memberKey, event.periodKey)

    return true
end

-- Rebuild donations[memberKey][periodKey] by summing events from the log.
-- Takes the MAX of (log sum, existing stored total) to preserve pre-log data.
function DB:_RecomputePeriodTotal(memberKey, periodKey)
    local logSum = 0
    local latestTs = 0
    for _, e in ipairs(self.sv.donationLog or {}) do
        if e.memberKey == memberKey and e.periodKey == periodKey then
            logSum = logSum + (e.amount or 0)
            if (e.timestamp or 0) > latestTs then latestTs = e.timestamp end
        end
    end

    local rec = self:GetMemberRecord(memberKey)
    local existing = rec.records[periodKey] or 0
    if type(existing) == "table" then
        existing = math.max(existing.own or 0, existing.synced or 0)
    end

    -- Use max so we never lose pre-log aggregated data
    rec.records[periodKey] = math.max(logSum, existing)
    rec.lastDeposit = math.max(rec.lastDeposit or 0, latestTs)
end

-- Check if a log event with this id has been seen
function DB:HasDonationEvent(id)
    return self.sv.donationLogSeen and self.sv.donationLogSeen[id] or false
end

-- Get all log events, optionally filtered by period
function DB:GetDonationLog(filter)
    local log = self.sv.donationLog or {}
    if not filter then return log end
    local result = {}
    for _, e in ipairs(log) do
        if (not filter.memberKey or e.memberKey == filter.memberKey)
           and (not filter.periodKey or e.periodKey == filter.periodKey)
           and (not filter.since or (e.timestamp or 0) >= filter.since) then
            result[#result + 1] = e
        end
    end
    return result
end

-- ── Idempotent total setter (max-merge) ─────────────────────────────────────

-- Sets a member's period total to max(current, newTotal).
-- Safe to call multiple times — never decreases a total.
--
-- If the detailed donationLog already contains real events for this member+
-- period, we TRUST the log and skip synthetic creation — otherwise a
-- DONATION_BATCH arriving alongside DEPOSIT_BATCH would double-count the same
-- deposits (once as a real event, once as a synthetic gap).
--
-- Synthetics are only created when no real events exist yet — i.e. when we're
-- receiving aggregated data from an old client that doesn't broadcast the
-- individual events.
function DB:SetDonationTotal(memberKey, periodKey, newTotal)
    local rec = self:GetMemberRecord(memberKey)
    local current = rec.records[periodKey] or 0
    if type(current) == "table" then
        current = math.max(current.own or 0, current.synced or 0)
    end

    -- Compute the real (non-synthetic) log sum for this member+period.
    local realLogSum = 0
    for _, e in ipairs(self.sv.donationLog or {}) do
        if e.memberKey == memberKey and e.periodKey == periodKey and not e.synthetic then
            realLogSum = realLogSum + (e.amount or 0)
        end
    end

    -- If the detailed log already accounts for (or exceeds) newTotal, the
    -- aggregated total is redundant — don't touch the log.
    if realLogSum >= newTotal then
        if newTotal > current then
            rec.records[periodKey] = math.max(current, realLogSum)
        end
        return
    end

    if newTotal > current then
        rec.records[periodKey] = newTotal
        rec.lastDeposit = time()

        -- Only the portion NOT covered by real events needs a synthetic.
        local gap = newTotal - realLogSum
        if gap > 0 then
            local syntheticId = "syn:" .. memberKey .. ":" .. periodKey .. ":" .. newTotal
            self.sv.donationLogSeen = self.sv.donationLogSeen or {}
            if not self.sv.donationLogSeen[syntheticId] then
                self.sv.donationLog = self.sv.donationLog or {}
                self.sv.donationLog[#self.sv.donationLog + 1] = {
                    id        = syntheticId,
                    timestamp = 0,  -- unknown
                    memberKey = memberKey,
                    amount    = gap,
                    periodKey = periodKey,
                    synthetic = true,
                }
                self.sv.donationLogSeen[syntheticId] = true
            end
        end
    end
end

-- Walk the donationLog and remove stale synthetic events that are fully
-- covered by real (timestamped) events for the same member+period. This
-- heals DBs that accumulated duplicates under the previous SetDonationTotal
-- implementation.
--
-- Returns the number of synthetic entries removed.
function DB:CleanupSyntheticDonations()
    local log = self.sv.donationLog
    if not log then return 0 end

    -- Group events by (memberKey :: periodKey)
    local byKey = {}
    for i, e in ipairs(log) do
        local key = (e.memberKey or "") .. "::" .. (e.periodKey or "")
        byKey[key] = byKey[key] or { realSum = 0, syntheticIndices = {}, maxNewTotal = 0 }
        local g = byKey[key]
        if e.synthetic then
            g.syntheticIndices[#g.syntheticIndices + 1] = i
            -- Parse the newTotal that was encoded into the synthetic id.
            local nt = tonumber(e.id and e.id:match(":(%d+)$") or nil)
            if nt and nt > g.maxNewTotal then g.maxNewTotal = nt end
        else
            g.realSum = g.realSum + (e.amount or 0)
        end
    end

    -- Collect indices of synthetics to remove (real events now cover them).
    local toRemove = {}
    for _, g in pairs(byKey) do
        if g.realSum >= g.maxNewTotal and #g.syntheticIndices > 0 then
            for _, idx in ipairs(g.syntheticIndices) do
                toRemove[#toRemove + 1] = idx
            end
        end
    end

    -- Remove in descending order so earlier indices stay valid.
    table.sort(toRemove, function(a, b) return a > b end)
    for _, idx in ipairs(toRemove) do
        local e = log[idx]
        table.remove(log, idx)
        if e and e.id and self.sv.donationLogSeen then
            self.sv.donationLogSeen[e.id] = nil
        end
    end

    -- Recompute all affected period totals so rec.records matches the log.
    for key, _ in pairs(byKey) do
        local mk, pk = key:match("^(.-)::(.+)$")
        if mk and pk then
            self:_RecomputePeriodTotal(mk, pk)
        end
    end

    return #toRemove
end
