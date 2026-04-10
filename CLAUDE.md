# GuildMate — Claude Session Handoff

This file exists so a Claude session on any machine can immediately understand the project and pick up where the previous session left off. Commit this file to Git.

---

## What this addon does

**GuildMate** is a WoW TBC Anniversary addon for guild donation tracking.

- Officers set a gold donation goal (weekly or monthly) for target ranks.
- The addon reads the guild bank money log and records deposits automatically.
- Officers see the full roster with colour-coded donation status, and can remind/announce.
- Non-officers see their own personal status and history.
- Data syncs across online officer clients via AceComm guild messages.

**Target client:** WoW TBC Anniversary (Interface version 20504). NOT retail, NOT modern Classic.

---

## Project status (as of 2026-04-10)

### Done and working in-game
- [x] Full Ace3 foundation (AceAddon, AceEvent, AceConsole, AceComm, AceGUI, LibDBIcon)
- [x] Main window: AceGUI Frame + TreeGroup sidebar + content pane
- [x] Minimap button (LibDBIcon)
- [x] Slash commands: `/gm`, `/guildmate`
- [x] Database layer with SavedVariables + schema migration
- [x] Guild bank log parsing — reads `GetGuildBankMoneyTransaction(i)` on bank open
- [x] Transaction deduplication (fingerprint → 45-day TTL in SavedVariables)
- [x] Guild-wide comm sync (broadcasts running totals via AceComm, idempotent max-merge)
- [x] Officer view: goal card, roster with colour-coded rows, Edit Goal, Remind, Announce
- [x] Member view: personal status card + period history (last 6 periods)
- [x] Goal editor: gold slider + typed box, weekly/monthly radio, rank checkboxes
- [x] Settings panel: officer ranks, reminder toggle, message template, announce channel
- [x] Auto-remind on login: officers whisper non-donating members 5 s after PLAYER_LOGIN
- [x] `/gm debug` — toggle officer view for testing (non-officers can see officer UI)

### Still TODO / nice to have
- [ ] Sound feedback on Remind/Announce (currently just `PlaySound(856)` on button click)
- [ ] Tooltip improvements (rank name already shows in roster tooltip)
- [ ] Edge case: member name contains a `-` before the realm hyphen (SplitMemberKey may mismatch)
- [ ] `/gm scanlog` and `/gm testbank` are debug commands; decide whether to keep or remove before release

### Residual sync limitation
Any deposit that rolls off the 25-entry bank log before any guild member opens the bank
is permanently unrecoverable (hard WoW API limitation). Mitigate by opening the bank regularly.

---

## File map

```
Updates.md                 — Human-readable changelog (newest first)
guildMate.toc              — Load order; Interface: 20504
guildMate.lua              — Addon entry point: OnInitialize, OnEnable, slash commands, minimap
embeds.xml                 — Loads all Libs/

Core/Database.lua          — SavedVariables schema, all DB accessors (goals, donations, settings)
Core/Utils.lua             — Pure helpers: money format, period keys, colour utils, SetFrameColor, Font
Core/Events.lua            — All WoW event registrations; guild bank polling & hook; dispatch to modules

UI/MainFrame.lua           — AceGUI Frame + TreeGroup shell; RegisterModule / Show / RefreshActiveView

Modules/Donations/
  DonationCore.lua         — Roster cache, ProcessTransactionLog, comm handler, RemindIncomplete, AnnounceProgress
  OfficerView.lua          — Officer UI: header (New Goal / ⚙), goal card (Edit Goal), roster rows, action bar
  MemberView.lua           — Member UI: personal status card + history list
  GoalEditor.lua           — Goal create/edit modal (rendered inside main content pane, not a separate window)
  SettingsView.lua         — Settings panel: officer ranks, reminder, announce channel
```

### Load order (from .toc)
`embeds.xml` → `guildMate.lua` → `Core/Database.lua` → `Core/Utils.lua` → `Core/Events.lua` → `UI/MainFrame.lua` → `Modules/Donations/DonationCore.lua` → `GoalEditor.lua` → `OfficerView.lua` → `MemberView.lua` → `SettingsView.lua`

