# Roadmap

## Done
- v0.1 Army census: members, online, leaders, zones, world map markers, Discord export, bug capture
- v0.2 Tabard Inspection: patrol auto-inspect, manual marks (player and guild), Discord export
- v0.3 The Realm: King -> Lords -> Captains -> ranks tree, leader/officer offline days, inactive 7/30d,
  level race, recruiting (free slots); layers named after the highest ranked member; guildmates on map
  and minimap; royal decrees (Call to Arms / Muster) with raid warning and map marker; button in
  Blizzard's Guild window that docks the Olympus window next to it; realm-themed texts
- Later versions up to v1.0.1: see the [GitHub releases](https://github.com/dnl-gentile/olympus-addon/releases)
- v1.1.0 The Fernmelder release: the LFG board (`/oly lfg`), the King's week with sign-ups (`/oly week`),
  a crafters' board and loot notes, a sound switch per alert, census search and marked rows, the
  first-open privacy page, the inactive list and mentors, net-off, block terms, alt links, the key
  rotation, a pinned line, the treasury's extras and the weekly dues; Spanish, French and German
- v1.1.1 The Chat tab: the [Olympus], [Captains] and [Lords] chats in the Olympus window, with search,
  a box to write in and the settings behind the gear (mute, chat window, an Olympus tab in the game chat)
- v1.1.2 Right-click a player for their Olympus version (Ask to update, Tell them about Olympus); the
  answer bank; a ? on every page; bug reports on request; Chattynator tabs; marks on Olympus lines in
  the game's chat
- v1.1.3 Ordinary clicks never start a restricted `/who`: census and player searches only from their own
  controls
- v1.1.4 Crafters as its own tab; the side tabs keep one order when they run out of room
- v1.1.5 Three elite borders (the King gold, the High Council silver, guild masters bronze) and
  their marks in the game's own chat (`/oly chatmarks`), none on Olympus lines; councillors'
  tooltips; a guild the High Council removed is no Olympus guild, with an appeal through the signed
  approved list; `<OLYMPIANS>` approved; the version letters (`/oly letters`); Blizzard's player
  menus untouched in gamepad mode (#56); restricted secret values ignored safely; the Chat tab's
  second help "i" gone (the window's own, left of the X, is the one there); the gamepad gate (every
  way into the game's own UI listed and asked of one gate: with the gamepad UI no typed command, no
  button in the guild windows, nothing on the world map; a switch steps back and says what a
  `/reload` completes); the nameplate marks no longer hook a plate's own layout (Lua errors)

## Next (after the base is proven in game)
- ~~Guild leader offline for X days~~ (v0.3)
- ~~**Guild leader offline for X days (alerts)** - `GetGuildRosterLastOnline(i)` gives years/months/days/hours for
  our own guild; add `leaderLastSeen` to the report so every guild's leader age shows up. Alert above N days.~~
  (1.1: one line when a Lord crosses `/oly warndays`.)
- ~~**Inactive players** - same API: count members offline > 7/14/30 days per guild; list for officers to kick.~~
  (1.1: your own guild's list by name, one removal per click.)
- ~~**Officers and org chart** - `GuildControlGetNumRanks` / `GuildControlGetRankName` + rankIndex per member:
  rank tree per guild (Leader -> Officers -> ranks -> counts), who is online per rank, officers in the report.~~
  (v0.3: the Realm's King, Lords and Captains and each guild's ranks with their counts; later each guild's
  members online.)
- ~~**Dues** (was tax collection) - Classic has no guild bank: track gold received through mail and trade from
  guild members (MAIL_INBOX_UPDATE / TRADE_* events), ledger per member, "who has not paid this week".~~
  (1.1: one fixed amount a week the King sets, counted from the treasury's books, never public.)
- ~~**Layers** - zoneUID from NPC GUIDs (`/oly layer` is the probe); sample from addon users per layer.~~
  (Each layer named after its highest ranked member since v0.3, announced by officers and a stable 1 in 8
  sample; the layer hop since v0.8.1.)
- ~~**Share inspections** between officers over OlympusNet so several inspectors build one list.~~
  (1.1: among your guild's officers over guild addon messages, `/oly patrolshare`, off until you say yes.)
- ~~**Verification badge** when two reporters of the same guild agree~~ (1.1: the census marks a row whose
  senders disagree, and one a single sender stands behind).
- ~~**Channels view** - per-tier history (`Channels.History`, `CHAT_CHANGED`) in the window.~~
  (1.1.1: the Chat tab.)
