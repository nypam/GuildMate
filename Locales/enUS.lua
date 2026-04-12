local L = LibStub("AceLocale-3.0"):NewLocale("GuildMate", "enUS", true)
if not L then return end

-- ── General ──────────────────────────────────────────────────────────────────
L["ADDON_NAME"]           = "GuildMate"
L["ADDON_TITLE"]          = "|cff4A90D9Guild|rMate"
L["VERSION_LINE"]         = "GuildMate v%s  by |cffffffffNypp|r |TInterface\\Icons\\INV_Drink_04:14|t"
L["TAGLINE"]              = "|cffaaaaaaA |cffd4af37Must Have|cffaaaaaa Addon|r"

-- ── Slash commands ───────────────────────────────────────────────────────────
L["CMD_HELP_HEADER"]      = "|cff4A90D9GuildMate|r commands:"
L["CMD_HELP_TOGGLE"]      = "  /gm             \226\128\148 Toggle main window"
L["CMD_HELP_DONATIONS"]   = "  /gm donations   \226\128\148 Open Donations panel"
L["CMD_HELP_DEBUG"]        = "  /gm debug       \226\128\148 Toggle officer view override (testing)"
L["CMD_HELP_SCANLOG"]     = "  /gm scanlog     \226\128\148 Dump raw bank log (open guild bank first)"
L["CMD_HELP_HELP"]        = "  /gm help        \226\128\148 Show this help"
L["CMD_UNKNOWN"]          = "Unknown command. Type |cffffd700/gm help|r for a list."
L["DEBUG_OFFICER_ON"]     = "Officer view override: |cff5fba47ON|r"
L["DEBUG_OFFICER_OFF"]    = "Officer view override: |cffcc3333OFF|r"

-- ── Minimap / Broker ─────────────────────────────────────────────────────────
L["MINIMAP_LEFT_CLICK"]   = "|cffaaaaaa Left-click|r to toggle"

-- ── Officer View ─────────────────────────────────────────────────────────────
L["DONATIONS"]            = "DONATIONS"
L["NEW_GOAL"]             = "+ New Goal"
L["EDIT_GOAL"]            = "Edit Goal"
L["DELETE_GOAL"]          = "Delete Goal"
L["DELETE_GOAL_HINT"]     = "This will deactivate the current goal."
L["DELETE_CONFIRM"]       = "|cffd9a400GuildMate:|r Click the X again within 3 seconds to confirm deletion."
L["GOAL_DELETED"]         = "|cff4A90D9GuildMate:|r Goal deleted."
L["SETTINGS"]             = "Settings"
L["TOOLS"]                = "TOOLS"
L["MEMBER_STATUS"]        = "MEMBER STATUS"
L["LOGS"]                 = "Logs"
L["MEMBER_STATUS_TAB"]    = "Member Status"
L["NO_GOAL"]              = "No active donation goal. Click |cffffd700+ New Goal|r to create one."
L["MEMBERS_WITH_ADDON"]   = "%d member%s with addon"
L["SEARCH"]               = "Search:"

-- ── Goal card ────────────────────────────────────────────────────────────────
L["GOAL_PER_MEMBER"]      = "|cffd4af37%s|r per member  \194\183  %s"
L["RANKS_LABEL"]          = "Ranks: %s"
L["RANKS_NONE"]           = "None"
L["DAYS_REMAINING"]       = "%d day%s remaining"
L["MEMBERS_MET_GOAL"]     = "%d / %d members met goal  (%d%%)"
L["COLLECTED_THIS_PERIOD"] = "Collected this period:"
L["WEEKLY"]               = "Weekly"
L["MONTHLY"]              = "Monthly"

-- ── Filters ──────────────────────────────────────────────────────────────────
L["FILTER_UNPAID"]        = "Unpaid"
L["FILTER_PARTIAL"]       = "Partially Paid"
L["FILTER_PAID"]          = "Paid"
L["NO_MEMBERS_MATCH"]     = "No members match the current filter."

-- ── Roster row ───────────────────────────────────────────────────────────────
L["DONATED_TOOLTIP"]      = "Donated: %s / %s  (%d%%)"
L["AHEAD_TOOLTIP"]        = "+%d %s%s ahead"
L["AHEAD_SHORT"]          = "+%d%s"
L["WEEK_SHORT"]           = "wk"
L["MONTH_SHORT"]          = "mo"
L["WEEK_FULL"]            = "week"
L["MONTH_FULL"]           = "month"
L["WHISPER_REMINDER_TIP"] = "Whisper reminder to %s"
L["REMINDER_SENT"]        = "|cff4A90D9GuildMate:|r Reminder sent to %s."
L["WHISPER_TEMPLATE"]     = "[GuildMate] Hi %s! Don't forget the %s guild donation goal of %s. You've donated %s so far (%s remaining)."

