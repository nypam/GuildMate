# Ace3 — WoW Addon Development Framework
## Claude Code Reference Document

> **Purpose:** Feed this document to Claude Code when building WoW addons using Ace3. It covers every library, the full API, file structure, and practical patterns. A Turtle WoW / vanilla 1.12 compatibility section is included at the end.

---

## 1. What Ace3 Is

Ace3 is a **modular Lua framework** for World of Warcraft addon development. It is not a monolith — you embed only the libraries you actually need. Each library is a standalone unit distributed as a subfolder.

**Core libraries in this repo:**

| Library | Purpose |
|---|---|
| `LibStub` | Versioned library loader (not Ace3 itself, but required) |
| `CallbackHandler-1.0` | Internal event/callback dispatcher used by Ace libs |
| `AceAddon-3.0` | Addon lifecycle, module system |
| `AceEvent-3.0` | WoW event + inter-addon message system |
| `AceDB-3.0` | SavedVariables management and profiles |
| `AceDBOptions-3.0` | Auto-generates AceConfig profile UI from AceDB |
| `AceConsole-3.0` | Print to chat, slash command registration |
| `AceConfig-3.0` | Options table registration hub |
| `AceConfigCmd-3.0` | Slash-command interface for options tables |
| `AceConfigDialog-3.0` | GUI dialog for options tables |
| `AceConfigRegistry-3.0` | Registry for options tables (used internally) |
| `AceGUI-3.0` | Widget library for building custom GUIs |
| `AceHook-3.0` | Safe function and script hooking |
| `AceTimer-3.0` | One-shot and repeating timers |
| `AceBucket-3.0` | Event throttling (burst event batching) |
| `AceComm-3.0` | Network communication between clients |
| `AceLocale-3.0` | Localization / translation system |
| `AceSerializer-3.0` | Serialize/deserialize Lua values to strings |
| `AceTab-3.0` | Tab-completion for slash commands |

---

## 2. File Structure

Every WoW addon is a folder inside `Interface/AddOns/`. The folder name must be unique.

### 2.1 Typical Folder Layout

```
MyAddon/
  MyAddon.toc
  embeds.xml
  Core.lua
  Modules/
    Module1.lua
  Libs/
    LibStub/
      LibStub.lua
    AceAddon-3.0/
      AceAddon-3.0.lua
      AceAddon-3.0.xml
    AceEvent-3.0/
      AceEvent-3.0.lua
      AceEvent-3.0.xml
    ... (other libs)
  Locales/
    enUS.lua
    deDE.lua
```

### 2.2 .toc File

Controls how WoW loads the addon. Lines starting with `##` are metadata, the rest are file paths relative to the addon folder.

```lua
## Interface: 40000         -- WoW client build (e.g. 40000 = 4.0, 11200 = 1.12)
## Title: My Addon
## Notes: Description here
## Author: YourName
## Version: 1.0
## SavedVariables: MyAddonDB

embeds.xml

Locales/enUS.lua
Locales/deDE.lua

Core.lua
Modules/Module1.lua
```

**Key metadata fields:**
- `## Interface:` — must match the WoW client version
- `## SavedVariables:` — comma-separated global variable names to persist
- `## SavedVariablesPerCharacter:` — per-character saved variables
- `## Dependencies:` — addons that must load first
- `## OptionalDeps:` — optional dependencies

### 2.3 embeds.xml

Declares library files to load. References each lib's own `.xml` file (which in turn loads the `.lua`).

```xml
<Ui xsi:schemaLocation="http://www.blizzard.com/wow/ui/ ..\FrameXML\UI.xsd">
  <Script file="Libs\LibStub\LibStub.lua"/>
  <Include file="Libs\CallbackHandler-1.0\CallbackHandler-1.0.xml"/>
  <Include file="Libs\AceAddon-3.0\AceAddon-3.0.xml"/>
  <Include file="Libs\AceEvent-3.0\AceEvent-3.0.xml"/>
  <Include file="Libs\AceConsole-3.0\AceConsole-3.0.xml"/>
  <Include file="Libs\AceDB-3.0\AceDB-3.0.xml"/>
  <Include file="Libs\AceDBOptions-3.0\AceDBOptions-3.0.xml"/>
  <Include file="Libs\AceHook-3.0\AceHook-3.0.xml"/>
  <Include file="Libs\AceTimer-3.0\AceTimer-3.0.xml"/>
  <Include file="Libs\AceConfig-3.0\AceConfig-3.0.xml"/>
  <Include file="Libs\AceGUI-3.0\AceGUI-3.0.xml"/>
</Ui>
```

---

## 3. LibStub — Library Loader

All Ace3 libraries register themselves through LibStub, a lightweight versioned loader. You retrieve any library with:

```lua
local MyLib = LibStub("LibraryName")
-- or, with silent failure:
local MyLib = LibStub("LibraryName", true)  -- returns nil instead of erroring if missing
```

You almost never use LibStub directly in addon code except to get a library reference. The mixin pattern (embedding into your addon via `NewAddon`) is preferred.

---

## 4. AceAddon-3.0 — Lifecycle & Module System

### 4.1 Creating an Addon

```lua
-- Minimal addon
MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon")

-- Addon with embedded libraries (mixin pattern — preferred)
MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon",
  "AceEvent-3.0",
  "AceConsole-3.0",
  "AceHook-3.0",
  "AceTimer-3.0"
)

-- Addon created from an existing frame table
local MyFrame = CreateFrame("Frame")
MyAddon = LibStub("AceAddon-3.0"):NewAddon(MyFrame, "MyAddon", "AceEvent-3.0")
```

### 4.2 Lifecycle Callbacks

