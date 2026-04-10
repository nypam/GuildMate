-- GuildMate: Goal editor modal
-- A popup panel (rendered inside the main content area) for creating/editing goals.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local AceGUI = LibStub("AceGUI-3.0")
local Utils  = GM.Utils

local GoalEditor = {}
GM.GoalEditor = GoalEditor

-- ── Constants ─────────────────────────────────────────────────────────────────

local COLOR_HEADER  = { 0.85,  0.85,  0.95  }

-- Gold slider min/max in copper
local SLIDER_MIN_G = 1
local SLIDER_MAX_G = 500

-- ── State ─────────────────────────────────────────────────────────────────────

local _draft = {}       -- working copy while editing
local _onSave = nil     -- callback(goal) when Save is confirmed
local _onCancel = nil   -- callback() when cancelled

-- ── Public API ────────────────────────────────────────────────────────────────

-- Render the editor into `container` (an AceGUI container).
-- `existingGoal` is nil for new goals, or an existing goal table to edit.
-- `onSave(goal)` called with the final goal table on confirmation.
-- `onCancel()` called if the user cancels.
function GoalEditor:Open(container, existingGoal, onSave, onCancel)
    _onSave   = onSave
    _onCancel = onCancel

    -- Initialise draft from existing goal or defaults
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
            goldAmount  = 50 * 10000,   -- 50g default
            period      = "weekly",
            targetRanks = {},
            startNow    = true,
        }
    end

    self:_Build(container)
end

-- ── Build UI ──────────────────────────────────────────────────────────────────

function GoalEditor:_Build(container)
    container:ReleaseChildren()
    container:SetLayout("Fill")

    -- Scroll wrapper so it works on small windows
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    container:AddChild(scroll)

    -- ── Title ─────────────────────────────────────────────────────────────────
    local title = AceGUI:Create("Label")
    title:SetText("|cff4A90D9" .. (_draft.id and "Edit Donation Goal" or "New Donation Goal") .. "|r")
    title:SetFullWidth(true)
    title:SetFont(Utils.Font(GameFontHighlight, 18))
    scroll:AddChild(title)

    self:_AddSpacer(scroll, 10)

    -- ── Gold amount ───────────────────────────────────────────────────────────
    local amtHeader = AceGUI:Create("Label")
    amtHeader:SetText("Gold Amount per Member")
    amtHeader:SetFullWidth(true)
    amtHeader:SetColor(COLOR_HEADER[1], COLOR_HEADER[2], COLOR_HEADER[3])
    scroll:AddChild(amtHeader)

    -- EditBox for typed input
    local amtBox = AceGUI:Create("EditBox")
    amtBox:SetLabel("")
    amtBox:SetText(tostring(math.floor(_draft.goldAmount / 10000)))
    amtBox:SetWidth(100)
    amtBox:SetCallback("OnEnterPressed", function(_, _, val)
        local g = tonumber(val)
        if g and g >= 1 then
            _draft.goldAmount = math.floor(g) * 10000
            slider:SetValue(math.floor(g))
        else
            amtBox:SetText(tostring(math.floor(_draft.goldAmount / 10000)))
        end
    end)
    scroll:AddChild(amtBox)
    self._amtBox = amtBox

    -- Slider (1g – 500g)
    local slider = AceGUI:Create("Slider")
    slider:SetLabel("  " .. SLIDER_MIN_G .. "g ◀──────────────────────▶ " .. SLIDER_MAX_G .. "g")
    slider:SetSliderValues(SLIDER_MIN_G, SLIDER_MAX_G, 1)
    slider:SetValue(math.floor(_draft.goldAmount / 10000))
    slider:SetFullWidth(true)
    slider:SetCallback("OnValueChanged", function(_, _, val)
        _draft.goldAmount = math.floor(val) * 10000
        amtBox:SetText(tostring(math.floor(val)))
    end)
    scroll:AddChild(slider)
    self._slider = slider

    self:_AddSpacer(scroll, 8)

    -- ── Period ────────────────────────────────────────────────────────────────
    local perHeader = AceGUI:Create("Label")
    perHeader:SetText("Donation Period")
    perHeader:SetFullWidth(true)
    perHeader:SetColor(COLOR_HEADER[1], COLOR_HEADER[2], COLOR_HEADER[3])
    scroll:AddChild(perHeader)

    local perGroup = AceGUI:Create("SimpleGroup")
    perGroup:SetLayout("Flow")
    perGroup:SetFullWidth(true)
    scroll:AddChild(perGroup)

    local weeklyBtn  = AceGUI:Create("CheckBox")
    local monthlyBtn = AceGUI:Create("CheckBox")

    weeklyBtn:SetLabel("  Weekly")
    weeklyBtn:SetType("radio")
    weeklyBtn:SetValue(_draft.period == "weekly")
    weeklyBtn:SetWidth(120)
    weeklyBtn:SetCallback("OnValueChanged", function(_, _, val)
        if val then
            _draft.period = "weekly"
            monthlyBtn:SetValue(false)
        end
    end)

    monthlyBtn:SetLabel("  Monthly")
    monthlyBtn:SetType("radio")
    monthlyBtn:SetValue(_draft.period == "monthly")
    monthlyBtn:SetWidth(130)
    monthlyBtn:SetCallback("OnValueChanged", function(_, _, val)
        if val then
            _draft.period = "monthly"
            weeklyBtn:SetValue(false)
        end
    end)

    perGroup:AddChild(weeklyBtn)
    perGroup:AddChild(monthlyBtn)

    self:_AddSpacer(scroll, 8)

    -- ── Target ranks ──────────────────────────────────────────────────────────
    local rankHeader = AceGUI:Create("Label")
    rankHeader:SetText("Apply To Ranks")
    rankHeader:SetFullWidth(true)
    rankHeader:SetColor(COLOR_HEADER[1], COLOR_HEADER[2], COLOR_HEADER[3])
    scroll:AddChild(rankHeader)

    local rankGroup = AceGUI:Create("SimpleGroup")
    rankGroup:SetLayout("Flow")
    rankGroup:SetFullWidth(true)
    scroll:AddChild(rankGroup)

    local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    for i = 0, numRanks - 1 do
        local rankName = GuildControlGetRankName and GuildControlGetRankName(i) or ("Rank " .. i)
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel("  " .. rankName)
        cb:SetValue(_draft.targetRanks[i] == true)
        cb:SetWidth(160)
        local rankIdx = i  -- capture for closure
        cb:SetCallback("OnValueChanged", function(_, _, val)
            _draft.targetRanks[rankIdx] = val or nil
        end)
        rankGroup:AddChild(cb)
    end

    self:_AddSpacer(scroll, 8)

    -- ── Start ─────────────────────────────────────────────────────────────────
    local startHeader = AceGUI:Create("Label")
    startHeader:SetText("Starts")
    startHeader:SetFullWidth(true)
    startHeader:SetColor(COLOR_HEADER[1], COLOR_HEADER[2], COLOR_HEADER[3])
    scroll:AddChild(startHeader)

    local startGroup = AceGUI:Create("SimpleGroup")
    startGroup:SetLayout("Flow")
    startGroup:SetFullWidth(true)
    scroll:AddChild(startGroup)

    local nowBtn  = AceGUI:Create("CheckBox")
    local nextBtn = AceGUI:Create("CheckBox")

    nowBtn:SetLabel("  This period")
    nowBtn:SetType("radio")
    nowBtn:SetValue(_draft.startNow ~= false)
    nowBtn:SetWidth(140)
    nowBtn:SetCallback("OnValueChanged", function(_, _, val)
        if val then _draft.startNow = true; nextBtn:SetValue(false) end
    end)

    nextBtn:SetLabel("  Next period")
    nextBtn:SetType("radio")
    nextBtn:SetValue(_draft.startNow == false)
    nextBtn:SetWidth(140)
    nextBtn:SetCallback("OnValueChanged", function(_, _, val)
        if val then _draft.startNow = false; nowBtn:SetValue(false) end
    end)

    startGroup:AddChild(nowBtn)
    startGroup:AddChild(nextBtn)

    self:_AddSpacer(scroll, 20)

    -- ── Action buttons ────────────────────────────────────────────────────────
    local btnGroup = AceGUI:Create("SimpleGroup")
    btnGroup:SetLayout("Flow")
    btnGroup:SetFullWidth(true)
    scroll:AddChild(btnGroup)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("Cancel")
    cancelBtn:SetWidth(110)
    cancelBtn:SetCallback("OnClick", function()
        PlaySound(856)
        if _onCancel then _onCancel() end
    end)

    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save Goal")
    saveBtn:SetWidth(130)
    saveBtn:SetCallback("OnClick", function()
        PlaySound(856)
        self:_Commit()
    end)

    btnGroup:AddChild(cancelBtn)
    btnGroup:AddChild(saveBtn)
