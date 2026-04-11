-- GuildMate: Utility helpers
-- Pure functions — no addon state, no side effects.

local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate") ---@type table
local Utils = {}
GM.Utils = Utils

-- ── Gold formatting ───────────────────────────────────────────────────────────

-- Format copper value as "Xg Ys Zc" with colour codes
function Utils.FormatMoney(copper)
    if copper <= 0 then return "|cffaaaaaa0g|r" end
    local gold   = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop    = copper % 100
    local out = ""
    if gold   > 0 then out = out .. "|cffd4af37" .. gold   .. "g|r " end
    if silver > 0 then out = out .. "|cffc0c0c0" .. silver .. "s|r " end
    if cop    > 0 then out = out .. "|ffb87333" .. cop     .. "c|r " end
    return out:match("^(.-)%s*$")  -- trim trailing space
end

-- Compact: "50g", "2g 30s", etc.  Used in tight UI cells.
function Utils.FormatMoneyShort(copper)
    if copper <= 0 then return "0g" end
    local gold   = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    if gold > 0 then
        if silver > 0 then
            return gold .. "g " .. silver .. "s"
        end
        return gold .. "g"
    end
    return silver .. "s"
end

-- Parse a human-readable gold string ("50g", "50g 30s") → copper integer
function Utils.ParseGoldInput(str)
    local copper = 0
    local g = str:match("(%d+)g")
    local s = str:match("(%d+)s")
    local c = str:match("(%d+)c")
    if g then copper = copper + tonumber(g) * 10000 end
    if s then copper = copper + tonumber(s) * 100   end
    if c then copper = copper + tonumber(c)          end
    return copper
end

-- ── Period helpers ────────────────────────────────────────────────────────────

-- Day of week for any date without using os.time.
-- Returns WoW wday format: 1=Sun, 2=Mon, ..., 7=Sat.
-- Uses Tomohiko Sakamoto's algorithm.
local function WdayForDate(year, month, day)
    local t = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}
    if month < 3 then year = year - 1 end
    return (year + math.floor(year/4) - math.floor(year/100)
            + math.floor(year/400) + t[month] + day) % 7 + 1
end

-- ISO 8601 week number for a Unix timestamp
local function ISOWeek(ts)
    local d = date("*t", ts)
    -- day-of-week: Sunday=1 … Saturday=7 → convert to Mon=1 … Sun=7
    local dow = (d.wday == 1) and 7 or (d.wday - 1)
    -- ordinal day of year
    local doy = d.yday
    -- week number
    local week = math.floor((doy - dow + 10) / 7)
    local year = d.year
    if week < 1 then
        -- belongs to last year's last week
        year = year - 1
        week = 53  -- simplified; precise calc not needed for display
    elseif week > 52 then
        -- check if really week 1 of next year (ISO: if Jan 1 is Mon-Thu, week 1 starts there)
        local jan1wday = WdayForDate(year + 1, 1, 1)
        local jan1dow  = (jan1wday == 1) and 7 or (jan1wday - 1)  -- Mon=1..Sun=7
        if jan1dow < 5 then
            year = year + 1
            week = 1
        end
    end
    return string.format("%d-W%02d", year, week)
end

-- Returns the period key for a given Unix timestamp and period type
function Utils.PeriodKey(ts, periodType)
    ts = ts or time()
    if periodType == "weekly" then
        return ISOWeek(ts)
    else  -- "monthly"
        return date("%Y-%m", ts)
    end
end

-- Human-readable period label: "Week 15, 2026" or "April 2026"
function Utils.PeriodLabel(periodKey)
    if periodKey:match("^%d+%-W%d+$") then
        local y, w = periodKey:match("^(%d+)%-W(%d+)$")
        return "Week " .. tonumber(w) .. ", " .. y
    else
        local y, m = periodKey:match("^(%d+)%-(%d+)$")
        local months = { "January","February","March","April","May","June",
                         "July","August","September","October","November","December" }
        return months[tonumber(m)] .. " " .. y
    end
end

-- Seconds remaining in the current period. Avoids os.time entirely.
function Utils.SecondsRemainingInPeriod(periodType)
    local d = date("*t")
    local secsIntoDay      = d.hour * 3600 + d.min * 60 + d.sec
    local secsUntilMidnight = 86400 - secsIntoDay

    if periodType == "weekly" then
        -- wday: 1=Sun 2=Mon … 7=Sat.  Compute days until NEXT Monday.
        local daysUntilMon = (2 - d.wday + 7) % 7
        if daysUntilMon == 0 then daysUntilMon = 7 end
        return secsUntilMidnight + (daysUntilMon - 1) * 86400
    else  -- "monthly"
        local mdays = {31,28,31,30,31,30,31,31,30,31,30,31}
        local dim = mdays[d.month]
        -- Leap year check
        if d.month == 2 and ((d.year%4==0 and d.year%100~=0) or d.year%400==0) then
            dim = 29
        end
        return secsUntilMidnight + (dim - d.day) * 86400
    end
