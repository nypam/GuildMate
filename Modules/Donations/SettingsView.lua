-- GuildMate: Settings panel
-- Raw WoW frames, no AceGUI.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Utils = GM.Utils

local SettingsView = {}
GM.SettingsView = SettingsView

-- ── Public API ───────────────────────────────────────────────────────────────

-- Render settings. `onBack` is called when the user clicks Back.
function SettingsView:Render(onBack)
    local parent = GM.MainFrame:ClearContent()
    local L = Utils.LayoutBuilder(parent)

    -- ── Title row ────────────────────────────────────────────────────────────
    local headerRow = L:AddRow(32)

    local backBtn = CreateFrame("Button", nil, headerRow, "UIPanelButtonTemplate")
    backBtn:SetSize(80, 24)
    backBtn:SetPoint("LEFT", headerRow, "LEFT", 0, 0)
    backBtn:SetText("Back")
    backBtn:SetScript("OnClick", function()
        PlaySound(856)
        if onBack then onBack() end
    end)

    local titleFs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetFont(Utils.Font(GameFontHighlight, 16))
    titleFs:SetPoint("LEFT", backBtn, "RIGHT", 10, 0)
    titleFs:SetText("|cff4A90D9SETTINGS|r")

    L:AddSpacer(8)

    -- Check if officer
    local _, _, playerRankIndex = GetGuildInfo("player")
    local isOfficer = GM.debugOfficer or GM.DB:IsOfficerRank(playerRankIndex or 99)

    -- ── Officer-only settings ────────────────────────────────────────────────
    if isOfficer then
        -- Goal Management
        L:AddHeader("Goal Management")
        L:AddSpacer(2)
        L:AddText("|cffaaaaaaRanks that can create, edit and delete donation goals.|r", 11)
        L:AddSpacer(6)

        local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
        for i = 0, numRanks - 1 do
            local rankName = (GuildControlGetRankName and GuildControlGetRankName(i + 1)) or ("Rank " .. i)
            local cb = L:AddCheckbox(rankName, GM.DB:IsOfficerRank(i))
            if i == 0 then
                cb:Disable()
                if cb._label then cb._label:SetTextColor(0.5, 0.5, 0.5) end
            else
                local idx = i
                cb:SetScript("OnClick", function(self)
                    GM.DB.sv.settings.officerRanks[idx] = self:GetChecked() or nil
                    PlaySound(856)
                end)
            end
        end

        L:AddSpacer(14)

        -- Announce Channel
        L:AddHeader("Announce Channel")
        L:AddSpacer(2)
        L:AddText("|cffaaaaaaWhere to post progress summaries when you click \"Announce to Guild\".|r", 11)
        L:AddSpacer(6)

        local channels = {
            { value = "GUILD",   label = "Guild Chat"   },
            { value = "OFFICER", label = "Officer Chat"  },
            { value = "OFF",     label = "Off"           },
        }
        local currentChan = GM.DB:GetSetting("announceChannel") or "GUILD"
        local chanBtns = {}

        local chanRow = L:AddRow(28)
        local cx = 0
        for _, ch in ipairs(channels) do
            local cb = CreateFrame("CheckButton", nil, chanRow, "UICheckButtonTemplate")
            cb:SetSize(24, 24)
            cb:SetPoint("LEFT", chanRow, "LEFT", cx, 0)
            cb:SetChecked(currentChan == ch.value)
            local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            lbl:SetText(ch.label)
            local chValue = ch.value
            cb:SetScript("OnClick", function()
                GM.DB:SetSetting("announceChannel", chValue)
                for _, other in ipairs(chanBtns) do
                    other:SetChecked(other == cb)
                end
                PlaySound(856)
            end)
            chanBtns[#chanBtns + 1] = cb
            cx = cx + 140
        end

        L:AddSpacer(14)
    end

    -- ── Settings visible to everyone ─────────────────────────────────────────

    -- Login Reminder
    L:AddHeader("Login Reminder")
    L:AddSpacer(2)
    local remindCb = L:AddCheckbox(
        "Show a reminder on login if I haven't met the donation goal",
        GM.DB:GetSetting("reminderEnabled"))
    remindCb:SetScript("OnClick", function(self)
        GM.DB:SetSetting("reminderEnabled", self:GetChecked())
        PlaySound(856)
    end)

    L:AddSpacer(14)

    -- Goal Met Announcement
    L:AddHeader("Goal Met Announcement")
    L:AddSpacer(2)
    local goalMetCb = L:AddCheckbox(
        "Announce in guild chat when a member meets the donation goal",
        GM.DB:GetSetting("goalMetAnnounce"))
    goalMetCb:SetScript("OnClick", function(self)
        GM.DB:SetSetting("goalMetAnnounce", self:GetChecked())
        PlaySound(856)
    end)

    L:AddSpacer(20)

    -- Save note
    L:AddText("|cffaaaaaa Settings are saved automatically and persist across sessions.|r", 11)

    L:Finish()
end