end

-- ── Commit ────────────────────────────────────────────────────────────────────

function GoalEditor:_Commit()
    -- Basic validation
    if _draft.goldAmount < 10000 then  -- less than 1g
        GM:Print("|cffff4444GuildMate:|r Gold amount must be at least 1g.")
        return
    end

    local hasRank = false
    for _ in pairs(_draft.targetRanks) do hasRank = true; break end
    if not hasRank then
        GM:Print("|cffff4444GuildMate:|r Select at least one target rank.")
        return
    end

    -- Build the final goal
    local goal = {
        id          = _draft.id or GM.DB:NextGoalId(),
        goldAmount  = _draft.goldAmount,
        period      = _draft.period,
        targetRanks = _draft.targetRanks,
        active      = true,
        createdBy   = UnitName("player") or "Unknown",
        startEpoch  = time(),
    }

    -- Deactivate any previous active goal before saving
    GM.DB:DeactivateAllGoals()
    GM.DB:SaveGoal(goal)

    -- Broadcast the new goal to guild
    GM:SendCommMessage("GuildMate",
        string.format("GOAL_UPDATE|%d|%d|%s", goal.id, goal.goldAmount, goal.period),
        "GUILD")

    GM:Print(string.format(
        "|cff4A90D9GuildMate:|r Goal set — %s per member, %s.",
        Utils.FormatMoneyShort(goal.goldAmount), goal.period))

    if _onSave then _onSave(goal) end
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

function GoalEditor:_AddSpacer(container, height)
    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    spacer:SetHeight(height or 8)
    container:AddChild(spacer)
end
