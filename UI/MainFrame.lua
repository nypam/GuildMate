-- GuildMate: Main window shell
-- Raw WoW frames — no AceGUI. Keeps AceAddon, AceEvent, AceComm, LibDBIcon.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Utils = GM.Utils

local MainFrame = {}
GM.MainFrame = MainFrame

-- ── Constants ────────────────────────────────────────────────────────────────

local MIN_W, MIN_H = 820, 490
local MAX_W, MAX_H = 2000, 1400
local SIDEBAR_W    = 130
local TITLEBAR_H   = 28
local STATUSBAR_H  = 20
local PADDING      = 8

-- ── Module registry ──────────────────────────────────────────────────────────

local _modules  = {}
local _activeId = nil

function MainFrame:RegisterModule(id, label, icon, module)
    _modules[#_modules + 1] = { id = id, label = label, icon = icon, module = module }
end

-- ── Build ────────────────────────────────────────────────────────────────────

function MainFrame:Build()
    if self._frame then return end

    local db = GM.DB.sv.settings

    -- ── Main frame ───────────────────────────────────────────────────────────
    local f = CreateFrame("Frame", "GuildMateMainFrame", UIParent)
    f:SetSize(db.windowWidth or 900, db.windowHeight or 550)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:Hide()

    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif f.SetMinResize then
        f:SetMinResize(MIN_W, MIN_H)
        f:SetMaxResize(MAX_W, MAX_H)
    end

    if db.windowX and db.windowY then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.windowX, db.windowY)
    else
        f:SetPoint("CENTER")
    end

    -- Background
    Utils.SetFrameColor(f, 0.06, 0.06, 0.06, 0.96)

    -- ESC to close
    tinsert(UISpecialFrames, "GuildMateMainFrame")

    self._frame = f

    -- ── Title bar ────────────────────────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(TITLEBAR_H)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT")
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    Utils.SetFrameColor(titleBar, 0.10, 0.10, 0.10, 1)

    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        GM.DB:SetSetting("windowX", f:GetLeft())
        GM.DB:SetSetting("windowY", f:GetTop() - UIParent:GetHeight())
    end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleText:SetText(GM.L["ADDON_TITLE"])
    titleText:SetFont(Utils.Font(GameFontNormal, 14))

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", 4, 4)
    closeBtn:SetScript("OnClick", function() MainFrame:Hide() end)

    -- ── Status bar ───────────────────────────────────────────────────────────
    local statusBar = CreateFrame("Frame", nil, f)
    statusBar:SetHeight(STATUSBAR_H)
    statusBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
    statusBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
    Utils.SetFrameColor(statusBar, 0.08, 0.08, 0.08, 1)

    local statusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("LEFT", statusBar, "LEFT", 8, 0)
    statusText:SetText(string.format(GM.L["VERSION_LINE"], GM.version or "0.1.0"))

    local tagline = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tagline:SetPoint("RIGHT", statusBar, "RIGHT", -8, 0)
    tagline:SetText(GM.L["TAGLINE"])

    -- ── Sidebar ──────────────────────────────────────────────────────────────
    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetWidth(SIDEBAR_W)
    sidebar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT")
    sidebar:SetPoint("BOTTOMLEFT", statusBar, "TOPLEFT")
    Utils.SetFrameColor(sidebar, 0.08, 0.08, 0.08, 1)
    self._sidebar = sidebar

    -- Vertical divider
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT")
    divider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT")
    divider:SetColorTexture(0.25, 0.25, 0.25, 1)

    -- ── Content area ─────────────────────────────────────────────────────────
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", SIDEBAR_W + 1, 0)
    content:SetPoint("BOTTOMRIGHT", statusBar, "TOPRIGHT")
    self._contentArea = content

    -- Scroll frame inside content
    local scrollFrame = CreateFrame("ScrollFrame", nil, content)
    scrollFrame:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING, -PADDING)
    scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -PADDING, PADDING)
    scrollFrame:EnableMouseWheel(true)
    self._scrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame")
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetHeight(1)
    self._scrollChild = scrollChild

    -- Sync scroll child width to scroll frame.
    -- Must read self._scrollChild (not closure var) because ClearContent replaces it.
    scrollFrame:SetScript("OnSizeChanged", function(sf, w)
        if MainFrame._scrollChild then
            MainFrame._scrollChild:SetWidth(w)
        end
    end)

    -- Mouse wheel scrolling — same: read the live _scrollChild reference.
    scrollFrame:SetScript("OnMouseWheel", function(sf, delta)
        local child = MainFrame._scrollChild
        if not child then return end
        local maxScroll = math.max(0, child:GetHeight() - sf:GetHeight())
        local cur = sf:GetVerticalScroll()
        sf:SetVerticalScroll(math.max(0, math.min(cur - delta * 40, maxScroll)))
    end)

    -- ── Resize handle ────────────────────────────────────────────────────────
    local resizer = CreateFrame("Button", nil, f)
    resizer:SetSize(16, 16)
    resizer:SetPoint("BOTTOMRIGHT")
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resizer:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        GM.DB:SetSetting("windowWidth", math.max(f:GetWidth(), MIN_W))
        GM.DB:SetSetting("windowHeight", math.max(f:GetHeight(), MIN_H))
    end)

    -- ── Build sidebar buttons ────────────────────────────────────────────────
    self:_BuildSidebar()