Define these methods on your addon object. AceAddon calls them automatically.

```lua
function MyAddon:OnInitialize()
  -- Called once when the addon first loads.
  -- SavedVariables are available here.
  -- Good place to initialize AceDB.
end

function MyAddon:OnEnable()
  -- Called on PLAYER_LOGIN, and each time the addon is re-enabled.
  -- Register events, start timers here.
end

function MyAddon:OnDisable()
  -- Called when the addon is disabled.
  -- Ace auto-unregisters events/timers if using mixin pattern.
end
```

### 4.3 Modules

Modules are sub-addons within an addon. They have the same lifecycle API.

```lua
-- Create a module
local MyModule = MyAddon:NewModule("MyModule")

-- Module with embedded libraries
local MyModule = MyAddon:NewModule("MyModule", "AceEvent-3.0")

-- Module with a prototype
local proto = { OnEnable = function(self) print("enabled") end }
local MyModule = MyAddon:NewModule("MyModule", proto, "AceEvent-3.0")

-- Set default libraries for all new modules
MyAddon:SetDefaultModuleLibraries("AceEvent-3.0")

-- Set default state for new modules (true = enabled by default)
MyAddon:SetDefaultModuleState(true)

-- Retrieve an existing module
local mod = MyAddon:GetModule("MyModule")

-- Iterate all modules
for name, module in MyAddon:IterateModules() do
  module:Enable()
end
```

### 4.4 AceAddon API

```lua
-- Retrieve an existing addon by name
local addon = LibStub("AceAddon-3.0"):GetAddon("AddonName")

-- Enable / disable
MyAddon:Enable()
MyAddon:Disable()

-- Query state
local enabled = MyAddon:IsEnabled()   -- boolean

-- Get real name (strips module prefixes)
local name = MyAddon:GetName()
```

---

## 5. AceEvent-3.0 — Events & Messages

Embed via `NewAddon(..., "AceEvent-3.0")` or call `LibStub("AceEvent-3.0"):Embed(obj)`.

### 5.1 WoW Game Events

```lua
-- Register: auto-calls MyAddon:PLAYER_ENTERING_WORLD when event fires
MyAddon:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Register with a custom handler (method name string)
MyAddon:RegisterEvent("UNIT_HEALTH", "OnUnitHealth")

-- Register with an inline function
MyAddon:RegisterEvent("PLAYER_REGEN_ENABLED", function(eventName)
  print("Combat ended")
end)

-- Handler signature: eventName is ALWAYS the first argument
function MyAddon:PLAYER_ENTERING_WORLD(eventName, isLogin, isReload)
  -- ...
end

function MyAddon:OnUnitHealth(eventName, unitId)
  -- unitId is the first event argument
end

-- Unregister
MyAddon:UnregisterEvent("PLAYER_ENTERING_WORLD")
MyAddon:UnregisterAllEvents()
```

### 5.2 Inter-Addon Messages (same client only)

```lua
-- Register for a custom message
MyAddon:RegisterMessage("MyAddon_SomethingHappened")
MyAddon:RegisterMessage("MyAddon_DataReady", "OnDataReady")

-- Send a message (synchronous, fires immediately)
MyAddon:SendMessage("MyAddon_SomethingHappened")
MyAddon:SendMessage("MyAddon_DataReady", payload1, payload2)

-- Unregister
MyAddon:UnregisterMessage("MyAddon_SomethingHappened")
MyAddon:UnregisterAllMessages()
```

> Messages are local-only (same WoW client). For cross-client communication, use AceComm.

---

## 6. AceDB-3.0 — Saved Variables & Profiles

### 6.1 TOC Setup

```
## SavedVariables: MyAddonDB
```

### 6.2 Initializing the Database

Always do this in `OnInitialize`, never in the main chunk.

```lua
local defaults = {
  profile = {
    enabled = true,
    fontSize = 12,
    colors = {
      text = { 1, 1, 1, 1 },
    },
    -- Wildcard key: any unset key gets this default table
    units = {
      ["*"] = { show = true },
    },
  },
  global = {
    version = 1,
  },
  char = {
    deaths = 0,
  },
}

function MyAddon:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("MyAddonDB", defaults, true)
  -- 3rd arg: default profile. true = shared "Default" profile.
  -- or pass a string for a named default profile.
end
```

### 6.3 Data Namespaces

```lua
self.db.profile       -- user-selectable profile (most common)
self.db.global        -- shared across all characters
self.db.char          -- per character
self.db.realm         -- per realm (all chars on realm)
self.db.class         -- per class
self.db.race          -- per race
self.db.faction       -- per faction (Alliance / Horde)
self.db.factionrealm  -- per faction + realm
```

### 6.4 Using the Database

```lua
-- Read / write exactly like a normal Lua table
self.db.profile.enabled = false
local size = self.db.profile.fontSize
self.db.char.deaths = self.db.char.deaths + 1
self.db.global.version = 2
```

### 6.5 Profile Management

```lua
-- Set active profile
self.db:SetProfile("MyProfile")

-- Get current profile name
local name = self.db:GetCurrentProfile()

-- Get all existing profiles (returns table + count)
local profiles, count = self.db:GetProfiles()
-- or pass a pre-allocated table: self.db:GetProfiles(myTable)

-- Copy a profile
self.db:CopyProfile("SourceProfile")

-- Delete a profile
self.db:DeleteProfile("OldProfile")

-- Reset current profile to defaults
self.db:ResetProfile()

-- Reset the entire DB
self.db:ResetDB()
```

### 6.6 DB Callbacks

