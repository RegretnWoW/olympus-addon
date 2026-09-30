<p align="center"><img src="docs/logo.png" width="96" alt=""></p>

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

<p align="center"><img src="docs/olympus-1.jpg" alt="The whole army at a glance: every Olympus guild, live"></p>

<table>
<tr>
<td><img src="docs/olympus-2.jpg" alt="The Realm: the King, the Treasurer and every Lord and Captain"></td>
<td><img src="docs/olympus-3.jpg" alt="Every guild in detail: hover a guild for members, online, Lord, free slots, level and classes"></td>
</tr>
<tr>
<td><img src="docs/olympus-4.jpg" alt="One click to anyone: whisper, invite or find a Lord or Captain"></td>
<td><img src="docs/olympus-5.jpg" alt="Where the army stands: soldiers per zone on the world map"></td>
</tr>
</table>

> **Status:** built for WoW: Forever and running on the Forever beta (1.60.1), where the
> census already adds up reports from many Olympus guilds. Also tested on Classic Era (1.15)
> and Anniversary (2.5). Please report anything that looks wrong (`/oly bug`).

---

**Horde too.** Olympus guilds on the Horde side use the same addon. The factions can't see
each other's guilds, so each one gets its own census, channels, decrees and untabarded list: the
addon picks yours from your character. On the Horde, the Crown is every Horde Olympus guild
master and the officers of the Horde guild named exactly "Olympus", if there is one.

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
1.1, the Alliance's `<OLYMPIAN>` (only a new version takes one of those off). Its members' addons, no Olympus members
until they hold that list, take it over their own guild alone (the list only: nothing else is
read, and they send nothing). The first of them pastes it with `/oly approved paste`, or a click
on the Join Olympus screen's last line (the author
or a High Councillor hands out the signed text; it is checked like any list, so it can't be forged
or changed), and his addon passes it to his guild every 5 minutes. `/oly approved` lists the
approved guilds of your faction. A newer signed list without a guild ends it on every client.

### Not in Olympus yet?
First it asks the obvious question: *"<Your Guild>? Disband immediately. What are you
doing?"* Then it helps you get in. The **Join Olympus** screen uses the game's own `/who` to
find Olympus members online, groups them by guild, and whispers one of them a ready-made
request that you can edit ("Hi! I'd love to join Olympus. Does <Olympus II> have room for
one more?"). No answer? **Try someone else** picks a member you have not asked yet. Replies
are highlighted. It is rate limited, so nobody gets spammed. The game lists 50 players per
`/who`: when there are more, each new click searches a range of levels and adds to the list.

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
- Olympus guilds where nobody runs the addon show too, in grey: opening the window (and any click in it) also searches
  `/who` and lists every Olympus guild it sees online, with how many. They count in no total.

### The Realm: the hierarchy
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
  answer or a no, and the next one is asked.
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
the zone you are in and the layer you want. The King's layer is known only while his crown
shows on the map (**Show me on the map** on his Throne, off by default): his addon sends it
the moment he shows the crown and repeats it every minute while it shows. With his crown
hidden (or while he is in a dungeon, where it hides) the line says so instead of "try again in
a minute". A layer is a copy of a zone inside one realm: when the census places him on another
realm than yours, the line says that, even if his layer reaches your channel. The `king:` line
of `/oly status` (and of `/oly bug`) says what your addon knows of him: online and how sure,
his realm, his layer and his crown, and how long ago each was heard.

### Person details
Click any Lord, Captain, racer or inspected player. You get the same card the Guild window
shows: level, class, zone, rank and status, with **Whisper**, **Invite** and **Who** buttons.
Any soldier can reach the Lord of another Olympus guild in two clicks.

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
- **Ask to update**, when they are behind the newest version your addon knows: on 1.1.2 or newer
  their addon shows a small notice with both versions and where to update; an older one can't, so
  the click opens a whisper with the ask for you to send. One ask per player a day, 5 an hour;
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
  line. A report nobody asked for gets its line and the list only. His version checks and his
  `/oly status` open in copy windows too. A window that opens by itself takes no keyboard, waits
  until a fight is over, and never covers a report he is reading.
- In a dungeon, a raid or a match the game holds addon messages: the lines that send show greyed
  and say why. Not on yourself, enemies, offline names or Battle.net friends, and only while you
  are in an Olympus guild. It uses the game's own way for addons to add to its menus (a client
  without it gets no lines); no Blizzard function is replaced, and nothing opens the game's chat
  box.

**Explanations and Answers.** Each page has a **?** in its bottom box (next to the gear on the
Chat tab): what the page shows and, where it counts, why the numbers can differ between players.
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
King's Steward (1.0.0, [below](#the-kings-steward-100)) sends the Crown's decrees for
`<Olympus>` on every client, whatever his rank, like the King.

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

- Higher ranks also use the channels below theirs: a Lord writes in all three.
- `/oly mute captains` (or `olympus`, `lords`) hides a channel in chat; the same command shows it again.
- **The Olympus tab (1.1.1).** One click in the Chat tab's settings (the gear), or
  `/oly chatwindow tab` (`aba` works too), sends the three channels to a tab of your chat named
  "Olympus". There each line comes without the channel's name, in its channel's colour: gold for
  [Olympus], teal for [Captains], purple for [Lords] (the tab's first line gives that legend).
  You make the tab yourself with the game's menu, as the click tells you: right-click the General
  tab, Create New Window, and name it Olympus; the lines land there as soon as it exists, in the
  main window until then. The click shows you where on the Chat tab, as its **Add an Olympus tab
  to the game chat** line does, with a pointer by that tab, and sends the channels there the
  moment it exists
  (1.1.1, below). Olympus
  cannot make it for you: the game's own code for a new chat window, run by
  an addon, taints the chat box, so `/cast`, `/target`, `/use` or `/click` typed there afterwards
  get blocked (with the gamepad UI, the game froze in 0.8.5). A new tab also shows Say, Guild,
  whispers and more: right-click it, Settings, and untick everything to have the Olympus chats
  alone there (the tab's first line says so, after the legend, when the tab shows other chat;
  `/oly chatwindow tab` says it again). The main window keeps Olympus's own notices and the
  pinned line's announcements. `/oly chatwindow main` brings the channels back to the main
  window.
- `/oly chatwindow <number or name>` shows the three channels in another chat window of yours
  (make it in the game first: right-click a chat tab, Create New Window), by name or by number;
  `/oly chatwindow Officers captains` moves one channel only, and `/oly chatwindow main` brings
  them back. In a window named anything but Olympus the lines keep the channel's name (name the
  tab "Oly" and pick it with `/oly chatwindow Oly` to have it). Only where the lines are printed
  changes: the addon never touches the chat box, so every command typed there works as always.
  A window closed or renamed sends its lines back to the main window, with a notice.
  `/oly status` shows where each channel goes.
