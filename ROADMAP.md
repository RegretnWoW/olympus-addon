# Roadmap

## Done
- v0.1 Army census: members, online, leaders, zones, world map markers, Discord export, bug capture
- v0.2 Tabard Inspection: patrol auto-inspect, manual marks (player and guild), Discord export
- v0.3 The Realm: King -> Lords -> Captains -> ranks tree, leader/officer offline days, inactive 7/30d,
  level race, recruiting (free slots); layers named after the highest ranked member; guildmates on map
  and minimap; royal decrees (Call to Arms / Muster) with raid warning and map marker; button in
  Blizzard's Guild window that docks the Olympus window next to it; realm-themed texts

## Next (after the base is proven in game)
- ~~Guild leader offline for X days~~ (v0.3)
- ~~**Guild leader offline for X days (alerts)** - `GetGuildRosterLastOnline(i)` gives years/months/days/hours for
  our own guild; add `leaderLastSeen` to the report so every guild's leader age shows up. Alert above N days.~~
  (1.1: one line when a Lord crosses `/oly warndays`.)
- ~~**Inactive players** - same API: count members offline > 7/14/30 days per guild; list for officers to kick.~~
  (1.1: your own guild's list by name, one removal per click.)
- **Officers and org chart** - `GuildControlGetNumRanks` / `GuildControlGetRankName` + rankIndex per member:
  rank tree per guild (Leader -> Officers -> ranks -> counts), who is online per rank, officers in the report.
- **Tax collection** - Classic has no guild bank: track gold received through mail and trade from guild
  members (MAIL_INBOX_UPDATE / TRADE_* events), ledger per member, "who has not paid this week".
- **Layers** - zoneUID from NPC GUIDs (`/oly layer` is the probe); sample from addon users per layer.
- **Share inspections** between officers over OlympusNet so several inspectors build one list.
- ~~**Verification badge** when two reporters of the same guild agree~~ (1.1: the census marks a row whose
  senders disagree, and one a single sender stands behind).
- **Channels view** - per-tier history (`Channels.History`, `CHAT_CHANGED`) in the window.