```lua
-- Fired when the active profile changes
self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
self.db.RegisterCallback(self, "OnProfileShutdown")  -- fires before logout cleanup

function MyAddon:OnProfileChanged(event, database, newProfileKey)
  -- Re-apply settings from new profile
end
```

### 6.7 Namespaces (for Modules)

```lua
local modDB = self.db:RegisterNamespace("MyModule", {
  profile = { someOption = false }
})
-- modDB behaves exactly like a full AceDB database
```

### 6.8 Smart Defaults

```lua
-- ["*"] — default for any key not explicitly set
-- ["**"] — deep default (applies recursively to sub-tables)
local defaults = {
  profile = {
    buttons = {
      ["*"] = {        -- any button key gets this default
        x = 0,
        y = 0,
        scale = 1.0,
      },
    },
  },
}
```

---

## 7. AceConsole-3.0 — Chat Output & Slash Commands

Embed via `NewAddon(..., "AceConsole-3.0")`.

### 7.1 Print

```lua
-- Prints to default chat frame, prefixed with addon name
MyAddon:Print("Hello, world!")

-- Print to a specific chat frame
MyAddon:Print(ChatFrame2, "Hello!")

-- Printf-style (uses string.format)
MyAddon:Printf("Player has %d HP", UnitHealth("player"))
```

### 7.2 Slash Commands

```lua
-- Register a slash command (do NOT include the leading slash)
MyAddon:RegisterChatCommand("myaddon", "SlashCommandHandler")
MyAddon:RegisterChatCommand("ma", "SlashCommandHandler")  -- alias

function MyAddon:SlashCommandHandler(input)
  -- input = everything after "/myaddon " as a string
  if input == "enable" then
    self:Enable()
  elseif input == "disable" then
    self:Disable()
  else
    self:Print("Unknown command: " .. input)
  end
end

-- Or delegate directly to AceConfig (most common pattern):
MyAddon:RegisterChatCommand("myaddon", function(input)
  LibStub("AceConfigCmd-3.0"):HandleCommand("myaddon", "MyAddon", input)
end)
```

---

## 8. AceConfig-3.0 — Options System

AceConfig is the hub. It connects your options table to one or more frontends (slash command, GUI dialog). Sub-libraries handle each frontend.

### 8.1 Register an Options Table

```lua
LibStub("AceConfig-3.0"):RegisterOptionsTable("MyAddon", myOptionsTable)

-- With slash commands auto-registered:
LibStub("AceConfig-3.0"):RegisterOptionsTable("MyAddon", myOptionsTable, {"myaddon", "ma"})
```

### 8.2 Open the Config Dialog

```lua
LibStub("AceConfigDialog-3.0"):Open("MyAddon")

-- Add to Blizzard's Interface Options panel
LibStub("AceConfigDialog-3.0"):AddToBlizOptions("MyAddon", "My Addon")

-- Add a sub-group as its own panel
LibStub("AceConfigDialog-3.0"):AddToBlizOptions("MyAddon", "Profiles", "My Addon", "profile")
```

### 8.3 Options Table Structure

Every options table is a tree of nodes. The root must be type `"group"`.

```lua
local options = {
  name = "MyAddon",
  handler = MyAddon,   -- object for string-based get/set
  type = "group",
  args = {

    -- Toggle (checkbox)
    enable = {
      name = "Enable",
      desc = "Enables the addon",
      type = "toggle",
      order = 1,
      get = function(info) return MyAddon.db.profile.enabled end,
      set = function(info, val) MyAddon.db.profile.enabled = val end,
    },

    -- Text input
    message = {
      name = "Message",
      type = "input",
      order = 2,
      get = function(info) return MyAddon.db.profile.message end,
      set = function(info, val) MyAddon.db.profile.message = val end,
    },

    -- Multiline input
    notes = {
      name = "Notes",
      type = "input",
      multiline = 5,
      order = 3,
      width = "full",
      get = function(info) return MyAddon.db.profile.notes end,
      set = function(info, val) MyAddon.db.profile.notes = val end,
    },

    -- Range (slider)
    scale = {
      name = "Scale",
      type = "range",
      order = 4,
      min = 0.5,
      max = 2.0,
      step = 0.05,
      isPercent = false,
      get = function(info) return MyAddon.db.profile.scale end,
      set = function(info, val) MyAddon.db.profile.scale = val end,
    },

    -- Select (dropdown)
    anchor = {
      name = "Anchor",
      type = "select",
      order = 5,
      values = {
        TOPLEFT = "Top Left",
        TOPRIGHT = "Top Right",
        BOTTOMLEFT = "Bottom Left",
        BOTTOMRIGHT = "Bottom Right",
      },
      get = function(info) return MyAddon.db.profile.anchor end,
      set = function(info, val) MyAddon.db.profile.anchor = val end,
    },

    -- Multi-select (checklist)
    flags = {
      name = "Flags",
      type = "multiselect",
      order = 6,
      values = { a = "Option A", b = "Option B", c = "Option C" },
      get = function(info, key) return MyAddon.db.profile.flags[key] end,
      set = function(info, key, val) MyAddon.db.profile.flags[key] = val end,
    },

    -- Execute (button)
    reset = {
      name = "Reset",
      type = "execute",
      order = 99,
      func = function() MyAddon.db:ResetProfile() end,
    },

    -- Color picker
    color = {
      name = "Text Color",
      type = "color",
      hasAlpha = true,
      order = 7,
      get = function(info)
        local c = MyAddon.db.profile.color
        return c.r, c.g, c.b, c.a
      end,
      set = function(info, r, g, b, a)
        local c = MyAddon.db.profile.color
        c.r, c.g, c.b, c.a = r, g, b, a
      end,
    },

    -- Sub-group
    advanced = {
      name = "Advanced",
      type = "group",
      order = 50,
      args = {
        -- more options
      },
    },

    -- Inline sub-group (rendered inline in parent, not as a tab/tree node)
    display = {
      name = "Display",
      type = "group",
      inline = true,
      order = 10,
      args = {
        -- options rendered inline
      },
    },

    -- Header (visual separator)
    sep = {
      name = "Section Title",
      type = "header",
      order = 20,
    },

    -- Description text
    info = {
      name = "This addon does something cool.",
      type = "description",
      order = 0,
    },
  },
}
```

