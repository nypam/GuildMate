-- GuildMate: Main window shell
-- Uses AceGUI TreeGroup for the left-nav + right-content split layout.
-- Individual modules call GM.MainFrame:RegisterModule(...) then Render(container).

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local AceGUI = LibStub("AceGUI-3.0")

local MainFrame = {}
GM.MainFrame = MainFrame

-- ── Constants ─────────────────────────────────────────────────────────────────

local MIN_W, MIN_H = 820, 490
local MAX_W, MAX_H = 2000, 1400

-- ── Module registry ───────────────────────────────────────────────────────────
-- { id="donations", label="Donations", icon="path", module=GM.Donations }

local _modules  = {}
local _activeId = nil

function MainFrame:RegisterModule(id, label, icon, module)
    table.insert(_modules, { id = id, label = label, icon = icon, module = module })
end

-- ── Build ─────────────────────────────────────────────────────────────────────

function MainFrame:Build()
    if self.frame then return end

    local db = GM.DB.sv.settings

    -- ── Outer AceGUI frame ────────────────────────────────────────────────────
    local f = AceGUI:Create("Frame")
    f:SetTitle("|cff4A90D9Guild|rMate")
    f:SetStatusText("GuildMate v" .. (GM.version or "0.1.0") .. "  ·  TBC Anniversary")
    f:SetWidth(db.windowWidth   or 900)
    f:SetHeight(db.windowHeight or 550)
    f:SetLayout("Fill")
    f:SetCallback("OnClose", function() MainFrame:Hide() end)

    -- Restore saved position
    if db.windowX and db.windowY then
        f.frame:ClearAllPoints()
        f.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.windowX, db.windowY)
    else
        f:SetPoint("CENTER")
    end

    f.frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)

    f:SetCallback("OnHeightSet", function(_, _, h)
        GM.DB:SetSetting("windowHeight", math.max(h, MIN_H))
    end)
    f:SetCallback("OnWidthSet", function(_, _, w)
        GM.DB:SetSetting("windowWidth", math.max(w, MIN_W))
    end)

    f.frame:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        GM.DB:SetSetting("windowX", fr:GetLeft())
        GM.DB:SetSetting("windowY", fr:GetTop() - UIParent:GetHeight())
    end)

    self.frame = f

    -- ── TreeGroup: left nav + right content ───────────────────────────────────
    local tree = AceGUI:Create("TreeGroup")
    tree:SetFullWidth(true)
    tree:SetFullHeight(true)
    tree:SetLayout("Fill")
    f:AddChild(tree)
    self.tree = tree

    tree:SetCallback("OnGroupSelected", function(container, _, group)
        _activeId = group
        container:ReleaseChildren()
        container:SetLayout("Fill")
        for _, entry in ipairs(_modules) do
            if entry.id == group and entry.module and entry.module.Render then
                entry.module:Render(container)
                break
            end
        end
    end)

    -- Populate the tree list (no selection yet — selection happens after Show)
    self:_RefreshTree()
end

-- Rebuild the tree list without selecting (selection needs the frame to be visible)
function MainFrame:_RefreshTree()
    local treeData = {}
    for _, entry in ipairs(_modules) do
        treeData[#treeData + 1] = {
            value = entry.id,
            text  = entry.label,
            icon  = entry.icon,
        }
    end
    self.tree:SetTree(treeData)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function MainFrame:Show()
    if not self.frame then self:Build() end
    self.frame:Show()
    -- Defer selection by one frame so AceGUI has finished its layout pass
    -- and the content area has real dimensions before we render into it.
    C_Timer.After(0, function()
        if not self.frame then return end
        local selectId = _activeId or (_modules[1] and _modules[1].id)
        if selectId and self.tree then
            self.tree:SelectByPath(selectId)
            _activeId = selectId
        end
    end)
end

function MainFrame:Hide()
    if self.frame then self.frame:Hide() end
end

function MainFrame:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Called by Events/modules when data changes — re-renders the active view
function MainFrame:RefreshActiveView()
    if self.frame and self.frame:IsShown() and _activeId and self.tree then
        self.tree:SelectByPath(_activeId)
    end
end
