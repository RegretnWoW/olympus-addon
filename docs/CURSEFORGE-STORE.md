# Olympus

**The whole Olympus army in one window, inside World of Warcraft: Forever.**

Olympus is Asmongold's guild for *World of Warcraft: Forever*: Alliance, PvP ruleset, a
place to find dungeon groups, organize raids, share class knowledge and build the guild
together. It grew past **10,000 members during the beta**. A WoW guild caps at 1,000
members, so Olympus is really a *realm* of many Olympus guilds. In game each player
only ever sees the roster of their own guild. Nobody could tell how many Olympus guilds
exist, who leads them, or where the army is.

This addon answers exactly that. It adds up every Olympus guild live, in a window that
looks like Blizzard's Guild window and docks right next to it.

![The whole army at a glance: every Olympus guild, live](https://raw.githubusercontent.com/dnl-gentile/olympus-addon/main/docs/olympus-1.jpg)

![Where the army stands: soldiers per zone on the world map](https://raw.githubusercontent.com/dnl-gentile/olympus-addon/main/docs/olympus-5.jpg)

> **Status:** built for WoW: Forever and running on the Forever beta (1.60.1), where the
> census already adds up reports from many Olympus guilds. Also tested on Classic Era (1.15)
> and Anniversary (2.5). Please report anything that looks wrong (`/oly bug`).

---

**Horde too.** Olympus guilds on the Horde side use the same addon. The factions can't see
each other's guilds, so each one gets its own census, channels, decrees and untabarded list: the
addon picks yours from your character. On the Horde, the Crown is every Horde Olympus guild
master and the officers of the Horde guild named exactly "Olympus", if there is one.

## Recent versions

- **1.1.6**: The Watch (each guild's moderation desk, the Tabards in it); crafting requests on the Crafters
  tab; the King's arrow on the minimap; Vox Populi's history and a guild master's own questions; the
  Guild treasuries in one list with one search; Bones between players for points, at a tavern or at a
  camp; no arbiters without bets (duels and Bones between their two players); duel points that
  consider levels; Find a player by level, distance and game
- **1.1.5**: Three elite borders (the King gold, the High Council silver, guild masters bronze) and
  their marks in the game's own chat (`/oly chatmarks`), none on Olympus lines; councillors'
  tooltips; a guild the High Council removed is no Olympus guild, with an appeal through the signed
  approved list; `<OLYMPIANS>` approved; the version letters (`/oly letters`); Blizzard's player
  menus untouched in gamepad mode ([#56](https://github.com/dnl-gentile/olympus-addon/issues/56)); restricted secret values ignored safely; the Chat tab's
  second help "i" gone (the window's own, left of the X, is the one there); the gamepad gate (every
  way into the game's own UI listed and asked of one gate: with the gamepad UI no typed command, no
  button in the guild windows, nothing on the world map; a switch steps back and says what a
  `/reload` completes); the nameplate marks no longer hook a plate's own layout (Lua errors)
- **1.1.4**: Crafters as its own tab; the side tabs keep one order when they run out of room

Every version's notes are in the [GitHub releases](https://github.com/dnl-gentile/olympus-addon/releases). This page is the short one for CurseForge: the [README](https://github.com/dnl-gentile/olympus-addon#olympus) has every section in full.

## Who can use it

**Only members of a guild with "Olympus" in its name**, however it was spelled: OLYMPVS the Roman way, Olimpus, Olmps, Olympuz, Olympos, Olimpo and other misspellings count too (Olympia or Olympic do not), and a guild against Olympus ("ANTI OLYMPUS", "Olympus Haters") does not. The check is fixed in the code and
cannot be switched off with a command. Outside an Olympus guild the addon joins no channel
and hears nothing of the army, but for the author's signed list below, over its own guild.
The only thing it offers there is the **Join Olympus**
screen described below, and its own few addon whispers are the only ones it sends or hears
there (1.1: which guild to ask, the answer, and your request, each to or from the one member
concerned).

**Approved guilds (1.1).** A guild of Asmon's Olympus whose name the rule leaves out (it leaves
Olympian and Olympia out on purpose) counts as an Olympus guild once the author names it in his
signed list: the same list, signed with the same key on his own computer, that names the High
Council and the King's Steward, for one faction and realm group. No census vote counts, and nobody
else can add one. A few ship with the addon itself, so their members have nothing to paste: since
1.1, the Alliance's `<OLYMPIAN>`, and since 1.1.5 its `<OLYMPIANS>` too (only a new version takes one of those off). Its members' addons, no Olympus members
until they hold that list, take it over their own guild alone (the list only: nothing else is
read, and they send nothing). The first of them pastes it with `/oly approved paste`, or a click
on the Join Olympus screen's last line (the author
or a High Councillor hands out the signed text; it is checked like any list, so it can't be forged
or changed), and his addon passes it to his guild every 5 minutes. `/oly approved` lists the
approved guilds of your faction. A newer signed list without a guild ends it on every client.

**Removed guilds (1.1.5).** A guild the High Council removed from Olympus is no Olympus guild,
whatever its name: its census, chats and marks are gone and its members' addon shows the Join
Olympus screen. Its way back is an appeal to the council: once the author names it in his signed
approved list, it counts again, with no new version. Until a player updates, the council's
[net-off](#net-off-11-the-moderators-hide-a-character-or-take-a-guild-off-the-network) word takes
such a guild off the network live.

### Not in Olympus yet?
First it asks the obvious question: *"<Your Guild>? Disband immediately. What are you
doing?"* Then it helps you get in. The **Join Olympus** screen uses the game's own `/who` to
find Olympus members online, groups them by guild, and whispers one of them a ready-made
request that you can edit ("Hi! I'd love to join Olympus. Does <Olympus II> have room for
one more?"). No answer? **Try someone else** picks a member you have not asked yet. Replies
are highlighted. It is rate limited, so nobody gets spammed.

**Where to go** (1.1): a search also asks one member's addon (an addon whisper, not a chat line)
where recruits should go, and its census answers: the guild the King opened **the gates** of
first, then the guilds with the **most free slots**, and a couple of their Lords and Captains
online (never the King). It names only what the census confirms: guilds two members' reports
agree on, and Lords and Captains two reports name. The screen lists them in that order, each
once `/who` found one of its members (the gates once a second member's answer agrees: one more
is asked), the guilds found with `/who` too, and a click asks one of those officers that `/who`
found in that guild, or another member it found there. Just before, their addon is asked
whether they take recruit whispers (again if it never answered): a member who set **do not
contact** (`/oly nocontact on`) is never offered, however many recruits ask him, and the
question closes before anything is sent. It stays **one whisper per click**, in your
own words (no dues line), 20 seconds apart. With it goes your request to the same member, so an
officer's addon shows it with **Invite** and **Decline** instead of a raw whisper. Members on
versions before 1.1 just get the whisper, as before.

## What it does

### Census: the army at a glance
- Every Olympus guild in one list: **Guild · Members · Online · Lord**. Columns sort by
  clicking, like the Guild window.
- **Total soldiers** and **online now** across the whole realm.
- **Where the army stands**: top zones ("Stormwind City 742") and totals per continent
  (Eastern Kingdoms, Kalimdor), counted by the guilds whose census comes from a member who
  shares their zone (see Privacy, below).
- Hover a guild: members, online, free slots, average level, inactive members, classes online, top zones.
- **Right after login** (1.1) the header, the Census and the Realm say *Rebuilding the census
  after login: N guilds heard so far* for about 3 minutes, while every guild's reporter answers.
  The beta often loads an empty save: the army is not gone, and no `/reload` is needed. The line
  only waits: it asks nothing (no `/who`) and opens nothing.
- **An update line** (1.1): when the author's own addon says on the Olympus channel that a newer
  version than yours is out (he marks it once CurseForge lists it, never a build he is still
  trying), a line at the foot of the Census, one line in chat once a session and `/oly status`
  say so. It is yours alone: nothing is sent and nobody is whispered.
- **Marked rows** (1.1): a warning mark on a guild whose senders disagree (on its Lord or
  Captains, or on its size, by more than 5 members or 5% plus the 20 a minute a guild may gain or
  lose between their two reports), a question mark on one that a single
  sender stands behind. Its tooltip says which and who: check before calling a muster or opening
  the gates on it (the gates ask again, with the reason). A marked row can still be right, and
  the mark changes nothing that counts. Your own guild (your roster) is never marked.
- **Asking to join** (1.1): a recruit who asked you from the Join Olympus screen shows on top of
  the Census, with their whisper. An officer (the game's guild invite permission) answers with
  **Invite** (the game's own guild invite) or **Decline** (one whisper pointing to the gates'
  guild while the King's gates are open, else naming your guild alone: never a guild the census
  lists for its room, which two made-up characters could report), one click each; anyone else
  can point them to an officer online. **Dismiss** sends nothing. In the Realm's Recruiting, one
  click (or `/oly nocontact`) sets your **do not contact** flag.
- **Search the census** (1.1): a guild, a Lord, a Captain, a player of a guild's top five or one
  seen online (the player shows under the guild's row), or a zone ("Stormwind": its soldiers
  and its guilds, most first). Type **recruiting** (or `free 50`) for every guild with room,
  most free slots first and the King's gates on top.
- **Tonight on this client** (1.1): under the list, the most soldiers your addon saw online at
  once tonight and when, and (in its tooltip, and next to a zone you search) how each zone
  filled or emptied since. Counted by your own addon once a minute from the reports it
  already holds, starting about 3 minutes after login once the census is rebuilt: another
  player's client counts its own evening, and nothing is sent.

### The Realm: the hierarchy
- **War Room**: members read their guild's records; its officers and verified War roles manage them.
  No cross-guild writes. Empty lists explain what is missing; role previews cannot act.
- The **King**, then every guild's **Lord** (guild master) and **Captains** (the officer rank
  right below the guild master).
  Each shows level, class and online or *offline 3d*. Long absences show in red
  (`/oly warndays <days>`, 3 by default). **A Lord away** (1.1): when a Lord crosses that, one
  chat line, once per absence: to his own guild's officers from their roster, and to the King,
  his Steward and his Hands for every guild's Lord, by the census's word (a guild that stopped
  reporting included, counted from its last report even when that showed him online). Never a
  popup, and nothing is done to anyone.
- The **Treasurer of Olympus** (Pyralis Ashandar, chosen by Asmongold's chat) right under
  the King, with a gold coin next to his name wherever he shows, his tooltip and his lines in
  the Olympus chats included. Only
  that exact character of the guild OLYMPUS gets it: look-alikes don't.
- **Members online** under each guild: your own guild's from your roster, any other's from
  `/who`. Opening a guild searches `/who` for that guild alone (up to 50 of its players).
  Click a name to whisper, invite or `/who` them.
- The **ranks** of each guild with how many members hold them.
- **Inactive members**: offline 7+ and 30+ days, per guild. Your own guild's line (or
  `/oly inactive`) opens the list by name (1.1): members offline 7, 14 or 30 days and more,
  with rank, class, level and last online, from your own roster, longest away first. A rank
  that may remove members (as in the game's Guild window: ranks below yours) removes **one
  person per click**, after a question that shows their rank and days away, a few seconds
  apart. There is no kick-all, and nothing is sent.
- **Mentors** (1.1): a Lord opens **Recruits and their mentors** on that page (or `/oly recruits`):
  his guild's lowest rank and whoever joined since he logged in. He clicks a recruit who is
  online, then one of his Captains, and says yes: **one whisper to each** from that click, the
  Captain told who to look after, the recruit told who to ask. The pair shows on his list (his
  client's alone); nothing goes on the channel.
- **Centurions and correspondents** (1.1.5): a guild master of an Olympus guild (not the King's)
  has a tab of his own in the Throne's place, **Guild** (or `/oly nominees`), laid out as the
  King's Hands page: **+ Name a centurion** (his target, or a name he types), his list (a click
  takes a title back, asked first), and a line per High Council department to name its
  correspondent. Up to 10
  centurions and one correspondent per department (6 at most), members of his own guild only: the
  addon refuses an 11th centurion, a second correspondent for a department, one name twice and
  anyone outside his roster, and says why. Each wears Max's bronze border without wings, and the
  bronze mark on nameplates and in the game's chat, only while the server gives them that guild.
  His own client sends the list on the Olympus channel; every addon takes it from that guild's
  master alone (proven as for his bronze wings: your roster for your own guild, two census senders
  for another), keeps it 6 hours after he stops repeating it, and drops it at once when he is no
  longer guild master. `/oly nominees centurion <name>`, `/oly nominees correspondent <department
  number> <name>` and `/oly nominees remove <name>` do the same from the chat.
  A confirmed correspondent also sees a **Guild** workspace for their own department. War and
  Justice duties apply only to their own guild, checked against its fresh roster and its current
  guild master's nomination; neither title grants federal powers. Artisanry and Heritage link to
  the existing boards and clearly say their dedicated workflows are not available yet. A Church
  contact still needs a Church appointment for its private room and recruitment numbers.
- **Level race**: the highest level players of the realm.
- **Recruiting**: the guilds that still have free slots, so new players go where there is room
  (the five with the most, then every one on a click, 1.1).
  When the King opens **the gates** of a guild, it tops the list: send new recruits there.
- **Layers** of your zone, named after the highest ranked Olympus member on each one
  ("Asmongold's layer"), with how many members are there.

### Layer hop: join the King's layer without begging in chat
While Asmongold is online, the top of the Census and the Realm shows **"Ask invite for Asmon
Layer"** with his crown. One click (or `/oly hop`) and the addon does the asking:

- You must already be in his zone (a layer is read per zone): if you are not, the line says
  where he is and nothing is asked.
- It asks the Olympus players on his layer who can invite (alone, or leading a group with a
  free seat). Only a handful answer, picked at random on each player's side, so a crowd of
  askers is spread over many players instead of flooding one.
- It picks one of them, favouring players outside a group and with fewer recent invites. They
  get **"X wants to join your layer"** with **Invite**, **Not now** and **Always invite**. No
  answer or a no, and the next one is asked. **Always invite** invites the next ones without
  the window while that player is alone or with only the addon's hop guests; clicked while they
  lead a party or raid of their own, it also covers that group until it ends (1.1.5, GitHub
  issue #50: the window came back with every request there). That group's permission is never
  saved: a later group asks first again, after a `/reload` the window asks once more, and
  `/oly layerauto off` ends it at once.
- The invite is accepted for you when that player is one the addon can vouch for (a member of
  your own guild, or a Lord or Captain the census confirms); anyone else's, and every invite
  while Blizzard's gamepad UI is on, waits for your click in the game's own invite window. The
  game moves you to the layer, and the addon takes you out of the group as soon as it sees the
  move (or offers a **Leave group** button if it can't tell).

Players alone on the King's layer are asked once per login: **"Asmon is online and you are on
his layer. May the addon invite the players who want to join, and take them out of the group
once they are there?"** with **For Olympus!**, **Can't right now** and **Invite manually**, and
a **Don't ask me again** box. With For Olympus! the addon invites on its own (only while you
are alone or with its guests, never into a group of your friends) and lets each guest go after
90 seconds: the guest's addon leaves the group, since only a click may remove someone.

Any other layer in the Realm tab's layer list works the same way: click it. Everyone who
shares their zone and layer (`/oly location on`) and said yes to layer help (1.1: the
first-open page, or `/oly layerhelp on`) helps: a player who keeps them private is never asked, since an offer would tell the asker where they are. `/oly layerhelp
off` stops the requests, `/oly layerhelp on` also forgets the answer to the King's layer
window, `/oly layerauto on` invites them without the window. Helpers must be in the same zone
as the layer they are on, and the King himself is never asked.

Layers are known from the members who share their zone and layer (see Privacy, below):
the more share, the better hopping works. Asking works either way, and says on the channel
the zone you are in and the layer you want. If the King's own layer announcement has not
arrived yet, clicking his hop line sends one discovery question on the Olympus channel while his crown is visible.
Clients that can see his exact nameplate keep that fact private until the question; eligible
helpers answer the asker alone, and two independent answers must agree before the ordinary
layer-hop ask begins. A lone or conflicting answer moves nobody. Turning location sharing,
layer help or the crown off cancels a queued answer and privately withdraws one already sent
while that discovery question remains active.

The King's layer is known only while his crown
shows on the map (**Show me on the map** on his Throne, off by default): his addon sends it
the moment he shows the crown and repeats it every minute while it shows. With his crown
hidden (or while he is in a dungeon, where it hides) the line says so instead of "try again in
a minute". A layer is a copy of a zone inside one realm: when the census places him on another
realm than yours, the line says that, even if his layer reaches your channel. The `king:` line
of `/oly status` (and of `/oly bug`) says what your addon knows of him: online and how sure,
his realm, his layer and his crown, and how long ago each was heard.

### Person details
Click any Lord, Captain, racer or inspected player. Their profile opens in the normal Olympus
window, at that window's size, with the census facts Olympus already knows: level, class, zone,
rank and status. **Back** returns to the same list or Realm subpage; **Whisper**, **Invite** and
**Who** stay on the profile. Offline players cannot be whispered or invited from it. This is
separate from the Blood Arena companion's player profile and opening it sends no new query.
`/oly profile Name` (or `Name-Realm`) opens a player's profile by name, yours with no name. A
profile opened from another one is one more step: **Back** goes to the profile before it, then
to the list.
Any soldier can reach the Lord of another Olympus guild in two clicks.

A High Councillor's tooltip (1.1.5) says so too: their mark and own icon after their name, then
**High Councillor**, their department and their title, for whoever may see the council (the
same as their card); none on the King's screen while the council's names are hidden.

### Right-click a player (1.1.2)
Right-click a player (the target frame, party and raid frames, a name in chat, the Who list, the
friends list, the guild roster) and the game's menu gets an **Olympus** part at the bottom:
- **Their version**: "Olympus 1.1.1 (out of date)", "up to date" or "not seen yet", and under it
  where it came from and when. Guildmates show up by themselves (their addon says hello to your
  guild), and so does a known version on the person card. Opening the menu sends nothing.
- **Check version**: for anyone else, one tiny addon whisper that their addon answers with its
  version and nothing else (a player once every 2 minutes, 6 a minute). Only 1.1.2 and newer
  answer, so no answer in 10 seconds can mean no Olympus, an older one, a dungeon or raid, or no
  Olympus guild (outside one the addon sends nothing). The author's check is his roll call to that
  player alone, which every version since 0.9.9 answers, and only after their yes to his roll calls.
- **Ask to update**, when they are behind the newest version your addon knows: first a small
  confirmation asks you before anything is sent. On 1.1.2 or newer their addon shows a compact
  notice with both versions and where to update; **Read update** opens a parchment letter in plain
  language, with reviewed public release notes and the safe next step. An older one can't show the
  notice, so after your confirmation Olympus opens a whisper with the ask for you to send. One ask per player a day, 5 an hour;
  they see one a day at most, **Don't remind me** hides them for 7 days (on the beta, which forgets
  addon data at login, these last until you log out), and a player they block (`/oly block`) or
  ignore, or one the moderators took off, never gets through. The notice never names a version the
  author has not released. The author's pick sends his usual update window, naming the version he
  marked as out (`/oly released`).
- **Tell them about Olympus**, when their addon did not answer: a whisper with a short invite and
  the CurseForge link (to get it, or update an old one) opens in Olympus's own window, for you to
  edit and send yourself. The click sends nothing.
- **Ask for a bug report** (the author alone, on a player running 1.1.2 or newer): their addon
  opens a window of its own, never a game popup, saying the author asks for their Olympus bug
  report, with **See what is sent** (the exact text, the same as `/oly bug`), **Send** and **Not
  now**. Send goes to him alone, in game; Not now sends nothing; an ask from anyone else is
  ignored. On his side the report he asked for opens by itself in a window you can copy from (the
  sender and time on top, **Select all**), and stays in the Workshop's list; chat gets one short
  line. A report nobody asked for gets its line and the list only. Since 1.1.5 his addon keeps the
  last 30 reports in its saved variables: where the game loads those back, a logout or a `/reload`
  loses none, and his list opens them in the same window, the date on top for one from an earlier
  day. The Forever beta, which forgets addon data at every login, still loses them at each logout
  or `/reload`. No other player's addon keeps any, and the Workshop's copy for Discord says only
  how many came, never who sent them or what they say. His version checks and his
  `/oly status` open in copy windows too. A window that opens by itself takes no keyboard, waits
  until a fight is over, and never covers a report he is reading.
- In a dungeon, a raid or a match the game holds addon messages: the lines that send show greyed
  and say why. Not on yourself, enemies, offline names or Battle.net friends, and only while you
  are in an Olympus guild. It uses the game's own way for addons to add to its menus (a client
  without it gets no lines); no Blizzard function is replaced, and nothing opens the game's chat
  box.

**Explanations and Answers.** Each page has a **?** in its bottom box: what the page shows and,
where it counts, why the numbers can differ between players. The Chat tab has no bottom box and,
since 1.1.5, no **?** of its own: the help button left of the window's X is the one there.
A count's tooltip (the header's totals, a guild's row, the Realm's online, Captains and
Recruiting, a layer's ~N, a zone and a map pin, the Treasury's week and ranking, the dues' guilds,
the Throne's roll call) ends with **Why can this differ?** and a short answer. The author, the
High Council and the Stewards also get an **Answers** button at the end of the Chat tab's box and
in Olympus's whisper window: ready answers by topic (the counts, each feature, installing and
updating), with a search. A click puts one in the box to edit (Shift-click: the longer one, to
copy for Discord); nothing is sent until you do. The explanations and answers are in English: in
another game language the tooltips leave them out, and a page's **?** says so first. The answers
live in `docs/answers.json`, and `luajit scripts/answers.lua` writes `Olympus/AnswerBank.lua`
from it.

### Decrees
| Decree | Who | What happens |
|---|---|---|
| **Call to arms!** | Captains | Alarm for every Olympus guild: raid warning, sound, red marker at the caller's position for 5 min |
| **Muster here** | Captains | Rally point: horn marker on the map for 30 min, soft alert |
| **Royal decree** | The Crown | A proclamation with free text, as a raid warning to the whole army |
| **Tabard inspection** | The Crown | Announces an inspection at the caller's position: wear your colors |

*The Crown* means the guild masters of Olympus guilds and the officers of the main
`<Olympus>` guild. Everyone else gets a local preview when they press the buttons. Since 1.0.0
the officers of `<Olympus>` are of the Crown for `<Olympus>`'s own members, whose roster (the
server's word) names them: on every other client, where only the census could, they count as
Captains, and the Crown of `<Olympus>` there is the King himself (by his character's name) and
the Hands his list or a Steward's own list names, on their word alone: while a list names them,
a Hand who is one of its officers has its Royal decrees, Tabard inspections and [Lords] lines
on every client. The King can't take back a Hand his Steward named: that Steward does, or the
author, by removing him. The
King's Steward (1.0.0, below) sends the Crown's decrees for `<Olympus>` on every client,
whatever his rank, like the King.

**Alert sounds (1.1).** Each kind of alert has a sound switch of its own, at the bottom of the
Decrees tab (a click on its line, with the gamepad UI too) or with `/oly sound <kind> on|off`:
`arms` (Call to Arms), `muster`, `royal` (Royal decrees and Tabard inspections), `court`, `vox`,
`agenda`, `throne` (the roll call, the Royal Inspection, writs), `help` (help requests and bug
reports), `hop`, `treasury`, `patrol` and `update`. Silence the chimes you don't want and keep
the Call to Arms: `/oly sound` alone is still the switch for every sound, and each kind keeps its
own switch under it. A softer chime never silences the Call to Arms that follows it. Only the
sound changes: the chat line, the raid warning and the Olympus window stay, and nothing is sent.

**In an instance or Busy (1.1).** In a dungeon, raid, battleground or arena, or while you are
Busy (`/dnd`), Olympus's alerts wait: no raid warning, no sound and no popup from the addon. Each
one still prints its chat line and waits on top of the Decrees tab, where a click shows it now.
Once you are out and not Busy, one line (and one raid warning and one sound) says what waited and
is still current, and only what is still open pops up: a Vox question still open, the King's call
to his audience within its two minutes, the Agenda still to come, a roll call within its minute,
an unread writ. What is over by then (a Call to Arms lasts 5 minutes) only stays in its list, and
nothing is ever answered for you. `/oly alerts always` shows them at once as before; `/oly alerts
quiet` (the default) holds them again; or a click on the line at the bottom of the Decrees tab.
Only on your computer: nothing is sent.

### Channels
Chat for the whole federation, carried by the addon over its hidden Olympus channel (no
WoW channel number to join). Each channel is exclusive to a rank:

| Channel | Command | Who reads and writes |
|---|---|---|
| **[Olympus]** | `/ol <text>` | every member of every Olympus guild |
| **[Captains]** | `/olc <text>` | the Captains (rank 1) and Lords of every Olympus guild |
| **[Lords]** | `/oll <text>` | the Lords (every guild master, the King included) and the officers of `<Olympus>` (their lines show to `<Olympus>`'s own members, and to everyone for the Hands the King's list or a Steward's own names, 1.0.0) |

*Continued in the README: [Channels](https://github.com/dnl-gentile/olympus-addon#channels).*

### The Chat tab (1.1.1)
The Olympus chats in a tab of the Olympus window, **Chat**, right after the Realm, like the chat
pane of the Guild & Communities window. Click the tab, type `/oly talk` (or `/ol`, `/olc` or
`/oll` with nothing after it), or Shift-click the minimap button: each opens the Olympus window
on its Chat tab, on that channel. `/oly talk lords`
opens it on [Lords]; the same command again closes the window.
When the side column of the new look runs out of room, its canonical tail continues from the
bottom of the window's left edge upward. Reading the right top-to-bottom and then the left
bottom-to-top always gives the same tab order; changing role or debug view never rearranges it.

*Continued in the README: [The Chat tab (1.1.1)](https://github.com/dnl-gentile/olympus-addon#the-chat-tab-111).*

### The Board: who is looking for a group, and where (1.1)
The Realm tab links **the Board** (or `/oly lfg`): who in Olympus wants a group right now, from
what each player chose to share, and the King's week.

- **The King's week** (`/oly week`): the King's Agenda for the next 7 days, by day, with your own
  guild's events from the game's calendar among them, so nobody books the army twice. Olympus
  can't write into the game's calendar: an officer's click opens it on the right day's month and
  says which day to right-click for the guild event. Your client keeps the week across a
  `/reload` or a login, so it shows while the King is offline.
- **The signup sheet**: Sign up on an Agenda entry with the role you claim; it goes to whoever set
  it, alone, and the army sees the counts (4 tanks, 9 healers...), kept by his client across a
  `/reload`. Nothing checks the role and nothing invites you: whoever runs the event invites by
  hand. Five minutes before an entry you signed, your client alone prints one line with the usual
  alert sound (nothing sent), after a `/reload` too.
- **Raise a flag** with one click: **Dungeon**, **Raid**, **PvP** or **Layer**, plus a short
  note if you want one (40 bytes at most). A box says first what goes out: your name, level,
  class and guild, the flag and the note, to every Olympus player of your realm and faction.
  The note goes the way chat does (the game's servers keep it, so abuse can be reported); on the
  King's screen no note shows.
- **Your zone shows on your card only while you share it** (`/oly location on`); otherwise the
  card says the zone is hidden. Never your position.
- **A click on someone's card whispers them.** Nothing invites anyone, queues or forms a group.
- One flag each, an hour at most; a click on yours, or `/oly lfg off`, lowers it at once.
- **Camps**: drop one where you stand (`/oly camp [note]`) so the army reuses a fire already up.
  Its zone only, never your spot; it needs `/oly location on` and ends by itself after 30
  minutes. The Board lists them by zone, and the world map shows one badge per zone with how
  many (mouse and keyboard only; `/oly camps off` hides them). **Bones can be played at a tavern
  or at a camp** (1.1.6): grouped, within about 10 yards, at the same inn or by your camp.

### Net-off (1.1): the moderators hide a character or take a guild off the network
The King, his Steward, a Hand (the King's list or a Steward's) or a High Councillor of the
author's signed list can hide one character for the whole army: **Hide a character** on the
**Decrees** tab (the name or your target, then the reason), or `/oly netoff Name: reason`. Every
addon then hides that character on every Olympus surface: their [Olympus], [Captains] and
[Lords] lines (and the lines the Olympus chats kept), their pinned line, their decrees, their layer and hop offers,
their Vox Populi votes and questions, their requests at court, and (1.1, Konig's review) their
signups to the King's week, their flags and camps on the Board (the camps' map badges too),
their listing, answers and recipe lists as a crafter, and their elite border and nameplate mark
(they show as no Olympus player). The names their player already linked as alts are hidden with
them (alt links, below). The rest of their guild, and
the census, are not touched: one name stops the spam.

*Continued in the README: [Net-off (1.1): the moderators hide a character or take a guild off the network](https://github.com/dnl-gentile/olympus-addon#net-off-11-the-moderators-hide-a-character-or-take-a-guild-off-the-network).*

### Alt links (1.1): one player, counted once
One player in three guilds used to swell the army by three and look like three donors. Link your
alts and the census counts people:
- On your main, `/oly alt add Name` names a character of this account; then log that character
  and say yes there. The offer waits in this account's saved variables, so only this account's
  characters can be linked, each confirming on itself: an officer can't attach anyone's alt,
  and a character added later is linked only once it confirms too. An alt never starts a link
  (its main does), and it gains nothing of its main's (a Hand's alt is no Hand).
- The army's total then counts each player once, whatever guilds their characters are in (each
  guild's own size stays its roster's; the header's tooltip says how many were counted once).
  The treasury's ranking and its week's donors put a player's characters on one line, under the
  main's name. Vox Populi takes one vote per player.
- Each linked character's addon says so on the Olympus channel (its name, its guild and the
  names it confirmed), and a link counts on a client only when both characters said it: a name
  someone claims alone links nothing.
- `/oly alt` shows your links; `/oly alt remove Name` takes one apart, from either character.
- While any linked name is hidden by the moderators (net-off), the links freeze: your addon adds
  and removes none, and every addon keeps the links it knew (it takes new names, drops none), so
  nobody drops the punished character to walk back in on an alt.
- The same faction and realm group only (one census). Up to 8 alts per player. On the Forever
  beta, which forgets addon data at every login, the offer can't reach the alt yet.

### The Throne (the King and his Hands)
A tab with a crown that only the King sees: the guild master of the guild named exactly
"Olympus" (of his faction), and on the Alliance that very character, Asmongold Asmongler: the
addon knows him by name, like the Treasurer. It opens on **the Throne Room** (the queue of
his court while it is open, and the army's key), and holding court takes him there. Since 1.1.5
the Treasury has its own tab alone, and under the Throne Room are **the centurions of the King's
guild** (up to 10, bronze without wings), named by the King or a High Councillor, who has the
Throne for them; his Steward and Hands read the list (department heads come in 1.1.6). Each of
his tools lives where it belongs:

*The list is in the README, with the rest of this section: [The Throne (the King and his Hands)](https://github.com/dnl-gentile/olympus-addon#the-throne-the-king-and-his-hands).*

### The King's Steward (1.0.0)
The King's right hand, so that he needn't set everything up himself: a character the author
marks as **Steward** in the High Council's signed titles list. On the Steward's client the
Throne opens as the King's, with **Acting for the King** on top of every page, and in the
King's name he:
- names and removes **Hands of his own**, beside the King's (the Hands button on the Throne):
  the King's list stays the King's, and his own is his;
- names and removes the **treasury's keepers**, and sets **what the army sees** of the
  treasury (its three switches), on the Treasury tab, and **sees the whole treasury as the King
  does**: the balance, the ranking, every keeper's shared book and the guild bank, whatever the
  switches (every keeper is told so before he shares his book);
- uses every tool of a Hand: the Agenda, Summon the Lords, the Royal Inspection, Vox Populi and
  the gates;
- sends the **Crown's decrees** for `<Olympus>` (Royal decrees, Tabard inspections, Calls to Arms,
  Musters), whatever his own rank: every client takes them by his name, `<Olympus>`'s own
  members' too, and they never wait behind the flood guard, like the King's. For the other
  guilds his [Lords] lines are the Crown's, as the Hands' are.

Never the King's own: his crown on the map and his layer, holding court, Royal Writs, Royal
Pardons, the untabarded list, and the King's own book of the treasury or his yes to share it
(the Steward keeps no book unless named a keeper).

*Continued in the README: [The King's Steward (1.0.0)](https://github.com/dnl-gentile/olympus-addon#the-kings-steward-100).*

### The Treasury (its keepers, the King, and the army when the King says so)
A tab with a coin for the treasury's keepers, for the King, and for every member once the King
shows the army something of it (1.1: for every member on the Treasurer's realms, with the dues' button
alone until then).

*Continued in the README: [The Treasury (its keepers, the King, and the army when the King says so)](https://github.com/dnl-gentile/olympus-addon#the-treasury-its-keepers-the-king-and-the-army-when-the-king-says-so).*

### Tabards: tabard inspection and the untabarded list
- **Patrol**: walk through the crowd and the addon inspects nearby Olympus members level 15
  and up, one by one (about 28 yards). Younger players are never flagged. It records who wears a tabard, who wears the wrong one and who
  wears none. Players it could not see properly are never accused.
- **Mark** a player (with a note: `/oly mark complained about the rule`) or a whole guild.
- **Gear seen** (1.1, officers): target a player in range (about 28 yards) and click **Inspect
  gear** on the Tabards tab (or type `/oly gear`). The addon inspects him once, in turn with every
  other inspection (one at a time, never in combat), and keeps what he wears in your saved
  variables, under **Gear seen**: a click shows his items in their slots, each with its own
  tooltip. A Captain can check a raid signup's last-seen gear days later without pulling him
  again. Only the guild master and the officer rank right below keep gear; nothing is scored,
  compared or sent, and nobody is told how to play.
- **Shared among officers** (1.1): what an officer's own inspections find (a player without the
  colors or with another tabard, and one caught before who wears ours again) goes to his guild's
  officers over guild addon messages, once a minute at most, and an officer's addon asks the others
  for the day's findings once a session: after its login, or at his yes if that came later. Each
  officer's Tabards page shows them with his own, the officer who found each in its tooltip, for a
  day (his own later inspection of that player replaces it). Nothing is inspected more or sooner for
  it, nothing goes on the Olympus channel, and only officers (the guild master and the rank right
  below, by each addon's own roster) send or keep it. The King's untabarded list stays his: another
  officer's finding never joins it, never rides in a Royal Inspection's report and never replaces
  what the King saw himself. Off until you say yes (officers get its line on the first-open page, or
  `/oly patrolshare on`); `/oly patrolshare off` stops it.
- Per guild: *"5 of 20 with problems"*.
- **Untabarded** (the "Wall of Shame" before 0.9.2): the players the Royal Inspection found
  without the colors are on the King's list, which only he sees. He alone can let the army see
  it (a switch on the Throne, off by default): then it shows on the Tabards page, quietly (no
  raid warning, no chat line, no sound), and it leaves every screen when he turns it off or
  stops repeating it. Nobody else can publish one. Players under level 15 are exempt: never
  flagged, never listed.
- Hover any player in the world to see their last inspection in the tooltip.

### Loot notes (1.1)
Loot arguments restart every raid because nobody kept last week's decision: the **Loot notes** of
your guild keep it (on the Realm tab, or `/oly loot`).
- Your guild's officers (the guild master and the officer rank right below) write the decision:
  which item went to whom, and why ("Ann passed on the gloves, Bob gets the next belt"). The
  items your group loots show to them there this session, from the game's own loot lines, so a
  click names one in its note.
- **Points**, if your guild uses them: a number per member that an officer sets by hand
  ("Bob 12"; the name alone clears it). A notebook: nothing adds or takes any, and the column only
  shows once someone has points.
- Every member with the addon reads the book, newest first, with the Realm tab's search and a copy
  for Discord. An officer's click removes a note for the whole guild.
- It is not a bid window and not a loot tool: no bids, no rolls, no gold (GDKP is not allowed on
  Forever), and nothing is handed out, traded or looted for anyone.
- Over guild addon messages only, never on the Olympus channel: each change once, when an officer
  makes it, and what a guildmate's addon lacks of the book when it asks (an officer's at login,
  anyone else's when the page opens): an answer holds some 5 KB, the newest notes first, and the
  addon asks again after each until its book is whole, however large. One officer's addon answers
  each ask, and only an officer's addon that holds that part of the book whole itself (the first
  officer online takes his own as the guild's). Each addon takes a change only from a sender its own
  roster ranks an officer, and one dated during your session only from the officer it names (a
  note's writer, the officer of a points change). Another officer's answer passes on changes from
  before your session began, and those come on the passing officer's word: nothing proves who made
  them (one made up and dated back looks the same), so the page names the officer who passed each
  one on ("Offi via Rival" on a note and in the copy for Discord, and in the tooltips of notes and
  points). Once your addon holds a note, no other officer changes its words (any officer can remove
  it), save its writer's own copy replacing one another officer passed on; an officer's addon sends
  a change in his name only as he made it. Kept per guild in your saved variables (on the Forever
  beta, which forgets them at every login, the book comes back from the officers online).

### Crafters tab (1.1.4)
"Who can make this?" is a chat scroll: the top-level **Crafters** tab turns it into one
whisper to a named crafter (`/oly craft`).
- When you open one of your professions, Olympus reads it (its skill, and the recipes you know:
  their recipe and item ids, never a specialization tree) and asks once, in a window of its own,
  whether to list it. With your yes the board of every Olympus player of your realm and faction
  shows you: your name, guild, that profession and its skill. `/oly crafter off` takes you off at
  once; `/oly crafter on` lists every profession read again.
- **Ask who can make an item**: shift-click it after `/oly craft` (or type part of its name). The
  crafters listed who know its recipe answer by whisper, their addons by themselves; the page shows
  who can, with their skill and the item, and a click whispers one of them. (From 1.2 the tab's
  **Ask who can make an item...** button opens the request page instead: see below.)
- A crafter's row opens a whisper to him and, on a click, the recipes he listed (hover one for the
  item). Search the board by crafter, guild or profession.
- It stays light on the Olympus channel and on your own messages: your listing goes once at login,
  every 45 minutes, and after a change (a profession listed or taken off 2 minutes after the last
  at the soonest, a skill up 10 minutes), so about 1.3 an hour while you play and 6 at most while
  you level. Your recipes go a part each 6 seconds (10 messages a minute at most), to two players
  at a time, and only while your addon's own messages (the census first) are few; the next player
  is told you are busy and clicks again a minute later.
- Nothing is crafted, ordered, bought or sold for anyone, nothing touches the auction house, and
  nothing is whispered for you: the whisper is yours to write. Old clients ignore the board.

### Crafting requests (1.2)
On the **Crafters** tab, **Ask who can make an item...** opens the request page: search an item
(your own recipes, the recipe lists other crafters sent you, the answers to your `/oly craft` ask,
and gathered herbs, ores and leathers) or paste its link, choose the quantity and the details, and
publish the request to the board.
- The request is a card on the board of every Olympus player of your realm and faction: the item and
  quantity, your guild, who brings the materials, a price reference and your details. It only ever
  says open, taken, cancelled or expired: never who took it, the terms or how it ended.
- A listed crafter who makes it, or for a gathered material a player whose own Herbalism, Mining or
  Skinning skill shows it (read on his client, sent nowhere), sees it marked and hears it once. The
  first claim to reach the requester wins; everything after it (the terms, the delivery, the
  request's chat) is a logged whisper between the two of them, and on the guild-mediated rail with
  the treasury keeper who holds the goods and the gold. Olympus fills a mail or says what to send:
  you press Trade or Send.
- Once a claim wins, Olympus opens the request's own chat on both players' Chat tab, with the
  Olympus window in front. It waits as Olympus's other windows do: in an instance or Busy until you
  are out (its line waits on the Decrees tab), in a fight until it ends, and while you are typing
  in the Chat tab's box until you send or leave it; by then it opens only if the deal is still
  open. It stays while the deal is open; once the deal is over you may remove it, and the
  request's **Open chat** brings it back.
- **The guild's 6% of a direct sale**: the seller owes the guild 6% of each direct sale made through
  the board, in gold, by 3 days after the sale the buyer confirmed (a sale the buyer never confirmed
  and nobody disputed owes it all the same, 3 days after the delivery the seller recorded or the
  trade both addons saw). He mails it to the guild's fee receiver (the Treasurer's mail character)
  titled "Olympus craft fee" and the request (his sale's line fills the mail). Late, he is warned and
  takes no new requests until it is paid; a fee mail that comes back is owed again. Both parties'
  addons tell the Treasurer's characters of the sale. The Treasurer, the King, the High Council and
  the author see the debtors, the most overdue first, each with his step on the guild's ladder (late,
  a warning from his guild's Watch, his guild's decision up to removal), and every fee owed; the
  reminders to a debtor are the Treasurer's and the King's. A sale only the buyer reported, or
  a buyer's price above the seller's, waits apart until the Treasurer confirms it. Nothing here
  removes anyone. There is no guarantee fund yet.

### The Missionary Church of Olympus (1.1.6)
The Church brings new players into Olympus. **Asmongold is its Head**, using the addon's canonical
King identity. This position cannot be nominated; a legacy signed Head marker grants no Head powers.
The author's signed list sets the Twelve Apostles. The King, the author and the signed High Council may name
other Apostles in game. Under the Apostles are their **missionaries**: an Apostle names missionaries, and each missionary may name more under himself, so
every Apostle's network grows. Each Olympus guild has one **Church correspondent**, named by its guild
master (or the Head, the King or the author), who keeps that guild full and answers to the Head.

*Continued in the README: [The Missionary Church of Olympus (1.1.6)](https://github.com/dnl-gentile/olympus-addon#the-missionary-church-of-olympus-116).*

### World map
- Soldiers per zone on zone and continent maps, and per continent on the world map (none with
  Blizzard's gamepad mode since 1.1.5: see below).
- Decrees are round icons (the horn, the war cry...) where they were called, and the King's
  crown where he stands; the Board's camps (1.1) one fire badge per zone, with how many. Over a
  zone's circle they move just outside its edge, top right first, so its number stays readable;
  several around one circle each take a place of their own.
- The round **Olympus** button in the bottom left corner of the map switches markers
  (army per zone, decrees, camps) on and off.
- Every zone of the game counts, not only Azeroth's (1.1): on TBC Anniversary Outland's zones
  get their circles, and Outland's total shows on the map above Azeroth and Outland. A zone a
  new patch adds is found by itself the first time a guildmate stands in it; one the addon still
  can't place shows as plain text in the census, and `/oly status` (and `/oly bug`) lists its
  name under "zones without a map id".

### Olympus Link: your Discord role (1.0.0, optional)
Prove to the Olympus bot on Discord that a character is yours, and the bot gives you your role.
It is the one part of Olympus that goes outside the game, and only if you choose to link a
character (or to confirm other players' links, below): no password, no Battle.net login, and
nothing is sent before you say yes.

Not open yet: the addon carries it, but `/oly discord` says it is not open until the Olympus bot
is ready and its key is in the addon. Until then no addon makes, keeps, announces or uses a
confirmer key.

1. **Get a code** from the Olympus bot on Discord (its `/verify` command, in the Olympus server:
   only you see the reply). It is good for 24 hours. Keep it to yourself, and don't show it (or
   the Olympus Link window) on a stream.
2. **Type `/oly discord <code>`** in the game's chat. The addon checks the bot's signature on the
   code, then asks whether to link this character to the Discord account the code names (the
   bot's word: nobody can change it). **Cancel** sends nothing.
3. **Players confirm in game**, by addon whisper, that this character asked: a High Councillor
   online, or, when none is, verified players drawn for your code (three of them must confirm).
   Each signs with a key of its own, for its character, which the bot certified. Every confirmer,
   High Councillors included, gets a key from the bot's keeper, made on a computer, and types it
   in the game with `/oly discord key <id> <key>`, then its certificate with
   `/oly discord cert <certificate>`; no addon makes a key of its own (the author's council
   authority, which could certify keys made in game, is off). Once the bot is ready, a
   confirmer's addon says so on the Olympus channel every 5 minutes and signs other players'
   requests by itself (`/oly discord key off` stops it).
4. **The proof reaches the bot.** The **Olympus Link** window shows a QR code and the same link
   in a copy box. Open the Olympus Link page, https://dnl-gentile.github.io/olympus-addon/ (a
   static page on the project's GitHub Pages): point your phone's camera at the code, share the
   game's window with the page, or paste the link, then sign in with Discord there (Discord's own
   sign-in page, which tells the bot who you are on Discord) and the page sends the proof to the
   bot. Or, later, the addon hands it to a High Councillor's watcher the next time you are both
   online, and the bot's keeper uploads it.

The page reads the code in your browser: the camera and the shared window never leave it, and
the proof rides after the `#` of the link, which a browser never sends to any server. The page
loads its fonts from Google Fonts. The bot keeps which character (name, realm, guild and
faction) is linked to which Discord account, and a record of each proof it received (for 90
days). A linked character never moves to another Discord account by a new link: the bot refuses
it. **Delete my link**, at the foot of the Olympus Link page (signed in with Discord), takes the
role away and deletes what the bot keeps about your account, except how many codes and links you
used today, counted for a day at most. The Olympus bot is Fernmelder's; how it checks a proof
is on [GitHub](https://github.com/dnl-gentile/olympus-addon) (the README and `web/FERN.md`).
`/oly discord show` opens the window again, `/oly discord status` lists every character of your
account, `/oly discord forget` drops this character's request and proof.

### Everywhere
- **Copy**: every tab produces a ready-to-paste text for Discord.
- **Version letters** (1.1.5): after the addon updates, once a version, a short letter on
  parchment, in a window like the Olympus window's, says what changed in that version, in the
  dev's own words. It waits until the privacy page is closed, and never opens in combat, in a
  dungeon or outside an Olympus guild. On the Forever beta, whose saved variables never load, it
  shows again every session, as the privacy page asks again. The Olympus window's help button
  (the **i** left of the X) keeps every letter: **Version letters** on its page lists them,
  newest first, and a click opens one; `/oly letters` (or `/oly letters 1.1.4`) does too. Nothing
  is sent: which letters you saw is kept on your computer, for your account.
- **What this client saw** (1.1, the Decrees tab and `/oly log`): a log of the acts your addon
  took while you were online (decrees, the gates opening and closing, pardons, the King's
  visibility switches for the treasury and the untabarded list, and the shared block terms'
  edits), each with the sender's name as the server stamped it, the newest 300. So "who opened the gates" has an answer after the message
  is gone. Only acts heard from whoever did them: a repeat or a relay of someone else's act (the
  Treasurer's book carrying the King's switches, another editor's list carrying a block term) and
  a state caught up on after a later login are not written. On the King's screen, while the
  council's names are hidden there (his stream), every sender but the King shows cut short, and
  the shared terms' words too, as everywhere on his screen. Kept on your computer only, never
  sent, never in `/oly bug`; a record, not proof (anyone can edit their own saved files). The
  Decrees tab lists it with a search box and a copy; `/oly log [n | word | copy | clear]` in chat.
- **Backup** (1.1): `/oly backup` puts one text in the copy box (keepers also have **Copy a
  backup of your book and settings** on the Treasury tab): this character's book of the treasury
  (its opening, its 500 lines and its sums of all time, each giver's weeks of the dues and each
  week's amount with them; on the Treasurer's characters his mail
  character's book too), the King's switches and keepers on his client or a Steward's, and your
  settings (sound, map, minimap, borders, nameplates, Vox, your chat windows and mutes, the
  players you blocked). Keep it in a text file: when the beta wipes the saved variables, `/oly
  restore` opens a box to paste it back, says what it restores and waits for your yes. Clipboard
  only: nothing is uploaded or sent anywhere (a keeper's book goes out afterwards as it always
  does). A book goes back only into that character's (merged with what it wrote since, nothing
  counted twice), a text that was cut or changed is refused, and it never holds your yeses to
  sharing (the addon asks them again). It never holds or sets the channel key, on anyone's
  character: a text someone else made would move your guild to another channel (your officers
  hand the key out in game as ever, or `/oly key`); the confirm says a key in a text is left out,
  and warns when it is one your guild replaced. The players it would block are named one by one
  in the confirm (30 at most) and added only on your yes.
- **Search**: a box on top of the Census (guilds, Lords, Captains, players, zones, recruiting),
  the Realm (guilds, Lords, Captains, members seen online), Crafters (crafter, guild or profession), the
  Tabards (inspected and untabarded players, by name or guild), the Treasury (donors in the
  ranking and the book, and since 1.1 the bank's items), the Decrees (since 1.1: the log of what this client saw) and the Chat tab (since 1.1.1: a name, a guild or words of a line). Any case, accents too; only what matches shows, under the headers it belongs to (a Captain under his guild, opened
  for you, a page of guilds at a time), with an **x** to empty it. Each tab keeps its text until
  you log out or `/reload`; a guild clicked in the Census opens in the Realm with its box emptied.
  It only changes what the list shows: **Copy** still gives everything, and nothing is sent.
- The window opens from `/oly`, the minimap button, or the round button in your guild window:
  the old Guild tab or the new Guild & Communities window, whichever one you use.
  Shift-click the minimap button for the Chat tab (1.1.1, above).
- Next to Forever's Guild & Communities window it takes that window's look: icon tabs down
  the right side, its rows, column headers, buttons and member card. When the tabs do not all fit
  down that side, the canonical tail continues from the bottom of the left edge upward. Reading
  the right top-to-bottom and then the left bottom-to-top always gives the same tab order.
- **Blizzard's gamepad mode** (Forever's controller interface): Olympus asks its questions in
  windows of its own instead of the game's popups, which Blizzard's gamepad code blocks (and
  freezes) when an addon opens one. With mouse and keyboard, the game's popups as always.
  Since 0.9.8 it also leaves the game's own frames alone there: no quiet `/who` on its own
  (**Refresh** and **Find Olympus online** still search, and so does the King's click on his
  Throne's /who line for his key rotation, 1.1: the answer shows in the game's
  Who list), and the Issue Reporter is the game's to show. Since 0.9.9 it leaves the world map
  alone there too: no zone counts, decrees, crown or guildmate dots on it (the minimap keeps
  the crown and the dots), because each of those went through the map library into the gamepad
  map's own state; since 1.1.5 its continent totals and Olympus button go too, the gamepad map
  being the game's alone. If the game still says it blocked
  Olympus, a `/reload` clears it; to tell us what it was, open the Olympus window, press its
  help button (left of the X), then **Report a bug**.
  **The gamepad gate (1.1.5).** Every way Olympus reaches into the game's own windows is listed in
  one place and asks one gate before it acts, so a new feature can't reach them with the gamepad
  UI on by accident. With the gamepad UI on, Olympus registers no typed command (`/oly`,
  `/olympus`, `/ol`, `/olc`, `/oll`): the game's chat box runs a command's function and then
  closes itself in that function's name, which is the very call the gamepad UI refuses. Nor does
  it put its round button in the game's guild windows, where the gamepad cursor would select it.
  Open Olympus with the minimap button (it shows there even when `/oly minimap` hid it), and use
  its window (its help button: **Report a bug**). Switched to the gamepad UI in the middle of a
  session (Options, Gamepad), Olympus steps back from the game's windows on the next frame: its
  marks, borders and buttons there hide, its tooltip lines and menu lines stop, and what the game
  keeps until a `/reload` (the commands typed with mouse and keyboard among it) is told once, in
  Olympus's own window, with a **Reload** button. Back to mouse and keyboard, it all comes back
  without a `/reload`.
- English and Portuguese in full, and since 1.1 Spanish, French and German for the main
  screens, the alerts and decrees, the Join screen and its whisper, the chats and the privacy
  questions (the rest in English; the pages' **?** explanations and the Answers of 1.1.2 are in
  English too). It follows the game language, and only the text on your
  screen changes: nothing sent between players does. `/oly status` shows the language in use.

## Install

**Easiest:** install **Olympus Guild** from the CurseForge app or WowUp. It installs in the
right place and keeps it updated. For Forever, pick the Forever (beta) installation of the
game in the app, not Classic Era.

**By hand:**
1. Download `Olympus-x.y.z.zip` from the **Files** tab here (or [GitHub Releases](https://github.com/dnl-gentile/olympus-addon/releases)).
2. Open your World of Warcraft folder. On Windows it is usually
   `C:\Program Files (x86)\World of Warcraft\` (on Mac: `/Applications/World of Warcraft/`).
3. Open the folder of the game version you play. For the **Forever beta** it is the one with
   *beta* in its name (for example `_classic_beta_`); Classic Era is `_classic_era_`, TBC
   Anniversary is `_anniversary_`.
4. Go into `Interface\AddOns\` (create `Interface` and `AddOns` if they don't exist) and
   extract the zip there, so you end up with `...\Interface\AddOns\Olympus\Olympus.toc`.
   Careful: Windows' *Extract All* adds a folder named after the zip
   (`AddOns\Olympus-0.8.1\Olympus\...`). If that happens, move the `Olympus` folder up into
   `AddOns`; the game only loads it from `AddOns\Olympus\`.
5. **Restart the game.** If the addon list says *out of date*, tick **Load out of date AddOns**.

The addon only shows **live data**: guilds appear as soon as one of their members with the
addon is online (give it a few minutes). There is no demo mode any more.

**One member per guild is enough** for that guild to appear for everyone. The more guilds
have at least one install, the more complete the census gets.

### For officers: seal the channel (recommended)
Type once, with a secret the Olympus officers agree on:
```
/oly key <secret>
```
Your guildmates with the addon receive it automatically through guild chat. From then on
the Olympus channel has a name and password derived from the secret, and outsiders can't
find or join it. Share the same secret with the officers of the other Olympus guilds
(for example in the officers' Discord), so all guilds meet on the same sealed channel.
Since 1.1 the King (or his Steward, for him) can also rotate the army's key from the Throne: his new key reaches the
Lords and Captains online of the guilds he picks whom his own /who saw in them by whisper, and
their guilds over guild chat, never on the Olympus channel.

## How it works

1. Every guild member can read their own guild's roster: name, level, class, zone, rank,
   online and last seen.
2. Members with the addon find each other through hidden addon messages in guild chat and
   **elect one reporter per guild**. The first name alphabetically wins, and every client
   computes the same answer.
   Each realm of WoW: Forever has a hidden channel of its own, so a guild with members on
   several realms elects one reporter on each realm (since 1.0.0).
3. The reporter sends a compact summary of its guild about every 3 minutes on the hidden Olympus channel.
4. Every client adds up all the summaries: that is the census.

The addon itself talks only in game, through the game's own addon messages: it has no server of
its own, and nothing it sends leaves the game. The one exception is Olympus Link (above), and
only when you choose to link a character: it uses a website (the Olympus Link page, on the
project's GitHub Pages) and the Olympus bot on Discord. A confirmer (a key from the bot's keeper)
signs other players' requests by itself once the bot is ready, and those signatures reach the bot
in their proofs.

**Realms vs layers.** A realm (ClassicBetaPvP, ClassicBetaPvP2...) is a separate world
with its own guilds; layers are copies of a zone *inside* one realm. Guilds on the same
realm always see each other, whatever layer they are on. The hidden channel stays inside
one realm (PvP and PvP 2 each have their own), while guild chat reaches a guild's members on
both. So since 1.0.0 each realm elects its own reporter for a guild, and the High Council's
lists cross over through guild chat. Realms whose guilds span each other share one
census and one realm key: PvP and PvP 2 on the beta from the start, and any realm your
guild turns out to be homed on. Alts on any other realm keep their census apart, and the
window shows which realms you are counting.

## Privacy

The addon itself talks only through the game's own addon messages: it has no server of its own,
and what it sends stays in the game. The one exception is Olympus Link, and only when you choose
to link a character, or to confirm other players' links: a link's proof goes to the Olympus bot
on Discord, through the Olympus Link page on GitHub Pages (where you sign in with Discord) or a
High Councillor's watcher. A confirmer, a High Councillor too, is someone who typed in a key the
bot's keeper made them (no addon makes or announces a key by itself, and the author's council
authority is off): once the bot is ready, their addon says so on the Olympus channel every 5
minutes and signs other players' requests by itself, and their character's name and signature
reach the bot in those players' proofs, until `/oly discord key off`. Your name is on every
message (the game adds it). What goes where:

*The table is in the README, with the rest of this section: [Privacy](https://github.com/dnl-gentile/olympus-addon#privacy).*

## Security and trust

**What the author's character can see.** The author (Faladoriel Skylance) has a Workshop tab
to keep the addon healthy. It reads the install counts every guild report already carries,
plus the addon versions of each guild's users. On demand he can ask for a roll call: each
addon online (a share of them when the army is large) answers, by addon whisper to him only,
with its version, game client, and whether it joined the channel, is its guild's reporter and
has the channel sealed with a key. Nothing about the character (no guild, level or class), no
position, no chat, nothing else. He may ask one player alone the same way, by addon whisper:
the same answer, and each addon answers him once every 4 minutes at most, however he asks.
He can also ask a player on an old version to update: a fixed window with the two version
numbers and nothing else. Only his character on his realm group
can do either: every addon checks the sender's name, which nobody else can carry. Since 1.1
a roll call is answered only after the player's yes (the first-open page, or `/oly rollcall on`),
and `/oly rollcall off` refuses both. Since 1.1 your addon also reads the released version his addon
announces on the channel (his presence): newer than yours, the Census, `/oly status` and one chat
line a session tell you to update. That is local to your client, sends nothing, and shows
whatever `/oly rollcall` says. He runs a new build on his own PC before it is published, so his
presence names only the version he marked as out with `/oly released [version]` (his character
only; the Workshop tab shows it) once CurseForge lists it, never the build he runs, and never one
newer than that build; addons before 1.1 read none of it. The addon's error catcher keeps only Olympus's own errors (for
`/oly bug`), never another addon's. For the store's screenshots he has a photo mode (`/oly
photo`, his character only): on his own screen it fades everything but Olympus and the world
map to invisible, and gives every frame its look back on the second `/oly photo` or a
`/reload`. Never in combat, not with the gamepad UI, not on a screen of more than 1000 frames
(it says so and leaves them as they are), and nothing is sent to anyone.
To check the elite borders his own rank doesn't carry, `/oly borders test <tier>` (his
character only) shows one of the borders round his own portrait, and on his target frame when he
targets himself, and its nameplate mark after his own name on his player frame and on every
friendly player's nameplate (`/oly borders test member`: the member's star alone), on his screen
alone until `/oly borders test off` or a `/reload`. It follows the borders' and the marks' own
rules (none with the gamepad UI, made out of combat), and nothing is sent.

The addon is plain Lua running on each player's computer, so anyone can edit their own
copy. No addon can prevent that. What this one does is check what every copy sends; what a
few characters working together can still reach is said plainly further down
([What colluding characters can reach](#what-colluding-characters-can-reach)):

*The list is in the README, with the rest of this section: [Security and trust](https://github.com/dnl-gentile/olympus-addon#security-and-trust).*

### What colluding characters can reach

Votes are counted per sender name, and nothing the server tells an addon proves which guild a
sender belongs to: a census report is its sender's word. So a few characters working together
can still reach the following today (1.0.0); each outcome was checked against this version's
code.

*The list is in the README, with the rest of this section: [What colluding characters can reach](https://github.com/dnl-gentile/olympus-addon#what-colluding-characters-can-reach).*

## Built for a crowd of thousands

- One summary per guild about every 3 minutes, not one per player.
- In a full guild only the members who could be elected keep saying hello; the rest go quiet.
- Layers are announced by officers plus a stable 1 in 8 sample who share them, every 10 minutes
  (the King's alone every minute, while his crown shows: one client, one message a minute).
- A layer request goes out once; only about 6 players answer it, each by a whisper to the asker.
- Messages are spaced 1.2 s apart, below Blizzard's addon message limits, and alert sounds
  play at most once every 15 seconds (1.1: a softer one never silences the Call to Arms or a
  louder alert after it).
- Chat has its own short lane: a line goes out within about a second, and while reports are
  waiting it never takes more than every other message slot.
- The Board (1.1): a flag is repeated every 10 to 30 minutes (less often the fuller the Board),
  and a Board's ask is answered by whisper, by about 40 flag holders at most.

## Commands

| Command | |
|---|---|
| `/oly` | open or close the window |
| `/oly realm` · `/oly decrees` · `/oly tabard` | open a tab |
| `/oly loot` | your guild's loot notes and points on the Realm tab (its officers write them; not a bid window) |
| `/oly craft [item or name]` · `/oly crafter on\|off` | who can make it (the top-level Crafters tab: shift-click an item after `/oly craft`); list your professions read so far, or take them off |
| `/oly approved` · `/oly approved paste` | the guilds of Asmon's Olympus the author's signed list makes Olympus guilds (their names don't say Olympus), and whether yours is one; paste that signed list (the first member of such a guild: his addon then passes it to the guild) |
| `/ol <text>` · `/olc <text>` · `/oll <text>` | write in [Olympus], [Captains] or [Lords]; alone (`/ol`, `/olc`, `/oll`): open the Chat tab on that channel (1.1.1) |
| `/oly mute olympus` · `/oly mute captains` · `/oly mute lords` | hide or show a channel in chat |
| `/oly chatwindow tab` · `/oly chatwindow <number or name> [olympus\|captains\|lords]` · `/oly chatwindow main` | the Olympus chats in a chat tab named Olympus (without the channel's name; it says how to make the tab), in another chat window (with Chattynator, one of its tabs, by name), or back in the main one |
| `/oly privacy` | the first-open page again: what the addon shares, and your Yes or No to each (1.1) |
| `/oly chat on\|off` | the Olympus chats on this client; off, nothing is sent or shown (1.1: off until you say yes) |
| `/oly talk [olympus\|captains\|lords]` | open or close the Olympus window on its Chat tab, on that channel; also `/ol`, `/olc` or `/oll` with nothing after it, or Shift-click the minimap button (1.1.1) |
| `/oly helpme [text]` (or **Ask a High Councillor** on the Realm tab) | ask the High Council (the moderators) for help: it goes by whisper to up to three of them online who take requests |
| `/oly discord <code>` · `/oly discord` | Olympus Link: link this character to your Discord account with the bot's code (or paste it in a box) |
| `/oly hop` | ask for an invite to the King's layer (while he is online) |
| `/oly lfg` · `/oly lfg dungeon\|raid\|pvp\|layer [note]` · `/oly lfg off` | the Board (1.1): who is looking for a group; raise your flag (a box with your note first) or lower it |
| `/oly week` | the King's week on the Board (1.1): his Agenda for 7 days with your guild's calendar events; the King and his Hands add entries with the Agenda button ("Sat 20:00 Raid night") |
| `/oly location on` · `/oly location off` | share (or not) your zone and layer on the Olympus channel |
| `/oly borders on` · `/oly borders off` | elite borders round the portrait of your target, focus, party members and your own frame (Forever): the game's gold wings for the King, silver wings for the High Council, Max's bronze wings for the guild masters of Olympus guilds, and his bronze without wings for the centurions and correspondents a guild master names, while they are in his guild (none for a character or a guild the moderators took off, net-off). Since 1.1.5 the rank borders (gold for Lords, silver for Captains, bronze for Raiders and Veterans) are gone, and any other member has the nameplate star alone. On by default, hidden with the gamepad UI. Off, the nameplate marks go too |
| `/oly nameplates on` · `/oly nameplates off` | a small mark left of the name on friendly players' nameplates (Forever; friendly nameplates show with Shift+V), like an elite creature's dragon: the game's gold elite mark for the King, its silver for the High Council, bronze for guild masters and the people they name, and a star for any other member of an Olympus guild (none for a character or a guild the moderators took off, net-off); on by default, hidden with the gamepad UI and with `/oly borders off` |
| `/oly chatmarks on` · `/oly chatmarks off` | 1.1.5: the mark of a player's border tier before their name in the game's own chat (channels, say, yell, emote, party, raid, instance and whispers; guild and officer chat the dragons alone, never the star): the King's gold dragon, a High Councillor's silver then their icon, the bronze of a guild master and the people he names, the star for any other member your addon can check. Olympus's own lines carry none. Through the game's own name filter, so the name's link, right-click and /r stay the game's; on by default, hidden with the gamepad UI, and a councillor's on the King's screen while the council's names are hidden |
| `/oly block <name>` | ignore a player |
| `/oly filter add\|remove <word>` · `/oly filter` | block terms: hide, on your screen, lines of addon text (Olympus chats, writs, decrees, Vox) with a word; the list (1.1) |
| `/oly alt add Name` · `/oly alt remove Name` · `/oly alt` | link a character of this account as your alt (log it and say yes there), take a link apart, or see your links: the census and the treasury count you once (1.1) |
| `/oly sound` · `/oly sound on\|off` | every alert sound on or off |
| `/oly bug` | copyable bug report (also: the help button left of the window's X, then **Report a bug**) |
| `/oly status` | diagnostics in chat (1.0.0: whom your addon knows as the King's Steward, and the lists of Hands it holds, whose each is; 1.1.2: the author's in a copy window) |

*Every command in the README: [Commands](https://github.com/dnl-gentile/olympus-addon#commands).*

## Reporting a bug

While the addon's author is online, the **Report a bug** window also has a **Send to
Faladoriel Skylance** button: your report goes to him in game, by addon whisper, and nowhere
else (once every 10 minutes at most, unless he asked for it). It first checks he is really there: the rest follows
only once he answers, and you are told when he got it.

Since 1.1.2 the author can also ask you for it from the right-click menu: your addon shows you
the exact text first, in a window of its own, and sends nothing without your **Send**.

Type `/oly bug` (or press **Report a bug**), copy the text and open an issue on [GitHub](https://github.com/dnl-gentile/olympus-addon/issues). Errors are
also saved in `WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua`.

## Credits

- **Asmongold** and his team (Daily Dose of Asmongold, Max, Heuto, Fernmelder and the High
  Council), for making Olympus the army's addon and for the ideas.
- **Security reviews:** Konig, bjess9 (jess), lordjumper and Fadirstave, who read the code and
  showed what an attacker could do.
- **Code and ideas:** RoyLeviGit (Olympus chats in their own chat window), Artz (hiding the
  Issue Reporter), bjess9 (CI and the shared checks), hypertectonic (Chattynator's tabs),
  Bernardo Costa / Costafitness (exact layer-hop confirmation and stale-request regressions,
  adapted from PR #51), and Rick-laboratory (bounded transport, cancellation and admission
  regressions, adapted from PR #52).
- **Feature requests:** Fernmelder, whose 39 posts became 1.1 (the Fernmelder release);
  shenanigans_ (the nameplate marks), Valdericht (`<OLYMPIAN>`), Pyralis Ashandar (taking
  donations) and Zeal (what the King hides stays off the channel).
- **Art:** Max (the bronze elite borders, drawn over the game's own: the winged one is the guild masters' since 1.1.5, the plain one their centurions' and correspondents').
- **Reports from the field:** Riukensei and PartyRockAce (the gamepad UI), Ignitheus (whispers
  to Forever names), Pyralis Ashandar, the Treasurer (the treasury and the guild bank), and the
  player who told us WoW had handed him the channel.
- Everyone who reported a bug, tested in game or asked for a feature.

## License

MIT. A fan project, not affiliated with Blizzard Entertainment, Asmongold or the
Olympus leadership. The Olympus emblem belongs to its owners and is used for the community.

*Sources for the Olympus description: the Olympus Discord welcome message,
[Prism on X](https://x.com/fwprism/status/2101809316382847172) (10K+ members in the beta),
[Dexerto](https://www.dexerto.com/world-of-warcraft/asmongold-responds-as-wow-forever-players-want-him-banned-over-massive-olympus-guild-3411199/).*


Source code: https://github.com/dnl-gentile/olympus-addon