end

-- ── Member key helpers ────────────────────────────────────────────────────────

-- Build the "Name-Realm" key used throughout the DB
function Utils.MemberKey(name, realm)
    realm = realm or (GetRealmName and GetRealmName() or "Unknown")
    return name .. "-" .. realm
end

-- Split "Name-Realm" → name, realm
-- Greedy first group splits on the LAST hyphen, so hyphenated names
-- like "Some-Name-Sulfuras" correctly yield ("Some-Name", "Sulfuras").
function Utils.SplitMemberKey(key)
    return key:match("^(.+)-([^-]+)$")
end

-- ── Colour helpers ────────────────────────────────────────────────────────────

-- Wrap a string in a WoW colour code: colour = {r, g, b}
function Utils.Colorize(str, color)
    return string.format("|cff%02x%02x%02x%s|r",
        color[1] * 255, color[2] * 255, color[3] * 255, str)
end

-- Status colour for a donation fraction (0-1)
function Utils.StatusColor(fraction)
    if fraction >= 1.0 then
        return { 0.373, 0.729, 0.275 }  -- green
    elseif fraction > 0 then
        return { 0.851, 0.608, 0.0 }    -- yellow
    else
        return { 0.557, 0.055, 0.075 }  -- red
    end
end

-- Status icon string for a fraction
function Utils.StatusIcon(fraction)
    if fraction >= 1.0 then return "|cff5fba47✔|r" end
    if fraction > 0    then return "|cffd9a400⚠|r" end
    return "|cff8e0e13✘|r"
end

-- ── Frame colour helpers ──────────────────────────────────────────────────────

-- Set a solid-colour background on any WoW frame.
-- Stores the texture in frame._gmBg so repeated calls just update the colour.
function Utils.SetFrameColor(frame, r, g, b, a)
    if not frame then return end
    if not frame._gmBg then
        local tex = frame:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints(frame)
        frame._gmBg = tex
    end
    if frame._gmBg.SetColorTexture then
        frame._gmBg:SetColorTexture(r, g, b, a or 1)
    else
        frame._gmBg:SetTexture(r, g, b, a or 1)
    end
    frame._gmBg:Show()
end

-- ── Font helpers ─────────────────────────────────────────────────────────────

-- Returns font path, size, flags for a given font object + custom size.
-- Usage: fs:SetFont(Utils.Font(GameFontHighlight, 16))
function Utils.Font(fontObject, size)
    local path, _, flags = fontObject:GetFont()
    return path, size, (flags or "")
end

-- ── Misc ──────────────────────────────────────────────────────────────────────

-- Safe string truncation with an ellipsis
function Utils.Truncate(str, maxLen)
    if #str <= maxLen then return str end
    return str:sub(1, maxLen - 1) .. "…"
end

-- (AceGUI progress bar helper removed — views now use raw frames directly)

-- ── Vertical layout builder ──────────────────────────────────────────────────
-- Lightweight replacement for AceGUI layout: stacks elements top-to-bottom
-- inside a parent frame, tracking the Y offset automatically.
--
-- Usage:
--   local L = Utils.LayoutBuilder(scrollChild)
--   L:AddText("Hello", 14)
--   L:AddSpacer(8)
--   local btn = L:AddButton("Click me", 120, 26)
--   L:Finish()  -- sizes the parent to total height (for scroll child)