Every file after `guildMate.lua` grabs the addon with:
```lua
local GM = LibStub("AceAddon-3.0"):GetAddon("GuildMate")
```

---

## Architecture patterns

### Module registration
Modules are registered in `guildMate.lua:OnInitialize`:
```lua
self.MainFrame:RegisterModule("donations", "Donations", "Interface\\Icons\\...", self.Donations)
```
`MainFrame` calls `module:Render(container)` when the tree node is selected.

### outerContainer pattern (critical — this burned us once)
Every view that can navigate to another panel (GoalEditor, SettingsView) **must** receive the real content container (`outerContainer`), NOT the scroll frame that lives inside it. If you pass `scroll` instead of `container`, the destination panel creates a ScrollFrame inside a ScrollFrame and the scroll area breaks.

In `OfficerView:Render(container)`:
- `container` is the real content pane → pass to `_RenderHeader` and `_RenderGoalCard`
- `scroll` is the ScrollFrame created inside → add rows to this, but never navigate from it

### Navigation pattern
"Back" navigation is done by calling the previous view's `Render` again:
```lua
GM.GoalEditor:Open(outerContainer, goal,
    function() OfficerView:Render(outerContainer) end,   -- onSave → back
    function() OfficerView:Render(outerContainer) end)   -- onCancel → back
```

### Reminder message substitution
Uses `gsub` named tokens, NOT `string.format` positional args:
```
%s = member name   %g = goal amount   %p = period   %d = donated so far
```

### Period keys
- Weekly: `"2026-W15"` (ISO 8601 week)
- Monthly: `"2026-04"`
- Computed by `Utils.PeriodKey(timestamp, "weekly"|"monthly")`
- Old transactions get correct historical keys via elapsed-offset arithmetic in `ProcessTransactionLog`

### Member keys
`"Name-Realm"` string, e.g. `"Thrall-Sulfuras"`. Built by `Utils.MemberKey(name, realm)`.

---

## TBC Anniversary API — confirmed pitfalls

These were all discovered through live in-game testing. Do not assume retail API names work.

| API | Status | Notes |
|-----|--------|-------|
| `GetGuildBankMoneyTransaction(i)` | ✅ WORKS | Returns `txType, name, amount, year, month, day, hour`. year/month/day/hour are elapsed offsets (0 = just now), not absolute date. |
| `GetNumGuildBankMoneyTransactions()` | ⚠ BROKEN | Always returns 0 even when data exists. **Ignore the count.** Iterate `for i = 1, 25 do ... if not txType then break end` instead. |
| `GetGuildBankTransactionInfo()` | ❌ MISSING | Item transaction API. Does not exist in TBC Anniversary. |
| `GUILDBANKFRAME_OPENED` event | ❌ UNRELIABLE | Does not fire reliably. Do not use. |
| `GUILDBANKFRAME_CLOSED` event | ❌ UNRELIABLE | Same. |
| `GuildBankFrame` global | ⚠ LAZY-LOADED | Is nil at OnEnable. Frame is demand-loaded at unpredictable time. **Use polling** (see Events.lua). |
| `GUILDBANK_UPDATE_MONEY` event | ✅ WORKS | Fires when bank money changes while bank is open. Guarded with `pcall` in Events.lua. |
| `GuildRoster()` | ❌ MISSING | Does not exist. `GUILD_ROSTER_UPDATE` fires automatically on login and roster changes. |
| `os` global | ❌ MISSING | The entire `os` library is absent in WoW Lua. Use `date("*t")` (no arg = current time table) and manual arithmetic. Never use `os.time(tbl)`. |
| `frame:SetBackdrop()` | ❌ MISSING | Not available on plain AceGUI container frames. Use `Utils.SetFrameColor()` (CreateTexture approach). |
| `label:SetFont(obj:GetFont(), size)` | ⚠ MULTI-RETURN TRAP | `obj:GetFont()` returns 3 values; only the first is forwarded as a function argument. Use `Utils.Font(obj, size)` which unpacks all 3 as the last expression. |
| `select(2, GetGuildInfo("player"))` | ❌ WRONG | `GetGuildInfo` returns `guildName, guildRankName, guildRankIndex, ...`. Use `local _, _, rankIndex = GetGuildInfo("player")`. |
| `GUILD_BANK_MAX_TABS` | ⚠ MAY BE NIL | Can be nil at addon load. Use `(GUILD_BANK_MAX_TABS or 6)`. |