### 8.4 Common Parameters (all node types)

| Parameter | Type | Description |
|---|---|---|
| `name` | string\|function | Display name |
| `desc` | string\|function | Tooltip description |
| `order` | number\|function | Sort order (default 100, 0=first, -1=last) |
| `disabled` | bool\|function | Greyed out but visible |
| `hidden` | bool\|function | Invisible |
| `width` | string | `"half"`, `"normal"`, `"double"`, `"full"` |
| `handler` | table | Object for method-name get/set/func |
| `validate` | function\|string | Return error string to block set |
| `confirm` | bool\|function\|string | Prompt before applying |
| `guiHidden` | bool | Hidden from dialog only |
| `cmdHidden` | bool | Hidden from slash command only |

---

## 9. AceHook-3.0 — Function & Script Hooking

Embed via `NewAddon(..., "AceHook-3.0")`.

### 9.1 Standard (Pre) Hook

Runs your handler before the original function. The original is called automatically after.

```lua
-- Hook a global API function
MyAddon:Hook("SomeAPIFunction")
function MyAddon:SomeAPIFunction(...)
  -- runs before original
end

-- Hook a method on another object
MyAddon:Hook(TargetFrame, "SomeMethod")
function MyAddon:SomeMethod(obj, ...)
  -- runs before original
end

-- Hook with a custom handler
MyAddon:Hook("SomeAPIFunction", "MyHandler")
function MyAddon:MyHandler(...) end

-- Hook and allow tainting a secure function (rare, use with caution)
MyAddon:Hook("SecureFunction", "MyHandler", true)
```

### 9.2 Raw (Pre) Hook

You must call the original yourself. Use to intercept or modify arguments.

```lua
MyAddon:RawHook("SomeAPIFunction")
function MyAddon:SomeAPIFunction(arg1, arg2)
  -- optionally call original:
  self.hooks["SomeAPIFunction"](arg1, arg2)
  -- or skip it
end

-- For object hooks:
MyAddon:RawHook(TargetObject, "TargetMethod")
function MyAddon:TargetMethod(obj, ...)
  self.hooks[obj]["TargetMethod"](obj, ...)
end
```

### 9.3 Secure (Post) Hook

Runs AFTER the original. Return values are discarded. Required for protected/secure UI elements.

```lua
MyAddon:SecureHook("ProtectedUIFunction")
function MyAddon:ProtectedUIFunction(...)
  -- runs after, return values ignored
end
```

### 9.4 Script Hooks

```lua
MyAddon:HookScript(SomeFrame, "OnShow")
function MyAddon:OnShow(frame)
  -- runs before original OnShow
end

MyAddon:SecureHookScript(SomeFrame, "OnEnter")
function MyAddon:OnEnter(frame, motion)
  -- runs after original OnEnter
end

MyAddon:RawHookScript(SomeFrame, "OnUpdate")
function MyAddon:OnUpdate(frame, elapsed)
  -- you handle it; original won't run unless you call self.hooks
end
```

### 9.5 Other Hook Methods

```lua
-- Check if something is already hooked
local exists, handler = MyAddon:IsHooked("SomeAPIFunction")
local exists, handler = MyAddon:IsHooked(obj, "Method")

-- Unhook
MyAddon:Unhook("SomeAPIFunction")
MyAddon:Unhook(obj, "Method")
MyAddon:UnhookAll()
```

---

## 10. AceTimer-3.0 — Timers

Embed via `NewAddon(..., "AceTimer-3.0")`. Minimum delay: 0.01s.

### 10.1 One-Shot Timer

```lua
-- Fires once after `delay` seconds
-- Returns a handle (store it if you need to cancel)
local handle = self:ScheduleTimer("MyCallback", 5)
local handle = self:ScheduleTimer("MyCallback", 5, arg1, arg2)
local handle = self:ScheduleTimer(function() print("fired") end, 2)

function MyAddon:MyCallback(arg1, arg2)
  print("5 seconds passed")
end
```

### 10.2 Repeating Timer

```lua
-- Fires every `delay` seconds until canceled
self.myTimer = self:ScheduleRepeatingTimer("TimerTick", 1)
self.myTimer = self:ScheduleRepeatingTimer("TimerTick", 1, extraArg)

function MyAddon:TimerTick()
  self.tickCount = (self.tickCount or 0) + 1
  if self.tickCount >= 10 then
    self:CancelTimer(self.myTimer)
  end
end
```

### 10.3 Canceling Timers

```lua
-- Cancel a specific timer (handle from ScheduleTimer / ScheduleRepeatingTimer)
self:CancelTimer(handle)

-- Cancel all timers registered by this addon object
self:CancelAllTimers()

-- Check time remaining (returns 0 if expired or invalid)
local remaining = self:TimeLeft(handle)
```

---

## 11. AceBucket-3.0 — Event Throttling

Use when an event fires many times in quick succession and you only need to react once per burst.

Embed via `NewAddon(..., "AceBucket-3.0")`.

