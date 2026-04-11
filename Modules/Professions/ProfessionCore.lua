-- GuildMate: Profession tracking core
-- Scans own professions, broadcasts to guild, stores per-member data.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Utils = GM.Utils

local Professions = {}
GM.Professions = Professions

-- ── Known profession names (TBC) ─────────────────────────────────────────────

local PRIMARY_PROFESSIONS = {
    ["Alchemy"] = true,
    ["Blacksmithing"] = true,
    ["Enchanting"] = true,
    ["Engineering"] = true,
    ["Herbalism"] = true,
    ["Jewelcrafting"] = true,
    ["Leatherworking"] = true,
    ["Mining"] = true,
    ["Skinning"] = true,
    ["Tailoring"] = true,
}

local SECONDARY_PROFESSIONS = {
    ["Cooking"] = true,
    ["First Aid"] = true,
    ["Fishing"] = true,
}

local ALL_PROFESSIONS = {}
for k in pairs(PRIMARY_PROFESSIONS) do ALL_PROFESSIONS[k] = true end
for k in pairs(SECONDARY_PROFESSIONS) do ALL_PROFESSIONS[k] = true end

function Professions:IsPrimary(name)
    return PRIMARY_PROFESSIONS[name] or false
end

-- ── DB helpers ───────────────────────────────────────────────────────────────

local function _EnsureDB()
    if not GM.DB.sv.professions then
        GM.DB.sv.professions = {}
    end
    return GM.DB.sv.professions
end

-- Get profession data for a single member. Returns nil if no data.
function Professions:GetMemberProfessions(memberKey)
    local db = _EnsureDB()
    return db[memberKey]
end

-- Get a sorted roster of members who have a specific profession.
-- Returns { { memberKey, name, rank, maxRank, online, classFilename }, ... }
function Professions:GetProfessionRoster(professionName)
    local db = _EnsureDB()
    local roster = GM.Donations and GM.Donations:GetRoster() or {}
    local result = {}

    for memberKey, data in pairs(db) do
        if data.skills and data.skills[professionName] then
            local skill = data.skills[professionName]
            local info = roster[memberKey]
            result[#result + 1] = {
                memberKey     = memberKey,
                name          = info and info.name or memberKey,
                rank          = skill.rank or 0,
                maxRank       = skill.maxRank or 375,
                online        = info and info.online or false,
                classFilename = info and info.classFilename or "WARRIOR",
            }
        end
    end

    -- Sort: highest rank first, then alphabetically
    table.sort(result, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        return a.name < b.name
    end)

    return result
end

-- Get overview stats for all professions.
-- Returns { { name, count, avgRank, maxPossible }, ... } sorted by name.
function Professions:GetOverview()
    local db = _EnsureDB()
    local stats = {}  -- [profName] = { total, sumRank, maxRank }

    for _, data in pairs(db) do
        if data.skills then
            for profName, skill in pairs(data.skills) do
                if not stats[profName] then
                    stats[profName] = { total = 0, sumRank = 0, maxRank = skill.maxRank or 375 }
                end
                stats[profName].total = stats[profName].total + 1
                stats[profName].sumRank = stats[profName].sumRank + (skill.rank or 0)
            end
        end
    end

    local result = {}
    for profName, s in pairs(stats) do
        result[#result + 1] = {
            name      = profName,
            count     = s.total,
            avgRank   = s.total > 0 and math.floor(s.sumRank / s.total) or 0,
            maxRank   = s.maxRank,
            isPrimary = PRIMARY_PROFESSIONS[profName] or false,
        }
    end

    -- Primary first, then secondary; alphabetical within groups
    table.sort(result, function(a, b)
        if a.isPrimary ~= b.isPrimary then return a.isPrimary end
        return a.name < b.name
    end)

    return result
end

-- ── Scanning own professions ─────────────────────────────────────────────────

function Professions:ScanSelf()
    if not GetNumSkillLines then return end

    local playerName = UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or "Unknown"
    local memberKey = Utils.MemberKey(playerName, realm)

    local skills = {}
    local numLines = GetNumSkillLines()

    for i = 1, numLines do
        local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if not isHeader and name and ALL_PROFESSIONS[name] and rank and rank > 0 then
            skills[name] = { rank = rank, maxRank = maxRank or 375 }
        end
    end

    -- Only update if we found at least one profession
    local count = 0
    for _ in pairs(skills) do count = count + 1 end
    if count == 0 then return end

    local db = _EnsureDB()
    db[memberKey] = {
        lastUpdate = time(),
        skills = skills,
    }

    -- Broadcast to guild
    self:BroadcastProfessions(memberKey)
end

-- ── Comm: broadcast ──────────────────────────────────────────────────────────

function Professions:BroadcastProfessions(memberKey)
    local db = _EnsureDB()
    local data = db[memberKey]
    if not data or not data.skills then return end

    -- Build message: PROF_UPDATE|memberKey|timestamp|Alchemy:375:375,Mining:300:375
    local parts = {}
    for profName, skill in pairs(data.skills) do
        parts[#parts + 1] = string.format("%s:%d:%d", profName, skill.rank, skill.maxRank)
    end

    if #parts == 0 then return end

    local msg = string.format("PROF_UPDATE|%s|%d|%s",
        memberKey, data.lastUpdate, table.concat(parts, ","))

    GM:SendCommMessage("GuildMate", msg, "GUILD")
end

-- ── Comm: receive ────────────────────────────────────────────────────────────

function Professions:OnCommReceived(message, _channel, sender)
    local cmd = message:match("^(%w+)")
    if cmd ~= "PROF_UPDATE" then return false end

    -- PROF_UPDATE|memberKey|timestamp|Alchemy:375:375,Mining:300:375
    local _, memberKey, tsStr, profStr = message:match("^(%w+)|(.+)|(%d+)|(.+)$")
    local timestamp = tonumber(tsStr)

    if not memberKey or not timestamp or not profStr then return true end

    local db = _EnsureDB()
    local existing = db[memberKey]

    -- Only accept newer data
    if existing and existing.lastUpdate and existing.lastUpdate >= timestamp then
        return true
    end

    -- Parse profession data
    local skills = {}
    for entry in profStr:gmatch("[^,]+") do
        local name, rank, maxRank = entry:match("^(.+):(%d+):(%d+)$")
        if name and rank then
            skills[name] = { rank = tonumber(rank), maxRank = tonumber(maxRank) or 375 }
        end
    end

    local count = 0
    for _ in pairs(skills) do count = count + 1 end
    if count == 0 then return true end

    db[memberKey] = {
        lastUpdate = timestamp,
        skills = skills,
    }

    -- Refresh UI if professions view is active
    GM.MainFrame:RefreshActiveView()

    return true
end

-- ── Event registration ───────────────────────────────────────────────────────

function Professions:RegisterEvents()
    -- Scan on login (delayed to let skill data load)
    C_Timer.After(12, function()
        Professions:ScanSelf()
    end)

    -- Re-scan when tradeskill window opens (catches level-ups)
    pcall(function()
        GM:RegisterEvent("TRADE_SKILL_SHOW", function()
            C_Timer.After(0.5, function() Professions:ScanSelf() end)
        end)
    end)

    pcall(function()
        GM:RegisterEvent("TRADE_SKILL_UPDATE", function()
            C_Timer.After(0.5, function() Professions:ScanSelf() end)
        end)
    end)

    -- Also scan when skill lines change (level up a gathering prof, etc.)
    pcall(function()
        GM:RegisterEvent("SKILL_LINES_CHANGED", function()
            C_Timer.After(1, function() Professions:ScanSelf() end)
        end)
    end)
end
