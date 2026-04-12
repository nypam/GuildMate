-- GuildMate: Profession tracking core
-- Scans own professions, broadcasts to guild, stores per-member data.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Utils = GM.Utils

local Professions = {}
GM.Professions = Professions

-- ── Known profession names (TBC) ─────────────────────────────────────────────

-- Profession names mapped to a canonical English key.
-- Supports English (enUS) and French (frFR) client locales.
-- The canonical key is what gets stored in the DB and displayed.
local PROF_CANONICAL = {
    -- English
    ["Alchemy"]         = "Alchemy",
    ["Blacksmithing"]   = "Blacksmithing",
    ["Enchanting"]      = "Enchanting",
    ["Engineering"]     = "Engineering",
    ["Herbalism"]       = "Herbalism",
    ["Jewelcrafting"]   = "Jewelcrafting",
    ["Leatherworking"]  = "Leatherworking",
    ["Mining"]          = "Mining",
    ["Skinning"]        = "Skinning",
    ["Tailoring"]       = "Tailoring",
    ["Cooking"]         = "Cooking",
    ["First Aid"]       = "First Aid",
    ["Fishing"]         = "Fishing",
    -- French (frFR)
    ["Alchimie"]              = "Alchemy",
    ["Forge"]                 = "Blacksmithing",
    ["Enchantement"]          = "Enchanting",
    ["Ing\195\169nierie"]     = "Engineering",
    ["Herboristerie"]         = "Herbalism",
    ["Joaillerie"]            = "Jewelcrafting",
    ["Travail du cuir"]       = "Leatherworking",
    ["Minage"]                = "Mining",
    ["D\195\169pe\195\167age"] = "Skinning",
    ["Couture"]               = "Tailoring",
    ["Cuisine"]               = "Cooking",
    ["Secourisme"]            = "First Aid",
    ["P\195\170che"]          = "Fishing",
}

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

-- Resolve a localized profession name to its canonical English key.
-- Returns nil if the name is not a known profession.
function Professions:Canonicalize(name)
    if ALL_PROFESSIONS[name] then return name end
    return PROF_CANONICAL[name]
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

-- ── Data pruning ─────────────────────────────────────────────────────────────