```lua
-- Bucket fires at most once per 0.2 seconds, collecting all BAG_UPDATE firings
MyAddon:RegisterBucketEvent("BAG_UPDATE", 0.2, "OnBagUpdate")

-- Multiple events in a single bucket
MyAddon:RegisterBucketEvent({"UNIT_HEALTH", "UNIT_MAXHEALTH"}, 1, "UpdateHealth")

-- With AceEvent messages
MyAddon:RegisterBucketMessage("MyAddon_DataChanged", 0.5, "ProcessData")

function MyAddon:OnBagUpdate(changedSlots)
  -- changedSlots is a table of [arg1] = true for each event that fired
end

function MyAddon:UpdateHealth(units)
  if units.player then
    print("Your HP changed!")
  end
end

-- Unregister specific bucket (returns the handle from Register*)
local h = MyAddon:RegisterBucketEvent("BAG_UPDATE", 0.2, "OnBagUpdate")
MyAddon:UnregisterBucket(h)

-- Unregister all buckets
MyAddon:UnregisterAllBuckets()
```

---

## 12. AceComm-3.0 — Network Communication

For sending messages between different players' clients. Embed via `NewAddon(..., "AceComm-3.0")`.

### 12.1 Sending

```lua
-- prefix: short identifier string, printable chars only (\032-\255)
-- text: the data payload (any chars except \000), auto-split if too long
-- distribution: "PARTY", "RAID", "BATTLEGROUND", "GUILD", "WHISPER"
-- target: only for "WHISPER", e.g. "Playerame" or "Playername-RealmName"

MyAddon:SendCommMessage("MyPrefix", "payload data", "PARTY")
MyAddon:SendCommMessage("MyPrefix", "payload data", "WHISPER", "Targetname")

-- With priority control (optional 5th arg): "ALERT", "NORMAL", "BULK"
MyAddon:SendCommMessage("MyPrefix", "data", "RAID", nil, "BULK")

-- With callback for progress (optional 6th arg):
MyAddon:SendCommMessage("MyPrefix", largeData, "GUILD", nil, "NORMAL",
  function(_, sent, total) print(sent .. "/" .. total) end
)
```

### 12.2 Receiving

```lua
-- Register to receive messages with this prefix
MyAddon:RegisterComm("MyPrefix")                                -- calls :OnCommReceived
MyAddon:RegisterComm("MyPrefix", "HandleComm")                 -- calls :HandleComm
MyAddon:RegisterComm("MyPrefix", function(p,m,d,s) end)       -- inline

-- Handler receives 4 args:
function MyAddon:OnCommReceived(prefix, message, distribution, sender)
  if prefix == "MyPrefix" then
    -- process message
  end
end

-- Unregister
MyAddon:UnregisterComm("MyPrefix")
```

### 12.3 Serialized Communication Pattern

Combine with AceSerializer for structured data:

```lua
function MyAddon:SendData(data)
  local serialized = self:Serialize(data)
  self:SendCommMessage("MyPrefix", serialized, "RAID")
end

function MyAddon:OnCommReceived(prefix, message, dist, sender)
  local ok, data = self:Deserialize(message)
  if ok then
    -- use data
  end
end
```

---

## 13. AceLocale-3.0 — Localization

### 13.1 Locale File (one per language)

Load locale files before main addon code in your .toc.

```lua
-- enUS.lua — default locale, third arg = true
local L = LibStub("AceLocale-3.0"):NewLocale("MyAddon", "enUS", true)
if L then
  L["Hello"] = "Hello"
  L["World"] = "World"
  L["Points format"] = function(n, name)
    return n .. " points for " .. name
  end
end
```

```lua
-- deDE.lua
local L = LibStub("AceLocale-3.0"):NewLocale("MyAddon", "deDE")
if L then
  L["Hello"] = "Hallo"
  L["World"] = "Welt"
end
```

> The `if L then` guard is required. AceLocale returns nil if you try to register the same locale twice.

### 13.2 Using Translations

```lua
-- In Core.lua
local L = LibStub("AceLocale-3.0"):GetLocale("MyAddon", true)
-- 2nd arg: silent=true means no error if locale is missing

MyAddon:Print(L["Hello"])
MyAddon:Print(L["Points format"](42, "Alice"))

-- Silent raw mode: missing keys return nil instead of the key string
local L = LibStub("AceLocale-3.0"):NewLocale("MyAddon", "frFR", false, "raw")
-- L["missing key"] == nil  instead of  "missing key"
```

---

## 14. AceSerializer-3.0 — Serialization

Converts Lua values to a portable string and back. Supports strings, numbers, booleans, nil, tables (but not functions or userdata).

Embed via `NewAddon(..., "AceSerializer-3.0")`.

```lua
-- Serialize
local str = MyAddon:Serialize(val1, val2, val3)
local str = MyAddon:Serialize(42, "text", {a=1, b=2}, true)

-- Deserialize
local ok, v1, v2, v3 = MyAddon:Deserialize(str)
if not ok then
  print("Error:", v1)  -- v1 is error message on failure
end
```

---

## 15. AceGUI-3.0 — Widget Library

AceGUI is NOT embedded via the mixin pattern. Get it via LibStub directly.

```lua
local AceGUI = LibStub("AceGUI-3.0")
```

> Do NOT pass `"AceGUI-3.0"` to NewAddon. It is not embeddable.

### 15.1 Creating Widgets

```lua
local widget = AceGUI:Create("WidgetTypeName")
-- Always release widgets when done with them:
AceGUI:Release(widget)
```

### 15.2 Container Widgets

