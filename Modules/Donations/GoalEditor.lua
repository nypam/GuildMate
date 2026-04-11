-- GuildMate: Goal editor
-- Create/edit donation goals — raw WoW frames, no AceGUI.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Utils = GM.Utils

local GoalEditor = {}
GM.GoalEditor = GoalEditor

-- ── State ────────────────────────────────────────────────────────────────────

local _draft = {}
local _onSave = nil
local _onCancel = nil

-- ── Public API ───────────────────────────────────────────────────────────────

-- Open the goal editor.
-- `existingGoal` is nil for new goals, or an existing goal table to edit.
-- `onSave(goal)` called on confirmation. `onCancel()` on cancel.
function GoalEditor:Open(existingGoal, onSave, onCancel)
    _onSave   = onSave
    _onCancel = onCancel

    if existingGoal then
        _draft = {
            id          = existingGoal.id,
            goldAmount  = existingGoal.goldAmount,
            period      = existingGoal.period,
            targetRanks = {},
            startNow    = false,
        }
        for k, v in pairs(existingGoal.targetRanks) do
            _draft.targetRanks[k] = v
        end
    else
        _draft = {
            goldAmount  = 50 * 10000,
            period      = "weekly",
            targetRanks = {},
            startNow    = true,
        }
    end

    self:_Build()
end

-- ── Build UI ─────────────────────────────────────────────────────────────────

