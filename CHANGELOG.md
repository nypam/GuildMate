# Changelog

All notable changes to GuildMate will be documented in this file.

## [Unreleased]

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
