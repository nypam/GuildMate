# Professions Module — Implementation Plan

## Overview

Track guild members' professions and skill levels, synced across all addon users via AceComm. Phase 1 covers professions + levels. Phase 2 adds recipe scanning.

---

## Phase 1 — Professions & Levels

### Goal
Any guild member with the addon can see a roster of who has which profession and at what skill level. Data is collected automatically on login and shared via guild comm.

### Data Flow

```
Player logs in
  → GetSkillLineInfo() scans own professions
  → Stores locally in GuildMateDB.professions[memberKey]
  → Broadcasts PROF_UPDATE to guild via AceComm
  → Other clients receive and max-merge (newer lastUpdate wins)
```

### API — Scanning Own Professions

TBC Anniversary API for reading skill lines:
```lua
for i = 1, GetNumSkillLines() do
    local name, isHeader, isExpanded, rank, numTempPoints,
          modifier, maxRank, isAbandonable, stepCost,
          rankCost, minLevel, levelCost, numAvail = GetSkillLineInfo(i)

    -- Trade skills have isHeader=false and are in the "Professions" header section.
    -- Filter by checking known profession names or by checking rank > 0 and
    -- name matches a known list.
end
```

Known TBC professions to match against:
- **Primary:** Alchemy, Blacksmithing, Enchanting, Engineering, Herbalism, Jewelcrafting, Leatherworking, Mining, Skinning, Tailoring
- **Secondary:** Cooking, First Aid, Fishing

### DB Schema

```lua
GuildMateDB.professions = {
    ["Nypp-Sulfuras"] = {
        lastUpdate = 1744300000,   -- Unix timestamp
        skills = {
            ["Alchemy"]   = { rank = 375, maxRank = 375 },
            ["Herbalism"] = { rank = 350, maxRank = 375 },
            ["Cooking"]   = { rank = 300, maxRank = 375 },
        },
    },
    ["Thrall-Sulfuras"] = {
        lastUpdate = 1744295000,
        skills = {
            ["Blacksmithing"] = { rank = 375, maxRank = 375 },
            ["Mining"]        = { rank = 375, maxRank = 375 },
        },
    },
}
```

Estimated DB size: 50 members × ~3 professions × ~50 bytes = **~7.5 KB**. Trivial.

### Comm Protocol

Message format (single message, fits in one AceComm packet):
```
PROF_UPDATE|Nypp-Sulfuras|1744300000|Alchemy:375:375,Herbalism:350:375,Cooking:300:375
```

Fields:
- `memberKey` — who this data is about (always the sender)
- `timestamp` — Unix time of the scan
- `professions` — comma-separated `Name:rank:maxRank` pairs

Receiving logic:
```lua
if incomingTimestamp > storedTimestamp then
    -- Replace entire profession record for this member
end
```

### File Structure

```
Modules/Professions/
    ProfessionCore.lua     — Scan, store, broadcast, receive
    ProfessionView.lua     — Per-profession roster display
```

### ProfessionCore.lua — Functions

```lua
Professions:ScanSelf()
-- Called on PLAYER_LOGIN (10s delay) and when tradeskill window opens.
-- Reads GetSkillLineInfo(), stores in DB, broadcasts to guild.

Professions:BroadcastProfessions()
-- Sends PROF_UPDATE with own profession data to guild channel.

Professions:OnCommReceived(message, channel, sender)
-- Parses PROF_UPDATE, max-merges into DB.

Professions:GetMemberProfessions(memberKey)
-- Returns the skills table for a member, or nil.

Professions:GetProfessionRoster(professionName)
-- Returns a sorted list of { memberKey, name, rank, maxRank, online }
-- for all members who have this profession.
```

### ProfessionView.lua — UI

When user clicks a profession in the sidebar (e.g. "Alchemy"):

```
┌─────────────────────────────────────────────────┐
│  ALCHEMY                              Search: [ ]│
├─────────────────────────────────────────────────┤
│ ■ Nypp              375 / 375   ██████████ 100% │
│ ■ Thrall (offline)  300 / 375   ████████░░  80% │
│ ■ Jaina             150 / 375   ████░░░░░░  40% │
│ □ Sylvanas          —                           │
└─────────────────────────────────────────────────┘
```

- Green/red square = has addon or not
- Progress bar = rank / maxRank
- Search to filter by name
- "(offline)" for offline members
- "—" for members with no data (no addon)

When user clicks the parent "Professions" button:

```
┌─────────────────────────────────────────────────┐
│  GUILD PROFESSIONS                              │
├─────────────────────────────────────────────────┤
│  Alchemy         5 members    avg 320 / 375     │
│  Blacksmithing   3 members    avg 350 / 375     │
│  Enchanting      2 members    avg 280 / 375     │
│  ...                                            │
└─────────────────────────────────────────────────┘
```

Overview showing how many members have each profession and average level.

### Events to Register

```lua
-- Scan on login (delayed)
PLAYER_LOGIN → C_Timer.After(10, ScanSelf)

-- Re-scan when player opens tradeskill window (catches level-ups)
TRADE_SKILL_SHOW → ScanSelf()
TRADE_SKILL_UPDATE → ScanSelf()
```

### TOC Changes

Add after DonationCore files:
```
Modules\Professions\ProfessionCore.lua
Modules\Professions\ProfessionView.lua
```

### Sidebar Integration

Already done — "Professions" parent with per-profession children in sidebar. Replace `profComingSoon` placeholder modules with real `ProfessionView` renders parameterised by profession name.

