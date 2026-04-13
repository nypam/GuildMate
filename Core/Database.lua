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

    -- ── Schema write lock ──────────────────────────────────────────────────
    -- Stamp MIN_COMPAT_VERSION into the DB. If an older client loads a DB
    -- where writeLock > their own version, they enter read-only mode and
    -- skip all data mutations. This prevents downgrades from corrupting
    -- forward-incompatible schema (e.g. recipe categories, event log).
    self.sv.writeLock = self.sv.writeLock or {}
    local myVer  = (GM and GM.version) or "0.0.0"
    local minVer = (GM and GM.MIN_COMPAT_VERSION) or "0.0.0"
    local function vkey(v)
        if GM and GM._VersionKey then return GM._VersionKey(v) end
        return 0
    end

    if vkey(myVer) >= vkey(minVer) then
        -- We're on a sufficiently-new client. Bump the lock forward.
        local locked = self.sv.writeLock.version or "0.0.0"
        if vkey(minVer) > vkey(locked) then
            self.sv.writeLock.version    = minVer
            self.sv.writeLock.lockedBy   = UnitName("player") or "?"
            self.sv.writeLock.lockedAt   = time()
        end
        self._readOnly = false
    else
        -- We're on an older client. If the lock is above our version, we
        -- can't safely mutate the DB. Mark read-only.
        local locked = self.sv.writeLock.version or "0.0.0"
        if vkey(locked) > vkey(myVer) then
            self._readOnly = true
            C_Timer.After(3, function()
                if GM and GM.Print then
                    GM:Print("|cffcc3333GuildMate:|r this SavedVariables file " ..
                        "was written by a newer version (v" .. locked .. "). " ..
                        "Running in |cffff4444READ-ONLY|r mode until you update " ..
                        "to v" .. locked .. " or later.")
                end
            end)
        else
            self._readOnly = false
        end
    end

    -- Heal any double-counting introduced by the old SetDonationTotal code.
    -- Two stages:
    --   1. Remove synthetic log entries that duplicate real events.
    --   2. Recompute every period total from the log so bloated
    --      rec.records[pk] values are overwritten with the real sum.
    -- Backs up first so /gm restore can undo the heal if needed.
    if self.sv.donationLog and #self.sv.donationLog > 0 then
        local hasSynthetics = false
        for _, e in ipairs(self.sv.donationLog) do
            if e.synthetic then hasSynthetics = true; break end
        end

        -- Always recompute from the log so bloated aggregates get corrected,
        -- even if synthetics were already cleaned on a prior reload.
        local didBackup = false
        if hasSynthetics then
            self:BackupDonations("pre-synthetic-cleanup")
            didBackup = true
            self:CleanupSyntheticDonations()
        end

        -- Collect unique (memberKey, periodKey) pairs and recompute each.
        local healed = 0
        local seen = {}
        for _, e in ipairs(self.sv.donationLog) do
            local key = (e.memberKey or "") .. "::" .. (e.periodKey or "")
            if not seen[key] and e.memberKey and e.periodKey and not e.synthetic then
                seen[key] = true
                local rec = self:GetMemberRecord(e.memberKey)
                local before = rec.records[e.periodKey] or 0
                if type(before) == "table" then
                    before = math.max(before.own or 0, before.synced or 0)
                end
                self:_RecomputePeriodTotal(e.memberKey, e.periodKey)
                local after = rec.records[e.periodKey] or 0
                if after < before then healed = healed + 1 end
            end
        end

        if healed > 0 then
            if not didBackup then
                self:BackupDonations("pre-total-heal")
            end
            C_Timer.After(3, function()
                if GM and GM.Print then
                    GM:Print("|cff4A90D9GuildMate:|r healed " .. healed ..
                        " bloated donation total" .. (healed == 1 and "" or "s") ..
                        " (trusted real-event log). Backup saved; use " ..
                        "|cffffd700/gm restore|r to undo.")
                end
            end)
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
    if self._readOnly then return end
    self.sv.goals[goal.id] = goal
end

function DB:GetActiveGoal()
    for _, goal in pairs(self.sv.goals) do
        if goal.active then return goal end
    end
    return nil
end

function DB:DeactivateAllGoals()
    if self._readOnly then return end
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

-- Convert a period key like "2026-W15" / "2026-04" into a comparable integer.
-- Consecutive periods differ by 1 — useful for counting gaps between records.
local function _PeriodOrdinal(pk)
    if not pk then return 0 end
    local y, w = pk:match("^(%d+)%-W(%d+)$")
    if y and w then return tonumber(y) * 53 + tonumber(w) end
    local y2, m = pk:match("^(%d+)%-(%d+)$")
    if y2 and m then return tonumber(y2) * 12 + tonumber(m) end
    return 0
end

