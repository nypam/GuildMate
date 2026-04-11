-- GuildMate: Profession view
-- Displays per-profession roster or overview — raw WoW frames.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Utils = GM.Utils

local ProfessionView = {}
GM.ProfessionView = ProfessionView

-- ── Profession icons ─────────────────────────────────────────────────────────

local PROF_ICONS = {
    ["Alchemy"]         = "Interface\\Icons\\Trade_Alchemy",
    ["Blacksmithing"]   = "Interface\\Icons\\Trade_BlackSmithing",
    ["Enchanting"]      = "Interface\\Icons\\Trade_Engraving",
    ["Engineering"]     = "Interface\\Icons\\Trade_Engineering",
    ["Herbalism"]       = "Interface\\Icons\\Trade_Herbalism",
    ["Jewelcrafting"]   = "Interface\\Icons\\INV_Misc_Gem_01",
    ["Leatherworking"]  = "Interface\\Icons\\Trade_LeatherWorking",
    ["Mining"]          = "Interface\\Icons\\Trade_Mining",
    ["Skinning"]        = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    ["Tailoring"]       = "Interface\\Icons\\Trade_Tailoring",
    ["Cooking"]         = "Interface\\Icons\\INV_Misc_Food_15",
    ["First Aid"]       = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    ["Fishing"]         = "Interface\\Icons\\Trade_Fishing",
}

-- ── Overview (parent "Professions" clicked) ──────────────────────────────────

-- All professions in display order
local ALL_PROF_LIST = {
    -- Primary
    "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism",
    "Jewelcrafting", "Leatherworking", "Mining", "Skinning", "Tailoring",
    -- Secondary
    "Cooking", "First Aid", "Fishing",
}