**Frame** — top-level resizable window
```lua
local f = AceGUI:Create("Frame")
f:SetTitle("My Window")
f:SetStatusText("Status text")
f:SetLayout("Flow")                   -- "Flow", "List", "Fill"
f:SetWidth(400)
f:SetHeight(300)
f:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end)

-- Add children
f:AddChild(someWidget)
-- Insert at specific position (optional 2nd arg):
f:AddChild(someWidget, 2)
```

**InlineGroup** — borderless container for grouping widgets
```lua
local g = AceGUI:Create("InlineGroup")
g:SetTitle("Group Title")
g:SetLayout("Flow")
g:SetFullWidth(true)
g:AddChild(...)
frame:AddChild(g)
```

**TabGroup** — tabbed container
```lua
local tabs = AceGUI:Create("TabGroup")
tabs:SetTabs({ {text="Tab1", value="tab1"}, {text="Tab2", value="tab2"} })
tabs:SetCallback("OnGroupSelected", function(widget, event, tab)
  widget:ReleaseChildren()
  if tab == "tab1" then
    -- add tab1 content
  end
end)
tabs:SelectTab("tab1")
frame:AddChild(tabs)
```

**ScrollFrame** — scrollable container
```lua
local scroll = AceGUI:Create("ScrollFrame")
scroll:SetLayout("List")
scroll:SetFullWidth(true)
scroll:SetFullHeight(true)
frame:AddChild(scroll)
scroll:AddChild(...)
```

**TreeGroup** — tree-navigation container
```lua
local tree = AceGUI:Create("TreeGroup")
tree:SetTree({
  { value = "node1", text = "Node 1" },
  { value = "node2", text = "Node 2",
    children = {
      { value = "child1", text = "Child 1" }
    }
  },
})
tree:SetCallback("OnGroupSelected", function(w, e, uniqueValue)
  -- uniqueValue is "node1", "node2\001child1" etc.
end)
```

**Window** — floating, non-resizable window (simpler than Frame)
```lua
local win = AceGUI:Create("Window")
win:SetTitle("Window")
win:SetLayout("Fill")
```

### 15.3 Basic Widgets

**Label**
```lua
local lbl = AceGUI:Create("Label")
lbl:SetText("Hello World")
lbl:SetFontObject(GameFontNormal)
lbl:SetFullWidth(true)
```

**Heading**
```lua
local h = AceGUI:Create("Heading")
h:SetText("Section Title")
h:SetFullWidth(true)
```

**Button**
```lua
local btn = AceGUI:Create("Button")
btn:SetText("Click Me")
btn:SetWidth(150)
btn:SetCallback("OnClick", function(widget, event)
  print("Clicked!")
end)
```

**CheckBox (Toggle)**
```lua
local cb = AceGUI:Create("CheckBox")
cb:SetLabel("Enable Feature")
cb:SetValue(true)
cb:SetCallback("OnValueChanged", function(widget, event, value)
  MyAddon.db.profile.enabled = value
end)
```

**EditBox (Input)**
```lua
local eb = AceGUI:Create("EditBox")
eb:SetLabel("Enter text")
eb:SetText("default")
eb:SetFullWidth(true)
eb:SetCallback("OnEnterPressed", function(widget, event, text)
  print("Input:", text)
end)
```

**Slider**
```lua
local sl = AceGUI:Create("Slider")
sl:SetLabel("Scale")
sl:SetSliderValues(0.5, 2.0, 0.05)
sl:SetValue(1.0)
sl:SetIsPercent(false)
sl:SetCallback("OnValueChanged", function(widget, event, value)
  print("Value:", value)
end)
```

**Dropdown**
```lua
local dd = AceGUI:Create("Dropdown")
dd:SetLabel("Choose")
dd:SetList({ opt1 = "Option 1", opt2 = "Option 2" })
dd:SetValue("opt1")
dd:SetCallback("OnValueChanged", function(widget, event, value)
  print("Selected:", value)
end)
```

**MultiLineEditBox**
```lua
local ml = AceGUI:Create("MultiLineEditBox")
ml:SetLabel("Notes")
ml:SetText("...")
ml:SetNumLines(5)
ml:SetFullWidth(true)
ml:SetCallback("OnEnterPressed", function(widget, event, text) end)
```

**ColorPicker**
```lua
local cp = AceGUI:Create("ColorPicker")
cp:SetLabel("Color")
cp:SetHasAlpha(true)
cp:SetColor(1, 0, 0, 1)   -- r, g, b, a
cp:SetCallback("OnValueChanged", function(widget, event, r, g, b, a) end)
cp:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a) end)
```

**Icon**
```lua
local icon = AceGUI:Create("Icon")
icon:SetImage("Interface\\Icons\\INV_Misc_Gem_01")
icon:SetImageSize(32, 32)
icon:SetLabel("My Icon")
icon:SetCallback("OnClick", function() end)
```

**InteractiveLabel**
```lua
local il = AceGUI:Create("InteractiveLabel")
il:SetText("Click me")
il:SetCallback("OnClick", function() end)
il:SetCallback("OnEnter", function() end)
il:SetCallback("OnLeave", function() end)
```

### 15.4 Widget Common Methods

```lua
widget:SetWidth(n)
widget:SetHeight(n)
widget:SetFullWidth(bool)
widget:SetFullHeight(bool)
widget:SetDisabled(bool)
widget:SetCallback("EventName", function(widget, event, ...) end)
widget:SetUserData("key", value)   -- store arbitrary data on widget
widget:GetUserData("key")
widget:ClearFocus()
container:ReleaseChildren()        -- release all child widgets
```

### 15.5 Layouts

| Layout | Behavior |
|---|---|
| `"Flow"` | Horizontal flow, wraps to next line |
| `"List"` | Vertical list, each widget on its own row |
| `"Fill"` | Single child fills entire container |

---

