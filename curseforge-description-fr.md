# GuildMate

Un outil de suivi des donations à la banque de guilde pour WoW TBC Anniversary.

La banque de guilde de WoW ne garde en mémoire que les 25 dernières transactions d'or. Après ça, les dépôts disparaissent comme s'ils n'avaient jamais existé. GuildMate enregistre chaque transaction dès qu'un membre de la guilde ouvre la banque, puis partage les données à toute la guilde en arrière-plan. Cette fois, votre historique de donations reste.

Encore en développement, mais ça fonctionne et c'est déjà utile.

## Fonctionnalités

- **Objectifs de donation.** Les officiers définissent des objectifs d'or hebdomadaires ou mensuels par rang, diffusés automatiquement à la guilde.
- **Suivi automatique.** Lit et enregistre les dépôts à chaque ouverture de la banque, avec dédoublonnage intégré.
- **Synchronisation entre membres.** Les données se propagent par messagerie addon. Plus il y a de membres qui l'installent, moins il y a de dépôts manqués. Pas de tableur, pas de bot Discord.
- **Tableau de bord officier.** Liste des membres colorée par statut (rouge/jaune/vert), recherche, filtres, barres de progression, rappels par chuchotement en un clic, annonces de guilde, export CSV.
- **Vue membre.** Carte de progression personnelle, jours restants, historique des 6 dernières périodes, rappel optionnel à la connexion.
- **Bouton minimap.** Accès rapide via LibDBIcon.

## Commandes

- `/gm` ou `/guildmate` pour ouvrir/fermer la fenêtre principale
- `/gm help` pour la liste complète

## Bon à savoir

- Conçu pour TBC Anniversary (Interface 20505). Pas retail, pas Classic moderne.
- Utilise les bibliothèques Ace3 (AceAddon, AceEvent, AceConsole, AceComm, AceGUI, AceConfig)
- Toutes les données sont stockées dans les SavedVariables, rien ne quitte le client de jeu

## Statut

Version 0.1.0. Le suivi des donations fonctionne et a été testé en jeu. D'autres outils de gestion de guilde sont prévus. Retours et signalements de bugs bienvenus.