function GoalEditor:_Build()
    local parent = GM.MainFrame:ClearContent()
    local L = Utils.LayoutBuilder(parent)

    -- Title
    L:AddText("|cff4A90D9" .. (_draft.id and GM.L["EDIT_DONATION_GOAL"] or GM.L["NEW_DONATION_GOAL"]) .. "|r", 18, GameFontHighlight)
    L:AddSpacer(10)

    -- ── Gold amount ──────────────────────────────────────────────────────────
    L:AddHeader(GM.L["GOLD_AMOUNT"])
    L:AddSpacer(4)

    local amtBox = L:AddEditBox(tostring(math.floor(_draft.goldAmount / 10000)), 100)

    local slider = L:AddSlider(1, 500, 1, math.floor(_draft.goldAmount / 10000), 400)

    -- Sync slider → editbox
    slider:SetScript("OnValueChanged", function(_, val)
        _draft.goldAmount = math.floor(val) * 10000
        amtBox:SetText(tostring(math.floor(val)))
    end)

    -- Sync editbox → slider
    amtBox:SetScript("OnEnterPressed", function(self)
        local g = tonumber(self:GetText())
        if g and g >= 1 then
            _draft.goldAmount = math.floor(g) * 10000
            slider:SetValue(math.floor(g))
        else
            self:SetText(tostring(math.floor(_draft.goldAmount / 10000)))
        end
        self:ClearFocus()
    end)

    L:AddSpacer(8)

    -- ── Period ───────────────────────────────────────────────────────────────
    L:AddHeader(GM.L["DONATION_PERIOD"])
    L:AddSpacer(4)

    local periodRow = L:AddRow(28)
    local weeklyBtn = CreateFrame("CheckButton", nil, periodRow, "UICheckButtonTemplate")
    weeklyBtn:SetSize(24, 24)
    weeklyBtn:SetPoint("LEFT", periodRow, "LEFT", 0, 0)
    weeklyBtn:SetChecked(_draft.period == "weekly")

    local weeklyLbl = weeklyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    weeklyLbl:SetPoint("LEFT", weeklyBtn, "RIGHT", 4, 0)
    weeklyLbl:SetText(GM.L["WEEKLY"])

    local monthlyBtn = CreateFrame("CheckButton", nil, periodRow, "UICheckButtonTemplate")
    monthlyBtn:SetSize(24, 24)
    monthlyBtn:SetPoint("LEFT", periodRow, "LEFT", 120, 0)
    monthlyBtn:SetChecked(_draft.period == "monthly")

    local monthlyLbl = monthlyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    monthlyLbl:SetPoint("LEFT", monthlyBtn, "RIGHT", 4, 0)
    monthlyLbl:SetText(GM.L["MONTHLY"])

    -- Radio behaviour
    weeklyBtn:SetScript("OnClick", function()
        _draft.period = "weekly"
        weeklyBtn:SetChecked(true)
        monthlyBtn:SetChecked(false)
    end)
    monthlyBtn:SetScript("OnClick", function()
        _draft.period = "monthly"
        weeklyBtn:SetChecked(false)
        monthlyBtn:SetChecked(true)
    end)

    L:AddSpacer(8)

    -- ── Target ranks ─────────────────────────────────────────────────────────
    L:AddHeader(GM.L["APPLY_TO_RANKS"])
    L:AddSpacer(4)

    local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    for i = 0, numRanks - 1 do
        local rankName = GuildControlGetRankName and GuildControlGetRankName(i + 1) or ("Rank " .. i)
        local cb = L:AddCheckbox(rankName, _draft.targetRanks[i] == true)
        local rankIdx = i
        cb:SetScript("OnClick", function(self)
            _draft.targetRanks[rankIdx] = self:GetChecked() or nil
        end)
    end

    L:AddSpacer(8)

    -- ── Start ────────────────────────────────────────────────────────────────
    L:AddHeader(GM.L["STARTS"])
    L:AddSpacer(4)

    local startRow = L:AddRow(28)
    local nowBtn = CreateFrame("CheckButton", nil, startRow, "UICheckButtonTemplate")
    nowBtn:SetSize(24, 24)
    nowBtn:SetPoint("LEFT", startRow, "LEFT", 0, 0)
    nowBtn:SetChecked(_draft.startNow ~= false)

    local nowLbl = nowBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nowLbl:SetPoint("LEFT", nowBtn, "RIGHT", 4, 0)
    nowLbl:SetText(GM.L["THIS_PERIOD"])

    local nextBtn = CreateFrame("CheckButton", nil, startRow, "UICheckButtonTemplate")
    nextBtn:SetSize(24, 24)
    nextBtn:SetPoint("LEFT", startRow, "LEFT", 140, 0)
    nextBtn:SetChecked(_draft.startNow == false)

    local nextLbl = nextBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nextLbl:SetPoint("LEFT", nextBtn, "RIGHT", 4, 0)
    nextLbl:SetText(GM.L["NEXT_PERIOD"])

    nowBtn:SetScript("OnClick", function()
        _draft.startNow = true
        nowBtn:SetChecked(true)
        nextBtn:SetChecked(false)
    end)
    nextBtn:SetScript("OnClick", function()
        _draft.startNow = false
        nowBtn:SetChecked(false)
        nextBtn:SetChecked(true)
    end)

    L:AddSpacer(20)

    -- ── Action buttons ───────────────────────────────────────────────────────
    local btnRow = L:AddRow(30)

    local cancelBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
    cancelBtn:SetSize(110, 26)
    cancelBtn:SetPoint("LEFT", btnRow, "LEFT", 0, 0)
    cancelBtn:SetText(GM.L["CANCEL"])
    cancelBtn:SetScript("OnClick", function()
        PlaySound(856)
        if _onCancel then _onCancel() end
    end)

    local saveBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
    saveBtn:SetSize(130, 26)
    saveBtn:SetPoint("LEFT", cancelBtn, "RIGHT", 8, 0)
    saveBtn:SetText(GM.L["SAVE_GOAL"])
    saveBtn:SetScript("OnClick", function()
        PlaySound(856)
        GoalEditor:_Commit()
    end)

    L:Finish()
end

-- ── Commit ───────────────────────────────────────────────────────────────────

function GoalEditor:_Commit()
    if _draft.goldAmount < 10000 then
        GM:Print(GM.L["ERR_MIN_GOLD"])
        return
    end

    local hasRank = false
    for _ in pairs(_draft.targetRanks) do hasRank = true; break end
    if not hasRank then
        GM:Print(GM.L["ERR_NO_RANK"])
        return
    end

    local goal = {
        id          = _draft.id or GM.DB:NextGoalId(),
        goldAmount  = _draft.goldAmount,
        period      = _draft.period,
        targetRanks = _draft.targetRanks,
        active      = true,
        createdBy   = UnitName("player") or "Unknown",
        startEpoch  = time(),
    }

    GM.DB:DeactivateAllGoals()
    GM.DB:SaveGoal(goal)
    GM.Donations:BroadcastGoal(goal)

    GM:Print(string.format(GM.L["GOAL_SET"],
        Utils.FormatMoneyShort(goal.goldAmount), goal.period))

    if _onSave then _onSave(goal) end
end