### Locale Keys to Add

```lua
L["PROFESSIONS"]         = "PROFESSIONS"
L["GUILD_PROFESSIONS"]   = "GUILD PROFESSIONS"
L["NO_PROFESSION_DATA"]  = "No profession data available. Members need the addon."
L["SKILL_LEVEL"]         = "%d / %d"
L["MEMBERS_COUNT"]       = "%d member%s"
L["AVG_LEVEL"]           = "avg %d / %d"
L["SCAN_NEEDED"]         = "Open your tradeskill window to scan"
```

---

## Phase 2 — Recipe Scanning (Future)

### Goal
Track which recipes each member knows, enabling "who can craft X?" searches.

### Additional Data Collection

```lua
-- Only works when tradeskill window is open
TRADE_SKILL_SHOW event → scan all recipes

for i = 1, GetNumTradeSkills() do
    local name, type, numAvailable, isExpanded = GetTradeSkillInfo(i)
    -- type: "header", "subheader", "optimal", "medium", "easy", "trivial"
    if type ~= "header" and type ~= "subheader" then
        -- This is a recipe
        local link = GetTradeSkillRecipeLink(i)
        local recipeID = link and tonumber(link:match("enchant:(%d+)"))
        -- Store recipeID (number) not name (string) for space efficiency
    end
end
```

### Additional DB Schema

```lua
GuildMateDB.professions["Nypp-Sulfuras"].recipes = {
    ["Alchemy"] = { 28579, 28571, 28566, ... },  -- recipe IDs
}
```

### Additional Comm Protocol

Recipes are chunked (can be 200+ per profession):
```
RECIPE_UPDATE|Nypp-Sulfuras|1744300000|Alchemy|28579,28571,28566,...
```

AceComm handles splitting messages > 255 bytes automatically via ChatThrottleLib.

### Storage Estimate

```
50 members × 2 professions × 150 recipes × 6 bytes per ID = ~90 KB
```

Still well within SavedVariables limits.

### UI Addition

- Recipe list below the member roster when clicking a specific member
- "Who can craft...?" search field at the top of each profession view
- Recipe names resolved via GetSpellInfo(recipeID) at display time (not stored)

### Risks

- Players must open their tradeskill window at least once for recipes to scan
- Recipe data can become stale (player learns new recipe but hasn't opened window)
- GetTradeSkillRecipeLink may not return a parseable ID for all recipe types in TBC Anniversary — needs in-game testing
- Cross-profession recipes (e.g. Enchanting uses GetCraftInfo, not GetTradeSkillInfo) need separate handling

---

## Phase 3 — Craft Requests (Future)

### Goal
Players can post "I need [Flask of Relentless Assault]" requests visible to guild members who can craft it. Part of the Requests module, not Professions.

### Design Sketch

- Request stored in DB and broadcast via comm
- Recipe data from Phase 2 used to auto-match requests to crafters
- Notification to crafters who are online
- Request board UI in the Requests module

This depends on Phase 2 being complete.

---

## Implementation Checklist

### Phase 1
- [ ] Create `Modules/Professions/ProfessionCore.lua`
  - [ ] `ScanSelf()` — read GetSkillLineInfo
  - [ ] DB accessor: `GetMemberProfessions()`, `GetProfessionRoster()`
  - [ ] Comm: broadcast `PROF_UPDATE` on login
  - [ ] Comm: receive and merge `PROF_UPDATE`
  - [ ] Register `TRADE_SKILL_SHOW` / `TRADE_SKILL_UPDATE` for re-scan
- [ ] Create `Modules/Professions/ProfessionView.lua`
  - [ ] Per-profession roster (name, rank, progress bar)
  - [ ] Overview page (all professions, member count, avg level)
  - [ ] Search field
- [ ] Add locale keys (enUS + frFR)
- [ ] Add files to .toc
- [ ] Replace sidebar placeholder modules with real ProfessionView
- [ ] Wire comm handler in guildMate.lua OnCommReceived
- [ ] Test in-game

### Phase 2
- [ ] Add recipe scanning on TRADE_SKILL_SHOW
- [ ] Add RECIPE_UPDATE comm protocol
- [ ] Add recipe storage in DB
- [ ] Add "who can craft?" search UI
- [ ] Test with Enchanting (uses GetCraftInfo, not GetTradeSkillInfo)

### Phase 3
- [ ] Design request data schema
- [ ] Build request board UI
- [ ] Match requests to crafters via recipe DB
- [ ] Notification system for online crafters

---

## TBC Anniversary API Notes

Verify these in-game before building:

| API | Expected | Notes |
|-----|----------|-------|
| `GetNumSkillLines()` | Should work | Returns count of all skill lines |
| `GetSkillLineInfo(i)` | Should work | 13 return values in TBC |
| `GetNumTradeSkills()` | Should work | Only when tradeskill window is open |
| `GetTradeSkillInfo(i)` | Should work | Returns name, type, etc. |
| `GetTradeSkillRecipeLink(i)` | Needs testing | May not exist in TBC Anniversary |
| `TRADE_SKILL_SHOW` event | Should fire | When player opens any tradeskill |
| `TRADE_SKILL_UPDATE` event | Should fire | When tradeskill list refreshes |
| `GetCraftInfo(i)` | Needs testing | Enchanting uses Craft API, not TradeSkill |

**Critical:** Test `GetSkillLineInfo` on the first login of a session. Some skill data may not be available immediately — may need a short delay (like we do for roster data).
