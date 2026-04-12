# Changelog

All notable changes to GuildMate will be documented in this file.

## [Unreleased]

## [v0.4.5] - 2026-04-12

### Fixed
- **Broadcast storm**: HELLO welcome dump removed — new logins no longer blast 5–50KB of data to the whole guild. HELLO now only exchanges versions; data propagates through real events (bank scans, goal edits, tradeskill opens) or explicit `/gm sync`.
- **Idle bank opens silent**: `BroadcastKnownTotals` only fires when the bank scan actually adds new events. Previously blasted after every bank open.
- **Donation double-counting healed**: synthetic event creation in `SetDonationTotal` removed. The real donation log is now authoritative; aggregates from other clients can only fill periods with no detail. `DB:Init()` re-runs the totals from the log on load, healing bloated values from older versions (auto-backup before touching anything).
- **Scan spam**: re-scans while tradeskill/craft window stays open are silent unless new recipes were found. Only the first scan per window session announces.
- **Enchanting categories**: missing headers were caused by not expanding collapsed sub-sections and over-strict header detection. Now expands via `ExpandCraftSkillLine` and falls back to "no reagents + no link = header" detection.

### Added
- **Per-sender rate limit** on incoming messages (60s sliding window, per-command caps). Runaway old clients can't saturate comm even when version-compatible.
- **Strict version gate**: data from senders whose version we don't yet know is rejected (was previously accepted). We fire an opportunistic HELLO so both sides learn each other's versions on the next round-trip.
- **Schema write lock** — `GuildMateDB.writeLock` records `MIN_COMPAT_VERSION` when a new-enough client runs. Older clients loading the same SavedVariables enter read-only mode and display a chat warning.
- **Addon version per member** in the officer roster — green/amber/red square + compact version tag. Tooltip shows exact version and MIN_COMPAT_VERSION when outdated.
- **Slot-based enchanting recipe grouping** (Helm → Shoulder → Cloak → Chest → Bracer → Gloves → Boots → 2H Weapon → Weapon → Shield → Ring) instead of Blizzard's generic "Enchant" category. English + French keyword detection.
- **Category-ordered recipe lists** for all other professions — matches the in-game tradeskill window order (Potion → Elixir → Flask, etc.) instead of alphabetical. Category + position captured during scan and synced via `RECIPE_UPDATE` (extended wire format, backward-compatible with 3-field entries).
- **Scan progress messages** — "Scanning recipes — keep this window open..." → "Synced N Alchemy recipes to the guild" printed to chat.
- **Goal shown in grey** for off-rank members (e.g. Reroll). Personal progress bar switches to guild-wide "N / M members met" with an "Applies to: Officer, Raider" hint. Still informational only.
- **Bidirectional HELLO handshake** — receiving a HELLO from an unknown sender sends one back so both sides sync versions without waiting for the next login.
- **CurseForge build independence** — libraries are now fully vendored; builds no longer depend on `repos.curseforge.com` availability.

### Changed
- Live Comm Feed in Debug view: colored badge (green down arrow for incoming, orange up arrow for outgoing) drawn from WHITE8X8 strips for true-white rendering. Columns left-aligned with spacing.
- Debug view: per-table "Last Update" column, refresh button on Comm Stats, destructive actions hidden when `/gm debug` is OFF.
- Scan events coalesced into a single deferred run (cancel-and-reschedule 0.6s timer) instead of N queued timers — prevents freeze when tradeskill window pulses updates.
- Filter resets no longer touch the user's tradeskill filter (caused UI stutter). If a filter is active, categories may be missing for some recipes — removing the filter and reopening rescans correctly.

## [v0.4.4] - 2026-04-12

### Added
- **Enchanting recipe scanning** — uses the separate Craft API (`GetNumCrafts`, `GetCraftInfo`, `CraftFrame`, `CRAFT_SHOW`/`CRAFT_UPDATE`). TBC quirk: enchanting predates the TradeSkill system and was silently invisible to the scanner.
- Recipe categories — scanner captures in-game category headers (e.g. "Potion", "Elixir", "Helm") and their positional order; recipe list displays grouped headers matching the tradeskill/craft window order

### Changed
- Recipe sort order now follows the in-game window (category → position) instead of alphabetical
- Live comm feed triangle is now pure white (`SetDesaturated(true)` strips the yellow tint baked into `ChatFrameExpandArrow`)

## [v0.4.3] - 2026-04-12

### Added
- Debug live comm feed — last 50 incoming/outgoing messages with direction badge, command, sender, bytes, and tooltip showing full payload
- Per-table "Last Update" column in Debug DB inspector (Xs/Xm/Xh ago)
- Refresh button on Debug Comm Stats
- `GOAL_NOT_APPLICABLE` locale string (enUS + frFR)

