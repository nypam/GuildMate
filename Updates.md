# GuildMate — Update Notes

---

## 2026-04-11 — Addon detection & per-player whisper reminders

### Addon detection
Every client now broadcasts a `HELLO|version` message to the guild on login. The officer
roster shows a green dot (the WoW online status icon) next to members who have GuildMate
installed. This tells officers at a glance who is contributing to bank scan coverage.

- Uses `Interface\FriendsFrame\StatusIcon-Online` inline icon
- Ephemeral — only tracks who's online this session, not persisted

### Per-player whisper reminder
Each roster row now shows a chat icon (`Interface\ChatFrame\UI-ChatIcon-Chat-Up`) after
the progress bar. Clicking it whispers that specific member a personalised donation
reminder with their current progress and remaining amount.

- Only shown for online members who haven't met the goal yet
- Tooltip on hover: "Whisper reminder to PlayerName"
- Prints confirmation in officer's chat: "Reminder sent to PlayerName."

---

## 2026-04-10 — Universal bank sync

### Problem
The guild bank money log only shows the last 25 transactions. If more than 25 deposits
happened between two bank opens, older entries roll off and are lost forever.

Previously, only officers ran the bank scan. This meant any donation not captured during
an officer's bank session was missed entirely.

### Fix

**Any guild member who opens the guild bank now contributes to the history.**

After every bank scan (triggered when anyone opens the guild bank), the addon broadcasts
all known donation totals for the current and previous period to the entire guild via
addon comm. Officers receive these broadcasts and max-merge them into their local DB.

Result: the collective coverage of all members opening the bank multiplies the chances
that every donation is captured before it rolls off the 25-entry window.

### Technical details

- `DonationCore:BroadcastKnownTotals()` — new function, called at the end of every
  `ProcessTransactionLog()` run regardless of whether new transactions were found.
  Sends `DONATION_TOTAL|memberKey|periodKey|total` for the current and previous period
  for every member with a recorded donation.

- `ProcessTransactionLog()` already ran for all members (the bank hook fires for
  everyone), but previously only broadcast newly-found transactions. Now it always
  broadcasts the full known state.

- `OnCommReceived` now debounces `RefreshActiveView` — a bulk sync sends many messages
  at once, so the UI redraws once after a 0.5s settling delay instead of once per
  message.

- **Database** (`Core/Database.lua`): donation records now store `{own, synced}` instead
  of a plain number. `own` = copper this client read from the bank directly. `synced` =
  highest total received from any comm broadcast. `GetDonated` returns `max(own, synced)`.
  This prevents double-counting if the same transaction is both locally read and received
  via comm. Old plain-number entries are migrated in-place on first access.

### Residual limitation
If a deposit rolls off the 25-entry log before **any** guild member opens the bank,
that transaction is permanently unrecoverable — this is a hard WoW API limitation.
Mitigate by encouraging officers (or anyone) to open the bank regularly.

---