-- ── Action bar ───────────────────────────────────────────────────────────────
L["REMIND_INCOMPLETE"]    = "Remind Incomplete (%d)"
L["ANNOUNCE_TO_GUILD"]    = "Announce to Guild"
L["EXPORT_CSV"]           = "Export CSV"
L["EXPORT_TITLE"]         = "|cff4A90D9GuildMate|r \226\128\148 Export CSV"
L["SENT_REMINDERS"]       = "|cff4A90D9GuildMate:|r Sent reminders to %d online member(s)."
L["NO_ACTIVE_GOAL"]       = "No active donation goal set."
L["ANNOUNCE_FORMAT"]      = "[GuildMate] Donation progress (%s): %d / %d members have met the %s goal."
L["GOAL_MET_ANNOUNCE"]    = "[GuildMate] %s has met the %s donation goal of %s!"

-- ── Logs tab ─────────────────────────────────────────────────────────────────
L["DONATION_HISTORY"]     = "DONATION HISTORY"
L["NO_DONATION_RECORDS"]  = "No donation records found."
L["GUILD_DONATION_LOGS"]  = "GUILD DONATION LOGS"
L["NO_GUILD_RECORDS"]     = "No guild donation records found."

-- ── Member View ──────────────────────────────────────────────────────────────
L["YOUR_DONATION_STATUS"] = "YOUR DONATION STATUS"
L["GOAL_HEADLINE"]        = "|cffd4af37%s goal:|r  %s per member"
L["PERIOD_REMAINING"]     = "%s  \194\183  %d day%s remaining"
L["GOAL_MET"]             = "|cff5fba47Goal met!|r  You donated %s"
L["GOAL_MET_AHEAD"]       = "|cff5fba47Goal met!|r  You donated %s  |cff5fba47+%d %s%s ahead|r"
L["DONATED_REMAINING"]    = "%s donated  \194\183  |cffd9a400%s remaining|r  (%d%%)"
L["LAST_DEPOSIT"]         = "Last deposit:  %s"
L["AUTO_TRACK_HINT"]      = "Deposits you make to the guild bank are tracked automatically."
L["NO_GOAL_SET"]          = "No donation goal has been set by an officer yet."
L["GOAL_NOT_APPLICABLE"]  = "The current donation goal does not apply to your rank."
L["GOAL_APPLIES_TO"]      = "Applies to: %s"
L["HISTORY"]              = "HISTORY"
L["NO_HISTORY"]           = "No donation history yet."

-- ── Login reminder ───────────────────────────────────────────────────────────
L["LOGIN_REMINDER"]       = "|cffd9a400Reminder:|r You still need to donate %s to meet the %s goal of %s."

-- ── Goal Editor ──────────────────────────────────────────────────────────────
L["NEW_DONATION_GOAL"]    = "New Donation Goal"
L["EDIT_DONATION_GOAL"]   = "Edit Donation Goal"
L["GOLD_AMOUNT"]          = "Gold Amount per Member"
L["DONATION_PERIOD"]      = "Donation Period"
L["APPLY_TO_RANKS"]       = "Apply To Ranks"
L["STARTS"]               = "Starts"
L["THIS_PERIOD"]          = "This period"
L["NEXT_PERIOD"]          = "Next period"
L["CANCEL"]               = "Cancel"
L["SAVE_GOAL"]            = "Save Goal"
L["ERR_MIN_GOLD"]         = "|cffff4444GuildMate:|r Gold amount must be at least 1g."
L["ERR_NO_RANK"]          = "|cffff4444GuildMate:|r Select at least one target rank."
L["GOAL_SET"]             = "|cff4A90D9GuildMate:|r Goal set \226\128\148 %s per member, %s."

-- ── Settings ─────────────────────────────────────────────────────────────────
L["BACK"]                 = "Back"
L["GOAL_MANAGEMENT"]      = "Goal Management"
L["GOAL_MGMT_DESC"]       = "Ranks that can create, edit and delete donation goals."
L["ANNOUNCE_CHANNEL"]     = "Announce Channel"
L["ANNOUNCE_CHANNEL_DESC"] = "Where to post progress summaries when you click \"Announce to Guild\"."
L["GUILD_CHAT"]           = "Guild Chat"
L["OFFICER_CHAT"]         = "Officer Chat"
L["OFF"]                  = "Off"
L["LOGIN_REMINDER_HEADER"] = "Login Reminder"
L["LOGIN_REMINDER_DESC"]  = "Show a reminder on login if I haven't met the donation goal"
L["GOAL_MET_HEADER"]      = "Goal Met Announcement"
L["GOAL_MET_DESC"]        = "Announce in guild chat when a member meets the donation goal"
L["SETTINGS_AUTO_SAVE"]   = "Settings are saved automatically and persist across sessions."

-- ── Interface Options panel ──────────────────────────────────────────────────
L["OPTIONS_DESC"]         = "|cff4A90D9GuildMate|r helps guild leaders and officers track member donations to the guild bank.\n\n|cffd4af37How it works:|r Officers set a gold donation goal (weekly or monthly) for selected ranks. When any guild member opens the guild bank, the addon reads the last 25 money transactions and records deposits automatically. Totals sync across all guild members who have the addon installed.\n\nOfficers see the full roster with colour-coded donation status, and can send reminders or announcements. Members see their own progress and history.\n\nUse |cffffd700/gm|r to open the main window, or click the minimap button."
L["OPEN_GUILDMATE"]       = "Open GuildMate"
