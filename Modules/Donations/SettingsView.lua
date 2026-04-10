-- GuildMate: Settings panel
-- Rendered inside the main content area when the officer clicks ⚙.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local AceGUI = LibStub("AceGUI-3.0")
local Utils  = GM.Utils

local SettingsView = {}
GM.SettingsView = SettingsView

-- ── Constants ─────────────────────────────────────────────────────────────────

local COLOR_HEADER = { 0.85, 0.85, 0.95 }

-- ── Public API ────────────────────────────────────────────────────────────────

-- Render into `container`; `onBack` is called when the user clicks Back.
function SettingsView:Render(container, onBack)
    container:ReleaseChildren()
    container:SetLayout("Fill")

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    container:AddChild(scroll)

    -- ── Title row ─────────────────────────────────────────────────────────────
    local titleRow = AceGUI:Create("SimpleGroup")
    titleRow:SetLayout("Flow")
    titleRow:SetFullWidth(true)
    scroll:AddChild(titleRow)

    local backBtn = AceGUI:Create("Button")
    backBtn:SetText("← Back")
    backBtn:SetWidth(90)
    backBtn:SetCallback("OnClick", function()
        PlaySound(856)
        if onBack then onBack() end
    end)
    titleRow:AddChild(backBtn)

    local title = AceGUI:Create("Label")
    title:SetText("  |cff4A90D9SETTINGS|r")
    title:SetFont(Utils.Font(GameFontHighlight, 16))
    title:SetRelativeWidth(0.8)
    scroll:AddChild(title)  -- full-width below the row looks better

    self:_AddSpacer(scroll, 8)

    -- Check if the current player is an officer
    local _, _, playerRankIndex = GetGuildInfo("player")
    local isOfficer = GM.debugOfficer or GM.DB:IsOfficerRank(playerRankIndex or 99)

    -- ── Officer-only settings ─────────────────────────────────────────────────
    if isOfficer then
        -- ── Officer Ranks ─────────────────────────────────────────────────────
        self:_SectionHeader(scroll, "Officer Ranks")

        local rankDesc = AceGUI:Create("Label")
        rankDesc:SetText("|cffaaaaaaMembers with these ranks see the full roster and can manage goals.|r")
        rankDesc:SetFullWidth(true)
        rankDesc:SetHeight(18)
        scroll:AddChild(rankDesc)

        self:_AddSpacer(scroll, 8)

        local rankBox = AceGUI:Create("SimpleGroup")
        rankBox:SetLayout("Flow")
        rankBox:SetFullWidth(true)
        scroll:AddChild(rankBox)

        local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
        for i = 0, numRanks - 1 do
            local rankName = (GuildControlGetRankName and GuildControlGetRankName(i + 1)) or ("Rank " .. i)
            local cb = AceGUI:Create("CheckBox")
            cb:SetLabel("  " .. rankName)
            cb:SetValue(GM.DB:IsOfficerRank(i))
            cb:SetWidth(180)
            if i == 0 then
                cb:SetDisabled(true)
            else
                local idx = i
                cb:SetCallback("OnValueChanged", function(_, _, val)
                    local ranks = GM.DB.sv.settings.officerRanks
                    ranks[idx] = val or nil
                    PlaySound(856)
                end)
            end
            rankBox:AddChild(cb)
        end

        self:_AddSpacer(scroll, 14)

        -- ── Announce Channel ──────────────────────────────────────────────────
        self:_SectionHeader(scroll, "Announce Channel")

        local chanDesc = AceGUI:Create("Label")
        chanDesc:SetText("|cffaaaaaaWhere to post progress summaries when you click \"Announce to Guild\".|r")
        chanDesc:SetFullWidth(true)
        scroll:AddChild(chanDesc)

        self:_AddSpacer(scroll, 4)

        local chanGroup = AceGUI:Create("SimpleGroup")
        chanGroup:SetLayout("Flow")
        chanGroup:SetFullWidth(true)
        scroll:AddChild(chanGroup)

        local channels = {
            { value = "GUILD",   label = "Guild Chat"   },
            { value = "OFFICER", label = "Officer Chat" },
            { value = "OFF",     label = "Off"          },
        }

        local btns = {}
        local currentChan = GM.DB:GetSetting("announceChannel") or "GUILD"

        for _, ch in ipairs(channels) do
            local btn = AceGUI:Create("CheckBox")
            btn:SetLabel("  " .. ch.label)
            btn:SetType("radio")
            btn:SetValue(currentChan == ch.value)
            btn:SetWidth(150)
            local chValue = ch.value
            btn:SetCallback("OnValueChanged", function(_, _, val)
                if val then
                    GM.DB:SetSetting("announceChannel", chValue)
                    for _, other in ipairs(btns) do
                        if other ~= btn then other:SetValue(false) end
                    end
                    PlaySound(856)
                end
            end)
            table.insert(btns, btn)
            chanGroup:AddChild(btn)
        end

        self:_AddSpacer(scroll, 14)
    end

    -- ── Settings visible to everyone ──────────────────────────────────────────

    -- ── Login Reminder ──────────────────────────────────────────────────────
    self:_SectionHeader(scroll, "Login Reminder")

    local remindToggle = AceGUI:Create("CheckBox")
    remindToggle:SetLabel("  Show a reminder on login if I haven't met the donation goal")
    remindToggle:SetFullWidth(true)
    remindToggle:SetValue(GM.DB:GetSetting("reminderEnabled"))
    remindToggle:SetCallback("OnValueChanged", function(_, _, val)
        GM.DB:SetSetting("reminderEnabled", val)
        PlaySound(856)
    end)
    scroll:AddChild(remindToggle)

    self:_AddSpacer(scroll, 14)

    -- ── Goal Met Announcement ─────────────────────────────────────────────────
    self:_SectionHeader(scroll, "Goal Met Announcement")

    local goalMetToggle = AceGUI:Create("CheckBox")
    goalMetToggle:SetLabel("  Announce in guild chat when a member meets the donation goal")
    goalMetToggle:SetFullWidth(true)
    goalMetToggle:SetValue(GM.DB:GetSetting("goalMetAnnounce"))
    goalMetToggle:SetCallback("OnValueChanged", function(_, _, val)
        GM.DB:SetSetting("goalMetAnnounce", val)
        PlaySound(856)
    end)
    scroll:AddChild(goalMetToggle)

    self:_AddSpacer(scroll, 20)

    -- ── Save note ─────────────────────────────────────────────────────────────
    local note = AceGUI:Create("Label")
    note:SetText("|cffaaaaaa Settings are saved automatically and persist across sessions.|r")
    note:SetFullWidth(true)
    scroll:AddChild(note)
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

function SettingsView:_SectionHeader(container, text)
    local lbl = AceGUI:Create("Label")
    lbl:SetText("|cffd4af37" .. text .. "|r")
    lbl:SetFont(Utils.Font(GameFontHighlight, 13))
    lbl:SetFullWidth(true)
    container:AddChild(lbl)
    self:_AddSpacer(container, 2)
end

function SettingsView:_AddSpacer(container, height)
    local sp = AceGUI:Create("Label")
    sp:SetText(" ")
    sp:SetFullWidth(true)
    sp:SetHeight(height or 8)
    container:AddChild(sp)
end