- **Chattynator (1.1.2, from hypertectonic's pull request #47).** With the Chattynator chat
  addon, its tabs are your chat windows: the game's own windows are hidden behind them, so
  Olympus leaves those out and picks Chattynator's tabs instead. `/oly chatwindow tab` (or the
  Chat tab's settings) sends the three channels to a Chattynator tab named Olympus, without the
  channel's name, and says how to make it: in Chattynator, click the + after its tabs, rename
  the new tab Olympus (right-click it, Rename tab), then right-click it, Tab Settings, and under
  Addons tick Olympus. `/oly chatwindow <name>` picks any other tab of Chattynator's by its
  name, in any case (`/oly chatwindow Guild captains`), as the tab shows it or as Chattynator
  keeps it ("GENERAL" for General); not by number. A tab shows Olympus's lines only if its
  filter lets Olympus in, which Olympus cannot see: each time you choose a Chattynator tab, the
  main window says how. A tab moved gets the new lines where it now is (the lines it showed
  before may not follow it: Chattynator files each line under the tab's place when it came);
  one removed or renamed sends them back to the main window, with a notice. Olympus only reads
  the names of Chattynator's tabs and prints its lines there through Chattynator's public API:
  it never makes, renames or sets up a tab, and your chat box works as always. Choosing a tab
  does not turn the Olympus chats on (the first-open page, or `/oly chat on`). Without
  Chattynator nothing changes.
- The flood guard keeps a busy channel readable: past 60 lines a minute (or 10 from one player
  while the channel is half full) the rest stay off the chat, and a notice says how many, at
  most once a minute. Those lines still go to the Chat tab (1.1.1), which keeps the last 100
  lines of each channel.
- A line still waiting to leave when the Olympus channel changes (a new realm key, from
  `/oly key` or the King's rotation) is not sent, to either channel, and you are told: it was
  written for the old channel's audience. Send it again to write on the new one (1.1.1, GitHub
  #34). The same holds for a line the privacy warning holds while the channel changes. Of a
  long line whose first parts had already left, the notice says how many went out, on the old
  channel.
- Shift-click an item or spell into the line and it stays a link. Long lines are split into
  up to 3 messages; if the game refuses one of them, the rest of that line is not sent
  either, and you are told (1.1.1).
- The channels show only in the chat of players with the addon.
- **Block terms (1.1).** `/oly filter add <word>` hides, on your screen, every line of addon
  text with that word: the Olympus chats, the King's writs, a decree's words and Vox Populi's
  question and answers. Whole words only, any case or accent, one word of 2 to 24 letters or
  digits (`/oly filter remove <word>`, `/oly filter` lists them). It never reads names, guilds,
  the census, the treasury or the game's own chat (Say, Trade, General). A hit hides the line and
  nothing else: its sender is not ignored, blocked or cut off, and their next line shows. The
  Chat tab says how many lines your filter hides in a channel, and a click shows them, marked; the
  Decrees tab offers a hidden writ, a decree's hidden words or a hidden Vox question with a click.
  The pinned line's words hide the same way (1.1), and a click on the line shows them.
  A companion addon reading the chats (the bridge) still gets hidden lines, as with a muted
  channel. **The shared block terms**: a second list the King, his Steward, a Hand or a High
  Councillor of the author's signed list edits for everyone (`/oly filter shared add|remove
  <word>`, 50 words at most, each one word of 4 letters at least: a short common word such as
  "the" or "de" would hide nearly every line), used on every client unless its player says
  `/oly filter shared off`. The shared list never hides the King's writs (your own filter still
  can). Each word is its own entry with the server's time of its edit, so two editors never undo
  each other's other words, and a removal is kept for 30 days (the list keeps 100 entries at
  most, the oldest removals going first, those of the same second in alphabetical order, so
  every addon keeps the same list whatever order the edits reached it in). Clients take it from those
  characters alone (the server stamps the sender), and each edit this client heard from the
  editor's own client, within 15 minutes of it, goes into its log of acts with the editor's name
  (another editor's repeat of it does not: it is not his act). Clients before 1.1 ignore the list.
- **Your choice (1.1).** The chats are off until you say yes on the first-open page (or
  `/oly chat on`). Off, `/ol`, `/olc`, `/oll` and `/oly pin` say so and send nothing, and no line
  from anyone shows or is kept on this client, nor any pinned line; the Realm tab and the Chat
  tab say the chats are off, a click to choose.
- The Realm tab links **the Olympus chats**: a click opens the Olympus window on its Chat tab
  (1.1.1, below), with the last lines of each channel your rank reads, even what was said while
  the window was closed.
- Ranks follow the rule of the decrees: whoever founds a guild with "Olympus" in its name is
  its Lord and gets [Lords], and its officers get [Captains].
- **One pinned line** (1.1): the King, his Stewards and Hands can pin one short line (100
  characters) on top of the Olympus chats and the Realm, for every member, for 2 hours: a raid
  move, a gates change (**Pin a line for the army...** in the Chat tab's settings). A guild
  master pins one for his own guild alone (**Pin a line for your guild...**): it goes over guild
  chat, and
  each guildmate's addon reads his rank in its own guild roster, never in the census (which
  anyone on the Olympus channel can report to). (The officers of <Olympus> read [Lords] only on
  its own members' addons, so they pin for the army as the King's Hands.) `/oly pin <text>` pins
  where your rank allows; `/oly pin off` (or a click on the line) takes it down: its setter, or
  a higher rank (the King anyone's, his Stewards and Hands a guild master's, over guild chat like
  the line itself, so it reaches his guildmates on every realm), and one line in chat says who
  took it down. A takedown sticks: every addon remembers the pins taken down for 2
  hours (in its saved variables), so a repeat that comes late, or a setter's addon that missed
  the takedown, never brings one back. It remembers 200 at most, and nobody's takedowns push a
  higher rank's out: a takedown naming a pin it does not hold is remembered once a minute at most
  from each sender, a sender's takedowns of his own pins 10 at most, and past 200 the lowest
  rank's go first. The addon that took it down says so again when it hears it repeated (once a
  minute at most), and the setter's addon lets it go. The setter's addon
  keeps its own pin through a `/reload`, to repeat it and take it down. On the Forever beta,
  which forgets addon data at every login, a `/reload` forgets both: `/oly pin off` with nothing
  pinned on your screen still takes your own line down wherever it shows (once a minute at most),
  and an addon that reloaded no longer knows the lines taken down, so one whose setter's addon
  missed the takedown can show there again until the addon that took it down hears it repeated
  and says so again. A pin shows only where the Olympus chats are on, and you pin only while
  yours are; none shows from a name or guild
  the moderators took off (net-off), whose own addon pins nothing and takes no one else's line
  down (only its own); your block terms hide its
  words, as any addon text, until a click on the line shows them. It is lighter than a writ: no
  parchment, nothing to acknowledge, no popup and no sound, one line in chat when it arrives.
  There is one line on each screen: a newer pin replaces one of its own rank or lower, so the
  King's newer pin always wins, and his Stewards' and Hands' outrank a guild master's. Its words
  are the setter's own, sent with the logged API like a chat line (abuse can be reported), and
  its setter's addon repeats it for late logins. Charters and dues stay in Discord, typed by a
  person. Addons before 1.1 don't show it.

**Not encrypted, not private:** every client on the hidden Olympus channel receives the text of
all three channels, and the addon only decides what to show. Anyone on that channel can read
[Captains] and [Lords] with a one-line script: without `/oly key` that is anyone who joins
"OlympusNet" by name; with a key, every member of the guilds that have it. The guild tag on an
[Olympus] line is not verified. Seal the channel with `/oly key`, and never share passwords there.
Before your first line in each channel the addon tells you this and waits for **Send**.
Since 1.1, while your channel is public, officers see one quiet grey line saying so on the
Census, the Realm and the Chat tab's settings (its tooltip says who can read it and how to seal
it);
every member sees how many guildmates are already on the sealed channel, and `/oly status`
says public or sealed. It only tells: nothing is sent and nothing changes.

### The Chat tab (1.1.1)
The Olympus chats in a tab of the Olympus window, **Chat**, right after the Realm, like the chat
pane of the Guild & Communities window. Click the tab, or type `/oly talk` (or `/ol`, `/olc` or
`/oll` with nothing after it), Shift-click the minimap button, or click **the Olympus chats** on
the Realm tab: each opens the Olympus window on its Chat tab, on that channel. `/oly talk lords`
opens it on [Lords]; the same command again closes the window.
With the King's tabs the side column of the new look runs out of room: his Treasury moves to the
window's left edge (for the author, his Workshop goes there first).

- On top, where the other tabs show the army's counts, the search box: a name, a guild or words
  of a line, and only the lines that hold it show (a line your block terms hide is found by its
  writer and guild, not its words), with an **x** to empty it; like every tab's, it keeps its text
  until you log out or `/reload`. On the same row, right of it: for a rank that reads more than
  one channel, a small switch with the channel shown, in its colour, and **+N** for the lines that
  came in on the others while the tab was open (a click lists your channels, each with its count,
  to pick one); then the gear of the settings (below). There is no row of channels: most players
  read [Olympus] alone, and the lines take that room. A channel muted in chat (`/oly mute`) still
  shows here, and a line you write here keeps it muted in chat. The pinned line shows over the
  lines, as on the Realm tab, and takes no room while nothing is pinned.
- Every line whole, in a bubble that wraps: never cut, nothing to hover to read it. Other
  players' lines on the left, yours on the right in the channel's colour (a line another of your
  characters wrote shows under that character's name, on the left); the writer's name, guild and
  time where a writer starts, and the date where the day changes. The lines take the room of the
  list and of the box under it (this tab has no detail box). The last 100 lines of each channel
  are kept, from every session, and scroll back. The tab follows the newest line until you scroll
  up; then the line you are reading stays in its place while new lines come in and the oldest go,
  and **N new** at the bottom takes you down to them.
- By each name, Olympus's marks, by the rules of the borders and the nameplate marks (but not
  switched off with them), and only where the guild a line names is proven: a nameplate reads the
  guild from the game, a chat line only claims it. The King's crown, the High Council's mark and
  colour, the game's silver elite mark for Lords and Captains, bronze for Raiders and Veterans of
  your own guild (the census does not carry other guilds' rank names), a star for any other member
  of your guild's roster or anyone the census names in theirs (and the King's Stewards and Hands),
  the Treasurer's coin, and **Steward** or **Hand** after the King's. A name whose Olympus guild
  cannot be checked (a plain member of another guild, or anyone claiming a guild's name) gets no
  mark. A click on a name whispers that player, in Olympus's whisper window.
- A line your block terms hide shows as a grey bubble, and a click shows it, marked. Over the
  lines, like the pinned line, how many your filter hides in the channel (no room while it hides
  none), and a click there shows them all (another hides them again). A link shows its tooltip
  when you hover it, and a Shift-click puts it in the tab's box.
- **The box** runs across the bottom, where the other tabs have their buttons, with no Send
  button: Enter sends. It is Olympus's own, not the game's chat box: it takes the keyboard only
  when you click into it or press your open-chat key (Enter, unless you changed it) while the tab
  shows (the tab never takes it when it opens, so your movement keys keep working; in a fight the
  key changes over when the fight ends). Enter sends to the channel shown and the cursor stays for
  the next line; Enter on an empty box, Escape or a left-click elsewhere gives the keyboard back to
  the game; Tab changes channel. With the gamepad UI only a click puts the cursor there, and Enter
  lets it go. It runs no command: a line that starts with `/` stays in the box and is not sent
  (commands go in the game's chat box, which Olympus never opens or touches). Your first line in
  each channel still waits for the privacy warning's **Send**. A line of yours that did not leave
  shows a note in its channel, and a click puts it back in the box when the box is empty (what you
  are writing is never replaced: the note waits).
- **Add an Olympus tab to the game chat**: while your game chat has no Olympus tab (see Channels
  above), a line over the lines offers one. Olympus cannot make that tab itself, so a click
  shows you where: a small Olympus pointer by your main chat tab says right-click it, Create New
  Window, and name it Olympus. The moment a chat window named Olympus exists, Olympus sends the
  chats there (as `/oly chatwindow tab` does) and says so once; the pointer and the line go. It
  only reads the game's chat windows to see the new one appear. With the gamepad UI there is no
  pointer (the game's chat tabs work otherwise there): the line gives the same steps as text. The
  line stays away while you send a channel to a chat window of your own (`/oly chatwindow`), and
  its **x** puts it away for good, on every character: the settings and `/oly chatwindow tab`
  still make the tab. With Chattynator (1.1.2) there is no pointer either (the game's tabs are
  hidden behind Chattynator's): the click sends the chats to its tab named Olympus at once, and
  chat says how to make that tab in Chattynator; the Chat tab reads Chattynator's tabs while it
  shows. The tab is announced once, by the Chat tab when it sees the tab or by the tab's first
  line if that comes first, and a channel you moved meanwhile stays where you put it.
- **Settings**: the gear at the end of the top row shows them in place of the lines (a click on it
  again, or **< Back to the lines**, goes back). The Olympus chats on or off on this client, what
  that means, and a click to choose (the first-open page); for officers while your channel is
  public, its quiet grey line. For each channel your rank reads: whether it shows in your game
  chat (a click mutes it there or shows it again, as `/oly mute`), and the chat window it prints
  in (a click moves it to the next chat window open in your game, then back to the main one, as
  `/oly chatwindow`; with Chattynator, to its next tab, by name, 1.1.2). The Olympus tab of the
  game chat: add it (as the line over the lines does),
  the steps while it is awaited, **on**, or waiting for a chat tab named Olympus. And for whoever
  may pin, **Pin a line for the army...** (or **for your guild...**). Each choice is the one its
  command makes, kept where it always was, so nothing chosen before 1.1.1 is lost; the game's chat
  windows are only read, and printed in.
- The tab has no place or size of its own: it is the Olympus window's, docked by your guild
  window or wherever you put it. Escape or the window's X closes it; it never opens by itself.
  With the chats off on this client it says so, what the choice means, and offers it.
- **Blizzard's gamepad mode**: the same tab, opened with `/oly talk`, `/ol` or the Realm tab's
  link; click into the box with the gamepad cursor to write. The Olympus window stays off the
  Escape list there (its X closes it), and the tab opens no game popup: the whisper, a pinned
  line's takedown and the settings' pin use Olympus's own windows.

### The Board: who is looking for a group, and where (1.1)
The Realm tab links **the Board** (or `/oly lfg`): who in Olympus wants a group right now, from
what each player chose to share, and the King's week.

- **The King's week** (1.1, on top of the Board, `/oly week`): the King's Agenda for the next 7
  days, by day, at the realm's hour, with your own guild's events from the game's calendar
  (green) among them, read on your computer and sent nowhere (on the King's screen, his stream,
  they read "Guild event"). Raid night, PvP night and court on one page, so nobody books the
  army twice. The King, his Steward and his Hands take an entry off with a click. Olympus can't
  write into the game's calendar (the game keeps creating events to its own button): an
  officer's click on an entry, **Put it on your guild's calendar**, opens the game's calendar
  and says which day to right-click, and he creates the guild event there. With the gamepad UI,
  or in combat, it only says how to open it (the minimap clock, `/calendar`, or the gamepad
  menu's Calendar). The King's client repeats his entries for late logins, every 10 minutes (every
  30 while one is more than a day away), and keeps them across a `/reload`. Every client keeps
  the week it heard across a `/reload` or a login, so it shows while the King is offline, until
  each entry is over or taken off (an entry taken off while you were away goes once its setter's
  client, back online, repeats his others without it). A client keeps 30 entries at most, and
  the King's and his Steward's always find a place: a Hand's furthest ahead gives way.
- **The signup sheet** (1.1) on every entry of the King's Agenda, its current event too: **Sign
  up**, then the role you claim (Tank, Healer, DPS or Any role; Withdraw takes it back). Nothing
  checks the claim and nothing invites you: the signup is a whisper to whoever set that entry,
  alone, and whoever runs the event invites by hand. His client keeps one signup per character
  and sends the army the counts ("Signed: 4 tanks · 9 healers · 60 dps · 3 any") soon after a
  change, then every 5 minutes while one of his entries has signups or is within 2 days (every 15
  otherwise), so the King knows whether the raid is 4 or 40 before anyone zones in; the names
  stay on his own screen, behind **Who signed** (a councillor's cut short on the King's stream).
  His client keeps the signups across a `/reload` or a login, with his entries. Signups the
  census can't place (more than a guild's size, a guild it doesn't know) are listed apart and not
  counted. Sign up shows only while that player's addon is online to take it.
- **A nudge for what you signed** (1.1): 5 minutes before an entry this character signed, your
  client alone prints one line with the usual alert sound ("You signed up as Healer: Raid night
  in 5 min"), once, after a `/reload` too (from your signup itself, if the entry isn't heard
  again before it begins). Not a raid warning, and nothing is sent: the army gets no extra alert.
  An entry taken off takes your signup and its nudge with it.
- **Raise a flag** with one click: **Dungeon**, **Raid**, **PvP** or **Layer**, plus a short
  note if you want one (40 bytes at most; `/oly lfg raid need a healer` fills it in). A box
  says first what goes out: your name, level, class and guild, the flag and the note, to every
  Olympus player of your realm and faction. The note goes the way chat does (the logged API:
  the game's servers keep it, so abuse can be reported); on the King's screen (his stream) no
  note shows, only names and guilds.
- **Your zone shows on your card only while you share it** (`/oly location on`); otherwise the
  card says the zone is hidden. It is never your position, and never in a dungeon. Turn sharing
  off and your zone leaves every card within 30 seconds.
- **A click on someone's card whispers them** (the game's chat box; Olympus's own window with
  the gamepad UI). Nothing invites anyone, queues or forms a group: the whisper is yours, and so
  is any invite that follows.
- One flag each; a new one takes its place (the old one comes down on every Board first, and the
  new one shows at once). It lasts an hour at most (you are told when it comes down), and a click
  on it, or `/oly lfg off`, lowers it for everyone at once, after a `/reload` too. 30 seconds
  between raises, 3 an hour; the Board holds 150 flags.
- Your addon repeats your flag every 10 to 30 minutes (the fuller the Board, the less often) for
  players who log in later, and the first time a session you open the Board your addon asks
  the channel once: the players with a flag up answer you alone, by whisper.
- The Realm's search box finds a flag, a name, a guild, a zone or words of a note.
- **Camps** (the Board's second list): drop one where you stand, **Drop a camp in <zone>** or
  `/oly camp [note]`, so the army reuses a fire that is already up instead of planting five in one
  zone. A camp carries its zone and nothing finer (never your spot), needs `/oly location on`,
  ends by itself after 30 minutes (one every 10 minutes per character) and is taken down the
  moment you stop sharing your location, or with a click (`/oly camp off`). The Board lists the
  camps by zone; a click whispers whoever dropped one. On the world map each zone with camps
  gets one badge beside its circle, with how many (mouse and keyboard only, like the decrees;
  `/oly camps off` or the map's Olympus menu hides them).

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
them ([alt links](#alt-links-11-one-player-counted-once)).
The rest of their guild, and the census, are not touched: one name stops the spam.
- The Decrees tab lists who is hidden, with the reason, who hid them and when (the server's
  clock), and who passed the word on when it reached you through another issuer's addon (the
  server's name for that one: nobody writes a word in someone else's name unseen). The same
  people show a name again with a click there, or `/oly neton Name`.
- Only a word from higher up reaches one who gives words: the King's reaches everyone but
  himself, a Steward's the Hands and High Councillors, and a Hand's or a councillor's no other
  issuer (nor the names they linked as alts). So a rogue Hand or councillor can't hide the
  Steward, another Hand or a councillor; the King (or the Steward, for a Hand or a councillor)
  hides the rogue, and the rogue's words then fade. And no word replaces one from higher up,
  whatever its date: a Hand or a councillor never shows again one the King or the Steward hid,
  nor hides again one they showed again, and the Steward never undoes the King's word (1.1,
  Konig's review: the King's undo no longer loses an edit war to a newer word). Nor through
  another name of that player: a word on a name he linked as an alt, or (Forever) on the same
  name on another realm of the group, doesn't hide him when his own name's word comes from
  higher up, or from as high and is newer.
- It never aims at the King (his name in any case), nor at the characters he linked as his
  alts. It uninvites nobody, demotes nobody and writes nothing to Blizzard's ignore list, and
  `/oly block` stays one client's and one player's. No treasury code can call it.
- The hidden player's addon tells them why, and sends none of it. A Hand or a Steward who is
  hidden calls the army in vain: their Agenda, roll call, Vox Populi, inspection and gates, and
  their entries on the King's week (their cancels of anyone else's too) and its signup sheets,
  show nowhere, and what an addon heard of them before the word leaves its week (whoever named
  them a Hand still decides whether they stay one). Taking their own entry off the week still
  reaches every addon, so it doesn't come back once they are shown again.
- A word goes on the Olympus channel with Blizzard's logged addon-message function (the issuer's
  own words: the server keeps them, so abuse can be reported), one word per name. Each issuer's
  addon repeats his own words for late logins, every 5 minutes, and never anyone else's (1.1,
  Konig's review: a word passed on in the King's name went out from the King's addon as his
  own), and the army repeats at most 20 words a minute however long the list (a long list is
  repeated less often). Among words of the same rank the newest wins, by the server's clock;
  on the same second the King's own, else the one hiding the name, so every addon keeps the
  same word, whatever reached it first.
  A word hiding someone lapses 30 days after it was given (give it again to keep it); a word
  showing a name again is kept for 30 days, so an older word never comes back. A word counts
  only from someone who may give one on that client now (the server stamps every sender's
  name), never from a name that is hidden itself, and a word passed on only while its giver
  may still give one on that client: the words of someone taken off the lists or hidden (or of
  a Hand while nobody who named him keeps his list alive) are no longer repeated, and fade
  within 3 days, as do, on the other addons, the words of an issuer who has not played for 3
  days (his addon repeats them when he is back). When the list is full (500 characters, 200
  guilds) a new word waits for room, except the King's own, which always finds it, and no word
  ever makes room by pushing out one from higher up (1.1, Konig's review: a Hand who filled the
  list pushed out the King's word showing a name again).
- On the King's screen, while the council's names are hidden (his stream), another issuer's
  reason (even one written in his name) and a councillor's name stay hidden until he shows the
  council's names. Nothing about him or his alts is printed on his screen.
- Each honest addon does it: a modified one can ignore it, and versions before 1.1 show
  everything.

The same people can also **take a guild off the Olympus network** (**Take a guild off the
network** on the Decrees tab: the guild's name or your target's guild, then the reason; or
`/oly netoff guild Name: reason`), and put it back on (`/oly neton guild Name`). While it is off,
honest addons stop sending and showing that guild's census (its size leaves the army's total),
its zones on the map, its layers and hop, its decrees, its Vox Populi votes, its Olympus chats
and pinned lines, and (1.1, Konig's review) its members' entries and signups on the King's
week, their flags and camps on the Board, and their listings, answers and recipe lists on the
crafters' board: its own members' addons send none of it and say why, and every other addon
drops what still comes. Every addon also drops its members' requests at court, and shows them
with no elite border or nameplate mark (as no Olympus player). Blizzard's guild chat and Guild
window stay up, and so do the guild's own addon messages among its members (its guild master's
pinned line aside: hidden with its chats). A
spam guild, or one that is not really Olympus, is cut out of the
federation without touching anyone's rank. One guild per word and never the King's: there is
no switch for the whole realm. Nothing about it is tied to the treasury or to any payment, and
no treasury code can call it. Its members' hop asks and offers are known by the guild their own
messages name (a census report names its sender's guild), never by the names written inside
someone else's report.

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
his court while it is open, and the Treasury), and holding court takes him there. Each of his
tools lives where it belongs:
- **The King's Agenda** (a button on the Throne): minutes and an event ("30 Raid on
  Crossroads"). The whole army gets a popup with the appointment (what, in how long, where)
  and sees it on the Census, with reminders 10 minutes and 1 minute before. Since 1.1 it also
  holds **the King's week**: a day and an hour of the realm, then what ("Sat 20:00 Raid night",
  "today 21:30 Court", "sáb 20h Raide"), up to 7 days ahead, 10 entries each for the King and
  his Steward and 5 for each Hand. The army sees them on the Board, by day (below), with one
  quiet chat line when an entry is added: no popup, raid warning or sound. The box starts
  empty, and a day and an hour typed after a number ("30 Sat 20:00 Raid night") still make a
  week entry, never a 30-minute Agenda.
- **Hold Court** (a button on the Throne): the King opens his court where he stands. Every
  Olympus player in that zone gets a line on top of the Census and the Realm; one click asks
  for an audience. The requests line up on his Throne and a click calls that player (a popup
  and a raid warning).
- **Summon the Lords** (on top of the Realm tab): every Lord and Captain online gets a popup,
  "Present, my King" or "Busy". While the roll call is fresh, each Lord and Captain in the
  tree carries a ready-check mark: present, busy, or not answered yet.
- **Royal Inspection** (on top of the Tabards tab): a raid warning for the whole army ("wear
  your tabard!"), then a sample of the soldiers with the addon (of those who said yes to it, 1.1) patrols the players around them
  for 2 minutes and reports to the King: how many were checked, the percentage in colors, per
  guild, and who was caught, on his untabarded list. It stays within a budget for the realm:
  once every 30 minutes at most (whoever calls it), each patrol inspects one player every 5
  seconds at most, and the sample is sized from the addons online so the whole realm sends
  about 20 inspect requests a second (100 patrols at once; everyone while the army is that small).
- **Vox Populi** (a tab of its own): the King asks the army a question with two to six
  answers, to pick one or to pick several, open for 30 seconds to 5 minutes. Everyone with
  the addon gets a window with check boxes and a countdown; each vote goes to the King alone.
  He watches the bar chart fill, on his tab or on his screen for the stream ("Show on
  screen"); when time is up everyone gets the chart and the winner (shares of the votes, or
  of the voters when each picked several). `/oly vox off` keeps the questions in chat.
- **Royal Writs** (in the Decrees tab): a letter from the King on parchment, to the Lords alone,
  to every Lord and Captain, or to the whole army. Lords and Captains can answer "As you
  command"; the King sees how many did. (The audience is who the addon shows it to: like
  everything on the channel, anyone on it can read the bytes.)
- **Open the Gates** (in the Realm tab, Recruiting): the King picks the guild new recruits
  should join for the next two hours; everyone sees it on top of Recruiting.
- **Royal Pardon** (on the untabarded list): a click takes a name off it, for everyone, for a
  week.
- **Rotate the army's key** (on the Throne, 1.1; or `/oly key rotate`): when the realm key
  leaked, his addon (or his Steward's, acting for him) makes a new one (nobody sees it, he
  neither). He then picks the guilds that
  get it: those his own /who saw are checked, and a guild only the census names waits for his
  click (two characters on the leaked channel can make up a guild and its Lords); nothing is
  sent before he hands it out. His addon whispers it to their Lords and Captains the census
  confirms online and his own /who saw in that guild in the last 30 minutes (the server's word:
  two characters can also call themselves a real guild's Lord and Captain in the census, and a
  name the census alone gives gets nothing). His click on a guild, or on the Throne's /who line, searches /who
  for the Lords and Captains picked it has not seen there yet, one search a click: every guild
  picked first, then each of them by name, at most once in 30 minutes (with the gamepad UI his
  click on the /who line searches each guild picked plainly, its answer in the game's Who list,
  never a name, and a guild again a minute after its last search; a click on a guild only checks
  it there, and the census's Refresh searches too). What his /who saw is kept with the rotation, through a /reload or
  relog too. Each hands it to his guild over guild chat, so
  nobody types `/oly key` by hand. It never travels on the Olympus channel. Whoever holds the
  old key outside the guilds he picks stays behind on the old channel; anyone in a guild that
  gets it has it too. For 10 minutes his addon keeps handing it to Lords and Captains who log in
  (once his /who saw them in their guild), on the old channel, a few
  whispers at a time so his other messages keep their place (a little longer while some picked
  still wait for their whisper), then he and his guild move to it ("Move now" sooner); the
  Throne says how many of those he whispered have it (an answer from anyone else is not
  counted), and of how many guilds (each counted for the guild his addon whispered him for,
  never the one his answer names). A guild with no officer online by then stays on the old channel
  until one of its officers types the key by hand. The King or his Steward: never a Hand.
  Each 1.1 addon keeps the newest key by the time it was made and remembers the keys a newer
  one replaced: an officer's plain `/oly key` from a version before 1.1 still moves his guild,
  as ever, but never back to a key a newer one replaced (the leaked one). A 1.1 officer's own
  `/oly key` is dated, and wins for his guild, as ever.
- **Hands of the King** (a button next to his map button): players he names use the roll
  call, the inspection, the agenda, Vox Populi and the gates in his name. Never the court,
  writs, pardons or his crown on the map. Their addons learn the list from his, and it ends
  when he stops sending it. A Hand who is an officer of `<Olympus>` keeps its Crown (Royal
  decrees, Tabard inspections, [Lords]) on every client, not only on its members' (1.0.0).
  Each Steward names Hands of his own beside his, in a list of his own, with the same tools and
  the same Crown, which the King can't change (1.0.0, [below](#the-kings-steward-100)).
- **Show me on the map** (his own button, with the crown): while he turns it on, everyone with
  the addon sees a crown where he is, on the world map and the minimap. Off by default (his
  position is on stream); the same button hides it, its tooltip says whether it is on now, and
  the top of the Throne page reminds him while it is. His layer goes out with it, at once and
  then every minute, so the army can ask to join him (**Ask invite for Asmon Layer**); hidden,
  it is withdrawn with the crown.

Every command is checked on each client: it only counts if the sender is the King by name
(the server stamps every sender's name, so nobody else can carry his), his Steward for what is
his to do in the King's name (1.0.0), or one of the Hands (the King's or a Steward's), for what
is lent to them. No census vote can make anyone else King or silence him. On the
Horde the King is Duskmonkey Boneback, guild master of `<Mudhutters>` (0.9.4): his guild counts
as an Olympus guild there, whatever its name. Answers go to the King alone. Nothing another player sends can put free text on his screen: only names and
Olympus guild names.

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

**The Hands: each list its owner's.** The Hands are the King's list and each Steward's own
list together, and a Hand has the same tools, and the same Crown for `<Olympus>` on the other
guilds' clients, whoever named him. Nobody changes anyone else's list: the King's Hands page
shows his own list, to change, and each Steward's, to read, under that Steward's name; a
Steward's page shows his own list, to change, and the King's and the other Stewards', to read.
**The King can't take back a Hand his Steward named**: that Steward does, or the author, by
removing him as Steward (both pages say so). The King's list is the same message as before
1.0.0, from his client alone, and ends 20 minutes after his client stopped repeating it, as
before. A Steward's list goes out from his own client alone, in a message of its own; every
client keeps the last one it heard from him (by his name, which the server stamps), and it ends
20 minutes after his client stopped repeating it, or at once, on every client, when a newer
signed list no longer names him: named again later, he starts from no Hands, as long as his
addon saw the list without him (on any of his characters there). Clients before 1.0.0 follow
the King's list alone, as they
always did, and leave a Steward's out: a Hand only a Steward named has his tools on 1.0.0
clients.

**The treasury: the newest word.** The treasury's keepers and its switches are one list each,
which the King and his Steward both set: each client takes them only from the King's character
or from a Steward its signed titles list names, each word dated by the server's clock. The
newest wins, and on the same second the King's: **the King's newer word always wins** (his
screen tells him when his Steward changed one of them; the name is cut short there while the
council's names are hidden on his stream). The King's client and the Steward's take the newest
word as theirs and repeat it, and each answers an older word it hears with the newer one. A word
dated more than a minute ahead of the server's clock is not taken.

**Who he is.** Only the author names a Steward, with the same key that signs the council (see
[The High Council's signed lists](#the-high-councils-signed-lists-the-author)): no name is
written in the addon, no census vote counts, and nobody else can make one. A Steward acts for
the Alliance's King (the Horde's only when the list names one for the Horde), on the list's
realm group, where a King is named. A newer signed list without him ends it on every client at
once. `/oly status` says whom your addon knows as the Steward, and the lists of Hands it holds
and whose each is.

### The Treasury (its keepers, the King, and the army when the King says so)
A tab with a coin for the treasury's keepers, for the King, and for every member once the King
shows the army something of it (1.1: for every member on the Treasurer's realms, with the dues' button
alone until then).
- **Its keepers (1.0)**: the Treasurer of Olympus (that exact character, in the guild OLYMPUS),
  the King, and up to 5 characters the King adds on the Treasury tab (**The treasury's
  keepers**, then **Add a treasury character**, by name or target; a click on one takes it off).
  The list is the King's word (or his Steward's, in his name): every client checks it comes from
  his character or a Steward's and keeps it (it never runs out while he is away); their addons
  repeat it. No keeper's book carries it, the Treasurer's included (his could otherwise name
  anyone a keeper).
- **The Treasurer's mail**: Pyralis Andarai, his hunter where the treasury's mail goes, keeps a book of its own like him (pinned by name on his realm group, in any guild or none; gold between the two is a transfer, and outside an Olympus guild its book reaches the others through the Treasurer's addon).
- **Each keeper's book**: gold and items a keeper receives by trade or mail are a donation, gold
  and items he gives a payment, each written down by itself in his own character's book, by his
  own addon (mail when he takes its gold, or once its items reach his bags; the auction house,
  cash on delivery and the game's mail don't count).
- **A book is not the keeper's gold**: its opening balance, plus what came in, less what went
  out. What he earns playing is his. A trade of his items (or his work: an enchant, a lock
  opened) for gold is a sale, of his gold for items a purchase, gold with his own characters his
  own: they go in the book as not counted, and a click on the line counts it if it was the
  treasury's (or stops counting one that wasn't). A payment by mail that comes back stops
  counting by itself.
- **Between keepers, a transfer**: gold or items one keeper gives another is the treasury's own
  moving: in both books and in each one's balance, never a donation or a payment (the totals and
  the ranking of donors leave it out). The addon can't tell another keeper's alts apart (that
  would mean sending every keeper's alts on the channel): gold from one of them shows as a
  donation, and a click on the line stops counting it.
- **One treasury**: the keepers' books together. The balance is their sum; the totals, the
  week's donations and the ranking of donors are one list each (someone who gave to two keepers
  is one line); the week's donors are a count from each keeper's book (1.1: their names never
  go out, see the dues below, so someone who gave to two keepers this week counts in each); the
  book shows every keeper's lines by time, with who received each one (1.1: on every other
  client, not the gold given to the Treasurer's characters: those lines are the dues, and never
  leave his client). Each
  keeper's balance and when his book last came show under the total; a keeper not heard from
  for a while still counts.
- **Items donated**: every item given to the treasury, how many, and who gave it last (hover it
  for the item itself), with the army's "book" switch; the item lines are in the book too.
- **1.0's fresh start**: at a keeper's first login on 1.0 the old book (0.9's, the Treasurer's)
  is closed and kept in the saved variables, never shown or sent, and his new book opens at his
  character's gold then (a keeper the King names later: at his gold then). The treasury starts
  from their sum; the totals, the week and the ranking start at zero. A keeper can set his own
  book's opening balance on the tab. The era travels in each book ("1.0"): 1.0 clients never
  read 0.9's treasury, and 0.9 clients get a short copy of 1.0's, in 0.9's shape, from the
  Treasurer's addon.
- **The ranking of donors** (all time) and the week's donations, with a copy for Discord.
- **Early supporters**: everyone who gave before 1.0 (from 0.9's closed book, sent by the Treasurer's addon), names only, in alphabetical order, under the ranking and with its switch. They go out only once the Treasurer said yes to 1.0's question, which says their names go to everyone on the channel (his yes of 0.9.3 is not enough: he is asked again).
- **The guild bank of <Olympus>**: whoever of that guild opens the bank with the addon on takes
  a snapshot of it (each tab's items with icons and counts, the bank's gold, when it was seen);
  a keeper's snapshot (the newest, whoever took it) reaches the King and, with his "book"
  switch, the army (1.1: on the channel only with that switch; without it, by whisper to the
  King, his Steward and the keepers alone). Hover an item for its tooltip. Nothing is ever moved in the bank: it is a
  picture. On WoW: Forever the bank's window opens through the game's interaction manager,
  which 1.0 listens to (0.9's addon never saw it open there); a client with no guild bank says
  so on the tab.
- **The bank's search and what left it** (1.1): the Treasury tab's search box finds the bank's
  items too (by the item's name as your game knows it, or its number: how many in all, and in
  which tabs; a click opens the first). Under the bank, **Gone since the last snapshot** lists
  the items whose count dropped since the snapshot before of the same source (the last one of
  your earlier visit, or the same keeper's before his newer one: never another keeper's, since a
  snapshot is its sender's word, Konig's review; with another's in between, an older one of his, or
  none until his next), counted over the tabs both snapshots saw, and the
  grid shows those stacks faded and red in the slots they sat in. Counts only: who took them is
  not known, the addon never reads the bank's log (a withdrawal nobody noted, a stack moved to a
  tab the other snapshot didn't see, or theft). The game sends a tab's slots only when asked,
  and some never arrive: an empty tab you did not click keeps its last items for that visit, so
  a tab emptied between two visits shows here once it reads empty again, a visit later (at once
  if you click it). A tab that reads empty with no earlier snapshot to keep it from (after your
  saved variables were wiped, or on a newly named keeper's first visit) is not sent, so nobody's
  screen lists its last items as gone.
- **Taking donations** (1.1, the Treasurer's idea): a keeper (the Treasurer, the King, a
  character he named) turns it on with **Taking donations** on the Treasury tab or `/oly
  donations on`: everyone with the addon sees a line on the Realm and Treasury tabs ("Pyralis
  Ashandar is taking donations in Stormwind City"), his zone only if he shares his location
  (`/oly location`; the King: his crown on the map), and one line in the [Olympus] chat when he
  turns it on (not with that chat muted or the Olympus chats off, nor for a late login; in the
  Olympus tab without "[Olympus]"). His addon repeats it every 2 minutes and when his zone
  changes; it is never saved, so it is off when he logs out (his addon says so as it leaves;
  otherwise it drops off every screen 5 minutes after his last word), and `/oly donations off`
  turns it off before.
- **Requests to the treasury** (1.1): a Lord or a Captain of any Olympus guild asks the treasury
  for an item and a count ("need 10 Ironwood"): a click on the item in the bank's grid (when he
  sees the bank), `/oly need 10 <item>` (the item shift-clicked into the chat line, its name or its
  number), or **Ask the treasury for an item** on the Treasury tab. No text travels: the item's
  number and the count, 3 open requests per character, each for 3 days. His addon whispers it to
  the keepers, the King and his Steward heard online whose addon reads it (1.1 or later), and
  again every 15 minutes while it is open.
  Their Treasury tab lists it next to the bank (**Requests to the treasury**, with what the bank
  holds of it); a click marks it done or declines it, and the requester is told. Handing it over
  stays a normal trade or mail, the keeper's own click: the request closes by itself when his book
  records that item given to that player. While the King shows the army the book, the keepers'
  addons also put the open requests on the channel, next to the bank, so everyone who sees the
  bank sees what is already asked for (a request line stops five officers from buying the same
  stack). Taken only from a Lord or Captain as the census confirms (it can be gamed: a request is
  its sender's word, shown with his name). Paced (Konig's review): at most 6 new requests an hour
  per character, one taken back included (his addon says when the next may go; a keeper's addon
  takes no more from one player, keeps 10 of his at most, and answers an open request once every
  7.5 minutes at most while nothing changed, a closed one never again once its asker was told),
  and a keeper's list on the channel once a minute at most (a change inside it goes when the
  minute is over).
- **Sister guilds' banks** (1.1): the guild master or an officer of another Olympus guild is
  asked once, when he opens his guild's bank, whether the King sees it (`/oly bank share
  on|off`). With his yes, his addon whispers its snapshot (items and counts, its gold, when it
  was seen; the tabs' names left out, shown as "Tab 1", "Tab 2") to the King, his Steward and
  his Hands when their addon asks, never on the Olympus channel. Their addon takes it only from
  a Lord or Captain of that guild as the census confirms (a snapshot is its sender's word), keeps
  it until logout, and shows it on the Treasury tab under **Sister guilds' banks** (a Hand's tab
  appears for it), its items in the search too. His no takes it back from their screens: at once
  from each one whose addon asked in the last 18 minutes (their addon asks every 15; his keeps who
  asked, and when, through a `/reload`), from the others at their next ask, once each, even after
  a `/reload` of his, for as long as his no stands (Konig's review: one who asked before could
  keep it all session); it counts from him even when the census no longer names him. The limit:
  one his addon did not hear ask in those 18 minutes (he was offline meanwhile) and does not hear
  again before he logs off keeps it on his screen until that player logs out (it is never saved).
- **Sent by each keeper's addon by itself** (every 5 minutes and after a change), once he said
  yes: his book's balance, totals, ranking, items donated and latest lines (1.1: never a line of
  gold given to the Treasurer's characters, see the dues below). On the Olympus
  channel only the parts the King shows the army (1.1); the whole book goes by whisper, in
  pieces, to the King, his Steward and the keepers whose addon was heard in the last few minutes
  and reads it (1.1 or later: it asks for it after login, then every 15 minutes; a 1.0 addon is
  never whispered). A changed book goes to each of them 3 minutes after the last one at the
  soonest, the latest then, and each piece only while the addon's own queue is nearly empty, so
  the whispers never push the keeper's census or his book on the channel out of it. Every client checks it comes from a keeper himself, and that it holds together (its
  shape and sizes, a balance its totals add up to, no list longer than a book sends, no date
  before 2026 or more than a day ahead of the server's clock): one that doesn't is refused whole,
  and the copy it had of that keeper's book stays. A keeper's own addon never sends such a date,
  even when his computer's clock is wrong: it sends his dates within the server's clock.
- **The King chooses what the army sees** (his Steward too, in his name), with three buttons:
  the balance, the ranking, the book. Until he does, only the keepers, the King and his Steward
  see them (a keeper's tab says so, and so does the question each keeper answers before sharing).
  With any of them on, the Treasury tab appears for every member with the addon, showing only
  what he turned on (the book behind its own button), and the balance shows under the Treasurer
  in the Realm. Each client takes his word from the King's addon and his Steward's alone, which
  repeat it every 5 minutes, and keeps the last one it heard: a member whose addon never met them
  online shows what that word shows (nothing, before any). (1.1, Konig's review: the Treasurer's
  book carried the word too, and a copy can't be told from one his addon made up or dated anew,
  so 1.1 takes none from it; 1.0's addons still read it there.) The King and his Steward
  always see all of it, whatever the switches, and the King the balance next to the soldiers on top of his window. **What he hides
  never goes on the channel from a keeper whose addon is 1.1**, which anyone on it can read: not
  in his book, not the guild bank, not the early supporters. His addon whispers it to the King,
  his Steward and the keepers alone (guild chat would reach every member of `<Olympus>`). What
  he shows goes on the channel, and every client on it receives it. A keeper still on 1.0 keeps
  sending his whole book on the channel, as 1.0 did, until he updates. A 1.0 addon of the army
  shows what the King shows, as before. A King's, Steward's or keeper's 1.0 addon is never
  whispered: it shows what the army sees of the books of keepers on 1.1, so, while the King
  hides the balance, a balance of zero (every switch off, as the King starts) or of only the
  parts he shows, as if it were the treasury's, until it updates. **The King, his Steward and
  the keepers should update to 1.1 first**; a 1.1 insider's Treasury tab names, in red, those
  heard lately still on 1.0.
- **Dues (1.1)**: one fixed amount of gold a week that members send the Treasurer by trade or
  mail, the same for everyone (1 gold until the King sets his; never a share of anyone's gold
  or loot). The King sets it on the dues page of the Treasury tab (his Steward too, in his name:
  dated, the newest wins, the King's on the same second); their addons repeat it, and only
  theirs: the Treasurer, who receives the dues, sets none of it (1.1, Konig's review: his addon's
  copy could set the amount, this week's too). A member's addon keeps the last amount it heard
  from them (1 gold before any). A new amount starts at the next weekly reset: the week it is
  set in keeps the amount it started with (the word carries it), so nobody who paid that week's amount turns
  under it afterwards, and each week is judged by its own. The dues page and the Send button's
  tip show the coming amount and the week it starts.
  - Every line of a keeper's book carries its week (from one weekly reset to the next), and
    each book keeps each giver's sum a week, for the last 5 weeks. A gift's guild is the one the
    game shows on the other side of a trade, the Treasurer's own roster for his guild's members,
    or the note a dues mail carries (the payer's word: it only places his own gold); otherwise
    "guild not known".
  - **Who sees what**: the King, his Steward and the Treasurer see every guild (its members in
    the census, how many paid the amount this week, the gold in, the percentage), and a guild's
    players a click away. A guild's Captains and Lord see their own guild's list: every member of
    their roster with his last payment, his gold this week, and above or below the amount (those
    below first). A player who paid with no guild on his payment (a mail without the dues' note)
    is in no guild's list: a Captain's page asks the Treasurer's addon about the members of his
    roster missing from his list, by five letters of each name's hash, and hears back about those
    alone (until then they show as "not known yet", never below). Above and below go by the
    week's amount as the King's word reached the viewer's own addon, never by the amount the
    Treasurer's list came with (the review of Konig's fixes: his addon, which receives the dues,
    decided who was under it). Where the two differ (one of the two addons has not heard the
    King's latest, or the Treasurer's is not the addon it says), the page says so and asks for a
    newer list, the King's table shows its "paid" as "?", and that list removes nobody. The
    army's Treasury tab keeps the King's three switches, and nothing of this.
  - **Clearing a seat (a guild's Captains and Lord)**: on their own guild's list, one click
    filters the roster to whoever is under the amount this week (never someone the Treasurer's
    list can't tell yet: a list still coming, or cut). A click picks one name; under it,
    **Remove <name> from the guild** asks first, then makes the game's own removal of that one
    member, as the Guild window's Remove does. Only where the player's rank may already remove
    members, only a member ranked below him, and checked again at the click. Never several at
    once, nothing at the weekly reset or on any timer, and never another guild's member: the
    King's and the Treasurer's view of the other guilds has no such line. The guild's size in
    the census frees no seat: only a removal does.
  - **Mail counts once the Treasurer takes it**: the Send button's mail goes to his mail
    character, whose own client alone takes it (and, in whatever guild or none, sends nothing);
    the Treasurer's addon reads that character's book from his account once it logs out. So a
    mail sent since, or not taken yet, is not in the lists, and cross-account gold mail also
    waits the game's own delay. A member with nothing in the Treasurer's book this week shows as
    "not in the book yet" (a plain "below" only with part of the amount); the page, the filter's
    tip and the removal's question say that a mail not taken yet is not counted, and when the mail
    character last played. **Remove** shows only with the Treasurer's list of the last 10
    minutes, counted by the King's amount; with an older one, or one counted by another amount,
    it says so, and a removal confirmed anyway does nothing and asks again.
  - **Send this week's dues**: a button on top of the Treasury tab, for every member on the
    Treasurer's realms (the tab is there for it even while the King shows the army nothing;
    a keeper has none: gold between keepers is a transfer). Its click fills in what the usual
    miss gets wrong, the person and the amount: with your mailbox open on its Send Mail tab, a
    mail to the Treasurer's mail character (Pyralis Andarai, where he asked the treasury's mail
    to go), the King's amount as money (never cash on delivery) and the note "Olympus fund
    <the week's first day> <your guild>"; with a trade open with the Treasurer (or his mail
    character), the trade's gold. You still press Send or Trade; closing the window sends
    nothing, and the addon never moves gold. Nothing fills itself in when the mailbox or a
    trade opens, and nothing pops up on loot. It never says you owe anything: nothing in
    Olympus depends on paying. With the gamepad interface it fills in nothing (the game's
    windows are its own there) and says what to send instead; where the game refuses the
    addon a trade's gold, it says so once and from then on tells you the amount to type.
  - **Never a switch**: nothing about the dues can turn anyone off. A guild that pays nothing,
    and its players under the amount, keep the census, the chats, the decrees and every Olympus
    feature (a test runs weeks of dues at 0% and checks it); nothing in Olympus is locked behind
    paying.
  - **Never on the channel** (a switch that only hid them would still send them to
    every client on it: a list of who is short): the week's donors leave every keeper's book as a
    count, never by name, and the lines of gold given to the Treasurer's characters (his book's,
    his mail character's he passes on, and 0.9's short copy) never leave his client: each is
    someone's dues, a name and his last payment. Every keeper's other lines still go, and the
    ranking of donors (all time) stays, as Fern said, but the Treasurer's books' part of it leaves
    out, of each giver's gold to his characters, each week's gold up to that week's amount (Konig's
    review: a ranked donor's total grew by the amount the week he paid it, which told who paid,
    and so who did not), and all he sent with the dues' note ("Olympus fund", as **Send this
    week's dues** writes it). A week's amount is the one his book kept while that week ran: the
    amount his addon knew then, raised when it hears a higher one, never lowered, and never changed
    by a later word of the King's (Konig's review again: worked out anew from each word, a second
    change of the amount re-judged the weeks kept and showed their payers); a backup keeps it. A
    total grows only by what a week's gold went over the amount, so one that did not grow may be a
    payer's or not (one that grew gave more than the amount that week). The limit: his addon hears
    the King's amount only from the King's or a Steward's addon while one of them is online, so a
    payer of a new amount it did not hear all that week, by trade or by a mail without the note,
    grows by the difference, which can tell that he paid. The tradeoff: it is that much lower
    than the Treasurer's own screen shows (his screen alone is whole), also for a donor who never
    meant it as dues. This holds on the channel, in the whole book whispered to the King, his
    Steward and the keepers, in 0.9's copy, in his mail character's book he passes on, and in the
    Discord copy of the Treasury tab, his own too (the review of Konig's fixes: his was whole);
    another keeper's book, which receives no dues, ranks as it is. It also
    holds after his book is restored from a backup, which keeps the weeks. The Treasurer's addon
    works the lists out from his books and whispers
    each one to whoever asks and may see it (the King or his Steward: any guild; a Captain or
    Lord: his own guild, his rank by the Treasurer's roster or the census), once every 5 minutes
    per asker, while the Treasurer shares his book. A list still coming, or cut to fit, marks
    nobody below who is not on it.
  - **Light on the channel**: a page that holds a list whole asks with its id, and the Treasurer's
    addon answers "the same list" in one whisper when nothing changed. One asker's answer waits
    once in its outbox (a newer one takes its place), his other messages (his book, the amount, a
    census report) go first, and when his outbox is full he says so in one whisper: the page shows
    it and asks again in a few minutes.

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

### Crafters' board (1.1)
"Who can make this?" is a chat scroll: the **Crafters** page of the Realm tab turns it into one
whisper to a named crafter (`/oly craft`).
- When you open one of your professions, Olympus reads it (its skill, and the recipes you know:
  their recipe and item ids, never a specialization tree) and asks once, in a window of its own,
  whether to list it. With your yes the board of every Olympus player of your realm and faction
  shows you: your name, guild, that profession and its skill. `/oly crafter off` takes you off at
  once; `/oly crafter on` lists every profession read again.
- **Ask who can make an item**: shift-click it after `/oly craft` (or type part of its name). The
  crafters listed who know its recipe answer by whisper, their addons by themselves; the page shows
  who can, with their skill and the item, and a click whispers one of them.
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

### World map
- Soldiers per zone on zone and continent maps, and per continent on the world map (with
  Blizzard's gamepad mode, only per continent: see below).
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

### Olympus Link: your Discord role (1.0.0)
Players in game prove to the Olympus bot on Discord that a character is yours, and the bot gives
you your role. No password, no Battle.net login, and nothing leaves the game before you say yes.

Not open yet: the addon carries it, but `/oly discord` says it is not open until the Olympus bot
is ready and its key is in the addon. Until then no addon makes, keeps, announces or uses a
confirmer key, and none asks for or signs a certificate.

The Olympus bot (Fernmelder's, on Discord) issues the codes, checks every proof and gives the role;
the Olympus Link page is a static page on this repository's GitHub Pages
(<https://dnl-gentile.github.io/olympus-addon/>, from `web/public/`) that only reads the proof and
sends it to the bot. The bot's side is in [`web/FERN.md`](web/FERN.md), every detail in
[`web/WORKER.md`](web/WORKER.md).

1. **Get a code** from the Olympus bot on Discord (its `/verify` command, in the Olympus
   server: only you see the reply). It looks like
   `OLC2.7K3M9QX2TB.your.name.1800000000.c.00000000.…` and is good for 24 hours. Keep it to
   yourself, and don't show it (or the Olympus Link window) on a stream.
2. **Type `/oly discord <code>`** in the game's chat (or `/oly discord` alone and paste it in the
   box: the bot's whole line, `/oly discord` included, is fine too). The addon checks the bot's
   signature and the expiry first, then asks: *"Link <Name> to the Discord account @your.name? …
   Only accept if @your.name is you."* The Discord account shown is the one the bot signed into
   the code: nobody can change it. Cancel sends nothing.
3. **Confirmers answer in game**, by addon whisper. A High Councillor online signs a proof that
   this character asked, with a key of their own that the bot certified (one is enough; they are
   asked one at a time, and a second councillor online is asked too, so two proofs can travel).
   When the bot allows it and no councillor is online, verified players drawn for your code are
   asked instead, five at once, and three must confirm. Nobody picks who is drawn: a key is
   drawn when SHA-256 of your code and its key id falls below the threshold the bot wrote into
   your code, and the code is new each time. Each confirmer also signs how it knows your guild:
   it is its own guild and its roster lists you, its `/who` saw you in it within 15 minutes, or it
   only has your word. When every proof only has your word, the addon says so and keeps asking
   for up to 10 minutes for one that knows it (a High Councillor who only had your word is asked
   again every 3 minutes: its quiet `/who` may have seen you since); then it finishes, and tells
   you the bot may refuse a guild nobody saw. No confirmer online? The request stays open until
   the code expires and is asked again when one comes online, and at each login.
4. **The proof reaches the bot** one of two ways:
   - **now**: the **Olympus Link** window shows a QR code and the same link in a copy box. On the
     Olympus Link page, share the WoW window, point your phone's camera at it, or paste the link,
     then sign in with Discord there and it goes to the bot. The proof rides after the `#` of the
     link, which a browser never sends to any server;
   - **or later, by itself**: the addon hands it to the bot's watcher (a High Councillor's
     character in watcher mode) the next time you are both online. The bot's keeper uploads what
     the watcher kept. One rule for how long, from your code's expiry: the bot takes the proof
     until 7 days after it, so the addon hands it to a watcher until 5 days after it (the keeper
     has 2 days left to upload it) and, after that, tells you to scan it: the window shows it until
     the bot's limit.

`/oly discord show` opens the window again, `/oly discord status` lists every character of your
account (waiting for confirmers, ready, delivered), `/oly discord forget` drops this character's
request and proof.

A character linked to one Discord account never moves to another by a new link: the bot refuses
it. To remove your link, use **Delete my link** at the foot of the Olympus Link page, signed in
with Discord: the bot takes the role away and deletes everything it keeps about your Discord
account (your linked characters, codes and their history) except how many codes and links you
used today, counted for a day at most. You can link again later with a new code (3 a day, the
ones before the delete included).

**For confirmers and watchers.** A confirmer's key belongs to one character, and so does its
certificate, which names it: another character of the same account confirms nothing with it.
**Every confirmer, High Councillors included, gets a key from the bot's keeper**, made on a
computer from a real random source (`scripts/link-keys.py confirmer`): an id and 43 letters, and
its certificate (a line starting with `OLK2.`, the bot's signature on the key's public half, its
tier, an expiry and your character's name). `/oly discord key <id> <key>` keeps the key for the
character you are on, then `/oly discord cert <certificate>` its certificate, which the addon
checks against the bot's key, your key's public half and your character before it keeps it; until
the bot's key is in the addon, both say Olympus Link is not open and keep nothing. `/oly discord
key` shows the key's id and public half (to compare with what was registered), `/oly discord
cert` the certificate's tier and days left. The key is never shown, sent, logged or written in
`/oly status` and `/oly bug`. `/oly discord key off` removes it; the old key keeps counting at
the bot until its keeper revokes it (the bot never asks your game), so it prints the old key's id
for you to send them, at once if it leaked. A new key comes from the keeper too. With a key and
its certificate, once the bot is ready, your addon says it is online every 5 minutes (the
certificate goes with it: requesters check it, and that it names the character announcing it,
before they ask you) and signs, by itself, the
requests of players of an Olympus guild of your faction: one a minute and five a day per
character, thirty a minute in all, never for the characters of your own account, and never when
what you know says otherwise (they claim your guild and your roster doesn't list them, or your
`/who` saw them in another guild in the last 15 minutes). A High Councillor taken off the signed
list stops at once in game (their addon confirms nothing, and nobody's asks them); at the bot,
their keys count until its keeper revokes their character. A High Councillor who could only take someone's word for their guild gets
their `/who` quietly with the next click in the Olympus window (mouse and keyboard only). High
Councillors can turn on `/oly discord watcher on`: the proofs players hand you are kept in your
SavedVariables once your addon has checked them (every signature against the certificate the
link carries, and enough for the bot), so made-up links never take a place. It keeps one link per
character (its latest: a newer one replaces it) and 500 in all, with no cap per code: a code's id
is public on a stream, and only the bot can check a link's tag, so a character that got a
councillor's real proof for itself with someone else's code takes its own place (the bot refuses
that link) and never the real requester's. Filling the inbox takes 500 characters; nothing
another character sent is dropped to make room, and an entry goes once the bot can no longer take
it, 7 days after its code expired.

The addon also carries a way for High Councillors' addons to make their own key in the game and
have the author's client certify it (the council authority), but it is **off**: a switch only the
author turns on (`ns.LINK_COUNCIL_AUTHORITY = false` in `Olympus/Link.lua`), and even on, nothing
of it runs before the bot is ready. WoW's Lua has no cryptographic random source, so a key made in
the game comes from a few tens of bits of frame timing, sits in plain text in the SavedVariables,
and its certificate would last a year (Konig's review of 1.0.0). While the switch is off no addon
makes such a key, asks the author's client for a certificate or signs one, and none takes one:
`/oly discord key new` says keys come from the bot's keeper, and a key an earlier version made in
the game is removed at login, with one line saying so.

### Everywhere
- **Copy**: every tab produces a ready-to-paste text for Discord.
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
  the Realm (guilds, Lords, Captains, members seen online), the
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
  down that side, the Workshop and then the Treasury move to the window's left edge, low, until
  the rest fit: the King's view with the Chat tab moves the Treasury alone, the author's preview
  both (1.1.1).
- **Blizzard's gamepad mode** (Forever's controller interface): Olympus asks its questions in
  windows of its own instead of the game's popups, which Blizzard's gamepad code blocks (and
  freezes) when an addon opens one. With mouse and keyboard, the game's popups as always.
  Since 0.9.8 it also leaves the game's own frames alone there: no quiet `/who` on its own
  (**Refresh** and **Find Olympus online** still search, and so does the King's click on his
  Throne's /who line for his key rotation, 1.1: the answer shows in the game's
  Who list), and the Issue Reporter is the game's to show. Since 0.9.9 it leaves the world map
  alone there too: no zone counts, decrees, crown or guildmate dots on it (the minimap keeps
  the crown and the dots, the Azeroth map its continent totals), because each of those went
  through the map library into the gamepad map's own state. If the game still says it blocked Olympus, a
  `/reload` clears it; to tell us what it was, open the Olympus window, press its help button
  (left of the X), then **Report a bug**. Don't type `/oly bug` with the gamepad: a command
  typed in the chat there can set the block off again.
- English and Portuguese in full, and since 1.1 Spanish, French and German for the main
  screens, the alerts and decrees, the Join screen and its whisper, the chats and the privacy
  questions (the rest in English; the pages' **?** explanations and the Answers of 1.1.2 are in
  English too). It follows the game language, and only the text on your
  screen changes: nothing sent between players does. `/oly status` shows the language in use.
  [CONTRIBUTING.md](CONTRIBUTING.md) says how to add a language or finish one.

## Install

**Easiest:** install **Olympus Guild** from the CurseForge app or WowUp. It installs in the
right place and keeps it updated. For Forever, pick the Forever (beta) installation of the
game in the app, not Classic Era.

**By hand:**
1. Download `Olympus-x.y.z.zip` from **[Releases](../../releases)**.
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
its own, and nothing it sends leaves the game. The one exception is
[Olympus Link](#olympus-link-your-discord-role-100), and only when you choose to link a
character: it uses a website (the Olympus Link page, on this repository's GitHub Pages) and the
Olympus bot on Discord, and the proof that a character is yours goes to the bot through that
page or a High Councillor's watcher. A confirmer (a key from the bot's keeper) signs other
players' requests by itself once the bot is ready, and those signatures reach the bot in their
proofs.

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

| What | Who receives it | When |
|---|---|---|
| Your guild's census: size, online count, classes, levels, rank names, the leader and officers (name, online, days away, class, level), addon versions | everyone on the Olympus channel | from one elected member per guild (and a runner-up), every few minutes |
| The census names people: your guild's leader and officers (above) and its five highest-level members (name, level and class), online or not, with the addon or not; the Realm's level race shows them | everyone on the Olympus channel | in every census report of your guild, from the member it elects: nobody named is asked |
| Zones in that census: members per zone (numbers only), a leader's or officer's zone | everyone on the Olympus channel | only if the member sending it shares their zone and layer; a leader's or officer's zone only if they share theirs too |
| Your zone, layer, guild rank and guild (layer announcements) | everyone on the Olympus channel | only if you share: officers and one member in eight announce, every 10 minutes and when their layer changes |
| A layer hop ask: the zone you are in and the layer you want | everyone on the Olympus channel | when you ask to hop |
| An answer to an ask for your layer (it tells the asker you are on it) | the asker alone (a whisper) | only if you share your zone and layer and said yes to layer help (1.1: off until you answer, on the first-open page or with `/oly layerhelp on`; `/oly layerhelp off` stops it) |
| [Olympus], [Captains] and [Lords] lines | everyone on the Olympus channel, all three | when you write one, only while the Olympus chats are on (1.1: off until you say yes, on the first-open page or with `/oly chat on`) |
| A pinned line (1.1): its words, your guild and, as on every message, your name | the King's, his Stewards' and Hands': everyone on the Olympus channel. A guild master's, and a higher rank's takedown of it: his guild alone (over guild chat) | when you pin one (only while your Olympus chats are on, never while the moderators have you off), again every 5 minutes while it lasts (2 hours at most, a `/reload` included), and when you take it down (`/oly pin off` with nothing pinned on your screen too, once a minute at most: a `/reload` on the Forever beta forgets your pin); a pin you took down (its number and your guild), when you take it down and again when its setter's addon repeats it, once a minute at most, never while the moderators have you off |
| A flag on the Board (1.1): your guild, level and class, the flag (dungeon, raid, PvP or layer), your note (with the logged API), and your zone only while you share it | everyone on the Olympus channel, and whispered to a player whose Board asked for the flags up | when you raise it, then every 10 to 30 minutes for an hour at most, until you lower it |
| The Board's ask (1.1): nothing but your name | everyone on the Olympus channel | once a session, the first time you open the Board |
| A signup (1.1): the Agenda entry, the role you claim (or that you withdraw) and your guild | whoever set that entry (the King, his Steward or a Hand), alone (a whisper) | only when you click Sign up |
| A signup sheet (1.1): the counts per role of each entry, no names, and when the next one comes | everyone on the Olympus channel | from the client of whoever set the entries, soon after a change, then every 5 minutes while one of them has signups or is within 2 days, every 15 otherwise |
| A camp on the Board (1.1): your guild, level and class, the camp's zone (never your spot) and your note (with the logged API) | everyone on the Olympus channel, and whispered to a player whose Board asked | only with `/oly location on`, when you drop it, then every 10 minutes for its 30 minutes, until you take it down |
| A net-off word (1.1): the character's name, hidden or shown again (or the guild's name, off or on again), the time, who gave it and the reason | everyone on the Olympus channel | when the King, his Steward, a Hand or a High Councillor gives one, then from the giver's own addon every few minutes for late logins |
| The army's key (1.1, when the King or his Steward rotates it): the new key, the time it was made and the hashes of the keys it replaces | each Lord and Captain the census confirms online in the guilds the King picks whom his own /who saw in that guild (a whisper from the King each), then each one's guild over guild chat; never the Olympus channel. Each 1.1 addon that has it tells the King so (a whisper), and after login asks its guild whether a newer key exists | only when the King rotates it on the Throne; a guildmate's ask once a login |
| Your alt links (1.1, only if you link your characters): each linked character's name and guild, and the names it confirmed (its main, or its alts) | everyone on the Olympus channel | from each character you linked yourself, confirmed on each: at login, when a link changes and every 30 minutes while you play |
| Hello: addon version, realm, public or sealed channel, whether you share your zone | your guild | every minute or so |
| Check version (1.1.2): nothing but a number to match the answer | the player you right-clicked, alone (a whisper) | only when you pick **Check version** (a player once every 2 minutes, 6 a minute) |
| The answer to a version check (1.1.2): your addon's version | the player whose addon asked, alone (a whisper) | when a player's addon asks: each once every 30 seconds at most, 20 a minute in all; never to a player you block or ignore, and to the author only after your yes to his roll calls (his checks are roll calls) |
| Ask to update (1.1.2): the newest version your addon knows | the player you right-clicked, alone (a whisper) | only when you pick **Ask to update** for a player on 1.1.2 or newer (a player once a day, 5 an hour); for an older one it only opens a whisper you send yourself |
| Your bug report (the same text as `/oly bug`) | the author alone (whispers) | only when you press **Send to** him in Report a bug, or **Send** in the window his ask opens (1.1.2) |
| The shared block terms (1.1): each word, whether it was added or removed, and when; for 15 minutes after an edit, the editor's own client adds his name to it (never to anyone else's) | everyone on the Olympus channel | only from the client of the King, his Steward, a Hand or a High Councillor: at once when they edit it, and every 10 minutes while they play (not when another client just sent the same list). Your own filter is never sent |
| Your position as a dot on the map | your guild | only with `/oly share` (off by default) |
| A Lord's mentor pair (1.1): the recruit's name to the Captain, the Captain's name to the recruit, as whispers in his words | those two players | only when the Lord clicks **Send both** |
| Join Olympus (1.1, outside an Olympus guild): "which guild should I ask?" (J1), and your request (J3: the guild you ask, your level and class) | the one member the screen asks: one found with `/who` at a search, and the one you are about to whisper | J1 at a search (one member every 15 seconds at most, none while a recent answer is known; while only one answer names the gates, one more member at once, three in 10 minutes at most) and just before a whisper (again if that member never answered); J3 with each whisper you send |
| The answer (J2): whether you take recruit whispers, the King's gates, and up to 8 guilds with room the census confirms, each with its free slots and up to 2 of its Lords and Captains online that two reports name (never the King) | the recruit who asked, alone | when a recruit's addon asks you, once a minute per recruit and 10 a minute at most (with do not contact on, a bare "no" to the rest) |
| A treasury keeper's book (balance, gold and items given and who gave them, the ranking) and the guild bank of `<Olympus>` (its gold and items) | the parts the King shows the army (his switches): everyone on the Olympus channel. The rest (1.1): the King, his Steward and the keepers alone, by whisper, never on the channel (from a keeper whose addon is 1.1: one still on 1.0 sends his whole book on the channel, as 1.0 did) | only after that keeper says yes (each keeper, the King too, is asked once; `/oly treasurer on\|off`), withdrawn at once when he turns it off, and again every 5 minutes while he plays, for clients that were offline |
| Your character's name and what you gave, when you give gold or items to a treasury keeper (by trade or mail): in the ranking of donors (the top 100, with each one's total), the items donated (with who gave each last) and the book's latest lines (1.1: never the lines of gold given to the Treasurer's characters, which are the dues; this week's donors only as a count, never by name; in the Treasurer's part of the ranking, your gold to his characters less each week's up to the dues' amount his addon knew that week, and less all you sent with the dues' note) | with the King's ranking or book switch on: everyone on the Olympus channel. Otherwise (1.1): the keepers, the King and his Steward alone, by whisper | while that keeper shares his book: his yes, and a donor is not asked |
| That you are taking donations, if you keep a book of the treasury (1.1), with your zone only if you share your location | everyone on the Olympus channel | only while you turn it on (**Taking donations**, `/oly donations on`): every 2 minutes and when your zone changes, off when you log out |
| A request to the treasury, if you are a Lord or a Captain (1.1): the item's number, the count, your guild | the treasury's keepers, the King and his Steward heard online (their addon 1.1 or later), by whisper; while the King shows the army the book, the open ones also on the Olympus channel, from the keepers' addons | when you ask (a click on an item, or `/oly need`; 6 new requests an hour at most), then every 15 minutes while it is open |
| Your guild bank's snapshot, if you are the guild master or an officer of an Olympus guild other than the King's (1.1): items and counts, its gold, when it was seen (not the tabs' names) | the King, his Steward and his Hands alone, by whisper, when their addon asks (never on the Olympus channel) | only after your yes (asked once when you open the bank; `/oly bank share on\|off`); your no takes it back from their screens: at once from those whose addon asked in the last 18 minutes, from the others at their next ask while you are online (one never heard again keeps it until he logs out) |
| Your character's name, if you gave to the treasury before 1.0 (the early supporters): names only, no amounts, in alphabetical order | with the King's ranking switch on: everyone on the Olympus channel, shown under the ranking. Otherwise (1.1): the keepers, the King and his Steward alone, by whisper | from the Treasurer's addon once he said yes to 1.0's question or to his line on the first-open page, both of which say their names go to everyone on the channel (his 0.9.3 yes is not enough), after his login and when a client asks: a donor is not asked |
| The dues' amount (1.1): one amount a week, the same for everyone | everyone on the Olympus channel | from the King's and his Steward's addons alone, when they set it and every 5 minutes |
| Your guild's dues list (1.1): each of its players who paid the Treasurer in the last 5 weeks with that guild on the payment (name, gold this week, hours since his last payment), how many hours ago the Treasurer's mail character last played, and a digest (with a secret of his session) that changes when this week's payers with no guild change | the King, his Steward, or a Captain or Lord of that guild who asked, alone (whispers from the Treasurer's addon); when nothing changed, one whisper saying so | when they open the dues page, once every 5 minutes per asker at most, while the Treasurer shares his book |
| A Captain's ask about his roster (1.1): five letters of the hash of each name on his guild's roster missing from its dues list | the Treasurer alone (whispers) | from a Captain's or Lord's dues page while this week's list says some paid with no guild on it, when that changes or his roster does, once a minute at most |
| Its answer (1.1): which of those codes paid the Treasurer this week with no guild on the payment, with the gold and the hours since | that Captain or Lord alone (whispers from the Treasurer's addon) | once per ask, as many codes as the guild has members at most |
| Every guild's dues this week (1.1): how many paid the amount, the gold in, how many players | the King or his Steward who asked, alone (whispers from the Treasurer's addon) | when they open the dues page, once every 5 minutes at most |
| An ask for a dues list (1.1): the week, the guild and the id of the list already held | the Treasurer alone (a whisper) | while the King, his Steward, a Captain or a Lord has the dues page open, once every 5 minutes per list |
| The dues' note (1.1): the fund, the week and your guild's name, in the subject of the mail the Send this week's dues button fills in | the Treasurer's mail character, in your mail | only when you click that button and then press Send yourself |
| The King's crown on the map, and with it his zone and layer | everyone on the Olympus channel | only while the King turns it on (Throne tab), whatever he answered to the question |
| A Royal Inspection's report (1.1: off until you say yes, on the first-open page or with `/oly inspection on`): when the King, his Steward or a Hand calls one and your addon is in the sample, it patrols for 2 minutes, inspecting the Olympus players of your faction around you, level 15 and up, with the game's own inspect, and records whether each wears the guild tabard, another one or none (kept in your saved variables); then it reports your guild, how many it found in each case (your own tabard counted) and up to 6 names, with their guild, of players caught without the colors | whoever called it, alone (a whisper); the King can show the names to the army on his untabarded list | each Royal Inspection you are sampled for (one every 30 minutes at most, for the whole realm), once you said yes and until `/oly inspection off`; you still get its raid warning either way |
| An officer's patrol findings (1.1): the name and guild of each player your own inspections caught without the colors or with another tabard (or wearing ours again after that), and how long ago | your guild's officers (a guild addon message: every guildmate's client receives the bytes, and only officers' addons keep them), for their Tabards pages alone: never the King's untabarded list, nor a Royal Inspection's report | only while you are an officer (the guild master or the rank right below) and said yes (1.1: off until you answer, on the first-open page or with `/oly patrolshare on`): each new finding once, at most once a minute, and the day's findings when another officer's addon asks (once a session: after its login, or at its officer's yes if later); `/oly patrolshare off` stops it. Nothing more is inspected for it |
| A loot note (1.1): an officer's words, the item and whom it went to; a member's points set by hand; and your addon's ask for the book (the spans of change times it lacks) | your guild (guild addon messages): every guildmate's addon keeps the notes and points; the ask is answered by one officer's addon, with the changes in those spans | a note or points when an officer writes or removes them (only officers do); the ask when the Loot notes page opens (an officer's at login), again after each answer while the book lacks something (16 a session at most) |
| Your crafter listing (1.1): your guild, and each profession you listed with its skill and how many recipes you know | everyone on the Olympus channel | only after your yes when you open that profession (asked once), once at login, then every 45 minutes while you play, and after a change: a profession listed or taken off (2 minutes after the last at the soonest), a skill up or a new recipe (10 minutes); `/oly crafter off` withdraws it at once |
| An answer to "who can make it" (1.1): your guild, the profession, your skill and the recipe and item ids of up to 6 recipes that match | the asker alone (a whisper) | only while you are listed, to asks heard on the Olympus channel, by your addon by itself (10 a minute at most) |
| Your recipes of a profession you listed (1.1): their recipe and item ids | the player who clicked "Show his recipes" (a whisper) | only while you are listed, on his click, once each 2 minutes to the same player: a part each 6 seconds, two players' lists at a time (the next is told you are busy) |
| Your ask "who can make it" (1.1): the item's id, or the words you typed | everyone on the Olympus channel | when you ask (one each 15 seconds at most) |
| Other players' lines in the Olympus chats as your addon accepted them (channel, sender and text; [Captains] and [Lords] only if your rank reads them), and the High Council list | other addons in your own game, through `OlympusBridge` (made for OfficerSpy, the moderators' companion addon, but any addon you install can read it) | always, while such an addon is loaded (no chat line while the Olympus chats are off on your client): Olympus sends nothing through it and never learns what that addon does with what it read |
| Olympus Link (1.0.0): a request (your guild, faction, a random number, your code's id and a tag made from your code's signature and your name) | the confirmers asked (a whisper each): a High Councillor, or verified players drawn for your code | only after you press **Accept** on `/oly discord <code>` |
| Olympus Link: the finished proof (your character name, realm, guild, faction, the tag, and the confirmers' names, how each knew your guild, their signatures and their keys' certificates) | the Olympus bot, through the page you scan it with, or a watcher (a High Councillor, by whisper) who hands it to the bot | when it is ready, until it is delivered (5 days after your code expired at most) |
| Olympus Link, if you confirm (a key and its certificate from the bot's keeper, High Councillors' too): your proof for another player's request (its time, your key's id, how you know their guild, your signature), and in their finished proof your character's name and your key's certificate | that player alone (a whisper), then the Olympus bot in their finished proof | by itself, without asking you each time, once the bot is ready: only for players of an Olympus guild of your faction, never your own account's characters, one a minute and five a day per character, thirty a minute in all, until `/oly discord key off` |
| Olympus Link: "a confirmer's key is online" (its certificate: the key's id, public half, tier, expiry and character), "a watcher is online" | everyone on the Olympus channel | every 5 minutes, only from characters with a key from the bot's keeper and its certificate, once the bot is ready (no addon makes or announces a key by itself), or a High Councillor's watcher on (`/oly discord watcher on`) |
| Olympus Link: a High Councillor's key's public half, and the certificate for it | the author's character, and back (a whisper each) | never while the council authority is off (as it ships: only the author turns it on, and only once the bot is ready); then only from a councillor of the signed list whose addon made its own key, once a session when it hears the author |

Decrees and the King's calls go out when someone sends one (a decree carries its sender's
position on the map).

**What waits for your yes.** Your zone and layer (below), layer help, your dot on your guild's
map, a treasury keeper's book, a sister guild's bank (1.1), a Royal Inspection's report, your answers to the author's roll
calls, the Olympus chats, an officer's patrol findings to his guild's officers, your crafter
listing (and with it your addon's answers to who can make it) and Olympus Link (your **Accept**, or a confirmer's typing in the key the
bot's keeper made them) wait for your yes. The rest of the table goes out while you are in an
Olympus guild, with no question first: your guild's census (from the member it elects, with the
names above), the hello and your addon's answer to a version check (1.1.2), an officer's loot notes and points to his guild and your addon's ask for what its book lacks
(when the page opens), and what other addons read through the bridge.

**The first-open page (1.1).** It is the first question the addon asks. About 45 seconds after
login, or when you open the Olympus window first (never in combat or in an instance, once a
session, while something on it has no answer), a page of its own says in plain words what always
goes out (the census, with the names it carries, and the hello) and asks **Yes** or **No** for
each of the rest: your zone and layer, layer help, your book of the treasury (keepers only), the
Royal Inspection, the author's roll call, the Olympus chats and your patrols' findings to your
guild's officers (officers only). Each one stays off until its Yes.
No on the chats means this client neither sends nor shows [Olympus], [Captains] or [Lords]. The
window, the census and your own guild's roster work whatever you answer, location included.
`/oly privacy` opens the page again, and each answer has its own command too (`/oly location`,
`/oly layerhelp`, `/oly treasurer`, `/oly inspection`, `/oly rollcall`, `/oly chat`,
`/oly patrolshare`). It is
Olympus's own window, never the game's popup, so it works with Blizzard's gamepad UI. The
author's update notices, which send nothing, still show until you say No to his roll call. The
Treasurer's line says what his 0.9.3 yes still sends until he answers there (his book), and that
his Yes also sends the early supporters' names to everyone on the channel, as 1.0's question
did. On the Forever beta, whose saved variables never load, the page asks again every session.

**Zone and layer: off until you choose.** Once after login (never in combat or in an
instance) the addon asks whether to share your zone and layer, saying what goes out and who
reads it: since 1.1 on the first-open page (the question's own popup only on a client updated
without restarting the game). Until you answer, and after **Keep private**, it announces no
layer, and the census
your addon sends for your guild names nobody's zone and counts nobody per zone. **Share**
turns both on. Change it any time with `/oly location on` or `/oly location off`; `/oly status`
shows it. Layers and hops work better the more members share. Versions before
0.9.1 still send all of it: update.

**How long it lasts.** A layer you announced shows on other screens for up to 21 minutes
after your last announcement. Turning sharing off (or the King hiding his crown) withdraws it
at once from 0.9.2 clients; older ones keep it until it expires. Your location is always your
own message: nothing relays another player's zone or layer, and nobody can withdraw yours.

**Public or sealed channel.** Without a realm key the Olympus channel ("OlympusNet", the
Horde's "OlympusNetH") is public: anyone can join it by name and read everything on it with a
script. With a key (`/oly key`) it gets a hidden name and the key as its password, and only
the key's holders can join. A shared key is only as private as its least careful holder:
every member of every guild that has it can read the channel, anyone can pass it on, and
nobody can take it back. If it leaks, the King or his Steward rotates it for the whole army (1.1, on the
Throne: a new key by whisper to the Lords and Captains his /who saw in the guilds he picks and
over guild chat, never on the Olympus channel), or officers set a new one (`/oly key <new secret>`) and
hand it out again.

**Chat is never private.** Every client on the channel receives [Olympus], [Captains] and
[Lords] alike; the addon only decides what to show. Before your first line in each of them
the addon says so and waits for **Send** (**Cancel** sends nothing), once per channel. Since
1.1 the chats are off until you say yes (the first-open page, or `/oly chat on`): off, this
client neither sends nor shows them, and a line that arrives is dropped before anything keeps it.

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
character only) shows one of the six round his own portrait, and on his target frame when he
targets himself, and its nameplate mark after his own name on his player frame and on every
friendly player's nameplate (`/oly borders test member`: the member's star alone), on his screen
alone until `/oly borders test off` or a `/reload`. It follows the borders' and the marks' own
rules (none with the gamepad UI, made out of combat), and nothing is sent.

The addon is plain Lua running on each player's computer, so anyone can edit their own
copy. No addon can prevent that. What this one does is check what every copy sends; what a
few characters working together can still reach is said plainly further down
([What colluding characters can reach](#what-colluding-characters-can-reach)):

- **Guild traffic is verified by Blizzard's servers.** Guild addon messages only reach
  members of that guild, so the realm key and guild elections can't be faked from outside.
- **Sender names cannot be forged.** The server stamps every message with its sender.
  - **The King and the Treasurer are known by name**, not by vote: only their characters can
    send their commands and the treasury (with the characters the King names to the treasury,
    whose books count while his list names them: a list taken from his character or his
    Steward's alone, never from a keeper's book). A report of `<Olympus>` naming anyone else as its
    leader counts for nothing, not even as a vote: no count of votes makes anyone else its King.
    Since 1.0.0 the King's decrees and [Lords] lines count by his name too, with no census.
    Their names count on their realm group only (Forever's PvP realms): a namesake anywhere
    else is someone else, and there is no King there.
  - **The King's Steward** (1.0.0) is named by the author's signature, like the High Council:
    a character the signed titles list marks, for his realm group and his King's faction, and
    nobody else (no name in the code, no vote). His word counts by his name, which the server
    stamps: a list of Hands of his own, beside the King's, whose Hands have the same Crown for
    `<Olympus>` on the other guilds' clients (nobody changes anyone else's list: the King can't
    take them back);
    the treasury's keepers and its switches, dated, the newest kept and the King's newer word
    always over his; and the Crown's decrees for `<Olympus>` on every client; and he sees the
    whole treasury as the King does, whatever the switches (every keeper is told so before
    sharing). Never the King's own list of Hands, his crown on the map, his court, writs,
    pardons, untabarded list, book or yes. This adds trust in the author's key: whoever holds it
    can make a character act for the King in these, as it can name the council. A newer signed
    list without him ends it, and the Hands he named with it, on every client at once. A word of
    the treasury dated more than a minute ahead of the server's clock is not taken.
  - A decree counts only if its sender is the Lord or a Captain of that guild as the census
    pictures it (below), or as our own roster says for our own guild; the King's by his name.
    The rank written inside the message is ignored. Since 1.0.0 a sender speaks for one guild
    in decrees as in the chats, and a decree's words go out with Blizzard's logged
    addon-message function (a decree that arrives any other way shows without its words).
  - **Ranks come from the picture most senders agree on.** Every report from the last 30
    minutes is its sender's vote on who leads the guild and who its officers are. One sender
    changing or repeating a report can't move the majority. When two pictures have as many
    senders each, only what both agree on counts. No Crown rank counts in a client's first
    3 minutes, so a guild's own reporters have voted before anyone else can win.
  - A report never proves its own sender's rank: someone else's vote must name them. The
    runner-up of each guild's election also reports every 10 minutes (and answers census
    requests), so a Lord or officer who is the elected reporter is still verified. (An officer
    who is the only one of their guild with the addon is not.)
  - **The Crown** (any guild master) needs two senders naming them, and one of the two may be
    that Lord himself (see below). The officers of `<Olympus>` are of the Crown only on
    `<Olympus>` members' clients, from their roster (1.0.0), and the Hands the King's list or a
    Steward's own list names (their word, never a vote; the King can't take back a Steward's
    Hand: that Steward does, or the author by removing him): everywhere else they count as
    Captains, so outsiders' reports can't add one to the Crown.
  - A sender speaks for one guild only (a player who changed guilds can speak for the new one
    after 15 quiet minutes). A guild is one whatever the capitals a report spells it with: a
    second spelling is a vote on the same guild, never a second guild.
  - **The row everyone sees is the majority's**: a report whose leader or officers differ from
    the picture most senders give is counted as a vote but does not replace what the census
    shows, so one outsider can't rename a Lord. A guild's numbers are not part of that picture
    (see below). A report claiming more members than a guild can hold is dropped as forged. A
    guild not heard from for a day leaves the total.
- **Only our channel counts**: addon messages that arrive on any other chat channel are
  ignored, so the sealed channel really keeps outsiders out.
- **Sealed channel** (`/oly key`): outsiders can't find the channel or join it.
- **The Join screen** (1.1): outside an Olympus guild the addon hears one message alone, a
  member's answer to its own question, and only from the member it asked in the last minute;
  a guild it names counts only if it is an Olympus guild. A member answers each recruit once a
  minute and ten a minute in all. A recruit's request shows only for your own guild, once per
  ten minutes per recruit, thirty kept at most, six chat lines a minute at most.
- **Validation**: every number is range checked, names are length limited, and malformed
  messages are dropped. Decrees are rate limited per sender (one a minute) and in total (6 a
  minute from senders only the census vouches for; since 1.0.0 the King's, his Steward's, the
  Hands' for `<Olympus>` (the King's list or a Steward's) and your own guild's officers' never
  wait behind that limit).
- **Admission** (0.9.3): one sender gets 60 messages at once and 2 a second after that, whatever
  they are; past it their messages are dropped unread. Pieces of long messages waiting for the
  rest are capped (4 per sender, 400 in all), so nobody can fill memory with pieces that never
  complete.
- **No escape codes from anyone** (0.9.2): every message from another player loses its "|"
  codes (colours, textures, links) and control bytes before anything reads it, so nobody can
  put a texture, a fake link or a fake line on your screen. Chat keeps only item, spell and
  quest links shaped the way the game makes them. Text the addon builds for Discord pings
  nobody. The offline tests send hostile messages for each of these rules and check they
  are refused.
- **Channels**: [Captains]/[Lords] lines count only if the sender's rank is verified like
  decrees; everyone else can use [Olympus] only. Sent with Blizzard's logged addon-message
  function (lines sent any other way are dropped); rate limited per sender and per channel, and
  no single sender can fill a channel.
- **Olympus Link** (1.0.0): the bot's codes carry an Ed25519 signature every addon checks
  against the bot's public key, written in `Olympus/Link.lua` (`ns.LINK_BACKEND_KEYS`), so the
  Discord account the question names is the bot's word. Each proof is an Ed25519 signature by a
  confirmer's own key, which is one character's and certified for that character by the bot; the
  bot's keeper makes every key on a computer, a High Councillor's too. (The council authority, the
  author's own client, could certify High Councillors' keys made in game, `ns.LINK_CA_KEYS`, its
  private key on his computer only and never printed, logged or sent; that path is off,
  `ns.LINK_COUNCIL_AUTHORITY`, and while it is off no addon takes its certificates.) Nothing of a
  key is made, kept, announced or used before the bot's key is in the addon. A requester asks only
  confirmers whose certificate checks and names the character that announced it (a "c" counts
  only from a name on the signed High Council list), counts a proof only once its signature
  checks with the certified key and it was signed within its code's life, and carries each
  proof's certificate in the link. The bot keeps only the public halves, can revoke one (a
  council authority's key too: a revocation list), and checks every proof again (the
  certificate, the signature, the key's owner and character, the time, the draw, how the guild
  was known). A proof is bound to its code and requester by a
  tag made from the code's signature, which never leaves the command you pasted: someone who sees
  your code's id on a stream can't make a link for their own character with it. The addon signs
  and checks in small slices over several frames, so the game never stops for it.
  `Olympus/Ed25519.lua` is checked against RFC 8032's vectors and signs byte for byte as Python's
  `cryptography` does, and the offline tests hold every slice to the game's Lua 5.1 rule (no
  yield across a pcall, a sort, a gsub, a metamethod or a generic for's iterator). No key is made
  in the game unless the author turns the council authority on (Konig's review): such a key comes
  from the best the client offers, which is no cryptographic random source (sub-millisecond frame
  timings, the time, the game's generator, table addresses, the cursor and the character, over
  eight frames, through SHA-512; the comment in `Link.lua` says what an attacker could guess), so
  every key, a High Councillor's too, is made on a computer by the bot's keeper, and a key an
  earlier version made in the game is removed at login.
- `/oly block <name>` ignores a player completely.
- **Block terms** (1.1) only hide lines on each screen: no word can ignore, block, kick or cut
  anyone off. The shared list is taken only from the King's, his Steward's, a Hand's or a signed
  High Councillor's character (the server stamps the sender), newest time first word by word, a
  time more than a minute ahead of the server's clock refused, and each player can ignore it.
  Its words are 4 letters at least and it never hides the King's writs (1.1, Konig's review:
  one editor adding "the" or "de" could hide nearly every decree and writ for everyone).

### What colluding characters can reach

Votes are counted per sender name, and nothing the server tells an addon proves which guild a
sender belongs to: a census report is its sender's word. So a few characters working together
can still reach the following today (1.0.0); each outcome was checked against this version's
code.

- **Two characters make a Lord.** Two characters, even two alts of one account logged in one
  after the other (a report counts as a vote for 30 minutes), make one of them the Lord of a
  made-up Olympus guild on every client. He gets [Lords] lines and the Crown's decrees (a Royal
  decree, a Tabard inspection) as raid warnings on every screen, for as long as their reports
  keep coming (15 minutes after the last one). Anyone who really founds such a guild can do
  the same.
- **One report makes Captains.** One character's report names others the officers of a
  made-up guild. On every other client each of them is a Captain, with [Captains] lines, Calls
  to Arms and Musters. Six of them fill the army's flood guard (6 decrees a minute) with raid
  warnings, and every other decree that a census rank vouches for is dropped for that minute.
- **A real guild: two contest it, three take it.** A real guild is pictured by its reporter and
  runner-up, two votes at most. Two outsiders who send another picture leave it contested: its
  Lord and officers lose their rank on every other client ([Lords], [Captains], their decrees)
  while the two keep voting. Three make theirs its picture: their Lord is of the Crown, the
  real one nobody. Two alts who join a real guild with names that sort first in its election
  become its reporter and runner-up, and name whom they like.
- **`<Olympus>`.** Its King counts by his character's name: no count of votes makes anyone else
  King or silences him. Three outsiders can still add one of their own to its officers in the
  census. Before 1.0.0 that made him of the Crown on every client outside `<Olympus>`; since
  1.0.0 the officers of `<Olympus>` are of the Crown on its own members' clients only (their
  roster), and a census officer of `<Olympus>` is a Captain everywhere else, unless the King's
  list or a Steward's own list names him a Hand (their word, never a vote).
- **Numbers.** A guild's size and online count are not part of the picture. One outsider who
  copies a guild's leader and officers with other numbers shows his numbers on every screen
  until its reporter's next report (800 members as 1, the King offline). Each made-up guild
  adds up to 1,000 soldiers to every client's army total for a day, and one character can
  start a new one every 15 minutes.
- **Trust elsewhere.** A made-up Captain who answers a layer-hop ask is a helper the addon
  vouches for, so his party invite is accepted for the player (never with the gamepad UI). His
  report on a Royal Inspection can put an innocent player on the King's untabarded list, which
  the King's share sends to the army. A made-up Captain of a real guild (above: three
  outsiders take its picture) can ask the Treasurer's addon for that guild's dues list (1.1):
  who of it paid him in the last five weeks, how much this week and when last; never another
  guild's list, and never on the channel. He, or any real Captain, can also ask about names of
  his choosing as his "roster" (nothing proves a roster is his), as many as his guild counts and
  once a minute, and hear which of them paid the Treasurer this week with no guild on their
  payment. A dues mail sent with the button carries its guild, and so does a trade: only those
  who pay without either can be found that way.
- **The King's new key (1.1).** Two characters who make a Lord of a made-up guild (above) are
  listed among the guilds the King can hand a new army key to when he rotates it. That guild is
  not checked unless his own /who saw a guild of that name, and he can uncheck any guild. Either
  way his addon whispers the key only to the Lords and Captains his own /who saw in that very
  guild (the server's word), so two characters who call themselves a real guild's Lord and
  Captain in the census get nothing either. Anyone in a real Olympus guild he picks gets the key
  from its officers, whoever leaked the old one. (Every member of an Olympus guild that has the
  key can read the sealed channel anyway.)

What 1.0.0 hardened: the King's decrees and [Lords] lines count by his name, with no census at
all, and the Hands' for `<Olympus>` by the word of the King or of the Steward whose own list
names them; those, the Steward's and your own guild's officers' decrees never wait behind the
flood guard, however many made-up Captains fill it; a decree speaks
for one guild per sender, as the chats do; a decree's words go out with Blizzard's logged
addon-message function (one that arrives any other way, from a sender before 1.0.0, still
shows, without its words); and the officers of `<Olympus>` are of the Crown on its own
members' clients only, and elsewhere only the Hands the King's list or a Steward's own list
names (the King can't take back a Steward's Hand: that Steward does, or the author by removing
him).

On the public channel anyone can try all of the above; **seal it with `/oly key`** and only
members of Olympus guilds can (any of them still can). The structural fix is **signed
leadership, planned for 1.1**: ranks that come with a signature every client checks, instead
of a count of votes.

Other limits:
- **The Forever beta forgets addon data at every login**: its client saves it but never loads
  it back ([a known beta bug](https://us.forums.blizzard.com/en/wow/t/savedvariables-never-load-in-the-beta-%E2%80%94-all-addon-settings-reset-on-login-69913/2354798)),
  so settings and the realm key reset every session. The census still refills in seconds: a
  client that logs in asks the channel, and each guild's reporter and runner-up answer at once.
- A real Olympus member who edits their copy could still send a wrong report for **their own**
  guild. Their guildmates' reports make it visible, but it can't be made impossible: since 1.1
  the census marks a row whose senders disagree on its leader, its officers or its size, and,
  fainter, one that a single sender stands behind (hover it for what the mark says).
- **Net-off is its issuers' word (1.1).** One Hand or High Councillor can hide anyone who gives
  no words (and neither the King nor his alts) for the whole army, or take any guild but the
  King's off the network. The Decrees tab shows everyone who did it, why and when, and who
  passed it on; an issuer as high or higher (the King always) can put it back on, and no word
  replaces one from higher up. Only the King, or the Steward for a Hand or a councillor, can
  hide an issuer, and a name that is hidden gives no word: its words fade. Without signatures, one issuer can still write a word in another
  issuer's name: the addon then shows who passed it on, his reason stays off the King's
  stream, the word weighs no more than his own rank, and no addon repeats it.

## Built for a crowd of thousands

- One summary per guild about every 3 minutes, not one per player.
- A census request (every login sends one) is answered with the next summary sent early, never
  an extra one: however many players log in, a guild's reporter still sends one summary about
  every 3 minutes and its runner-up one every 10. A client that heard a summary after asking
  does not ask a second time.
- In a full guild only the members who could be elected keep saying hello; the rest go quiet.
- Layers are announced by officers plus a stable 1 in 8 sample who share them, every 10 minutes
  (the King's alone every minute, while his crown shows: one client, one message a minute).
  Announcements from other zones redraw the window at most once every 5 seconds.
- A layer request goes out once; only about 6 players answer it, each by a whisper to the asker.
  After a request that found nobody the next one waits 20 seconds, then 60, then 3 minutes; and
  when more than 10 players asked for the same layer in the last 10 seconds, a new request goes
  out a few seconds later.
- The Royal Inspection is limited to about 20 inspect requests a second for the whole realm
  (see the Throne), and the quiet `/who` a click in the window makes goes once a minute at most.
- Tabard inspections are kept for two weeks, 2000 players at most (marked and caught players
  first); the Tabards page lists the first 200.
- Messages are spaced 1.2 s apart, below Blizzard's addon message limits, and alert sounds
  play at most once every 15 seconds (1.1: a softer one never silences the Call to Arms or a
  louder alert after it).
- Chat has its own short lane: a line goes out within about a second, and while reports are
  waiting it never takes more than every other message slot.
- The Board (1.1): a flag is repeated every 10 minutes while the Board is small, every 30 when
  it holds 150, so the channel carries about the same whatever the crowd. The ask a player's
  Board sends once a session is answered by whisper, by about 40 flag holders at most, and
  nobody answers past the first 4 asks of a minute (`ch:G1`, `ch:GQ` in `/oly status`).

## Commands

| Command | |
|---|---|
| `/oly` | open or close the window |
| `/oly realm` · `/oly decrees` · `/oly tabard` | open a tab |
| `/oly inactive [7\|14\|30]` | your guild's members offline that long, by name (a rank that may remove members removes one per click, asked first) |
| `/oly warndays <days>` | when a Lord or Captain counts as away: red in the Realm, and one line when a Lord crosses it |
| `/oly recruits` | Lords: your recruits, and a Captain as each one's mentor (one whisper to each, from your click) |
| `/oly nocontact on\|off` | do not contact: recruits' Join screens skip you (on), or may ask you (off) |
| `/oly patrol` | start or stop the tabard patrol |
| `/oly mark [note]` | mark your target |
| `/oly gear` (or **Inspect gear** on the Tabards tab) | officers: inspect the player you target (in range) once and keep what he wears, under **Gear seen** on the Tabards tab; nothing is scored or sent |
| `/oly patrolshare on\|off` | officers: pass what your inspections find to your guild's officers and take theirs (off until you say yes, here or on the first-open page), or not |
| `/oly loot` | your guild's loot notes and points on the Realm tab (its officers write them; not a bid window) |
| `/oly craft [item or name]` · `/oly crafter on\|off` | who can make it (the crafters' board on the Realm tab: shift-click an item after `/oly craft`); list your professions read so far, or take them off |
| `/oly approved` · `/oly approved paste` | the guilds of Asmon's Olympus the author's signed list makes Olympus guilds (their names don't say Olympus), and whether yours is one; paste that signed list (the first member of such a guild: his addon then passes it to the guild) |
| `/oly arms [text]` · `/oly muster [text]` | send a decree (`test` = local preview) |
| `/ol <text>` · `/olc <text>` · `/oll <text>` | write in [Olympus], [Captains] or [Lords]; alone (`/ol`, `/olc`, `/oll`): open the Chat tab on that channel (1.1.1) |
| `/oly all <text>` · `/oly captains <text>` · `/oly lords <text>` | the same, as `/oly` commands |
| `/oly mute olympus` · `/oly mute captains` · `/oly mute lords` | hide or show a channel in chat |
| `/oly pin <text>` · `/oly pin off` · `/oly pin` | the King, his Stewards and Hands: pin one line for the army on top of the Olympus chats and the Realm (2 hours); a guild master: one for his own guild. Take it down, or see what is pinned |
| `/oly chatwindow tab` · `/oly chatwindow <number or name> [olympus\|captains\|lords]` · `/oly chatwindow main` | the Olympus chats in a chat tab named Olympus (without the channel's name; it says how to make the tab), in another chat window (with Chattynator, one of its tabs, by name), or back in the main one |
| `/oly treasurer on\|off` | a keeper of the treasury (the Treasurer, the King, a character he named) shares his book and the guild bank, or keeps them private (1.1: what the King hides goes only to the King, his Steward and the keepers, by whisper) |
| `/oly backup` · `/oly restore` | copy a backup of your treasury book and your settings as text, or paste one back after a wipe (nothing is sent anywhere, never the channel key) (1.1) |
| `/oly donations on\|off` | a keeper of the treasury tells everyone with the addon he is taking donations (a line on the Realm and Treasury tabs, with his zone if he shares it, one line in the [Olympus] chat), until he logs out (1.1) |
| `/oly need <count> <item>` · `/oly need` | Lords and Captains: ask the treasury for an item (shift-click it into the chat line, or its name or number); alone, your requests and where each stands (1.1) |
| `/oly bank share on\|off` | the guild master or an officer of an Olympus guild other than the King's shows his guild bank's snapshot to the King, his Steward and his Hands (by whisper, never on the channel), or not (1.1) |
| `/oly rollcall on\|off` | answer the author's roll calls (version, client, channel state) or not (1.1: not until you say yes) |
| `/oly privacy` | the first-open page again: what the addon shares, and your Yes or No to each (1.1) |
| `/oly chat on\|off` | the Olympus chats on this client; off, nothing is sent or shown (1.1: off until you say yes) |
| `/oly talk [olympus\|captains\|lords]` | open or close the Olympus window on its Chat tab, on that channel; also `/ol`, `/olc` or `/oll` with nothing after it, or Shift-click the minimap button (1.1.1) |
| `/oly inspection on\|off` | take part in the King's Royal Inspection when sampled (a 2-minute patrol reported to him), or not (1.1: not until you say yes) |
| `/oly issuereporter hide\|show` | hide Blizzard's Issue Reporter box (beta clients) at every login, or show it again (also a "Hide" button on it) |
| `/oly helpme [text]` (or **Ask a High Councillor** on the Realm tab) | ask the High Council (the moderators) for help: it goes by whisper to up to three of them online who take requests |
| `/oly council list` · `/oly council help on\|off` | the High Council as your addon knows it; moderators: take help requests or not. The list is signed by the author on his own computer and checked by every client: no name is written in the addon's code, and nobody can forge or change it. An addon without the list (`High Council: -`) asks the channel for it a minute or so after login, and again until it has it (two and a half minutes later when nobody answered, up to 3 times). Since 1.0.0 the list also crosses realms through guild chat: guildmates on another realm answer the ask and pass the list on, and it goes on to your realm's channel |
| `/oly council icon` (or **My council icon** on the Realm tab, councillors only) | moderators: a councillor's name in the Olympus chats always carries the High Council's mark (the game's target-frame skull), which nobody can change. An icon of your own after it is optional: pick it from the game's icons, like a macro's. Your addon announces it on the channel (at once, then every 20 minutes), and other clients take it only from a councillor and only as a game icon |
| `/oly discord <code>` · `/oly discord` | Olympus Link: link this character to your Discord account with the bot's code (or paste it in a box) |
| `/oly discord show` · `status` · `forget` | the Olympus Link window (QR code and link) again; every character's request or proof; drop this character's |
| `/oly discord key <id> <key>` · `key` · `key new` · `key off` | confirmers (High Councillors too): keep the key the bot's keeper gave you for this character (once the bot's key is in the addon), show its id and public half, say where a new one comes from (the keeper; a key made in game only with the council authority on, off as it ships), remove it (and its certificate) and print the old key's id, which counts at the bot until its keeper revokes it |
| `/oly discord cert <certificate>` · `cert` | confirmers: keep the bot's certificate for that key and this character (checked first), show its tier and days left |
| `/oly discord watcher on\|off` | High Councillors: keep the proofs players hand you for the bot |
| `/oly discord certified` | the author: every certificate his client signed as the council authority (off as it ships) for a High Councillor's key (key id, character, end), for the bot's keeper |
| `/oly hop` | ask for an invite to the King's layer (while he is online) |
| `/oly lfg` · `/oly lfg dungeon\|raid\|pvp\|layer [note]` · `/oly lfg off` | the Board (1.1): who is looking for a group; raise your flag (a box with your note first) or lower it |
| `/oly week` | the King's week on the Board (1.1): his Agenda for 7 days with your guild's calendar events; the King and his Hands add entries with the Agenda button ("Sat 20:00 Raid night") |
| `/oly camp [note]` · `/oly camp off` · `/oly camps on\|off` | drop a camp in your zone (1.1: it needs `/oly location on`) or take yours down; the camps' badges on the world map |
| `/oly vox off` · `/oly vox on` | Vox Populi questions in chat only, or in a window |
| `/oly layerhelp on` · `/oly layerhelp off` | get (or not) requests to invite players to your layer (1.1: not until you say yes) |
| `/oly layerauto on` · `/oly layerauto off` | invite layer requests without the window |
| `/oly location on` · `/oly location off` | share (or not) your zone and layer on the Olympus channel |
| `/oly borders on` · `/oly borders off` | elite borders round the portrait of your target, focus and your own frame (Forever): the game's gold wings for the King, silver wings for the High Council, gold for Lords and silver for Captains, and Max's bronze wings for Raiders and bronze for Veterans of Olympus guilds (none for a character or a guild the moderators took off, net-off); on by default, hidden with the gamepad UI. Off, the nameplate marks go too |
| `/oly nameplates on` · `/oly nameplates off` | a small mark left of the name on friendly players' nameplates (Forever; friendly nameplates show with Shift+V), like an elite creature's dragon: the game's gold elite mark for the King, its silver for the High Council, Lords and Captains, bronze for Raiders and Veterans, and a star for any other member of an Olympus guild (none for a character or a guild the moderators took off, net-off); on by default, hidden with the gamepad UI and with `/oly borders off` |
| `/oly key <secret>` | officers: seal the Olympus channel |
| `/oly key rotate` | the King or his Steward: a new key for the whole army, by whisper to the Lords and Captains his /who saw in the guilds he picks and over guild chat, never on the Olympus channel (also on the Throne) (1.1) |
| `/oly block <name>` | ignore a player |
| `/oly filter add\|remove <word>` · `/oly filter` | block terms: hide, on your screen, lines of addon text (Olympus chats, writs, decrees, Vox) with a word; the list (1.1) |
| `/oly filter shared on\|off` · `/oly filter shared add\|remove <word>` | use the shared block terms or not; the King, his Steward, his Hands and the High Council edit them (1.1) |
| `/oly netoff Name: reason` · `/oly neton Name` · `/oly netoff` | the King, his Steward, a Hand or a High Councillor: hide a character for the whole army, or show them again (also on the Decrees tab); alone, who is hidden (1.1) |
| `/oly netoff guild Name: reason` · `/oly neton guild Name` | the same people: take a guild off the Olympus network for the army, or put it back on (also on the Decrees tab) (1.1) |
| `/oly alt add Name` · `/oly alt remove Name` · `/oly alt` | link a character of this account as your alt (log it and say yes there), take a link apart, or see your links: the census and the treasury count you once (1.1) |
| `/oly map` | zone markers on the world map |
| `/oly sound` · `/oly sound on\|off` | every alert sound on or off |
| `/oly alerts quiet\|always` | in an instance or Busy, Olympus's raid warnings, sounds and popups wait until you are out (quiet, the default), or show at once (1.1) |
| `/oly sound <kind> on\|off` | one kind's sound (1.1): `arms`, `muster`, `royal`, `court`, `vox`, `agenda`, `throne`, `help`, `hop`, `treasury`, `patrol`, `update`; also a click on its line at the bottom of the Decrees tab |
| `/oly bug` | copyable bug report (also: the help button left of the window's X, then **Report a bug**) |
| `/oly log [n \| word \| copy \| clear]` | the acts this client saw (decrees, gates, pardons, visibility switches), each with the sender's name; kept on this computer, never sent (1.1) |
| `/oly status` | diagnostics in chat (1.0.0: whom your addon knows as the King's Steward, and the lists of Hands it holds, whose each is; 1.1.2: the author's in a copy window) |

## Reporting a bug

While the addon's author is online, the **Report a bug** window also has a **Send to
Faladoriel Skylance** button: your report goes to him in game, by addon whisper, and nowhere
else (once every 10 minutes at most, unless he asked for it). It first checks he is really there: the rest follows
only once he answers, and you are told when he got it.

Since 1.1.2 the author can also ask you for it from the right-click menu: your addon shows you
the exact text first, in a window of its own, and sends nothing without your **Send**.

Type `/oly bug` (or press **Report a bug**), copy the text and open an issue. Errors are
also saved in `WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua`.

## Development

A feature that should leave a line in the acts log (1.1) calls `ns.Chronicle.Add(kind, by, what,
opts)` (`Olympus/Chronicle.lua`, where its arguments are described): `by` is the sender as the
server stamped it, and `opts.key`/`opts.value` write a repeated state (a switch, a list) once per
change.

With Bash and LuaJIT installed, run `bash scripts/check.sh` from the repository root to
check all addon and test Lua files for syntax errors, validate the files listed in
`Olympus/Olympus.toc`, run the local/global lint, and run the offline suite. With
python3 installed (CI has it) it also compiles the Python scripts and runs the High
Council signing round trip: a throwaway key in a temporary folder, lists signed with
`scripts/council-sign.py` and checked by `Olympus/Sign.lua` (never the author's key). This
is the same command CI uses; it stops with a nonzero exit status on failure.
The TOC file check also catches filename case mismatches on CI's Linux filesystem.
The offline suite checks the border textures in `Olympus/media/borders/` (32-bit TGAs with
alpha, 256 x 256, and the member's 32 x 32 star for the nameplate marks); with Pillow installed,
`scripts/check.sh` also checks they are what `scripts/make-borders.py` builds from Max's PNGs in
`media/borders/src/` (the star it draws itself: no game file is copied).

```bash
bash scripts/check.sh                    # full repository checks used by CI
luajit tests/run.lua                      # offline tests: codec, roster, hierarchy, security, layers, decrees, channels
scripts/lint-globals.sh                   # catches locals used before they are declared
bash tests/check-scripts.sh               # verify check-script failure handling (also run in CI)
bash tests/sign-roundtrip.sh              # the High Council signing script end to end (needs python3)
python3 tests/fixtures/make-link-vectors.py --check  # Olympus Link's shared vectors, sample, draw and inbox (needs "cryptography")
node --test web/test/*.test.mjs          # Olympus Link's page, core, Worker and tools (Node 22.13 or newer; also run in CI)
python3 scripts/make-borders.py [--check] # the border textures from media/borders/src (needs Pillow)
python3 scripts/link-keys.py ca           # the author, once: Olympus Link's council authority (see below)
python3 scripts/council-sign.py sign "First Surname,..." [realm group]  # the author: sign the High Council list
python3 scripts/council-sign.py council [council.json]  # the author: sign the names, departments and titles (see the script)
python3 scripts/council-sign.py steward "<Name-Realm>"  # the author: mark the King's Steward, sign the council (below)
python3 scripts/council-sign.py guild "<Guild Name>"  # the author: approve a guild of Olympus, sign the council (below)
python3 scripts/council-sign.py check     # the author: read dist/CouncilList.lua back, check its signatures with the key
scripts/package.sh                        # dist/Olympus-<version>.zip
WOW_HOST=user@pc scripts/deploy.sh        # copy to a Windows PC over SSH
WOW_HOST=user@pc scripts/logs.sh          # read the log and captured errors from that PC
```

`scripts/link-keys.py ca` writes `dist/LinkCA.lua` (the council authority's seed, like
`dist/CouncilList.lua` local only: never committed or in the zip) and prints its public key,
which goes into `ns.LINK_CA_KEYS` in `Olympus/Link.lua` and the Worker's `LINK_CA_PUBLIC`.
The author copies the file to his own game only (`Interface/AddOns/Olympus/LinkCA.lua`) and adds
`LinkCA.lua` at the end of `Olympus.toc` there. His client certifies nothing, and no councillor's
addon makes a key, while `ns.LINK_COUNCIL_AUTHORITY` in `Olympus/Link.lua` is `false`, as it
ships (Konig's review: every key comes from the bot's keeper). Only if he sets it to `true`, and
once the bot's key is in the addon, does his client certify the High Councillors' own keys by
itself and record each one in his SavedVariables (`/oly discord certified` lists them), and the
bot's keeper decides then whether to set `LINK_CA_PUBLIC`. When he takes a councillor off the
signed list, the bot's keeper revokes that character at the bot too. `web/WORKER.md` (step 1b)
says the rest, rotation included.

### The High Council's signed lists (the author)

The council's names, its departments and titles, and since 1.0.0 the King's Steward are signed
on the author's own computer with his key (`~/.olympus/council-key.json`), from his council
file (`~/.olympus/council.json`, the format at the top of `scripts/council-sign.py`). The
script writes `dist/CouncilList.lua`, local only like `LinkCA.lua`; he copies it to his own game
(`Interface/AddOns/Olympus/CouncilList.lua`, listed at the end of `Olympus.toc` there) and
`/reload`s: his client takes the lists and sends them within seconds, and every client checks
the signature and passes them on.

To make a character the King's Steward (the Alliance King's; add `Horde` after the name for the
Horde's):

```bash
python3 scripts/council-sign.py steward "<Name-Realm>"
python3 scripts/council-sign.py check
```

The first adds him to the council file's `"stewards"` (the rest of the file kept) and signs the
council at once, both lists newer than the last; the second reads `dist/CouncilList.lua` back,
checks both signatures with the key and prints the names, departments and Stewards it holds.
He stays in the file, so a later `council` signing keeps him. To end it, sign a newer council
without him (every client takes the newer list and he is no longer the Steward, at once):

```bash
python3 scripts/council-sign.py steward --remove "<Name-Realm>"
```

To approve a guild of Asmon's Olympus whose name the name rule leaves out (1.1; add `Horde` after
the name for a Horde guild):

```bash
python3 scripts/council-sign.py guild "<Guild Name>"
python3 scripts/council-sign.py check
```

The first adds it to the council file's `"guilds"` and signs the council at once, and prints the
signed titles list whole: its members' addons hear nothing of Olympus until they hold it, so the
first of them pastes that text in game (`/oly approved paste`) and his addon passes it to his
guild. `check` prints the approved guilds of each faction. `guild --remove "<Guild Name>"` signs a
newer council without it, which ends it on every client. `<Guild Name>` is the guild's name as the
game shows it (letters and spaces, 24 at most).

`<Name-Realm>` is his character as the server writes it (first name and surname, then his
realm), on a realm of the list's group. The script refuses anything the addon would not take,
before anything is signed. Whoever holds this key can name a Steward, as it names the council:
see [Security and trust](#security-and-trust).

Bundled libraries: LibStub (public domain), CallbackHandler-1.0 (Ace3, BSD),
HereBeDragons by Nevcairiel (BSD), the map library Questie uses, and luaqrcode by Patrick
Gundlach and contributors (speedata, 3-clause BSD) for Olympus Link's QR code
(`Olympus/libs/QREncode/qrencode.lua`, its changes listed at its top).

## Credits

- **Asmongold** and his team (Daily Dose of Asmongold, Max, Heuto, Fernmelder and the High
  Council), for making Olympus the army's addon and for the ideas.
- **Security reviews:** Konig, bjess9 (jess), lordjumper and Fadirstave, who read the code and
  showed what an attacker could do.
- **Code and ideas:** RoyLeviGit (Olympus chats in their own chat window), Artz (hiding the
  Issue Reporter), bjess9 (CI and the shared checks), hypertectonic (Chattynator's tabs).
- **Feature requests:** Fernmelder, whose 39 posts became 1.1 (the Fernmelder release);
  shenanigans_ (the nameplate marks), Valdericht (`<OLYMPIAN>`), Pyralis Ashandar (taking
  donations) and Zeal (what the King hides stays off the channel).
- **Art:** Max (the bronze elite borders of Raiders and Veterans, drawn over the game's own).
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