### Changed
- Member view now hides the donation goal card for players whose rank is not in the goal's target ranks (shows "The current donation goal does not apply to your rank." instead)
- Debug view no longer shows the "Destructive actions are hidden" hint text when `/gm debug` is OFF — the section simply collapses
- Live comm feed direction cell uses a colored square badge with a white triangle (▼ green for incoming, ▲ orange for outgoing) rendered via `ChatFrameExpandArrow` texture rotated with `SetTexCoord`
- Live comm feed columns are left-aligned with spacing between the direction label and the Command column

## [v0.4.1] - 2026-04-12

### Added
- **Event-based donation tracking** — individual deposit events with timestamps stored in `donationLog`
- Count-based reconciliation between bank log and DB (handles same-amount deposits correctly)
- `/gm rescan` and Debug "Rescan Bank" button — re-read bank log and rebuild recent events
- `/gm backup`, `/gm backups`, `/gm restore` — donation history snapshot system (5 rolling slots)
- Auto-backup donations before schema migrations and Reset All
- Debug "Actions" section now hidden unless `/gm debug` is ON (prevents accidental destructive ops)
- French profession name canonicalization (Joaillerie → Jewelcrafting, Alchimie → Alchemy, etc.)
- `DONATION_BATCH` message replaces N individual `DONATION_TOTAL` (100x reduction)
- `DEPOSIT` and `DEPOSIT_BATCH` messages for rich event sync with timestamps
- `/gm commtest` PING/PONG for comm verification
- Data pruning on roster refresh (addonUsers, profession crafters — never donations)
- CSV export rewritten: one row per deposit with Date/Time/Player/Realm/Rank/Amount/Period/EventId

### Changed
- Donation history is now sacred — **never** deleted by purge, reset, or roster changes
- Backup retention expanded to 5 rolling snapshots
- Reset All now preserves donation backups across wipe
- Reagent encoding uses backslash escapes (fixes corruption of names with hyphens)
- Comm regex uses `[%w_]+` instead of `%w+` (fixes silent failure of underscore commands)
- Comm field parsers use `[^|]+` instead of greedy `(.+)` (fixes misparsing)
- Simplified donation records to plain numbers (removed dead `{own, synced}` pattern)