-- Effective donated for a period including carryover from prior overpayments.
-- Walks every period the member has on record from the earliest up through
-- `currentPeriodKey`, accumulating surplus where they overpaid and depleting
-- it (by `goal.goldAmount`) for each missed period in between. Returns the
-- effective amount available against the current period's goal — i.e. the
-- player's donation plus any unconsumed carryover credit.
--
-- If goal is nil or has no goldAmount, falls back to GetDonated (no carryover).
function DB:GetEffectiveDonated(memberKey, currentPeriodKey, goal)
    if not currentPeriodKey then return 0 end
    if not goal or not goal.goldAmount or goal.goldAmount <= 0 then
        return self:GetDonated(memberKey, currentPeriodKey)
    end

    local rec = self.sv.donations[memberKey]
    if not rec or not rec.records then return 0 end

    -- Collect period keys with non-zero donations up to (and including) current.
    local periodKeys = {}
    for pk in pairs(rec.records) do
        if pk <= currentPeriodKey then
            local amt = self:GetDonated(memberKey, pk)
            if amt and amt > 0 then
                periodKeys[#periodKeys + 1] = pk
            end
        end
    end
    if #periodKeys == 0 then
        return self:GetDonated(memberKey, currentPeriodKey)
    end
    table.sort(periodKeys)

    local goalAmount = goal.goldAmount
    local surplus    = 0
    local prevOrd    = nil

    for _, pk in ipairs(periodKeys) do
        local ord = _PeriodOrdinal(pk)
        if prevOrd then
            -- Deplete surplus by goal for each missed period in the gap.
            local missed = ord - prevOrd - 1
            if missed > 0 then
                if missed * goalAmount >= surplus then
                    surplus = 0
                else
                    surplus = surplus - missed * goalAmount
                end
            end
        end
        if pk == currentPeriodKey then
            return self:GetDonated(memberKey, pk) + surplus
        end
        local donated = self:GetDonated(memberKey, pk)
        surplus = math.max(0, surplus + donated - goalAmount)
        prevOrd = ord
    end

    -- Current period had no record. Apply gap depletion from the last record
    -- through every period up to (but not including) current.
    if prevOrd then
        local endOrd = _PeriodOrdinal(currentPeriodKey)
        local missed = endOrd - prevOrd - 1
        if missed > 0 then
            if missed * goalAmount >= surplus then
                surplus = 0
            else
                surplus = surplus - missed * goalAmount
            end
        end
    end
    return surplus
end

-- Update a member's rank index (called on roster refresh)
function DB:SetMemberRank(memberKey, rankIndex)
    if self._readOnly then return end
    local rec = self:GetMemberRecord(memberKey)
    rec.rankIndex = rankIndex
end

-- ── Donation event log ──────────────────────────────────────────────────────

-- Add a deposit event to the log. Returns true if added (new), false if dup.
-- id is a stable fingerprint. The aggregated donations[periodKey] total is
-- recomputed by summing all events for that member+period, so we stay
-- consistent even if some events were imported from pre-log aggregates.
function DB:AddDonationEvent(event)
    if self._readOnly then return false end
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

-- Rebuild donations[memberKey][periodKey] from the log.
-- If we have real events for this period, their sum is authoritative — we
-- overwrite the stored total (including healing any pre-existing bloat from
-- old synthetic-based code paths). If we have no real events, preserve the
-- stored aggregate so data received via DONATION_BATCH from other clients
-- isn't lost.
function DB:_RecomputePeriodTotal(memberKey, periodKey)
    local realSum = 0
    local hasReal = false
    local latestTs = 0
    for _, e in ipairs(self.sv.donationLog or {}) do
        if e.memberKey == memberKey and e.periodKey == periodKey then
            if not e.synthetic then
                realSum = realSum + (e.amount or 0)
                hasReal = true
            end
            if (e.timestamp or 0) > latestTs then latestTs = e.timestamp end
        end
    end

    local rec = self:GetMemberRecord(memberKey)
    local existing = rec.records[periodKey] or 0
    if type(existing) == "table" then
        existing = math.max(existing.own or 0, existing.synced or 0)
    end

    if hasReal then
        -- Log wins: overwrite with the real sum so stale/bloated aggregates
        -- are healed on next scan or incoming event.
        rec.records[periodKey] = realSum
    else
        -- No detail available — keep whatever aggregate we have.
        rec.records[periodKey] = existing
    end

    if latestTs > 0 then
        rec.lastDeposit = math.max(rec.lastDeposit or 0, latestTs)
    end
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
-- NOTE: we used to create "synthetic" events in donationLog to preserve
-- aggregate totals received before per-deposit DEPOSIT events arrived. That
-- caused runaway double-counting because real events would later cover the
-- same amount without removing the synthetic. We no longer touch donationLog
-- here — aggregate totals live in rec.records[periodKey], and real event
-- detail is added exclusively via AddDonationEvent().
function DB:SetDonationTotal(memberKey, periodKey, newTotal)
    if self._readOnly then return end
    if not memberKey or not periodKey or type(newTotal) ~= "number" then return end

    local rec = self:GetMemberRecord(memberKey)
    local current = rec.records[periodKey] or 0
    if type(current) == "table" then
        current = math.max(current.own or 0, current.synced or 0)
    end

    -- Count real (non-synthetic) events we already have for this period.
    local realLogSum = 0
    local hasRealEvents = false
    for _, e in ipairs(self.sv.donationLog or {}) do
        if e.memberKey == memberKey and e.periodKey == periodKey and not e.synthetic then
            realLogSum = realLogSum + (e.amount or 0)
            hasRealEvents = true
        end
    end

    -- If we have real event detail for this period, the log is authoritative.
    -- Reject any aggregate that disagrees — otherwise one client's bloated DB
    -- (e.g. from legacy synthetic double-counts) propagates across the guild
    -- via DONATION_BATCH and poisons everyone.
    if hasRealEvents then
        if realLogSum > current then
            rec.records[periodKey] = realLogSum
            rec.lastDeposit = time()
        elseif current ~= realLogSum then
            -- current was already bloated/stale — heal it.
            rec.records[periodKey] = realLogSum
        end
        return
    end

    -- No real events: trust the incoming aggregate, max-merge so we don't
    -- drop totals a different client previously shared with us.
    if newTotal > current then
        rec.records[periodKey] = newTotal
        rec.lastDeposit = time()
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
