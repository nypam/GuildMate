-- GuildMate: Database layer
-- Defines the SavedVariables schema and provides clean accessors.
-- guildMate.lua loads first and creates the addon; we fetch it here.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local DB = {}
GM.DB = DB

-- Default schema — merged with any existing SavedVariables on load
DB.defaults = {
    version = 1,

    -- Active and past donation goals, keyed by a numeric id
    goals = {},

    -- Per-member donation records, keyed by "Name-Realm"
    donations = {},

    -- Persisted transaction fingerprints for deduplication across reloads.
    -- [fingerprint] = expiry Unix timestamp (pruned after TRANSACTION_TTL seconds)
    seenTransactions = {},

    -- Addon-wide settings
    settings = {
        -- Rank indices (0-based) whose members see the officer view.
        -- 0 = Guild Master is always implicitly included.
        officerRanks = { [0] = true, [1] = true },

        reminderEnabled = true,
        reminderMessage = "Hi %s! Don't forget the %p guild donation goal of %g. You've donated %d so far.",

        -- "GUILD" | "OFFICER" | "OFF"
        announceChannel = "GUILD",

        -- Announce in /g when a member meets their donation goal
        goalMetAnnounce = true,

        -- Main window geometry
        windowWidth  = 900,
        windowHeight = 550,
        windowX      = nil,
        windowY      = nil,

        -- Minimap button angle
        minimapPos   = 45,
    },
}

-- Called from guildMate.lua:OnInitialize after GuildMateDB is available
function DB:Init()
    GuildMateDB = GuildMateDB or {}
    self:_Migrate(GuildMateDB)
    self.sv = GuildMateDB
end

-- Shallow-merge defaults into an existing (or empty) saved-variable table
function DB:_Migrate(sv)
    for k, v in pairs(self.defaults) do
        if sv[k] == nil then
            if type(v) == "table" then
                sv[k] = self:_DeepCopy(v)
            else
                sv[k] = v
            end
        end
    end

    -- Nested: settings
    if sv.settings then
        for k, v in pairs(self.defaults.settings) do
            if sv.settings[k] == nil then
                sv.settings[k] = (type(v) == "table") and self:_DeepCopy(v) or v
            end
        end
    end
end

function DB:_DeepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = (type(v) == "table") and self:_DeepCopy(v) or v
    end
    return copy
end

-- ── Settings helpers ──────────────────────────────────────────────────────────

function DB:GetSetting(key)
    return self.sv.settings[key]
end

function DB:SetSetting(key, value)
    self.sv.settings[key] = value
end

function DB:IsOfficerRank(rankIndex)
    if rankIndex == 0 then return true end  -- Guild Master always
    return self.sv.settings.officerRanks[rankIndex] == true
end

-- ── Goal helpers ──────────────────────────────────────────────────────────────

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

-- ── Donation record helpers ───────────────────────────────────────────────────

-- Returns (or creates) the donation record for a member key ("Name-Realm")
function DB:GetMemberRecord(memberKey)
    if not self.sv.donations[memberKey] then
        self.sv.donations[memberKey] = {
            records     = {},   -- [periodKey] = { own=N, synced=N }
            lastDeposit = 0,
            rankIndex   = -1,
        }
    end
    return self.sv.donations[memberKey]
end

-- Ensure a period entry is in {own, synced} format.
-- Migrates legacy plain-number entries written by older addon versions.
local function _Normalize(rec, periodKey)
    local r = rec.records[periodKey]
    if r == nil then
        rec.records[periodKey] = { own = 0, synced = 0 }
    elseif type(r) == "number" then
        rec.records[periodKey] = { own = r, synced = 0 }
    end
    return rec.records[periodKey]
end

-- Add copper from a bank transaction this client personally read.
-- Returns the new effective total (max of own and synced).
function DB:AddDonation(memberKey, periodKey, copper)
    local rec = self:GetMemberRecord(memberKey)
    local r = _Normalize(rec, periodKey)
    r.own = r.own + copper
    rec.lastDeposit = time()
    return math.max(r.own, r.synced)
end

-- Donated copper for a member in a specific period (0 if none).
-- Returns max(own, synced) so either source produces the correct total.
function DB:GetDonated(memberKey, periodKey)
    local rec = self.sv.donations[memberKey]
    if not rec then return 0 end
    local r = rec.records[periodKey]
    if not r then return 0 end
    if type(r) == "number" then return r end  -- legacy entry not yet normalised
    return math.max(r.own or 0, r.synced or 0)
end

-- Update a member's rank index (called on roster refresh)
function DB:SetMemberRank(memberKey, rankIndex)
    local rec = self:GetMemberRecord(memberKey)
    rec.rankIndex = rankIndex
end

-- ── Transaction deduplication ─────────────────────────────────────────────────

-- How long (seconds) to remember a fingerprint — 45 days covers any period
local TRANSACTION_TTL = 45 * 86400

function DB:HasSeenTransaction(fp)
    local expiry = self.sv.seenTransactions[fp]
    if not expiry then return false end
    if time() > expiry then
        self.sv.seenTransactions[fp] = nil  -- expired; treat as unseen
        return false
    end
    return true
end

function DB:MarkTransactionSeen(fp)
    self.sv.seenTransactions[fp] = time() + TRANSACTION_TTL
end

-- Remove fingerprints whose TTL has elapsed. Call occasionally (e.g. on login).
function DB:PruneSeenTransactions()
    local now = time()
    for fp, expiry in pairs(self.sv.seenTransactions) do
        if now > expiry then
            self.sv.seenTransactions[fp] = nil
        end
    end
end

-- ── Idempotent total setter (used by comm sync) ───────────────────────────────

-- Updates the synced (comm-received) total to max(current_synced, newTotal).
-- Never touches own (bank-captured) total, so the two sources stay independent.
function DB:SetDonationTotal(memberKey, periodKey, newTotal)
    local rec = self:GetMemberRecord(memberKey)
    local r = _Normalize(rec, periodKey)
    if newTotal > r.synced then
        r.synced = newTotal
        rec.lastDeposit = time()
    end
end