### Fixed
- **Critical**: `PROF_UPDATE`, `RECIPE_UPDATE`, `DONATION_TOTAL`, `GOAL_UPDATE` silently failing because Lua `%w` doesn't match underscore
- Duplicate donation events caused by WoW's fuzzy "X hours ago" timestamps drifting
- Professions not syncing for non-English clients
- Goal not propagating to new members (HELLO now triggers goal broadcast)
- Recipes not syncing to players without the profession
- Recipe icons showing question marks (GetRecipeList wasn't exposing icon/itemLink)
- French locale format string mismatch causing Lua error on officer view

## [v0.4.0] - 2026-04-11

### Added
- **Professions Phase 2** — recipe scanning with spell ID-based storage (locale-independent)
- Recipe icons, reagent icons, and item tooltips on hover
- Reagent inventory check (bag count with green/orange/red colour)
- Click any recipe to expand reagent details
- Recipe search field with debounced filtering
- Recipe broadcast via RECIPE_UPDATE (spellID~icon format)
- `/gm sync` command — forces full broadcast of goal, donations, professions, recipes
- `/gm status` command — shows local DB state (goal, donation/profession/recipe counts)
- `/gm commtest` command — PING/PONG comm test with toggle logging
- Force Goal button for Guild Master — pushes goal to all online members
- Auto-broadcast goal + donations when new addon user sends HELLO
- Scroll position preserved when clicking recipes
- French profession name canonicalization (Joaillerie → Jewelcrafting, etc.)
- Version number read from TOC metadata at runtime

### Changed
- Recipe storage rewritten: keyed by spellID instead of localized name
- Recipe names resolved at display time via GetSpellInfo (correct per client locale)
- New DB table `recipes2` replaces old `recipes` (old data ignored)
- Prefer GetTradeSkillIcon (item icon) over GetSpellInfo icon for recipes
- All comm regex patterns fixed: `%w+` → `[%w_]+` (Lua `%w` doesn't match underscore)
- All comm field patterns fixed: `(.+)` → `([^|]+)` (greedy match caused misparsing)
- Simplified GOAL message format (dropped createdBy field)

### Fixed
- **Critical**: All comm messages with underscores (DONATION_TOTAL, GOAL_UPDATE, PROF_UPDATE, RECIPE_UPDATE) were silently failing to parse on receiving clients
- Goal sync not working for new members
- French locale format string mismatch (DAYS_REMAINING had extra %s)
- Recipe icons showing question marks (GetRecipeList wasn't passing icon data)
- Professions not syncing for non-English clients (localized names not recognized)

## [v0.3.1] - 2026-04-11

### Added
- **Professions Phase 2** — recipe scanning with icons, reagents, and inventory check
- Recipe icons captured via GetTradeSkillIcon during tradeskill window scan
- Reagent icons captured via GetTradeSkillReagentInfo texture return
- Item tooltips on recipe hover (via stored item links)
- Reagent tooltips on hover in expanded recipe detail
- Bag inventory count per reagent (green/orange/red colour-coded)
- Click any recipe to expand and see required materials
- Recipe search field with debounced filtering
- Auto-broadcast goal + donation data when a new addon user sends HELLO (fixes new members not seeing the goal)
- TradeSkillFrame OnShow hook as fallback for recipe scanning

### Fixed
- Recipe icons showing question marks — GetRecipeList wasn't passing icon/itemLink to the view
- Old recipes without icons now get re-scanned when tradeskill window is opened
- Reagents without stored icons get re-scanned automatically
- New guild members not receiving the active goal until next officer login

## [v0.3.0] - 2026-04-11

### Added
- **Professions module (Phase 1)** — scans own professions on login, broadcasts to guild via AceComm, synced across all addon users
- Professions overview page — all 13 TBC professions listed with member count, highest level, avg level, progress bars
- Per-profession roster view — class-coloured member list with skill levels, progress bars, search field
- Sidebar sub-menu for professions: primary crafting, primary gathering, secondary (collapsible, only visible when active)
- Profession data persisted in SavedVariables (`GuildMateDB.professions`)
- Auto re-scan on TRADE_SKILL_SHOW, TRADE_SKILL_UPDATE, SKILL_LINES_CHANGED events
- Requests module placeholder with Gold/Craft sub-items (coming soon)
- Current week/month highlight in member history (tinted background, left accent bar, "(current)" label)
- Collapsible Guild Donation Logs in member view (Show/Hide button, off by default)
- Summary + last deposit merged into single row with status-coloured background in member view
- Two-container layout in member view: goal info (with padding) + status bar (edge-to-edge), wrapped in a single parent border

### Changed
- Member view status card split into bordered goal container + edge-to-edge status summary
- History rows now show progress bars, coloured squares, and future "covered" periods
- Professions overview sorted by highest level first, then alphabetical
- Sidebar profession order: crafting → gathering → secondary

## [v0.2.0] - 2026-04-11

### Added
- Full UI rewrite using raw WoW frames (removed AceGUI dependency)
- French localization (enUS + frFR) via AceLocale — 107 translated strings
- Interface Options panel (ESC → AddOns → GuildMate) with embedded settings
- Per-player whisper reminders — chat icon in each roster row
- Addon detection — green/red squares show who has GuildMate installed
- Addon user tracking persisted in SavedVariables across sessions
- Search field in roster (Member Status tab)
- Search field in donation logs
- Logs tab — full donation history grouped by period, most recent first
- Tabbed interface (Member Status / Logs) inside a bordered container
- Bordered containers for Goal, Tools, and Member Status sections
- Delete goal button with 3-second confirmation
- Periods ahead display (+3wk / +2mo) for members who overpay
- Guild-wide total collected per period shown in goal card
- CurseForge packaging (.pkgmeta + GitHub Actions CI/CD)
- CHANGELOG.md for tracking releases

### Changed
- UI built with LayoutBuilder + CreateFrame instead of AceGUI
- Settings "Officer Ranks" renamed to "Goal Management"
- Goal met announcement only fires for online members (no retroactive spam)
- Cog icon button for settings (replaces text button)
- Donation records now store {own, synced} to prevent double-counting
- All guild members contribute to bank scan coverage (not just officers)
- Debounced UI refresh on bulk comm sync (0.5s settling delay)
- Progress bar capped at 100% for members who exceeded the goal

### Fixed
- Ghost FontStrings staying on screen after closing addon (ClearContent hides scroll child)
- Scroll child not updating width after content refresh (closure captured stale reference)
- AceGUI layout conflicts with manually anchored frames
- CreateFontString crash with font object instead of string template name in TBC

## [v0.1.0] - 2026-04-10

### Added
- Initial release
- Guild bank money log parsing via GetGuildBankMoneyTransaction (TBC Anniversary API)
- Transaction deduplication with 45-day TTL fingerprints
- Officer view: goal card, colour-coded roster, Remind Incomplete, Announce to Guild
- Member view: personal status card with progress bar and history (last 6 periods)
- Goal editor: gold slider + typed input, weekly/monthly, rank selection
- Settings panel: officer ranks, reminder toggle, announce channel
- Guild-wide donation sync via AceComm (idempotent max-merge)
- Auto-remind on login (officers whisper non-donating members)
- Self-reminder on login for members who haven't met the goal
- Guild bank frame polling (handles demand-loaded GuildBankFrame in TBC)
- Minimap button (LibDBIcon)
- Slash commands: /gm, /gm donations, /gm debug, /gm testbank, /gm scanlog, /gm help
- CSV export of donation data
- Goal broadcast to guild on officer login
- Debug officer view toggle (/gm debug)