## 16. AceDBOptions-3.0 — Profile UI Integration

Generates a ready-made AceConfig group for profile management.

```lua
function MyAddon:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("MyAddonDB", defaults, true)

  local options = { ... }  -- your options table

  -- Inject the profile subtable into your options
  options.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)

  LibStub("AceConfig-3.0"):RegisterOptionsTable("MyAddon", options)
  LibStub("AceConfigDialog-3.0"):AddToBlizOptions("MyAddon", "My Addon")
end
```

> Do NOT modify the returned options table. It is shared across all addons.

---

## 17. CallbackHandler-1.0 — Direct Usage

Rarely used directly. AceEvent and AceDB use it internally. If you build a library that exposes callbacks:

```lua
local CH = LibStub("CallbackHandler-1.0")
MyLib.callbacks = CH:New(MyLib)

-- Fire a callback
MyLib.callbacks:Fire("MyLib_SomethingHappened", arg1, arg2)

-- Register from outside
MyLib.callbacks:RegisterCallback(self, "MyLib_SomethingHappened", "OnSomething")
```

---

## 18. Complete Addon Boilerplate

A full, working minimal addon using the most common Ace3 patterns:

```lua
-- Core.lua

-- Create the addon with common embedded libraries
MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon",
  "AceConsole-3.0",
  "AceEvent-3.0",
  "AceHook-3.0",
  "AceTimer-3.0"
)

-- Local reference to AceGUI (not embeddable via mixin)
local AceGUI = LibStub("AceGUI-3.0")

-- Database defaults
local defaults = {
  profile = {
    enabled = true,
    message = "Hello!",
    scale = 1.0,
  },
}

-- Options table
local options = {
  name = "MyAddon",
  handler = MyAddon,
  type = "group",
  args = {
    enabled = {
      name = "Enable",
      type = "toggle",
      order = 1,
      get = function(info) return MyAddon.db.profile.enabled end,
      set = function(info, val) MyAddon.db.profile.enabled = val end,
    },
    message = {
      name = "Message",
      type = "input",
      order = 2,
      get = function(info) return MyAddon.db.profile.message end,
      set = function(info, val) MyAddon.db.profile.message = val end,
    },
    profile = {},  -- populated in OnInitialize
  },
}

-- LIFECYCLE

function MyAddon:OnInitialize()
  -- Set up saved variables
  self.db = LibStub("AceDB-3.0"):New("MyAddonDB", defaults, true)
  self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
  self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
  self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

  -- Inject profile management UI
  options.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)

  -- Register options and slash command
  LibStub("AceConfig-3.0"):RegisterOptionsTable("MyAddon", options)
  LibStub("AceConfigDialog-3.0"):AddToBlizOptions("MyAddon", "My Addon")
  self:RegisterChatCommand("myaddon", "SlashCommand")
end

function MyAddon:OnEnable()
  -- Register for game events
  self:RegisterEvent("PLAYER_ENTERING_WORLD")

  -- Start a repeating timer
  self.heartbeat = self:ScheduleRepeatingTimer("OnHeartbeat", 5)

  self:Print("Enabled.")
end

function MyAddon:OnDisable()
  self:Print("Disabled.")
end

-- EVENT HANDLERS

function MyAddon:PLAYER_ENTERING_WORLD(event, isLogin, isReload)
  if self.db.profile.enabled then
    self:Print(self.db.profile.message)
  end
end

-- TIMER HANDLERS

function MyAddon:OnHeartbeat()
  -- fires every 5 seconds
end

-- CALLBACKS

function MyAddon:RefreshConfig()
  -- called when profile changes; re-apply settings
end

-- SLASH COMMAND

function MyAddon:SlashCommand(input)
  if input == "" or input == "config" then
    LibStub("AceConfigDialog-3.0"):Open("MyAddon")
  elseif input == "reset" then
    self.db:ResetProfile()
    self:Print("Profile reset.")
  else
    self:Print("Usage: /myaddon [config|reset]")
  end
end
```

---

## 19. Patterns & Best Practices

### 19.1 Always Initialize AceDB in OnInitialize

```lua
-- CORRECT
function MyAddon:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("MyAddonDB", defaults)
end

-- WRONG — SavedVariables may not be loaded yet
MyAddon.db = LibStub("AceDB-3.0"):New("MyAddonDB", defaults)
```

### 19.2 Register Events in OnEnable, Not OnInitialize

```lua
function MyAddon:OnEnable()
  self:RegisterEvent("UNIT_HEALTH")   -- correct
end
-- Registering in OnInitialize means events fire even when addon is disabled
```

### 19.3 Module Pattern for Large Addons

```lua
-- In Core.lua
MyAddon:SetDefaultModuleLibraries("AceEvent-3.0")

-- In Modules/Combat.lua
local Combat = MyAddon:NewModule("Combat", "AceTimer-3.0")

function Combat:OnEnable()
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Combat:PLAYER_REGEN_DISABLED()
  MyAddon:SendMessage("MyAddon_CombatStarted")
end
```

### 19.4 Always Store Timer Handles

```lua
function MyAddon:OnEnable()
  -- Store handle so you can cancel
  self.updateTimer = self:ScheduleRepeatingTimer("Update", 0.1)
end

function MyAddon:OnDisable()
  -- Ace auto-cancels on disable if embedded, but explicit is safer
  if self.updateTimer then
    self:CancelTimer(self.updateTimer)
    self.updateTimer = nil
  end
end
```

### 19.5 Bucket Events for Performance

```lua
-- BAG_UPDATE can fire dozens of times per second; bucket it
function MyAddon:OnEnable()
  self:RegisterBucketEvent("BAG_UPDATE", 0.3, "UpdateBags")
end
```

