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
cannot be switched off with a command. Outside an Olympus guild the addon joins no channel,
sends nothing and receives nothing. The only thing it offers there is the **Join Olympus**
screen described below.

### Not in Olympus yet?
First it asks the obvious question: *"<Your Guild>? Disband immediately. What are you
doing?"* Then it helps you get in. The **Join Olympus** screen uses the game's own `/who` to
find Olympus members online, groups them by guild, and whispers one of them a ready-made
request that you can edit ("Hi! I'd love to join Olympus. Does <Olympus II> have room for
one more?"). No answer? **Try someone else** picks a member you have not asked yet. Replies
are highlighted. It is rate limited, so nobody gets spammed. The game lists 50 players per
`/who`: when there are more, each new click searches a range of levels and adds to the list.

## What it does

### Census: the army at a glance
- Every Olympus guild in one list: **Guild · Members · Online · Lord**. Columns sort by
  clicking, like the Guild window.
- **Total soldiers** and **online now** across the whole realm.
- **Where the army stands**: top zones ("Stormwind City 742") and totals per continent
  (Eastern Kingdoms, Kalimdor), counted by the guilds whose census comes from a member who
  shares their zone (see Privacy, below).
- Hover a guild: members, online, free slots, average level, inactive members, classes online, top zones.
- Olympus guilds where nobody runs the addon show too, in grey: opening the window (and any click in it) also searches
  `/who` and lists every Olympus guild it sees online, with how many. They count in no total.

### The Realm: the hierarchy
- The **King**, then every guild's **Lord** (guild master) and **Captains** (the officer rank
  right below the guild master).
  Each shows level, class and online or *offline 3d*. Long absences show in red.