-- Remove profession/recipe data for members no longer in the guild roster.
function Professions:PruneStaleData(roster)
    if not roster or not next(roster) then return end

    -- Prune profession records for ex-members
    local profDB = GM.DB.sv.professions
    if profDB then
        for key in pairs(profDB) do
            if not roster[key] then
                profDB[key] = nil
            end
        end
    end

    -- Prune crafter entries in recipes
    local recipeDB = GM.DB.sv.recipes2
    if recipeDB then
        for _, profRecipes in pairs(recipeDB) do
            for _, recipeData in pairs(profRecipes) do
                if recipeData.crafters then
                    local clean = {}
                    for _, ck in ipairs(recipeData.crafters) do
                        if roster[ck] then
                            clean[#clean + 1] = ck
                        end
                    end
                    recipeData.crafters = clean
                end
            end
        end
    end
end

-- ── Recipe DB helpers ─────────────────────────────────────────────────────────
-- Recipes are keyed by spellID (number) so they're locale-independent.
-- At display time, GetSpellInfo(spellID) resolves the localized name + icon.

local function _EnsureRecipeDB()
    if not GM.DB.sv.recipes2 then
        GM.DB.sv.recipes2 = {}
    end
    return GM.DB.sv.recipes2
end

-- Resolve a spellID to { name, icon } for the current locale
function Professions:ResolveSpell(spellID)
    if not spellID or not GetSpellInfo then return nil, nil end
    local name, _, icon = GetSpellInfo(spellID)
    return name, icon
end

-- Get sorted recipe list for a profession.
-- Returns { { spellID, name, icon, itemLink, crafters, reagents, hasCrafter }, ... }
function Professions:GetRecipeList(professionName)
    local db = _EnsureRecipeDB()
    local profRecipes = db[professionName] or {}
    local result = {}

    for spellIDStr, data in pairs(profRecipes) do
        local spellID = tonumber(spellIDStr)
        local name, spellIcon = Professions:ResolveSpell(spellID)
        -- Fallback: use stored name if GetSpellInfo fails
        name = name or data.fallbackName or ("Spell " .. tostring(spellID))
        -- Prefer stored icon (from GetTradeSkillIcon = item icon) over spell icon
        local icon = data.icon or spellIcon

        result[#result + 1] = {
            spellID       = spellID,
            name          = name,
            icon          = icon,
            itemLink      = data.itemLink,
            crafters      = data.crafters or {},
            reagents      = data.reagents or {},
            hasCrafter    = data.crafters and #data.crafters > 0,
            category      = data.category,
            categoryOrder = data.categoryOrder or 9999,
            recipeOrder   = data.recipeOrder or 9999,
        }
    end

    -- Sort: follow in-game order (category, then position within category).
    -- Recipes without category info sink to the bottom, sorted alphabetically.
    table.sort(result, function(a, b)
        if a.categoryOrder ~= b.categoryOrder then
            return a.categoryOrder < b.categoryOrder
        end
        if a.recipeOrder ~= b.recipeOrder then
            return a.recipeOrder < b.recipeOrder
        end
        return a.name < b.name
    end)

    return result
end

-- ── Recipe scanning ──────────────────────────────────────────────────────────

-- Extract spellID from a tradeskill recipe link.
-- TBC format: "|cffffd000|Henchant:SPELLID|h[Name]|h|r"
-- Also handles: "|Htrade:...:SPELLID|h" and "|Hspell:SPELLID|h"
local function _ExtractSpellID(link)
    if not link then return nil end
    local id = link:match("|Henchant:(%d+)|")
        or link:match("|Htrade:[^:]*:(%d+)|")
        or link:match("|Hspell:(%d+)|")
    return tonumber(id)
end

function Professions:ScanRecipes()
    -- Only works when tradeskill window is open
    local getNumTS = _G["GetNumTradeSkills"]
    local getTSInfo = _G["GetTradeSkillInfo"]
    local getTSReagent = _G["GetTradeSkillReagentInfo"]
    local getNumReagents = _G["GetTradeSkillNumReagents"]
    local getTSIcon = _G["GetTradeSkillIcon"]
    local getTSItemLink = _G["GetTradeSkillItemLink"]
    local getTSRecipeLink = _G["GetTradeSkillRecipeLink"]

    if not getNumTS or not getTSInfo then return end

    local numSkills = getNumTS()
    if not numSkills or numSkills == 0 then return end

    -- Determine which profession is open (may be localized)
    local profName = nil
    if _G["GetTradeSkillLine"] then
        local rawName = GetTradeSkillLine()
        profName = Professions:Canonicalize(rawName)
    end
    if not profName then
        for i = 1, numSkills do
            local name, skillType = getTSInfo(i)
            if skillType == "header" then
                local canonical = Professions:Canonicalize(name)
                if canonical then
                    profName = canonical
                    break
                end
            end
        end
    end
    if not profName then return end

    local playerName = UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or "Unknown"
    local memberKey = Utils.MemberKey(playerName, realm)

    local db = _EnsureRecipeDB()
    if not db[profName] then db[profName] = {} end

    local changed = false
    local currentCategory = nil
    local categoryOrder = 0
    local recipeOrder = 0
    local seenCategories = {}

    for i = 1, numSkills do
        local name, skillType = getTSInfo(i)
        if name and skillType and (skillType == "header" or skillType == "subheader") then
            -- Category separator — remember it for the recipes that follow
            currentCategory = name
            if not seenCategories[name] then
                categoryOrder = categoryOrder + 1
                seenCategories[name] = categoryOrder
            end
        elseif name and skillType then
            recipeOrder = recipeOrder + 1

            -- Try to get spellID from recipe link
            local recipeLink = getTSRecipeLink and getTSRecipeLink(i)
            local spellID = _ExtractSpellID(recipeLink)

            -- If no spell link available, try item link
            if not spellID and getTSItemLink then
                local itemLink = getTSItemLink(i)
                spellID = _ExtractSpellID(itemLink)
            end

            -- Fallback: use a hash of the name (not ideal but functional)
            if not spellID then
                spellID = 0
                for c = 1, #name do
                    spellID = spellID * 31 + string.byte(name, c)
                end
                spellID = spellID % 1000000
            end

            local key = tostring(spellID)

            if not db[profName][key] then
                db[profName][key] = { crafters = {}, reagents = {} }
                changed = true
            end

            local recipe = db[profName][key]

            -- Store fallback name (localized, for display if GetSpellInfo fails)
            recipe.fallbackName = name

            -- Store category + in-window position for grouped, ordered display
            if currentCategory then
                recipe.category = currentCategory
                recipe.categoryOrder = seenCategories[currentCategory]
            end
            recipe.recipeOrder = recipeOrder

            -- Always refresh icon when window is open
            if getTSIcon then
                local newIcon = getTSIcon(i)
                if newIcon then recipe.icon = newIcon end
            end

            -- Store item link for tooltip
            if getTSItemLink then
                local newLink = getTSItemLink(i)
                if newLink then
                    recipe.itemLink = newLink
                    if GetItemInfo then GetItemInfo(newLink) end
                end
            end

            -- Add this player as crafter
            local alreadyCrafter = false
            for _, ck in ipairs(recipe.crafters) do
                if ck == memberKey then alreadyCrafter = true; break end
            end
            if not alreadyCrafter then
                recipe.crafters[#recipe.crafters + 1] = memberKey
                changed = true
            end

            -- Scan reagents (rescan if empty or missing icons)
            local needsRescan = #recipe.reagents == 0
            if not needsRescan and #recipe.reagents > 0 and not recipe.reagents[1].icon then
                recipe.reagents = {}
                needsRescan = true
            end
            if needsRescan and getNumReagents and getTSReagent then
                local numReagents = getNumReagents(i)
                if numReagents and numReagents > 0 then
                    for j = 1, numReagents do
                        local reagentName, reagentTex, reagentCount = getTSReagent(i, j)
                        if reagentName then
                            recipe.reagents[#recipe.reagents + 1] = {
                                name  = reagentName,
                                count = reagentCount or 1,
                                icon  = reagentTex,
                            }
                        end
                    end
                    changed = true
                end
            end
        end
    end

    if changed then
        self:BroadcastRecipes(memberKey, profName)
        GM.MainFrame:RefreshActiveView()
    end
end

-- ── Enchanting (Craft API — different from TradeSkill in TBC) ──────────────
-- Enchanting uses CraftFrame + GetCraft* APIs, not TradeSkill. This is a TBC
-- quirk — enchanting was built as a "craft" before the tradeskill system existed.

function Professions:ScanCraftRecipes()
    local getNumCrafts = _G["GetNumCrafts"]
    local getCraftInfo = _G["GetCraftInfo"]
    local getCraftName = _G["GetCraftName"]
    local getCraftIcon = _G["GetCraftIcon"]
    local getCraftItemLink = _G["GetCraftItemLink"]
    local getCraftNumReagents = _G["GetCraftNumReagents"]
    local getCraftReagent = _G["GetCraftReagentInfo"]

    if not getNumCrafts or not getCraftInfo then return end

    local numCrafts = getNumCrafts()
    if not numCrafts or numCrafts == 0 then return end

    -- CraftFrame is only Enchanting in TBC (Beast Training uses it too but we
    -- canonicalize by name so non-enchanting crafts will simply fail Canonicalize).
    local rawName = getCraftName and getCraftName() or nil
    local profName = rawName and Professions:Canonicalize(rawName) or nil
    if not profName then
        -- Fallback: if no craft name API, assume Enchanting if player has the skill
        profName = "Enchanting"
    end

    local playerName = UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or "Unknown"
    local memberKey = Utils.MemberKey(playerName, realm)

    local db = _EnsureRecipeDB()
    if not db[profName] then db[profName] = {} end

    local changed = false
    local currentCategory = nil
    local categoryOrder = 0
    local recipeOrder = 0
    local seenCategories = {}

    for i = 1, numCrafts do
        local name, _, craftType = getCraftInfo(i)
        if name and craftType == "header" then
            currentCategory = name
            if not seenCategories[name] then
                categoryOrder = categoryOrder + 1
                seenCategories[name] = categoryOrder
            end
        elseif name and craftType then
            recipeOrder = recipeOrder + 1

            local recipeLink = getCraftItemLink and getCraftItemLink(i)
            local spellID = _ExtractSpellID(recipeLink)

            if not spellID then
                -- Hash fallback
                spellID = 0
                for c = 1, #name do
                    spellID = spellID * 31 + string.byte(name, c)
                end
                spellID = spellID % 1000000
            end

            local key = tostring(spellID)

            if not db[profName][key] then
                db[profName][key] = { crafters = {}, reagents = {} }
                changed = true
            end

            local recipe = db[profName][key]
            recipe.fallbackName = name

            -- Store category + in-window position for grouped, ordered display
            if currentCategory then
                recipe.category = currentCategory
                recipe.categoryOrder = seenCategories[currentCategory]
            end
            recipe.recipeOrder = recipeOrder

            if getCraftIcon then
                local newIcon = getCraftIcon(i)
                if newIcon then recipe.icon = newIcon end
            end

            if recipeLink then
                recipe.itemLink = recipeLink
                if GetItemInfo then GetItemInfo(recipeLink) end
            end

            -- Add self as crafter
            local alreadyCrafter = false
            for _, ck in ipairs(recipe.crafters) do
                if ck == memberKey then alreadyCrafter = true; break end
            end
            if not alreadyCrafter then
                recipe.crafters[#recipe.crafters + 1] = memberKey
                changed = true
            end

            -- Reagents
            local needsRescan = #recipe.reagents == 0
            if not needsRescan and #recipe.reagents > 0 and not recipe.reagents[1].icon then
                recipe.reagents = {}
                needsRescan = true
            end
            if needsRescan and getCraftNumReagents and getCraftReagent then
                local numReagents = getCraftNumReagents(i)
                if numReagents and numReagents > 0 then
                    for j = 1, numReagents do
                        local reagentName, reagentTex, reagentCount = getCraftReagent(i, j)
                        if reagentName then
                            recipe.reagents[#recipe.reagents + 1] = {
                                name  = reagentName,
                                count = reagentCount or 1,
                                icon  = reagentTex,
                            }
                        end
                    end
                    changed = true
                end
            end
        end
    end

    if changed then
        self:BroadcastRecipes(memberKey, profName)
        GM.MainFrame:RefreshActiveView()
    end
end

-- ── Recipe comm: broadcast ───────────────────────────────────────────────────

function Professions:BroadcastRecipes(memberKey, profName)
    local db = _EnsureRecipeDB()
    local profRecipes = db[profName]
    if not profRecipes then return end

    -- Build list: "spellID~icon~reagents;..." where reagents = "name:count:icon,..."
    local parts = {}
    for spellIDStr, data in pairs(profRecipes) do
        for _, ck in ipairs(data.crafters) do
            if ck == memberKey then
                local iconStr = data.icon and tostring(data.icon) or "0"
                -- Encode reagents with backslash-based escaping (safe for all item names)
                local reagentParts = {}
                if data.reagents then
                    for _, r in ipairs(data.reagents) do
                        local rIcon = r.icon and tostring(r.icon) or "0"
                        local safeName = (r.name or "?")
                            :gsub("\\", "\\\\")
                            :gsub(":", "\\c")
                            :gsub(",", "\\m")
                            :gsub(";", "\\s")
                            :gsub("~", "\\t")
                        reagentParts[#reagentParts + 1] = safeName .. ":" .. (r.count or 1) .. ":" .. rIcon
                    end
                end
                local reagentStr = #reagentParts > 0 and table.concat(reagentParts, ",") or ""
                parts[#parts + 1] = spellIDStr .. "~" .. iconStr .. "~" .. reagentStr
                break
            end
        end
    end

    if #parts == 0 then return end

    -- RECIPE_UPDATE|memberKey|profName|spellID~icon~reagents;...
    local msg = string.format("RECIPE_UPDATE|%s|%s|%s",
        memberKey, profName, table.concat(parts, ";"))

    GM:SendCommMessage("GuildMate", msg, "GUILD")
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
        if not isHeader and name and rank and rank > 0 then
            local canonical = Professions:Canonicalize(name)
            if canonical then
                skills[canonical] = { rank = rank, maxRank = maxRank or 375 }
            end
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
    local cmd = message:match("^([%w_]+)")

    if cmd == "RECIPE_UPDATE" then
        -- RECIPE_UPDATE|memberKey|profName|spellID~icon;spellID~icon;...
        local _, memberKey, profName, recipeStr = message:match("^([%w_]+)|([^|]+)|([^|]+)|(.+)$")
        if not memberKey or not profName or not recipeStr then return true end

        local db = _EnsureRecipeDB()
        if not db[profName] then db[profName] = {} end

        for entry in recipeStr:gmatch("[^;]+") do
            -- Parse: spellID~icon~reagents or spellID~icon or spellID
            local spellIDStr, iconStr, reagentStr = entry:match("^(%d+)~(%d+)~(.*)$")
            if not spellIDStr then
                spellIDStr, iconStr = entry:match("^(%d+)~(%d+)$")
            end
            if not spellIDStr then
                spellIDStr = entry:match("^(%d+)$")
            end
            if not spellIDStr then
                -- Legacy name-based entry, skip
            else
                local key = spellIDStr
                local iconID = tonumber(iconStr)

                if not db[profName][key] then
                    db[profName][key] = { crafters = {}, reagents = {} }
                end
                if iconID and iconID > 0 then
                    db[profName][key].icon = iconID
                end

                -- Parse reagents if provided and we don't have them yet
                if reagentStr and reagentStr ~= "" and #db[profName][key].reagents == 0 then
                    for rEntry in reagentStr:gmatch("[^,]+") do
                        local rName, rCount, rIcon = rEntry:match("^(.+):(%d+):(%d+)$")
                        if rName then
                            -- Reverse backslash-based encoding (decode in reverse order)
                            rName = rName:gsub("\\t", "~"):gsub("\\s", ";"):gsub("\\m", ","):gsub("\\c", ":"):gsub("\\\\", "\\")
                            db[profName][key].reagents[#db[profName][key].reagents + 1] = {
                                name  = rName,
                                count = tonumber(rCount) or 1,
                                icon  = tonumber(rIcon) or nil,
                            }
                        end
                    end
                end

                -- Add sender as crafter if not already listed
                local already = false
                for _, ck in ipairs(db[profName][key].crafters) do
                    if ck == memberKey then already = true; break end
                end
                if not already then
                    db[profName][key].crafters[#db[profName][key].crafters + 1] = memberKey
                end
            end
        end

        GM.MainFrame:RefreshActiveView()
        return true
    end

    if cmd ~= "PROF_UPDATE" then return false end

    -- PROF_UPDATE|memberKey|timestamp|Alchemy:375:375,Mining:300:375
    local _, memberKey, tsStr, profStr = message:match("^([%w_]+)|([^|]+)|(%d+)|(.+)$")
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

    -- Re-scan when tradeskill window opens (catches level-ups + recipes)
    pcall(function()
        GM:RegisterEvent("TRADE_SKILL_SHOW", function()
            C_Timer.After(0.5, function()
                Professions:ScanSelf()
                Professions:ScanRecipes()
            end)
        end)
    end)

    -- Fallback: hook TradeSkillFrame if event doesn't fire (TBC Anniversary)
    C_Timer.After(3, function()
        if _G["TradeSkillFrame"] then
            if not TradeSkillFrame._gmHooked then
                TradeSkillFrame._gmHooked = true
                TradeSkillFrame:HookScript("OnShow", function()
                    C_Timer.After(0.5, function()
                        Professions:ScanSelf()
                        Professions:ScanRecipes()
                    end)
                end)
            end
        end
        -- Enchanting uses the separate Craft API / CraftFrame
        if _G["CraftFrame"] then
            if not CraftFrame._gmHooked then
                CraftFrame._gmHooked = true
                CraftFrame:HookScript("OnShow", function()
                    C_Timer.After(0.5, function()
                        Professions:ScanSelf()
                        Professions:ScanCraftRecipes()
                    end)
                end)
            end
        end
    end)

    pcall(function()
        GM:RegisterEvent("TRADE_SKILL_UPDATE", function()
            C_Timer.After(0.5, function()
                Professions:ScanSelf()
                Professions:ScanRecipes()
            end)
        end)
    end)

    -- Enchanting: Craft API events (separate from TradeSkill)
    pcall(function()
        GM:RegisterEvent("CRAFT_SHOW", function()
            C_Timer.After(0.5, function()
                Professions:ScanSelf()
                Professions:ScanCraftRecipes()
            end)
        end)
    end)
    pcall(function()
        GM:RegisterEvent("CRAFT_UPDATE", function()
            C_Timer.After(0.5, function()
                Professions:ScanSelf()
                Professions:ScanCraftRecipes()
            end)
        end)
    end)

    -- Also scan when skill lines change (level up a gathering prof, etc.)
    pcall(function()
        GM:RegisterEvent("SKILL_LINES_CHANGED", function()
            C_Timer.After(1, function() Professions:ScanSelf() end)
        end)
    end)
end