### 19.6 Defensive Profile Access

```lua
-- Use a local shortcut to avoid constant self.db.profile indexing
function MyAddon:OnEnable()
  local p = self.db.profile
  self.frame:SetScale(p.scale)
  self.frame:SetAlpha(p.alpha)
end
```

### 19.7 AceConfig get/set via Handler Strings

If your handler is `MyAddon`, you can use method name strings instead of anonymous functions:

```lua
options = {
  handler = MyAddon,
  args = {
    enabled = {
      type = "toggle",
      get = "GetEnabled",
      set = "SetEnabled",
    }
  }
}

function MyAddon:GetEnabled(info)
  return self.db.profile.enabled
end

function MyAddon:SetEnabled(info, value)
  self.db.profile.enabled = value
end
```

The `info` table passed to get/set contains: `info[1]..info[n]` = path through options tree, `info.option` = the option table entry, `info.type` = option type, `info.uiType` = "dialog" or "cmd", `info.handler` = handler object.

---

## 20. Turtle WoW / Vanilla 1.12 Compatibility

Turtle WoW runs interface version **11200** (vanilla 1.12). The standard Ace3 from this repo targets modern WoW and **will not work directly** on Turtle WoW.

### 20.1 The Problem

Modern Ace3 relies on APIs that do not exist in vanilla:
- `C_Timer.After` — used by AceTimer-3.0 (does not exist in 1.12)
- `hooksecurefunc` — exists in vanilla but behavior differs
- `CreateFrame` secure template differences
- Various WoW API function signatures changed between 1.12 and later clients

### 20.2 Vanilla-Compatible Fork

Use **Ace3v** (vanilla port) instead of the standard repo for Turtle WoW:

- Primary: `https://github.com/laytya/Ace3v` — most community-recommended port
- Alternative: `https://github.com/zerosnake0/Ace3v`
- There is also an "Ace3 for Turtle WoW" community effort (see Turtle WoW forums)

### 20.3 .toc Interface Version

```
## Interface: 11200    -- vanilla 1.12 / Turtle WoW
```

Modern WoW uses `## Interface: 100207` (10.2.7) or similar. The interface version must match the client or the addon will appear as "out of date."

### 20.4 APIs Absent in Vanilla (avoid these)

| Modern API | Status in 1.12 |
|---|---|
| `C_Timer.After` | Does not exist |
| `C_Timer.NewTimer` | Does not exist |
| `C_Item.*` | Does not exist |
| `C_Container.*` | Does not exist (use `GetContainerItem*`) |
| `C_ChatInfo.*` | Does not exist |
| `Enum.*` | Does not exist |
| `strsplit` | Available but limited |
| `RegisterAddonMessagePrefix` | Does not exist |
| `ChatThrottleLib` | Must be bundled separately |

### 20.5 Vanilla Event Differences

Some events have different signatures in 1.12:
- `UNIT_HEALTH` → passes only `unitId` in vanilla, no extra args
- `BAG_UPDATE` → passes `bagId` in some versions
- `PLAYER_ENTERING_WORLD` → no `isLogin/isReload` args in vanilla
- `CHAT_MSG_*` events → slightly different arg order in some cases

### 20.6 AceComm on Vanilla

`RegisterAddonMessagePrefix` does not exist in 1.12. AceComm-3.0 will fail. For addon-to-addon networking on vanilla, use `CHAT_MSG_ADDON` directly or find a vanilla-compatible comm library.

### 20.7 Recommended Vanilla Workflow

1. Use `laytya/Ace3v` as your library base
2. Set `## Interface: 11200` in your .toc
3. Avoid all `C_*` namespaced APIs
4. Test with `GetBuildInfo()` to detect client version at runtime if needed:
   ```lua
   local version, build, date, tocversion = GetBuildInfo()
   local isVanilla = tocversion < 20000
   ```

---

## 21. Quick Reference — Library Loading Cheat Sheet

```lua
-- Embed with NewAddon (recommended for most libs):
MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon",
  "AceConsole-3.0",       -- :Print, :RegisterChatCommand
  "AceEvent-3.0",         -- :RegisterEvent, :SendMessage
  "AceHook-3.0",          -- :Hook, :SecureHook, :HookScript
  "AceTimer-3.0",         -- :ScheduleTimer, :CancelTimer
  "AceBucket-3.0",        -- :RegisterBucketEvent
  "AceComm-3.0",          -- :SendCommMessage, :RegisterComm
  "AceSerializer-3.0"     -- :Serialize, :Deserialize
)

-- Get directly (NOT embeddable via mixin):
local AceGUI    = LibStub("AceGUI-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceDialog = LibStub("AceConfigDialog-3.0")
local AceCmd    = LibStub("AceConfigCmd-3.0")
local AceDB     = LibStub("AceDB-3.0")
local AceDBOpts = LibStub("AceDBOptions-3.0")
local AceLocale = LibStub("AceLocale-3.0")
```

---

## 22. Resources

- GitHub repo: `https://github.com/WoWUIDev/Ace3`
- Full docs: `https://www.wowace.com/projects/ace3/pages/`
- Getting Started: `https://www.wowace.com/projects/ace3/pages/getting-started`
- AceConfig options tables: `https://www.wowace.com/projects/ace3/pages/ace-config-3-0-options-tables`
- AceDB tutorial: `https://www.wowace.com/projects/ace3/pages/ace-db-3-0-tutorial`
- AceGUI widgets: `https://www.wowace.com/projects/ace3/pages/ace-gui-3-0-widgets`
- Vanilla port (Turtle WoW): `https://github.com/laytya/Ace3v`
