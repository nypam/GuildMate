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

-- ── Scan status toast ───────────────────────────────────────────────────────
-- Small floating indicator anchored below the tradeskill/craft window so the
-- user knows we're scanning + broadcasting and should keep the window open.

local _scanToast = nil
local _scanToastHideTimer = nil

local function _GetScanToast()
    if _scanToast then return _scanToast end

    local f = CreateFrame("Frame", "GuildMateScanToast", UIParent)
    f:SetSize(260, 42)
    f:SetFrameStrata("DIALOG")
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.05, 0.05, 0.08, 0.92)
    f._bg = bg

    -- Border (1px, colored to match state)
    local function Edge(p1, r1, p2, r2, w, h)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetPoint(p1, f, r1)
        t:SetPoint(p2, f, r2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        return t
    end
    f._borderTop    = Edge("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, 1)
    f._borderBottom = Edge("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, 1)
    f._borderLeft   = Edge("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", 1, nil)
    f._borderRight  = Edge("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", 1, nil)

    -- GuildMate accent strip (left edge)
    local accent = f:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    accent:SetVertexColor(0.29, 0.56, 0.85, 0.9)  -- GuildMate blue

    -- Label
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -6)
    title:SetText("|cff4A90D9Guild|r|cffffffffMate|r")
    f._title = title

    local msg = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    msg:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    msg:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    msg:SetJustifyH("LEFT")
    f._msg = msg

    _scanToast = f
    return f
end

local function _SetBorderColor(f, r, g, b, a)
    for _, side in ipairs({ f._borderTop, f._borderBottom, f._borderLeft, f._borderRight }) do
        side:SetColorTexture(r, g, b, a)
    end
end

local function _AnchorToast(f)
    -- Prefer the profession window that's actually showing
    if _G["TradeSkillFrame"] and TradeSkillFrame:IsShown() then
        f:ClearAllPoints()
        f:SetPoint("TOP", TradeSkillFrame, "BOTTOM", 0, -4)
        return true
    elseif _G["CraftFrame"] and CraftFrame:IsShown() then
        f:ClearAllPoints()
        f:SetPoint("TOP", CraftFrame, "BOTTOM", 0, -4)
        return true
    end
    return false
end

local function _ShowScanToast(message, color)
    local f = _GetScanToast()
    if not _AnchorToast(f) then return end  -- no window open; skip
    f._msg:SetText(color .. message .. "|r")
    _SetBorderColor(f, 0.29, 0.56, 0.85, 0.7)
    f:Show()
    if _scanToastHideTimer then
        _scanToastHideTimer:Cancel()
        _scanToastHideTimer = nil
    end
end

local function _CompleteScanToast(message)
    local f = _scanToast
    if not f or not f:IsShown() then return end
    f._msg:SetText("|cff5fba47" .. message .. "|r")
    _SetBorderColor(f, 0.37, 0.73, 0.28, 0.9)  -- green success
    if _scanToastHideTimer then _scanToastHideTimer:Cancel() end
    _scanToastHideTimer = C_Timer.NewTimer(4, function()
        if _scanToast then _scanToast:Hide() end
        _scanToastHideTimer = nil
    end)
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
    -- Re-entrancy guard: expanding headers / resetting filters fires
    -- TRADE_SKILL_UPDATE, which would call us again and loop forever.
    if self._scanningRecipes then return end

    -- Time-based debounce: TRADE_SKILL_UPDATE fires many times per window
    -- open (once per filter change, once per header expand). Without this,
    -- 10+ deferred scans stack up and freeze the game iterating 100+ recipes
    -- and calling expensive APIs (GetTradeSkillRecipeLink, etc.) each time.
    local now = GetTime()
    if self._lastRecipeScan and (now - self._lastRecipeScan) < 5 then return end

    self._scanningRecipes = true
    self._lastRecipeScan = now

    _ShowScanToast("Scanning recipes — keep this window open\226\128\166", "|cffffffff")

    local scanResult
    local ok, err = pcall(function() scanResult = self:_DoScanRecipes() end)
    self._scanningRecipes = false
    if not ok then
        GM:Print("|cffcc3333GuildMate:|r ScanRecipes error: " .. tostring(err))
        return
    end

    if scanResult then
        _CompleteScanToast(string.format("Synced %d %s recipes to the guild",
            scanResult.count or 0, scanResult.profName or "?"))
    end
end

function Professions:_DoScanRecipes()
    -- Only works when tradeskill window is open
    local getNumTS = _G["GetNumTradeSkills"]
    local getTSInfo = _G["GetTradeSkillInfo"]
    local getTSReagent = _G["GetTradeSkillReagentInfo"]
    local getNumReagents = _G["GetTradeSkillNumReagents"]
    local getTSIcon = _G["GetTradeSkillIcon"]
    local getTSItemLink = _G["GetTradeSkillItemLink"]
    local getTSRecipeLink = _G["GetTradeSkillRecipeLink"]

    if not getNumTS or not getTSInfo then return end

    -- Expand every header so recipes within are enumerated and we can
    -- capture their category. Each Expand call fires TRADE_SKILL_UPDATE,
    -- but our re-entrancy guard + 5s debounce prevent a cascade.
    -- NOTE: we deliberately do NOT reset the user's filters — doing so
    -- fires extra events and causes visible UI stutter. If a user has a
    -- filter active, scanned recipes will miss categories — they can
    -- remove the filter and re-open to rescan.
    local expandFn = _G["ExpandTradeSkillSubClass"]
    if expandFn then
        local n = getNumTS() or 0
        for i = n, 1, -1 do
            local _, sType = getTSInfo(i)
            if sType == "header" then pcall(expandFn, i) end
        end
    end

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

    return { count = recipeOrder, profName = profName, changed = changed }
end

-- ── Enchanting (Craft API — different from TradeSkill in TBC) ──────────────
-- Enchanting uses CraftFrame + GetCraft* APIs, not TradeSkill. This is a TBC
-- quirk — enchanting was built as a "craft" before the tradeskill system existed.

-- Returns true if ANY of our locally-scanned recipes for the given profession
-- are missing category info — a signal that we need to force a re-scan so the
-- new category-capturing code can fill them in.
local function _NeedsRecategorize(profName)
    local db = GM.DB.sv.recipes2 and GM.DB.sv.recipes2[profName]
    if not db then return false end
    local playerName = UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or "?"
    local mk = GM.Utils.MemberKey(playerName, realm)
    for _, data in pairs(db) do
        if data.crafters then
            for _, ck in ipairs(data.crafters) do
                if ck == mk and not data.category then
                    return true
                end
            end
        end
    end
    return false
end

function Professions:ScanCraftRecipes()
    if self._scanningCraft then return end

    -- Force a rescan if our existing Enchanting data has no category info
    -- (e.g. scanned under an older version). This keeps the debounce while
    -- ensuring one-time migration works automatically.
    local forceRescan = _NeedsRecategorize("Enchanting")

    local now = GetTime()
    if not forceRescan and self._lastCraftScan and (now - self._lastCraftScan) < 5 then return end

    self._scanningCraft = true
    self._lastCraftScan = now

    _ShowScanToast("Scanning enchants — keep this window open\226\128\166", "|cffffffff")

    local scanResult
    local ok, err = pcall(function() scanResult = self:_DoScanCraftRecipes() end)
    self._scanningCraft = false
    if not ok then
        GM:Print("|cffcc3333GuildMate:|r ScanCraftRecipes error: " .. tostring(err))
        return
    end

    if scanResult then
        _CompleteScanToast(string.format("Synced %d %s recipes to the guild",
            scanResult.count or 0, scanResult.profName or "?"))
    end
end

function Professions:_DoScanCraftRecipes()
    local getNumCrafts = _G["GetNumCrafts"]
    local getCraftInfo = _G["GetCraftInfo"]
    local getCraftName = _G["GetCraftName"]
    local getCraftIcon = _G["GetCraftIcon"]
    local getCraftItemLink = _G["GetCraftItemLink"]
    local getCraftNumReagents = _G["GetCraftNumReagents"]
    local getCraftReagent = _G["GetCraftReagentInfo"]

    if not getNumCrafts or not getCraftInfo then return end

    -- Expand every header so recipes within collapsed sections are returned.
    -- TBC Anniversary: the Craft window can hide entire sub-categories when
    -- their header is collapsed — without this we might scan 0 recipes.
    local expandCraftFn = _G["ExpandCraftSkillLine"]
    if expandCraftFn then
        local n = getNumCrafts() or 0
        for i = n, 1, -1 do
            local _, _, sType = getCraftInfo(i)
            if sType == "header" then pcall(expandCraftFn, i) end
        end
    end

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

        -- Robust header detection:
        --  1. Explicit craftType == "header" (standard case)
        --  2. Fallback: no reagents AND no item link — TBC Anniversary
        --     sometimes returns nil/empty craftType for enchanting
        --     category dividers.
        local isHeader = (craftType == "header")
        if not isHeader and name then
            local hasLink = getCraftItemLink and getCraftItemLink(i) ~= nil
            local reagentCount = getCraftNumReagents and getCraftNumReagents(i) or 0
            if reagentCount == 0 and not hasLink then
                isHeader = true
            end
        end

        if name and isHeader then
            currentCategory = name
            if not seenCategories[name] then
                categoryOrder = categoryOrder + 1
                seenCategories[name] = categoryOrder
            end
        elseif name then
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

    return { count = recipeOrder, profName = profName, changed = changed }
end

-- ── Recipe comm: broadcast ───────────────────────────────────────────────────

function Professions:BroadcastRecipes(memberKey, profName)
    local db = _EnsureRecipeDB()
    local profRecipes = db[profName]
    if not profRecipes then return end

    -- Encode a string for the wire: escape backslash, field separators, and
    -- list separators so reagent names / categories survive round-trip.
    local function encode(s)
        return (s or "")
            :gsub("\\", "\\\\")
            :gsub(":", "\\c")
            :gsub(",", "\\m")
            :gsub(";", "\\s")
            :gsub("~", "\\t")
            :gsub("|", "\\p")
    end

    -- Build list: "spellID~icon~catOrder~categoryName~reagents;..."
    --   reagents = "name:count:icon,..."
    -- Older v0.4.x clients expect 3-field entries (spellID~icon~reagents);
    -- the new parser on the receiver side accepts both layouts.
    local parts = {}
    for spellIDStr, data in pairs(profRecipes) do
        for _, ck in ipairs(data.crafters) do
            if ck == memberKey then
                local iconStr = data.icon and tostring(data.icon) or "0"
                local catOrder = data.categoryOrder and tostring(data.categoryOrder) or "0"
                local catName = encode(data.category or "")
                local reagentParts = {}
                if data.reagents then
                    for _, r in ipairs(data.reagents) do
                        local rIcon = r.icon and tostring(r.icon) or "0"
                        reagentParts[#reagentParts + 1] = encode(r.name or "?") .. ":" .. (r.count or 1) .. ":" .. rIcon
                    end
                end
                local reagentStr = #reagentParts > 0 and table.concat(reagentParts, ",") or ""
                parts[#parts + 1] = spellIDStr .. "~" .. iconStr .. "~" .. catOrder .. "~" .. catName .. "~" .. reagentStr
                break
            end
        end
    end

    if #parts == 0 then return end

    -- RECIPE_UPDATE|memberKey|profName|spellID~icon~catOrder~category~reagents;...
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
    local existing = db[memberKey]

    -- Dedupe: only broadcast if the skill data actually changed.
    -- TRADE_SKILL_UPDATE and friends fire constantly; without this, we
    -- send PROF_UPDATE on every event and melt the comm channel.
    local unchanged = false
    if existing and existing.skills then
        unchanged = true
        local oldCount = 0
        for _ in pairs(existing.skills) do oldCount = oldCount + 1 end
        if oldCount ~= count then
            unchanged = false
        else
            for k, v in pairs(skills) do
                local old = existing.skills[k]
                if not old or old.rank ~= v.rank or old.maxRank ~= v.maxRank then
                    unchanged = false
                    break
                end
            end
        end
    end

    if unchanged then return end

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
        -- Version gating happens in GM:OnCommReceived before we arrive here.

        -- RECIPE_UPDATE|memberKey|profName|<entry>;<entry>;...
        -- <entry> new format: spellID~icon~catOrder~category~reagents
        -- <entry> old format: spellID~icon~reagents
        local _, memberKey, profName, recipeStr = message:match("^([%w_]+)|([^|]+)|([^|]+)|(.+)$")
        if not memberKey or not profName or not recipeStr then return true end

        local db = _EnsureRecipeDB()
        if not db[profName] then db[profName] = {} end

        -- Reverse the encode() used in BroadcastRecipes.
        local function decode(s)
            if not s or s == "" then return nil end
            return (s:gsub("\\p", "|"):gsub("\\t", "~"):gsub("\\s", ";")
                     :gsub("\\m", ","):gsub("\\c", ":"):gsub("\\\\", "\\"))
        end

        for entry in recipeStr:gmatch("[^;]+") do
            -- Try new 5-field format first: spellID~icon~catOrder~category~reagents
            local spellIDStr, iconStr, catOrderStr, catNameRaw, reagentStr =
                entry:match("^(%d+)~(%d+)~(%d+)~([^~]*)~(.*)$")

            -- Fallback to old 3-field: spellID~icon~reagents
            if not spellIDStr then
                spellIDStr, iconStr, reagentStr = entry:match("^(%d+)~(%d+)~(.*)$")
            end
            -- Older still: spellID~icon
            if not spellIDStr then
                spellIDStr, iconStr = entry:match("^(%d+)~(%d+)$")
            end
            if not spellIDStr then
                spellIDStr = entry:match("^(%d+)$")
            end

            if spellIDStr then
                local key = spellIDStr
                local iconID = tonumber(iconStr)

                if not db[profName][key] then
                    db[profName][key] = { crafters = {}, reagents = {} }
                end
                if iconID and iconID > 0 then
                    db[profName][key].icon = iconID
                end

                -- Category info (new format only)
                if catOrderStr then
                    local catOrder = tonumber(catOrderStr) or 0
                    if catOrder > 0 then
                        db[profName][key].categoryOrder = catOrder
                    end
                end
                if catNameRaw and catNameRaw ~= "" then
                    db[profName][key].category = decode(catNameRaw)
                end

                -- Parse reagents if provided and we don't have them yet
                if reagentStr and reagentStr ~= "" and #db[profName][key].reagents == 0 then
                    for rEntry in reagentStr:gmatch("[^,]+") do
                        local rName, rCount, rIcon = rEntry:match("^(.+):(%d+):(%d+)$")
                        if rName then
                            db[profName][key].reagents[#db[profName][key].reagents + 1] = {
                                name  = decode(rName),
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