### Guild bank detection — the working approach (Events.lua)
```lua
-- Poll every 1 second until GuildBankFrame appears, then hook OnShow/OnHide once.
local _pollCount = 0
local function _PollForBankFrame()
    if _G["GuildBankFrame"] then
        if not GuildBankFrame._gmHooked then
            GuildBankFrame._gmHooked = true
            GuildBankFrame:HookScript("OnShow", Events.OnGuildBankOpened)
            GuildBankFrame:HookScript("OnHide", Events.OnGuildBankClosed)
        end
        if GuildBankFrame:IsShown() and not GM.Events._bankOpen then
            Events.OnGuildBankOpened()
        end
    elseif _pollCount < 7200 then
        _pollCount = _pollCount + 1
        C_Timer.After(1, _PollForBankFrame)
    end
end
C_Timer.After(1, _PollForBankFrame)
```
Approaches that did NOT work:
1. `GUILDBANKFRAME_OPENED` event — unreliable, often doesn't fire
2. `hooksecurefunc("GuildBankFrame_LoadUI", ...)` — fires before frame is fully ready
3. Hooking `GuildBankFrame:HookScript(...)` directly in `OnEnable` — GuildBankFrame is nil

---

## SavedVariables schema (GuildMateDB)

```lua
GuildMateDB = {
    version = 1,
    goals = {
        [id] = {
            id, goldAmount, period, targetRanks, active, createdBy, startEpoch
        }
    },
    donations = {
        ["Name-Realm"] = {
            records     = { ["2026-W15"] = copperTotal, ... },
            lastDeposit = unixTimestamp,
            rankIndex   = 0,
        }
    },
    seenTransactions = {
        ["name|amount|year|month|day|hour"] = expiryTimestamp,  -- 45-day TTL
    },
    settings = {
        officerRanks     = { [0]=true, [1]=true },
        reminderEnabled  = true,
        reminderMessage  = "Hi %s! Don't forget the %p guild donation goal of %g. You've donated %d so far.",
        announceChannel  = "GUILD",  -- "GUILD" | "OFFICER" | "OFF"
        windowWidth      = 900,
        windowHeight     = 550,
        windowX          = nil,
        windowY          = nil,
        minimapPos       = 45,
        minimapData      = { hide=false, minimapPos=45 },
    },
}
```

---

## AceComm message format

Prefix: `"GuildMate"` (≤16 chars, registered in `OnInitialize`).

| Message | Direction | Format |
|---------|-----------|--------|
| `DONATION_TOTAL` | officer → guild | `DONATION_TOTAL\|Name-Realm\|2026-W15\|150000` |
| `GOAL_UPDATE` | officer → guild | `GOAL_UPDATE\|id\|goldAmount\|period` (received but not fully deserialised yet) |

Sync is idempotent: receivers do `max(local, received)` on totals. Never broadcast deltas.

---

## Slash commands

| Command | Effect |
|---------|--------|
| `/gm` or `/gm show` | Toggle main window |
| `/gm donations` | Open donations panel |
| `/gm debug` | Toggle officer view override (lets non-officers see officer UI for testing) |
| `/gm testbank` | Force-scan guild bank log immediately (sets `_bankOpen=true`, calls `ProcessTransactionLog`) |
| `/gm scanlog` | Dump all `GuildBank*` globals + first money transaction to `GuildMateDB.debugScan` in SavedVariables |
| `/gm help` | List commands in chat |

---

## Libs included (in Libs/)

- LibStub
- CallbackHandler-1.0
- AceAddon-3.0
- AceEvent-3.0
- AceConsole-3.0
- AceComm-3.0 (+ ChatThrottleLib)
- AceLocale-3.0
- AceGUI-3.0
- AceConfig-3.0 (AceConfigDialog, AceConfigCmd, AceConfigRegistry)
- LibDataBroker-1.1
- LibDBIcon-1.0