end

-- ── Sidebar ──────────────────────────────────────────────────────────────────

function MainFrame:_BuildSidebar()
    local yOff = -8
    for _, entry in ipairs(_modules) do
        local btn = CreateFrame("Button", nil, self._sidebar)
        btn:SetHeight(32)
        btn:SetPoint("TOPLEFT", self._sidebar, "TOPLEFT", 4, yOff)
        btn:SetPoint("RIGHT", self._sidebar, "RIGHT", -4, 0)

        -- Active highlight background
        local activeBg = btn:CreateTexture(nil, "BACKGROUND")
        activeBg:SetAllPoints()
        activeBg:SetColorTexture(0.15, 0.28, 0.45, 0.6)
        activeBg:Hide()
        btn._activeBg = activeBg

        -- Hover highlight
        local hoverBg = btn:CreateTexture(nil, "BACKGROUND")
        hoverBg:SetAllPoints()
        hoverBg:SetColorTexture(0.2, 0.2, 0.2, 0.4)
        hoverBg:Hide()

        btn:SetScript("OnEnter", function() if not activeBg:IsShown() then hoverBg:Show() end end)
        btn:SetScript("OnLeave", function() hoverBg:Hide() end)

        -- Icon
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", btn, "LEFT", 6, 0)
        icon:SetTexture(entry.icon)

        -- Label
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        label:SetText(entry.label)

        local moduleId = entry.id
        btn:SetScript("OnClick", function()
            PlaySound(856)
            MainFrame:SelectModule(moduleId)
        end)

        entry._btn = btn
        yOff = yOff - 34
    end
end

function MainFrame:_UpdateSidebarHighlight()
    for _, entry in ipairs(_modules) do
        if entry._btn and entry._btn._activeBg then
            if entry.id == _activeId then
                entry._btn._activeBg:Show()
            else
                entry._btn._activeBg:Hide()
            end
        end
    end
end

-- ── Content management ───────────────────────────────────────────────────────

function MainFrame:ClearContent()
    -- Hide the entire old scroll child. This also hides all FontStrings and
    -- textures (regions), not just child frames — GetChildren() misses those.
    if self._scrollChild then
        self._scrollChild:Hide()
    end

    -- Create a fresh scroll child
    local newChild = CreateFrame("Frame")
    self._scrollFrame:SetScrollChild(newChild)
    local sfWidth = self._scrollFrame:GetWidth()
    newChild:SetWidth(sfWidth > 0 and sfWidth or 600)
    newChild:SetHeight(1)
    self._scrollChild = newChild
    self._scrollFrame:SetVerticalScroll(0)

    -- Deferred width sync: scrollFrame may not have its final width yet
    C_Timer.After(0, function()
        if MainFrame._scrollChild == newChild and MainFrame._scrollFrame then
            local w = MainFrame._scrollFrame:GetWidth()
            if w > 0 then newChild:SetWidth(w) end
        end
    end)

    return newChild
end

function MainFrame:GetContent()
    return self._scrollChild
end

-- ── Public API ───────────────────────────────────────────────────────────────

function MainFrame:SelectModule(id)
    _activeId = id
    self:_UpdateSidebarHighlight()
    for _, entry in ipairs(_modules) do
        if entry.id == id and entry.module and entry.module.Render then
            entry.module:Render()
            break
        end
    end
end

function MainFrame:Show()
    if not self._frame then self:Build() end
    self._frame:Show()
    C_Timer.After(0, function()
        if not self._frame then return end
        local selectId = _activeId or (_modules[1] and _modules[1].id)
        if selectId then
            self:SelectModule(selectId)
        end
    end)
end

function MainFrame:Hide()
    if self._frame then self._frame:Hide() end
end

function MainFrame:Toggle()
    if self._frame and self._frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function MainFrame:RefreshActiveView()
    if self._frame and self._frame:IsShown() and _activeId then
        self:SelectModule(_activeId)
    end
end