function Utils.LayoutBuilder(parent)
    local lb = { parent = parent, y = 0, items = {}, marginL = 0, marginR = 0 }

    -- Add a FontString label, full width. Returns the FontString.
    -- fontObj can be a FontObject (GameFontHighlight) or nil. Always use string
    -- template for CreateFontString (TBC requires a string, not an object).
    -- Set left/right margins for all subsequent elements
    function lb:SetMargins(left, right)
        self.marginL = left or 0
        self.marginR = right or 0
    end

    function lb:AddText(text, fontSize, fontObj, r, g, b)
        local fs = self.parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetFont(Utils.Font(fontObj or GameFontNormal, fontSize or 12))
        fs:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.marginL, -self.y)
        fs:SetPoint("RIGHT", self.parent, "RIGHT", -self.marginR, 0)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetText(text or "")
        if r then fs:SetTextColor(r, g, b) end
        local h = math.max(fontSize or 14, 16)
        self.y = self.y + h + 2
        return fs
    end

    -- Add a raw Frame with given height, full width (respects margins). Returns the frame.
    function lb:AddFrame(height)
        local f = CreateFrame("Frame", nil, self.parent)
        f:SetHeight(height)
        f:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.marginL, -self.y)
        f:SetPoint("RIGHT", self.parent, "RIGHT", -self.marginR, 0)
        self.y = self.y + height
        return f
    end

    -- Add vertical spacing
    function lb:AddSpacer(height)
        self.y = self.y + (height or 8)
    end

    -- Add a standard UIPanelButton. Returns the button.
    function lb:AddButton(text, width, height, xOffset)
        height = height or 24
        local btn = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
        btn:SetSize(width or 120, height)
        btn:SetPoint("TOPLEFT", self.parent, "TOPLEFT", xOffset or 0, -self.y)
        btn:SetText(text)
        self.y = self.y + height + 4
        return btn
    end

    -- Add a CheckButton (checkbox). Returns the check button.
    function lb:AddCheckbox(text, checked, xOffset)
        local cb = CreateFrame("CheckButton", nil, self.parent, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", self.parent, "TOPLEFT", xOffset or 0, -self.y)
        cb:SetChecked(checked)
        local label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(text or "")
        cb._label = label
        self.y = self.y + 28
        return cb
    end

    -- Add an EditBox. Returns the edit box.
    function lb:AddEditBox(text, width, xOffset)
        local eb = CreateFrame("EditBox", nil, self.parent, "InputBoxTemplate")
        eb:SetSize(width or 200, 22)
        eb:SetPoint("TOPLEFT", self.parent, "TOPLEFT", (xOffset or 0) + 6, -self.y)
        eb:SetAutoFocus(false)
        eb:SetText(text or "")
        self.y = self.y + 26
        return eb
    end

    -- Add a Slider. Returns the slider.
    function lb:AddSlider(minVal, maxVal, step, value, width)
        local s = CreateFrame("Slider", nil, self.parent, "OptionsSliderTemplate")
        s:SetWidth(width or 300)
        s:SetHeight(17)
        s:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 8, -self.y - 10)
        s:SetMinMaxValues(minVal, maxVal)
        s:SetValueStep(step or 1)
        s:SetObeyStepOnDrag(true)
        s:SetValue(value or minVal)
        -- Hide the default low/high text
        if s.Low then s.Low:SetText("") end
        if s.High then s.High:SetText("") end
        if s.Text then s.Text:SetText("") end
        self.y = self.y + 30
        return s
    end

    -- Add a horizontal row of buttons/items. Give it a height, returns a frame.
    -- Callers anchor children inside manually using "LEFT".
    function lb:AddRow(height)
        return self:AddFrame(height or 28)
    end

    -- Add a coloured bar section header
    function lb:AddHeader(text)
        local fs = self.parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetFont(Utils.Font(GameFontHighlight, 13))
        fs:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 0, -self.y)
        fs:SetPoint("RIGHT", self.parent, "RIGHT", 0, 0)
        fs:SetJustifyH("LEFT")
        fs:SetText("|cffd4af37" .. text .. "|r")
        self.y = self.y + 18
        return fs
    end

    -- Set the parent frame height to total content (for ScrollFrame scroll child)
    function lb:Finish()
        self.parent:SetHeight(self.y + 8)
    end

    -- Get current Y offset
    function lb:GetY()
        return self.y
    end

    -- Set Y directly (e.g. for aligning after manual anchoring)
    function lb:SetY(newY)
        self.y = newY
    end

    return lb
end

-- ── Class colour ─────────────────────────────────────────────────────────────

-- Class colour hex string (e.g. "ff8156" for Warlock)
local CLASS_COLORS = {
    WARRIOR    = { 0.780, 0.612, 0.431 },
    PALADIN    = { 0.961, 0.549, 0.733 },
    HUNTER     = { 0.667, 0.827, 0.451 },
    ROGUE      = { 1.000, 0.957, 0.416 },
    PRIEST     = { 1.000, 1.000, 1.000 },
    SHAMAN     = { 0.000, 0.439, 0.871 },
    MAGE       = { 0.412, 0.800, 1.000 },
    WARLOCK    = { 0.529, 0.408, 0.733 },
    DRUID      = { 1.000, 0.490, 0.039 },
}

function Utils.ClassColor(classFilename)
    return CLASS_COLORS[classFilename] or { 0.8, 0.8, 0.8 }
end
