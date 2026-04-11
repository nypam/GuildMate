# Changelog

All notable changes to GuildMate will be documented in this file.

## [Unreleased]

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