- The **Treasurer of Olympus** (Pyralis Ashandar, chosen by Asmongold's chat) right under
  the King, with a gold coin next to his name wherever he shows, his tooltip and his lines in
  the Olympus chats included. Only
  that exact character of the guild OLYMPUS gets it: look-alikes don't.
- **Members online** under each guild: your own guild's from your roster, any other's from
  `/who`. Opening a guild searches `/who` for that guild alone (up to 50 of its players).
  Click a name to whisper, invite or `/who` them.
- The **ranks** of each guild with how many members hold them.
- **Inactive members**: offline 7+ and 30+ days, per guild.
- **Level race**: the highest level players of the realm.
- **Recruiting**: the guilds that still have free slots, so new players go where there is room.
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
shares their zone and layer (`/oly location on`) helps by default: a player who keeps them
private is never asked, since an offer would tell the asker where they are. `/oly layerhelp
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
the Hands he names, on his word alone: while his list names them, a Hand who is one of its
officers has its Royal decrees, Tabard inspections and [Lords] lines on every client. The
King's Steward (1.0.0, [below](#the-kings-steward-100)) sends the Crown's decrees for
`<Olympus>` on every client, whatever his rank, like the King.

### Channels
Chat for the whole federation, carried by the addon over its hidden Olympus channel (no
WoW channel number to join). Each channel is exclusive to a rank:

| Channel | Command | Who reads and writes |
|---|---|---|
| **[Olympus]** | `/ol <text>` | every member of every Olympus guild |
| **[Captains]** | `/olc <text>` | the Captains (rank 1) and Lords of every Olympus guild |
| **[Lords]** | `/oll <text>` | the Lords (every guild master, the King included) and the officers of `<Olympus>` (their lines show to `<Olympus>`'s own members, and to everyone for those the King names his Hands, 1.0.0) |

- Higher ranks also use the channels below theirs: a Lord writes in all three.
- `/oly mute captains` (or `olympus`, `lords`) hides a channel in chat; the same command shows it again.
- `/oly chatwindow Olympus` shows the three channels in your chat window called "Olympus"
  (make the tab in the game first: right-click a chat tab, Create New Window), by name or by
  number; `/oly chatwindow Olympus captains` moves one channel only, and `/oly chatwindow main`
  brings them back. Only where the lines are printed changes: the addon never touches the chat
  box, so every command typed there works as always. A window closed or renamed sends its
  lines back to the main window, with a notice. `/oly status` shows where each channel goes.
- The flood guard keeps a busy channel readable: past 60 lines a minute (or 10 from one player
  while the channel is half full) the rest stay off the chat, and a notice says how many, at
  most once a minute. Those lines still go to the Realm tab's Olympus chats, which keep the
  last 100 lines of each channel.
- Shift-click an item or spell into the line and it stays a link. Long lines are split into
  up to 3 messages.
- The channels show only in the chat of players with the addon.
- The Realm tab links **the Olympus chats**: the last lines of each channel your rank reads,
  newest first, even what was said while the window was closed. A click whispers the player.
- Ranks follow the rule of the decrees: whoever founds a guild with "Olympus" in its name is
  its Lord and gets [Lords], and its officers get [Captains].

**Not encrypted, not private:** every client on the hidden Olympus channel receives the text of
all three channels, and the addon only decides what to show. Anyone on that channel can read
[Captains] and [Lords] with a one-line script: without `/oly key` that is anyone who joins
"OlympusNet" by name; with a key, every member of the guilds that have it. The guild tag on an
[Olympus] line is not verified. Seal the channel with `/oly key`, and never share passwords there.
Before your first line in each channel the addon tells you this and waits for **Send**.

### The Throne (the King and his Hands)
A tab with a crown that only the King sees: the guild master of the guild named exactly
"Olympus" (of his faction), and on the Alliance that very character, Asmongold Asmongler: the
addon knows him by name, like the Treasurer. It opens on **the Throne Room** (the queue of
his court while it is open, and the Treasury), and holding court takes him there. Each of his
tools lives where it belongs:
- **The King's Agenda** (a button on the Throne): minutes and an event ("30 Raid on
  Crossroads"). The whole army gets a popup with the appointment (what, in how long, where)
  and sees it on the Census, with reminders 10 minutes and 1 minute before.
- **Hold Court** (a button on the Throne): the King opens his court where he stands. Every
  Olympus player in that zone gets a line on top of the Census and the Realm; one click asks
  for an audience. The requests line up on his Throne and a click calls that player (a popup
  and a raid warning).
- **Summon the Lords** (on top of the Realm tab): every Lord and Captain online gets a popup,
  "Present, my King" or "Busy". While the roll call is fresh, each Lord and Captain in the
  tree carries a ready-check mark: present, busy, or not answered yet.
- **Royal Inspection** (on top of the Tabards tab): a raid warning for the whole army ("wear
  your tabard!"), then a sample of the soldiers with the addon patrols the players around them
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
- **Hands of the King** (a button next to his map button): players he names use the roll
  call, the inspection, the agenda, Vox Populi and the gates in his name. Never the court,
  writs, pardons or his crown on the map. Their addons learn the list from his, and it ends
  when he stops sending it. A Hand who is an officer of `<Olympus>` keeps its Crown (Royal
  decrees, Tabard inspections, [Lords]) on every client, not only on its members' (1.0.0).
  Each Steward names Hands of his own beside his, in a list of his own (1.0.0,
  [below](#the-kings-steward-100)).
- **Show me on the map** (his own button, with the crown): while he turns it on, everyone with
  the addon sees a crown where he is, on the world map and the minimap. Off by default (his
  position is on stream); the same button hides it, its tooltip says whether it is on now, and
  the top of the Throne page reminds him while it is. His layer goes out with it, at once and
  then every minute, so the army can ask to join him (**Ask invite for Asmon Layer**); hidden,
  it is withdrawn with the crown.

Every command is checked on each client: it only counts if the sender is the King by name
(the server stamps every sender's name, so nobody else can carry his), his Steward for what is
his to do in the King's name (1.0.0), or one of the King's Hands, for what is lent to them. No
census vote can make anyone else King or silence him. On the
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
signed list no longer names him. Clients before 1.0.0 follow the King's list alone, as they
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
shows the army something of it.
- **Its keepers (1.0)**: the Treasurer of Olympus (that exact character, in the guild OLYMPUS),
  the King, and up to 5 characters the King adds on the Treasury tab (**The treasury's
  keepers**, then **Add a treasury character**, by name or target; a click on one takes it off).
  The list is the King's word (or his Steward's, in his name): every client checks it comes from
  his character or a Steward's, keeps it (it never runs out while he is away), and the
  Treasurer's addon repeats it.
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
  is one line); the book shows every keeper's lines by time, with who received each one. Each
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
- **Early supporters**: everyone who gave before 1.0 (from 0.9's closed book, sent by the Treasurer's addon), names only, in alphabetical order, under the ranking and with its switch.
- **The guild bank of <Olympus>**: whoever of that guild opens the bank with the addon on takes
  a snapshot of it (each tab's items with icons and counts, the bank's gold, when it was seen);
  a keeper's snapshot (the newest, whoever took it) reaches the King and, with his "book"
  switch, the army. Hover an item for its tooltip. Nothing is ever moved in the bank: it is a
  picture. On WoW: Forever the bank's window opens through the game's interaction manager,
  which 1.0 listens to (0.9's addon never saw it open there); a client with no guild bank says
  so on the tab.
- **Sent by each keeper's addon by itself** (every 5 minutes and after a change), once he said
  yes: his book's balance, totals, ranking, items donated and latest lines, on the Olympus
  channel. Every client checks it comes from a keeper himself.
- **The King chooses what the army sees** (his Steward too, in his name), with three buttons:
  the balance, the ranking, the book. Until he does, only the keepers, the King and his Steward
  see them (a keeper's tab says so, and so does the question each keeper answers before sharing).
  With any of them on, the Treasury tab appears for every member with the addon, showing only
  what he turned on (the book behind its own button), and the balance shows under the Treasurer
  in the Realm. The Treasurer's addon repeats the King's latest word, so members who never meet
  the King online get it too. The King and his Steward always see all of it, whatever the
  switches, and the King the balance next to the soldiers on top of his window. (The channel
  can be read by anyone on it: the buttons choose what the addon shows, they don't make the
  numbers secret.)

### Tabards: tabard inspection and the untabarded list
- **Patrol**: walk through the crowd and the addon inspects nearby Olympus members level 15
  and up, one by one (about 28 yards). Younger players are never flagged. It records who wears a tabard, who wears the wrong one and who
  wears none. Players it could not see properly are never accused.
- **Mark** a player (with a note: `/oly mark complained about the rule`) or a whole guild.
- Per guild: *"5 of 20 with problems"*.
- **Untabarded** (the "Wall of Shame" before 0.9.2): the players the Royal Inspection found
  without the colors are on the King's list, which only he sees. He alone can let the army see
  it (a switch on the Throne, off by default): then it shows on the Tabards page, quietly (no
  raid warning, no chat line, no sound), and it leaves every screen when he turns it off or
  stops repeating it. Nobody else can publish one. Players under level 15 are exempt: never
  flagged, never listed.
- Hover any player in the world to see their last inspection in the tooltip.

### World map
- Soldiers per zone on zone and continent maps, and per continent on the world map (with
  Blizzard's gamepad mode, only per continent: see below).
- Decrees are round icons (the horn, the war cry...) where they were called, and the King's
  crown where he stands. Over a zone's circle they move just outside its edge, top right first,
  so its number stays readable; several around one circle each take a place of their own.
- The round **Olympus** button in the bottom left corner of the map switches markers
  (army per zone, decrees) on and off.

### Olympus Link: your Discord role (1.0.0)
Players in game prove to the Olympus bot on Discord that a character is yours, and the bot gives
you your role. No password, no Battle.net login, and nothing leaves the game before you say yes.

Not open yet: the addon carries it, but `/oly discord` says it is not open until the Olympus bot
is ready and its key is in the addon. High Councillors' addons already make their own keys and
get them certified in the meantime.

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

**For confirmers and watchers.** A confirmer's key belongs to one character, and so does its
certificate, which names it: another character of the same account confirms nothing with it.
**High Councillors paste nothing**: the first time the signed High Council list names your
character, your addon makes a key of its own in the game (from the finest timings the client
has, over several frames; the key never leaves your computer) and asks the author's client for
its certificate the next time it hears him (a whisper with the key's public half); his client
checks you are on the signed list and signs one for a year (for one character per key: it keeps a
record of every key it certified, and another councillor who sends your key's public half gets
nothing), and your addon checks it before it keeps it. `/oly discord key new` makes a new key and
asks again (a lost or leaked one), `/oly discord key off` removes it (your addon makes none by
itself after that, until `key new`). Either way the old key keeps counting at the bot until its
keeper revokes it (the bot never asks your game, and a certificate lasts a year), so both print
the old key's id for you to send them, at once if it leaked. `/oly discord certified`, in the
author's game, lists every certificate his client signed (key id, character, end) for the
keeper, who can revoke one key or every key of a character. Other confirmers get a key from the bot's keeper (an id and
43 letters) and its certificate (a line starting with `OLK2.`, the bot's signature on the key's
public half, its tier, an expiry and your character's name): `/oly discord key <id> <key>` keeps
the key for the character you are on, then `/oly discord cert <certificate>` its certificate,
which the addon checks against the bot's key, your key's public half and your character before
it keeps it. `/oly discord key` shows the key's id and public half (to compare with what was
registered), `/oly discord cert` the certificate's tier and days left. The key is never shown,
sent, logged or written in `/oly status` and `/oly bug`. With a key and its certificate, your
addon says it is online every 5 minutes (the certificate goes with it: requesters check it, and
that it names the character announcing it, before they ask you) and signs, by itself, the
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

### Everywhere
- **Copy**: every tab produces a ready-to-paste text for Discord.
- **Search**: a box on top of the Census (a guild or its Lord), the Realm (guilds, Lords, Captains,
  members seen online, the Olympus chats' lines), the Tabards (inspected and untabarded players,
  by name or guild) and the Treasury (donors in the ranking and the book). Any case, accents too;
  only what matches shows, under the headers it belongs to (a Captain under his guild, opened
  for you, a page of guilds at a time), with an **x** to empty it. Each tab keeps its text until
  you log out or `/reload`; a guild clicked in the Census opens in the Realm with its box emptied.
  It only changes what the list shows: **Copy** still gives everything, and nothing is sent.
- The window opens from `/oly`, the minimap button, or the round button in your guild window:
  the old Guild tab or the new Guild & Communities window, whichever one you use.
- Next to Forever's Guild & Communities window it takes that window's look: icon tabs down
  the right side, its rows, column headers, buttons and member card.
- **Blizzard's gamepad mode** (Forever's controller interface): Olympus asks its questions in
  windows of its own instead of the game's popups, which Blizzard's gamepad code blocks (and
  freezes) when an addon opens one. With mouse and keyboard, the game's popups as always.
  Since 0.9.8 it also leaves the game's own frames alone there: no quiet `/who` on its own
  (**Refresh** and **Find Olympus online** still search, and the answer shows in the game's
  Who list), and the Issue Reporter is the game's to show. Since 0.9.9 it leaves the world map
  alone there too: no zone counts, decrees, crown or guildmate dots on it (the minimap keeps
  the crown and the dots, the Azeroth map its continent totals), because each of those went
  through the map library into the gamepad map's own state. If the game still says it blocked Olympus, a
  `/reload` clears it; to tell us what it was, open the Olympus window, press its help button
  (left of the X), then **Report a bug**. Don't type `/oly bug` with the gamepad: a command
  typed in the chat there can set the block off again.
- English and Portuguese (follows the game language).

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

Nothing leaves the game. There is no server, no website, no account and no tracking. The one
exception is Olympus Link, and only when you ask for it: the proof that a character is yours
goes to the Olympus bot on Discord, through the page you scan it with or a watcher.

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

The addon talks only through the game's own addon messages: no server, no website, no
tracking. Your name is on every message (the game adds it). What goes where:

| What | Who receives it | When |
|---|---|---|
| Your guild's census: size, online count, classes, levels, rank names, the leader and officers (name, online, days away, class, level), the top levels, addon versions | everyone on the Olympus channel | from one elected member per guild (and a runner-up), every few minutes |
| Zones in that census: members per zone (numbers only), a leader's or officer's zone | everyone on the Olympus channel | only if the member sending it shares their zone and layer; a leader's or officer's zone only if they share theirs too |
| Your zone, layer, guild rank and guild (layer announcements) | everyone on the Olympus channel | only if you share: officers and one member in eight announce, every 10 minutes and when their layer changes |
| A layer hop ask: the zone you are in and the layer you want | everyone on the Olympus channel | when you ask to hop |
| An answer to an ask for your layer (it tells the asker you are on it) | the asker alone (a whisper) | only if you share your zone and layer, while layer help is on (`/oly layerhelp off` stops it) |
| [Olympus], [Captains] and [Lords] lines | everyone on the Olympus channel, all three | when you write one |
| Hello: addon version, realm, public or sealed channel, whether you share your zone | your guild | every minute or so |
| Your position as a dot on the map | your guild | only with `/oly share` (off by default) |
| A treasury keeper's book (balance, gold and items given and who gave them, the ranking) and the guild bank of `<Olympus>` (its gold and items) | everyone on the Olympus channel receives the bytes; the addon shows them to the King and his Steward, and to the army only with the King's switches | only after that keeper says yes (each keeper, the King too, is asked once; `/oly treasurer on\|off`), withdrawn at once when he turns it off |
| The King's crown on the map, and with it his zone and layer | everyone on the Olympus channel | only while the King turns it on (Throne tab), whatever he answered to the question |
| Olympus Link (1.0.0): a request (your guild, faction, a random number, your code's id and a tag made from your code's signature and your name) | the confirmers asked (a whisper each): a High Councillor, or verified players drawn for your code | only after you press **Accept** on `/oly discord <code>` |
| Olympus Link: the finished proof (your character name, realm, guild, faction, the tag, and the confirmers' names, how each knew your guild, their signatures and their keys' certificates) | the Olympus bot, through the page you scan it with, or a watcher (a High Councillor, by whisper) who hands it to the bot | when it is ready, until it is delivered (5 days after your code expired at most) |
| Olympus Link: "a confirmer's key is online" (its certificate: the key's id, public half, tier, expiry and character), "a watcher is online" | everyone on the Olympus channel | every 5 minutes, only from characters with a key and its certificate, or the watcher on |
| Olympus Link: a High Councillor's key's public half, and the certificate for it | the author's character, and back (a whisper each) | only from a councillor of the signed list whose addon made its own key, once a session when it hears the author |

Decrees and the King's calls go out when someone sends one (a decree carries its sender's
position on the map).

**Zone and layer: off until you choose.** Once after login (never in combat or in an
instance) the addon asks whether to share your zone and layer, saying what goes out and who
reads it. Until you answer, and after **Keep private**, it announces no layer, and the census
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
nobody can take it back. If it leaks, officers set a new one (`/oly key <new secret>`) and hand
it out again.

**Chat is never private.** Every client on the channel receives [Olympus], [Captains] and
[Lords] alike; the addon only decides what to show. Before your first line in each of them
the addon says so and waits for **Send** (**Cancel** sends nothing), once per channel.

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
can do either: every addon checks the sender's name, which nobody else can carry. `/oly
rollcall off` refuses both. The addon's error catcher keeps only Olympus's own errors (for
`/oly bug`), never another addon's. For the store's screenshots he has a photo mode (`/oly
photo`, his character only): on his own screen it fades everything but Olympus and the world
map to invisible, and gives every frame its look back on the second `/oly photo` or a
`/reload`. Never in combat, not with the gamepad UI, and nothing is sent to anyone.

The addon is plain Lua running on each player's computer, so anyone can edit their own
copy. No addon can prevent that. What this one does is check what every copy sends; what a
few characters working together can still reach is said plainly further down
([What colluding characters can reach](#what-colluding-characters-can-reach)):

- **Guild traffic is verified by Blizzard's servers.** Guild addon messages only reach
  members of that guild, so the realm key and guild elections can't be faked from outside.
- **Sender names cannot be forged.** The server stamps every message with its sender.
  - **The King and the Treasurer are known by name**, not by vote: only their characters can
    send their commands and the treasury (with the characters the King names to the treasury,
    whose books count while his list names them). A report of `<Olympus>` naming anyone else as its
    leader counts for nothing, not even as a vote: no count of votes makes anyone else its King.
    Since 1.0.0 the King's decrees and [Lords] lines count by his name too, with no census.
    Their names count on their realm group only (Forever's PvP realms): a namesake anywhere
    else is someone else, and there is no King there.
  - **The King's Steward** (1.0.0) is named by the author's signature, like the High Council:
    a character the signed titles list marks, for his realm group and his King's faction, and
    nobody else (no name in the code, no vote). His word counts by his name, which the server
    stamps: a list of Hands of his own, beside the King's (nobody changes anyone else's list);
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
    `<Olympus>` members' clients, from their roster (1.0.0), and those the King names his Hands
    (his word, never a vote): everywhere else they count as Captains, so outsiders' reports
    can't add one to the Crown.
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
- **Validation**: every number is range checked, names are length limited, and malformed
  messages are dropped. Decrees are rate limited per sender (one a minute) and in total (6 a
  minute from senders only the census vouches for; since 1.0.0 the King's, his Hands' for
  `<Olympus>` and your own guild's officers' never wait behind that limit).
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
  confirmer's own key, which is one character's and certified for that character: by the bot, or
  a High Councillor's by the council authority, the author's own client (`ns.LINK_CA_KEYS`; its
  private key is on his computer only and never printed, logged or sent). A requester asks only
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
  yield across a pcall, a sort, a gsub, a metamethod or a generic for's iterator). A High
  Councillor's key made in the game comes from the best the client offers, which is no
  cryptographic random source: sub-millisecond frame timings, the time, the game's generator,
  table addresses, the cursor and the character, over eight frames, through SHA-512 (the comment
  in `Link.lua` says what an attacker could guess). Such a key only confirms, lasts a year and
  can be revoked and replaced at once; a councillor who wants one made on a computer asks the
  bot's keeper instead.
- `/oly block <name>` ignores a player completely.

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
  roster), and a census officer of `<Olympus>` is a Captain everywhere else, unless the King
  names him one of his Hands (his word, never a vote).
- **Numbers.** A guild's size and online count are not part of the picture. One outsider who
  copies a guild's leader and officers with other numbers shows his numbers on every screen
  until its reporter's next report (800 members as 1, the King offline). Each made-up guild
  adds up to 1,000 soldiers to every client's army total for a day, and one character can
  start a new one every 15 minutes.
- **Trust elsewhere.** A made-up Captain who answers a layer-hop ask is a helper the addon
  vouches for, so his party invite is accepted for the player (never with the gamepad UI). His
  report on a Royal Inspection can put an innocent player on the King's untabarded list, which
  the King's share sends to the army.

What 1.0.0 hardened: the King's decrees and [Lords] lines count by his name, with no census at
all, and his Hands' for `<Olympus>` by his word; those and your own guild's officers' decrees
never wait behind the flood guard, however many made-up Captains fill it; a decree speaks
for one guild per sender, as the chats do; a decree's words go out with Blizzard's logged
addon-message function (one that arrives any other way, from a sender before 1.0.0, still
shows, without its words); and the officers of `<Olympus>` are of the Crown on its own
members' clients only, and elsewhere only those the King names his Hands.

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
  guild. Their guildmates' reports and the conflict flag make a changed leader, size or officer
  list visible, but it can't be made impossible.

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
  play at most once every 15 seconds.
- Chat has its own short lane: a line goes out within about a second, and while reports are
  waiting it never takes more than every other message slot.

## Commands

| Command | |
|---|---|
| `/oly` | open or close the window |
| `/oly realm` · `/oly decrees` · `/oly tabard` | open a tab |
| `/oly patrol` | start or stop the tabard patrol |
| `/oly mark [note]` | mark your target |
| `/oly arms [text]` · `/oly muster [text]` | send a decree (`test` = local preview) |
| `/ol <text>` · `/olc <text>` · `/oll <text>` | write in [Olympus], [Captains] or [Lords] |
| `/oly all <text>` · `/oly captains <text>` · `/oly lords <text>` | the same, as `/oly` commands |
| `/oly mute olympus` · `/oly mute captains` · `/oly mute lords` | hide or show a channel in chat |
| `/oly chatwindow <number or name> [olympus\|captains\|lords]` · `/oly chatwindow main` | show the Olympus chats in another chat window, or back in the main one |
| `/oly treasurer on\|off` | a keeper of the treasury (the Treasurer, the King, a character he named) shares his book and the guild bank, or keeps them private |
| `/oly rollcall on\|off` | answer the author's roll calls (version, client, channel state) or not |
| `/oly inspection on\|off` | take part in the King's Royal Inspection when sampled (a 2-minute patrol reported to him), or not |
| `/oly issuereporter hide\|show` | hide Blizzard's Issue Reporter box (beta clients) at every login, or show it again (also a "Hide" button on it) |
| `/oly helpme [text]` (or **Ask a High Councillor** on the Realm tab) | ask the High Council (the moderators) for help: it goes by whisper to up to three of them online who take requests |
| `/oly council list` · `/oly council help on\|off` | the High Council as your addon knows it; moderators: take help requests or not. The list is signed by the author on his own computer and checked by every client: no name is written in the addon's code, and nobody can forge or change it. An addon without the list (`High Council: -`) asks the channel for it a minute or so after login, and again until it has it (two and a half minutes later when nobody answered, up to 3 times). Since 1.0.0 the list also crosses realms through guild chat: guildmates on another realm answer the ask and pass the list on, and it goes on to your realm's channel |
| `/oly council icon` (or **My council icon** on the Realm tab, councillors only) | moderators: a councillor's name in the Olympus chats always carries the High Council's mark (the game's target-frame skull), which nobody can change. An icon of your own after it is optional: pick it from the game's icons, like a macro's. Your addon announces it on the channel (at once, then every 20 minutes), and other clients take it only from a councillor and only as a game icon |
| `/oly discord <code>` · `/oly discord` | Olympus Link: link this character to your Discord account with the bot's code (or paste it in a box) |
| `/oly discord show` · `status` · `forget` | the Olympus Link window (QR code and link) again; every character's request or proof; drop this character's |
| `/oly discord key <id> <key>` · `key` · `key new` · `key off` | confirmers: keep the key the bot's keeper gave you for this character, show its id and public half, make a new one (High Councillors: certified by the author's client by itself), remove it (and its certificate); the last two print the old key's id, which counts at the bot until its keeper revokes it |
| `/oly discord cert <certificate>` · `cert` | confirmers: keep the bot's certificate for that key and this character (checked first), show its tier and days left |
| `/oly discord watcher on\|off` | High Councillors: keep the proofs players hand you for the bot |
| `/oly discord certified` | the author: every certificate his client signed for a High Councillor's key (key id, character, end), for the bot's keeper |
| `/oly hop` | ask for an invite to the King's layer (while he is online) |
| `/oly vox off` · `/oly vox on` | Vox Populi questions in chat only, or in a window |
| `/oly layerhelp on` · `/oly layerhelp off` | get (or not) requests to invite players to your layer |
| `/oly layerauto on` · `/oly layerauto off` | invite layer requests without the window |
| `/oly location on` · `/oly location off` | share (or not) your zone and layer on the Olympus channel |
| `/oly borders on` · `/oly borders off` | the game's elite borders round the portrait of your target, focus and your own frame (Forever): gold for the King, silver for Lords, Captains and the High Council, grey for Veterans and Raiders of Olympus guilds; on by default, hidden with the gamepad UI |
| `/oly key <secret>` | officers: seal the Olympus channel |
| `/oly block <name>` | ignore a player |
| `/oly map` | zone markers on the world map |
| `/oly sound` | alert sounds on or off |
| `/oly bug` | copyable bug report (also: the help button left of the window's X, then **Report a bug**) |
| `/oly status` | diagnostics in chat (1.0.0: whom your addon knows as the King's Steward, and the lists of Hands it holds, whose each is) |

## Reporting a bug

While the addon's author is online, the **Report a bug** window also has a **Send to
Faladoriel Skylance** button: your report goes to him in game, by addon whisper, and nowhere
else (once every 10 minutes at most). It first checks he is really there: the rest follows
only once he answers, and you are told when he got it.

Type `/oly bug` (or press **Report a bug**), copy the text and open an issue. Errors are
also saved in `WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua`.

## Development

With Bash and LuaJIT installed, run `bash scripts/check.sh` from the repository root to
check all addon and test Lua files for syntax errors, validate the files listed in
`Olympus/Olympus.toc`, run the local/global lint, and run the offline suite. With
python3 installed (CI has it) it also compiles the Python scripts and runs the High
Council signing round trip: a throwaway key in a temporary folder, lists signed with
`scripts/council-sign.py` and checked by `Olympus/Sign.lua` (never the author's key). This
is the same command CI uses; it stops with a nonzero exit status on failure.
The TOC file check also catches filename case mismatches on CI's Linux filesystem.

```bash
bash scripts/check.sh                    # full repository checks used by CI
luajit tests/run.lua                      # offline tests: codec, roster, hierarchy, security, layers, decrees, channels
scripts/lint-globals.sh                   # catches locals used before they are declared
bash tests/check-scripts.sh               # verify check-script failure handling (also run in CI)
bash tests/sign-roundtrip.sh              # the High Council signing script end to end (needs python3)
python3 tests/fixtures/make-link-vectors.py --check  # Olympus Link's shared vectors, sample, draw and inbox (needs "cryptography")
python3 scripts/link-keys.py ca           # the author, once: Olympus Link's council authority (see below)
python3 scripts/council-sign.py sign "First Surname,..." [realm group]  # the author: sign the High Council list
python3 scripts/council-sign.py council [council.json]  # the author: sign the names, departments and titles (see the script)
python3 scripts/council-sign.py steward "<Name-Realm>"  # the author: mark the King's Steward, sign the council (below)
python3 scripts/council-sign.py check     # the author: read dist/CouncilList.lua back, check its signatures with the key
scripts/package.sh                        # dist/Olympus-<version>.zip
WOW_HOST=user@pc scripts/deploy.sh        # copy to a Windows PC over SSH
WOW_HOST=user@pc scripts/logs.sh          # read the log and captured errors from that PC
```

`scripts/link-keys.py ca` writes `dist/LinkCA.lua` (the council authority's seed, like
`dist/CouncilList.lua` local only: never committed or in the zip) and prints its public key,
which goes into `ns.LINK_CA_KEYS` in `Olympus/Link.lua` and the Worker's `LINK_CA_PUBLIC`.
The author copies the file to his own game only (`Interface/AddOns/Olympus/LinkCA.lua`) and adds
`LinkCA.lua` at the end of `Olympus.toc` there: his client then certifies the High Councillors'
own keys by itself and records each one in his SavedVariables (`/oly discord certified` lists
them). When he takes a councillor off the signed list, the bot's keeper revokes that character at
the bot too. `web/WORKER.md` (step 1b) says the rest, rotation included.

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
  Issue Reporter), bjess9 (CI and the shared checks).
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
