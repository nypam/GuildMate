local L = LibStub("AceLocale-3.0"):NewLocale("GuildMate", "frFR")
if not L then return end

-- ── General ──────────────────────────────────────────────────────────────────
L["ADDON_NAME"]           = "GuildMate"
L["ADDON_TITLE"]          = "|cff4A90D9Guild|rMate"
L["VERSION_LINE"]         = "GuildMate v%s  par |cffffffffNypp|r |TInterface\\Icons\\INV_Drink_04:14|t"
L["TAGLINE"]              = "|cffaaaaaaUn addon |cffd4af37indispensable|r"

-- ── Slash commands ───────────────────────────────────────────────────────────
L["CMD_HELP_HEADER"]      = "|cff4A90D9GuildMate|r commandes :"
L["CMD_HELP_TOGGLE"]      = "  /gm             \226\128\148 Afficher/masquer la fen\195\170tre"
L["CMD_HELP_DONATIONS"]   = "  /gm donations   \226\128\148 Ouvrir le panneau Donations"
L["CMD_HELP_DEBUG"]        = "  /gm debug       \226\128\148 Basculer la vue officier (test)"
L["CMD_HELP_SCANLOG"]     = "  /gm scanlog     \226\128\148 Exporter le journal brut (ouvrir la banque d'abord)"
L["CMD_HELP_HELP"]        = "  /gm help        \226\128\148 Afficher cette aide"
L["CMD_UNKNOWN"]          = "Commande inconnue. Tapez |cffffd700/gm help|r pour la liste."
L["DEBUG_OFFICER_ON"]     = "Vue officier forc\195\169e : |cff5fba47ACTIV\195\137E|r"
L["DEBUG_OFFICER_OFF"]    = "Vue officier forc\195\169e : |cffcc3333D\195\137SACTIV\195\137E|r"

-- ── Minimap / Broker ─────────────────────────────────────────────────────────
L["MINIMAP_LEFT_CLICK"]   = "|cffaaaaaa Clic gauche|r pour afficher"

-- ── Officer View ─────────────────────────────────────────────────────────────
L["DONATIONS"]            = "DONATIONS"
L["NEW_GOAL"]             = "+ Nouvel objectif"
L["EDIT_GOAL"]            = "Modifier"
L["DELETE_GOAL"]          = "Supprimer l'objectif"
L["DELETE_GOAL_HINT"]     = "Cela d\195\169sactivera l'objectif en cours."
L["DELETE_CONFIRM"]       = "|cffd9a400GuildMate :|r Cliquez \195\160 nouveau dans 3 secondes pour confirmer."
L["GOAL_DELETED"]         = "|cff4A90D9GuildMate :|r Objectif supprim\195\169."
L["SETTINGS"]             = "Param\195\168tres"
L["TOOLS"]                = "OUTILS"
L["MEMBER_STATUS"]        = "\195\137TAT DES MEMBRES"
L["LOGS"]                 = "Journal"
L["MEMBER_STATUS_TAB"]    = "\195\137tat des membres"
L["NO_GOAL"]              = "Aucun objectif actif. Cliquez |cffffd700+ Nouvel objectif|r pour en cr\195\169er un."
L["MEMBERS_WITH_ADDON"]   = "%d membre%s avec l'addon"
L["SEARCH"]               = "Recherche :"

-- ── Goal card ────────────────────────────────────────────────────────────────
L["GOAL_PER_MEMBER"]      = "|cffd4af37%s|r par membre  \194\183  %s"
L["RANKS_LABEL"]          = "Rangs : %s"
L["RANKS_NONE"]           = "Aucun"
L["DAYS_REMAINING"]       = "%d jour%s restant%s"
L["MEMBERS_MET_GOAL"]     = "%d / %d membres ont atteint l'objectif  (%d%%)"
L["COLLECTED_THIS_PERIOD"] = "Collect\195\169 cette p\195\169riode :"
L["WEEKLY"]               = "Hebdomadaire"
L["MONTHLY"]              = "Mensuel"

