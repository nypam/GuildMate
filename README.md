# GuildMate

A guild bank donation tracker for WoW TBC Anniversary.

WoW's guild bank only remembers the last 25 money transactions. After that, deposits vanish like they never happened. GuildMate grabs every transaction whenever any guild member peeks at the bank, then quietly shares it across the guild. Your donation history actually sticks around this time.

Still in early development, but it works and it's already useful.

## Features

- **Donation goals.** Officers set weekly or monthly gold targets per rank, broadcast automatically to the guild.
- **Automatic tracking.** Reads and records bank deposits on open, with deduplication built in.
- **Guild-wide sync.** Data spreads via addon messaging. More members installed means fewer missed deposits. No spreadsheets, no Discord bots.
- **Officer dashboard.** Color-coded roster (red/yellow/green), search, filters, progress bars, one-click whisper reminders, guild announcements, CSV export.
- **Member view.** Personal progress card, days remaining, last 6 periods of history, optional login reminder.
- **Minimap button.** Left-click to toggle the main window.

## Installation

1. Download or clone this repo
2. Copy the `guildMate` folder into `World of Warcraft/_anniversary_/Interface/AddOns/`
3. Restart WoW or type `/reload`
4. Type `/gm` to open the main window

## Commands

| Command | What it does |
|---|---|
| `/gm` | Toggle the main window |
| `/gm show` | Open the main window |
| `/gm help` | List all commands |
| `/gm debug` | Toggle officer view for testing (non-officers can see officer UI) |

## How the sync works

When any guild member opens the guild bank, GuildMate reads the transaction log and broadcasts donation totals to the guild via addon messaging. Other clients receive these totals and keep the highest known value for each member and period. This means the collective bank visits of your entire guild feed into a single shared ledger.

The catch: if a deposit rolls off the 25-entry bank log before anyone opens the bank, it's gone for good. That's a hard WoW API limitation. Mitigate it by having members open the bank regularly.

## Project structure

```
guildMate.toc              Load order and metadata (Interface: 20505)
guildMate.lua              Entry point: init, slash commands, minimap button
embeds.xml                 Loads all libraries from Libs/

Core/
  Database.lua             SavedVariables schema, DB accessors for goals/donations/settings
  Utils.lua                Money formatting, period keys, color helpers, layout builder
  Events.lua               WoW event registrations, guild bank polling and hooks

UI/
  MainFrame.lua            Main window shell with sidebar navigation and content pane

Modules/Donations/
  DonationCore.lua         Roster cache, transaction processing, comm sync, reminders
  GoalEditor.lua           Goal create/edit panel
  OfficerView.lua          Officer dashboard with roster, actions, and progress tracking
  MemberView.lua           Personal status card and donation history
  SettingsView.lua         Officer ranks, reminder toggle, announce channel config
```

## Dependencies

All libraries are bundled in `Libs/`:

LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0, AceConsole-3.0, AceComm-3.0, ChatThrottleLib, AceLocale-3.0, AceGUI-3.0, AceConfig-3.0, LibDataBroker-1.1, LibDBIcon-1.0

## TBC Anniversary API notes

A few things behave differently in TBC Anniversary compared to retail or modern Classic:

- `GetNumGuildBankMoneyTransactions()` always returns 0 even when data exists. GuildMate iterates 1 to 25 and breaks on nil instead.
- `GUILDBANKFRAME_OPENED` / `GUILDBANKFRAME_CLOSED` events are unreliable. GuildMate polls for the `GuildBankFrame` global and hooks `OnShow`/`OnHide` once it appears.
- `GuildRoster()` doesn't exist. The addon relies on `GUILD_ROSTER_UPDATE` which fires automatically.
- The `os` library is absent. Date math uses `date("*t")` and manual arithmetic.

## Planned features

GuildMate is meant to grow into a broader guild management toolkit. Here's what's on the roadmap:

- **Craft recipe directory.** Track which guild members can craft what. Browse available recipes across the guild so you know who to ask instead of spamming guild chat.
- **Crafting order book.** Request crafts from guildmates and see open orders. A lightweight in-guild work order system without needing trade chat or external tools.
- **Localization.** AceLocale is already bundled, just not wired up yet. French support first, more languages to follow via CurseForge community translations.

## Contributing

Feedback, bug reports, and pull requests are welcome. This is a hobby project so responses may not be instant, but they will happen.

## License

MIT