function ProfessionView:RenderOverview()
    local parent = GM.MainFrame:ClearContent()
    local L = Utils.LayoutBuilder(parent)

    L:AddText("|cffffffffGUILD PROFESSIONS|r", 16, GameFontHighlight)
    L:AddSpacer(8)

    -- Build stats lookup from DB
    local overviewMap = {}
    for _, o in ipairs(GM.Professions:GetOverview()) do
        overviewMap[o.name] = o
    end

    -- Build full list: all professions, with data if available
    local rows = {}
    for _, profName in ipairs(ALL_PROF_LIST) do
        local data = overviewMap[profName]
        rows[#rows + 1] = {
            name      = profName,
            count     = data and data.count or 0,
            avgRank   = data and data.avgRank or 0,
            maxRank   = data and data.maxRank or 375,
            highRank  = 0,
            isPrimary = GM.Professions:IsPrimary(profName),
        }
    end

    -- Find highest level per profession
    local db = GM.DB.sv.professions or {}
    for _, memberData in pairs(db) do
        if memberData.skills then
            for profName, skill in pairs(memberData.skills) do
                for _, r in ipairs(rows) do
                    if r.name == profName and skill.rank > r.highRank then
                        r.highRank = skill.rank
                    end
                end
            end
        end
    end

    -- Sort: highest level first, then alphabetical
    table.sort(rows, function(a, b)
        if a.highRank ~= b.highRank then return a.highRank > b.highRank end
        return a.name < b.name
    end)

    -- Column headers
    local headerRow = L:AddFrame(20)
    local function HeaderText(x, w, text)
        local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", headerRow, "LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetText("|cff888888" .. text .. "|r")
    end
    HeaderText(30, 140, "Profession")
    HeaderText(180, 70, "Members")
    HeaderText(255, 70, "Highest")
    HeaderText(330, 80, "Avg Level")

    L:AddSpacer(2)

    for _, prof in ipairs(rows) do
        local row = L:AddFrame(30)
        row:EnableMouse(true)

        local bgTex = row:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints()
        bgTex:SetTexture("Interface\\Buttons\\WHITE8X8")
        bgTex:SetVertexColor(0.12, 0.12, 0.12, 0.3)

        row:SetScript("OnEnter", function() bgTex:SetVertexColor(0.18, 0.18, 0.18, 0.5) end)
        row:SetScript("OnLeave", function() bgTex:SetVertexColor(0.12, 0.12, 0.12, 0.3) end)

        -- Click to navigate
        local profName = prof.name
        row:SetScript("OnMouseUp", function()
            PlaySound(856)
            local profId = "prof_" .. profName:lower():gsub(" ", "")
            GM.MainFrame:SelectModule(profId)
        end)

        -- Icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        icon:SetTexture(PROF_ICONS[prof.name] or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Name (dimmed if no members)
        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFs:SetPoint("LEFT", row, "LEFT", 30, 0)
        nameFs:SetWidth(140)
        nameFs:SetJustifyH("LEFT")
        if prof.count > 0 then
            nameFs:SetText(prof.name)
        else
            nameFs:SetText("|cff555555" .. prof.name .. "|r")
        end

        -- Member count
        local countFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        countFs:SetPoint("LEFT", row, "LEFT", 180, 0)
        countFs:SetWidth(70)
        countFs:SetJustifyH("LEFT")
        if prof.count > 0 then
            countFs:SetText("|cffaaaaaa" .. prof.count .. "|r")
        else
            countFs:SetText("|cff555555—|r")
        end

        -- Highest level
        local highFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        highFs:SetPoint("LEFT", row, "LEFT", 255, 0)
        highFs:SetWidth(70)
        highFs:SetJustifyH("LEFT")
        if prof.highRank > 0 then
            if prof.highRank >= prof.maxRank then
                highFs:SetText("|cff5fba47" .. prof.highRank .. "|r")
            else
                highFs:SetText("|cffd4af37" .. prof.highRank .. "|r")
            end
        else
            highFs:SetText("|cff555555—|r")
        end

        -- Avg level
        local avgFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        avgFs:SetPoint("LEFT", row, "LEFT", 330, 0)
        avgFs:SetWidth(80)
        avgFs:SetJustifyH("LEFT")
        if prof.count > 0 then
            avgFs:SetText(prof.avgRank .. " / " .. prof.maxRank)
        else
            avgFs:SetText("|cff555555—|r")
        end

        -- Progress bar (based on highest)
        local frac = prof.maxRank > 0 and (prof.highRank / prof.maxRank) or 0
        local barFrame = CreateFrame("Frame", nil, row)
        barFrame:SetHeight(8)
        barFrame:SetPoint("LEFT", row, "LEFT", 420, 0)
        barFrame:SetPoint("RIGHT", row, "RIGHT", -8, 0)

        local track = barFrame:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
        track:SetVertexColor(0.1, 0.1, 0.1, 0.8)

        local fill = barFrame:CreateTexture(nil, "BORDER")
        fill:SetPoint("TOPLEFT")
        fill:SetPoint("BOTTOMLEFT")
        fill:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
        if frac >= 1 then
            fill:SetVertexColor(0.37, 0.73, 0.28, 0.85)
        elseif frac > 0 then
            fill:SetVertexColor(0.29, 0.56, 0.85, 0.85)
        else
            fill:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        end
        fill:SetWidth(1)

        barFrame:SetScript("OnSizeChanged", function(_, w)
            fill:SetWidth(math.max(1, w * math.max(frac, 0.01)))
        end)
    end

    L:Finish()
end

-- ── Per-profession roster ────────────────────────────────────────────────────

local _profSearchText = ""

function ProfessionView:RenderProfession(professionName)
    local parent = GM.MainFrame:ClearContent()
    local L = Utils.LayoutBuilder(parent)

    -- Header
    local headerRow = L:AddRow(32)

    local profIcon = headerRow:CreateTexture(nil, "ARTWORK")
    profIcon:SetSize(24, 24)
    profIcon:SetPoint("LEFT", headerRow, "LEFT", 0, 0)
    profIcon:SetTexture(PROF_ICONS[professionName] or "Interface\\Icons\\INV_Misc_QuestionMark")

    local titleFs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetFont(Utils.Font(GameFontHighlight, 16))
    titleFs:SetPoint("LEFT", profIcon, "RIGHT", 8, 0)
    titleFs:SetText("|cffffffff" .. professionName:upper() .. "|r")

    -- Search
    local searchBox = CreateFrame("EditBox", "GuildMateProfSearchBox", headerRow, "InputBoxTemplate")
    searchBox:SetSize(140, 20)
    searchBox:SetPoint("RIGHT", headerRow, "RIGHT", -6, 0)
    searchBox:SetTextInsets(4, 4, 0, 0)
    searchBox:SetAutoFocus(false)
    searchBox:EnableMouse(true)
    searchBox:SetText(_profSearchText)
    searchBox:SetCursorPosition(0)

    local searchLabel = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("RIGHT", searchBox, "LEFT", -8, 0)
    searchLabel:SetText("|cffaaaaaa" .. GM.L["SEARCH"] .. "|r")

    local searchTimer = nil
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        _profSearchText = self:GetText():lower()
        if searchTimer then searchTimer:Cancel() end
        searchTimer = C_Timer.NewTimer(0.3, function()
            searchTimer = nil
            ProfessionView:RenderProfession(professionName)
            C_Timer.After(0, function()
                local box = _G["GuildMateProfSearchBox"]
                if box then
                    box:SetFocus()
                    box:SetCursorPosition(#box:GetText())
                end
            end)
        end)
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        _profSearchText = ""
        self:SetText("")
        self:ClearFocus()
        ProfessionView:RenderProfession(professionName)
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    L:AddSpacer(8)

    -- Roster
    local roster = GM.Professions:GetProfessionRoster(professionName)

    -- Apply search filter
    if _profSearchText ~= "" then
        local filtered = {}
        for _, r in ipairs(roster) do
            if r.name:lower():find(_profSearchText, 1, true) then
                filtered[#filtered + 1] = r
            end
        end
        roster = filtered
    end

    if #roster == 0 then
        L:AddText("|cffaaaaaaNo guild members found with " .. professionName .. ".|r", 12)
        L:Finish()
        return
    end

    -- Column headers
    local colRow = L:AddFrame(18)
    local function ColText(x, w, text)
        local fs = colRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", colRow, "LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetText("|cff888888" .. text .. "|r")
    end
    ColText(24, 160, "Name")
    ColText(200, 100, "Level")

    L:AddSpacer(2)

    -- Member rows
    local ROW_H = 30
    local addonUsers = GM.Donations:GetAddonUsers()

    for _, member in ipairs(roster) do
        local frac = member.maxRank > 0 and (member.rank / member.maxRank) or 0
        local row = L:AddFrame(ROW_H)
        row:EnableMouse(true)

        local bgTex = row:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints()
        bgTex:SetTexture("Interface\\Buttons\\WHITE8X8")
        bgTex:SetVertexColor(0.12, 0.12, 0.12, 0.3)

        row:SetScript("OnEnter", function()
            bgTex:SetVertexColor(0.18, 0.18, 0.18, 0.5)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(member.name, 1, 1, 1)
            GameTooltip:AddLine(string.format("%s: %d / %d", professionName, member.rank, member.maxRank), 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            bgTex:SetVertexColor(0.12, 0.12, 0.12, 0.3)
            GameTooltip:Hide()
        end)

        -- Addon square
        local square = row:CreateTexture(nil, "OVERLAY")
        square:SetSize(8, 8)
        square:SetPoint("LEFT", row, "LEFT", 6, 0)
        square:SetTexture("Interface\\Buttons\\WHITE8X8")
        if addonUsers[member.memberKey] then
            square:SetVertexColor(0.2, 0.8, 0.2, 1)
        else
            square:SetVertexColor(0.7, 0.15, 0.15, 1)
        end

        -- Name (class coloured)
        local classColor = Utils.ClassColor(member.classFilename)
        local classHex = string.format("|cff%02x%02x%02x",
            classColor[1] * 255, classColor[2] * 255, classColor[3] * 255)
        local onlineStr = member.online and "" or " |cffaaaaaa(offline)|r"

        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFs:SetPoint("LEFT", row, "LEFT", 22, 0)
        nameFs:SetWidth(170)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetText(classHex .. Utils.Truncate(member.name, 16) .. "|r" .. onlineStr)

        -- Level text
        local levelFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        levelFs:SetPoint("LEFT", row, "LEFT", 200, 0)
        levelFs:SetWidth(80)
        levelFs:SetJustifyH("LEFT")
        levelFs:SetText(member.rank .. " / " .. member.maxRank)

        -- Progress bar
        local barFrame = CreateFrame("Frame", nil, row)
        barFrame:SetHeight(10)
        barFrame:SetPoint("LEFT", row, "LEFT", 290, 0)
        barFrame:SetPoint("RIGHT", row, "RIGHT", -8, 0)

        local track = barFrame:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
        track:SetVertexColor(0.1, 0.1, 0.1, 0.8)

        local fill = barFrame:CreateTexture(nil, "BORDER")
        fill:SetPoint("TOPLEFT")
        fill:SetPoint("BOTTOMLEFT")
        fill:SetTexture("Interface\\RAIDFRAME\\Raid-Bar-Hp-Fill")
        fill:SetWidth(1)

        -- Colour: green if maxed, blue-ish if in progress
        if frac >= 1 then
            fill:SetVertexColor(0.37, 0.73, 0.28, 0.85)
        else
            fill:SetVertexColor(0.29, 0.56, 0.85, 0.85)
        end

        local pctFs = barFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pctFs:SetPoint("CENTER")
        pctFs:SetText(math.floor(frac * 100) .. "%")
        pctFs:SetTextColor(1, 1, 1, 0.9)

        barFrame:SetScript("OnSizeChanged", function(_, w)
            fill:SetWidth(math.max(1, w * frac))
        end)
    end

    L:Finish()
end