-- ── Filters ──────────────────────────────────────────────────────────────────
L["FILTER_UNPAID"]        = "Non pay\195\169"
L["FILTER_PARTIAL"]       = "Partiellement pay\195\169"
L["FILTER_PAID"]          = "Pay\195\169"
L["NO_MEMBERS_MATCH"]     = "Aucun membre ne correspond au filtre."

-- ── Roster row ───────────────────────────────────────────────────────────────
L["DONATED_TOOLTIP"]      = "Donn\195\169 : %s / %s  (%d%%)"
L["AHEAD_TOOLTIP"]        = "+%d %s%s d'avance"
L["AHEAD_SHORT"]          = "+%d%s"
L["WEEK_SHORT"]           = "sem"
L["MONTH_SHORT"]          = "mo"
L["WEEK_FULL"]            = "semaine"
L["MONTH_FULL"]           = "mois"
L["WHISPER_REMINDER_TIP"] = "Envoyer un rappel \195\160 %s"
L["REMINDER_SENT"]        = "|cff4A90D9GuildMate :|r Rappel envoy\195\169 \195\160 %s."
L["WHISPER_TEMPLATE"]     = "[GuildMate] Salut %s ! N'oublie pas l'objectif %s de %s pour la guilde. Tu as donn\195\169 %s jusqu'ici (%s restant)."

-- ── Action bar ───────────────────────────────────────────────────────────────
L["REMIND_INCOMPLETE"]    = "Rappeler (%d)"
L["ANNOUNCE_TO_GUILD"]    = "Annoncer \195\160 la guilde"
L["EXPORT_CSV"]           = "Exporter CSV"
L["EXPORT_TITLE"]         = "|cff4A90D9GuildMate|r \226\128\148 Exporter CSV"
L["SENT_REMINDERS"]       = "|cff4A90D9GuildMate :|r Rappels envoy\195\169s \195\160 %d membre(s) en ligne."
L["NO_ACTIVE_GOAL"]       = "Aucun objectif de donation actif."
L["ANNOUNCE_FORMAT"]      = "[GuildMate] Progression des donations (%s) : %d / %d membres ont atteint l'objectif de %s."
L["GOAL_MET_ANNOUNCE"]    = "[GuildMate] %s a atteint l'objectif %s de %s !"

-- ── Logs tab ─────────────────────────────────────────────────────────────────
L["DONATION_HISTORY"]     = "HISTORIQUE DES DONATIONS"
L["NO_DONATION_RECORDS"]  = "Aucun enregistrement trouv\195\169."
L["GUILD_DONATION_LOGS"]  = "JOURNAL DES DONATIONS DE GUILDE"
L["NO_GUILD_RECORDS"]     = "Aucun enregistrement de guilde trouv\195\169."

-- ── Member View ──────────────────────────────────────────────────────────────
L["YOUR_DONATION_STATUS"] = "VOTRE STATUT DE DONATION"
L["GOAL_HEADLINE"]        = "|cffd4af37Objectif %s :|r  %s par membre"
L["PERIOD_REMAINING"]     = "%s  \194\183  %d jour%s restant%s"
L["GOAL_MET"]             = "|cff5fba47Objectif atteint !|r  Vous avez donn\195\169 %s"
L["GOAL_MET_AHEAD"]       = "|cff5fba47Objectif atteint !|r  Vous avez donn\195\169 %s  |cff5fba47+%d %s%s d'avance|r"
L["DONATED_REMAINING"]    = "%s donn\195\169  \194\183  |cffd9a400%s restant|r  (%d%%)"
L["LAST_DEPOSIT"]         = "Dernier d\195\169p\195\180t :  %s"
L["AUTO_TRACK_HINT"]      = "Vos d\195\169p\195\180ts \195\160 la banque de guilde sont suivis automatiquement."
L["NO_GOAL_SET"]          = "Aucun objectif n'a \195\169t\195\169 d\195\169fini par un officier."
L["HISTORY"]              = "HISTORIQUE"
L["NO_HISTORY"]           = "Pas encore d'historique."

-- ── Login reminder ───────────────────────────────────────────────────────────
L["LOGIN_REMINDER"]       = "|cffd9a400Rappel :|r Il vous reste %s \195\160 donner pour atteindre l'objectif %s de %s."

-- ── Goal Editor ──────────────────────────────────────────────────────────────
L["NEW_DONATION_GOAL"]    = "Nouvel objectif de donation"
L["EDIT_DONATION_GOAL"]   = "Modifier l'objectif"
L["GOLD_AMOUNT"]          = "Montant en or par membre"
L["DONATION_PERIOD"]      = "P\195\169riode de donation"
L["APPLY_TO_RANKS"]       = "Appliquer aux rangs"
L["STARTS"]               = "D\195\169but"
L["THIS_PERIOD"]          = "Cette p\195\169riode"
L["NEXT_PERIOD"]          = "Prochaine p\195\169riode"
L["CANCEL"]               = "Annuler"
L["SAVE_GOAL"]            = "Sauvegarder"
L["ERR_MIN_GOLD"]         = "|cffff4444GuildMate :|r Le montant doit \195\170tre d'au moins 1g."
L["ERR_NO_RANK"]          = "|cffff4444GuildMate :|r S\195\169lectionnez au moins un rang."
L["GOAL_SET"]             = "|cff4A90D9GuildMate :|r Objectif d\195\169fini \226\128\148 %s par membre, %s."

-- ── Settings ─────────────────────────────────────────────────────────────────
L["BACK"]                 = "Retour"
L["GOAL_MANAGEMENT"]      = "Gestion des objectifs"
L["GOAL_MGMT_DESC"]       = "Rangs pouvant cr\195\169er, modifier et supprimer les objectifs."
L["ANNOUNCE_CHANNEL"]     = "Canal d'annonce"
L["ANNOUNCE_CHANNEL_DESC"] = "O\195\185 publier le r\195\169sum\195\169 lorsque vous cliquez \"Annoncer \195\160 la guilde\"."
L["GUILD_CHAT"]           = "Chat guilde"
L["OFFICER_CHAT"]         = "Chat officier"
L["OFF"]                  = "D\195\169sactiv\195\169"
L["LOGIN_REMINDER_HEADER"] = "Rappel \195\160 la connexion"
L["LOGIN_REMINDER_DESC"]  = "Afficher un rappel \195\160 la connexion si je n'ai pas atteint l'objectif"
L["GOAL_MET_HEADER"]      = "Annonce d'objectif atteint"
L["GOAL_MET_DESC"]        = "Annoncer dans le chat de guilde quand un membre atteint l'objectif"
L["SETTINGS_AUTO_SAVE"]   = "Les param\195\168tres sont sauvegard\195\169s automatiquement."

-- ── Interface Options panel ──────────────────────────────────────────────────
L["OPTIONS_DESC"]         = "|cff4A90D9GuildMate|r aide les chefs et officiers de guilde \195\160 suivre les donations des membres \195\160 la banque de guilde.\n\n|cffd4af37Comment \195\167a marche :|r Les officiers d\195\169finissent un objectif de donation en or (hebdomadaire ou mensuel) pour les rangs s\195\169lectionn\195\169s. Quand un membre ouvre la banque de guilde, l'addon lit les 25 derni\195\168res transactions et enregistre les d\195\169p\195\180ts automatiquement. Les totaux se synchronisent entre tous les membres qui ont l'addon.\n\nLes officiers voient la liste compl\195\168te avec un statut color\195\169, et peuvent envoyer des rappels ou des annonces. Les membres voient leur propre progression et historique.\n\nUtilisez |cffffd700/gm|r pour ouvrir la fen\195\170tre principale, ou cliquez sur le bouton de la minimap."
L["OPEN_GUILDMATE"]       = "Ouvrir GuildMate"
