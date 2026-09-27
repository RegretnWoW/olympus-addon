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

![The census live on WoW: Forever: 35,679 soldiers in 72 Olympus guilds](https://raw.githubusercontent.com/dnl-gentile/olympus-addon/main/docs/census.png)

![Hovering a guild: members, online, Lord, free slots, average level, classes and zones](https://raw.githubusercontent.com/dnl-gentile/olympus-addon/main/docs/6-guild-tooltip.png)

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
are highlighted. It is rate limited, so nobody gets spammed.

## What it does

### Census: the army at a glance
- Every Olympus guild in one list: **Guild · Members · Online · Lord**. Columns sort by
  clicking, like the Guild window.
- **Total soldiers** and **online now** across the whole realm.
- **Where the army stands**: top zones ("Stormwind City 742") and totals per continent
  (Eastern Kingdoms, Kalimdor), counted by the guilds whose census comes from a member who
  shares their zone (see Privacy, below).
- Hover a guild: members, online, free slots, average level, inactive members, classes online, top zones.

### The Realm: the hierarchy
- The **King**, then every guild's **Lord** (guild master) and **Captains** (the officer rank
  right below the guild master).
  Each shows level, class and online or *offline 3d*. Long absences show in red.
- The **Treasurer of Olympus** (Pyralis Ashandar, chosen by Asmongold's chat) right under
  the King, with a gold coin next to his name wherever he shows, his tooltip included. Only
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
- The invite is accepted for you, the game moves you to the layer, and the addon takes you out
  of the group as soon as it sees the move (or offers a **Leave group** button if it can't
  tell).

Players alone on the King's layer are asked once per login: **"Asmon is online and you are on
his layer. May the addon invite the players who want to join, and take them out of the group
once they are there?"** with **For Olympus!**, **Can't right now** and **Invite manually**, and
a **Don't ask me again** box. With For Olympus! the addon invites on its own (only while you
are alone or with its guests, never into a group of your friends) and lets each guest go after
90 seconds: the guest's addon leaves the group, since only a click may remove someone.

Any other layer in the Realm tab's layer list works the same way: click it. Everyone with the
addon helps by default; `/oly layerhelp off` stops the requests, `/oly layerhelp on` also
forgets the answer to the King's layer window, `/oly layerauto on` invites them without the
window. Helpers must be in the same zone as the layer they are on, and the King himself is
never asked.

Layers are known from the members who share their zone and layer (see Privacy, below):
the more share, the better hopping works. Asking works either way, and says on the channel
the zone you are in and the layer you want. The King's layer is known while he shares it or
shows his crown on the map.

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
`<Olympus>` guild. Everyone else gets a local preview when they press the buttons.

### Channels
Chat for the whole federation, carried by the addon over its hidden Olympus channel (no
WoW channel number to join). Each channel is exclusive to a rank:

| Channel | Command | Who reads and writes |
|---|---|---|
| **[Olympus]** | `/ol <text>` | every member of every Olympus guild |
| **[Captains]** | `/olc <text>` | the Captains (rank 1) and Lords of every Olympus guild |
| **[Lords]** | `/oll <text>` | the Lords (every guild master, the King included) and the officers of `<Olympus>` |

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
addon knows him by name, like the Treasurer. It opens on the author's letter, its cover; **the Throne Room**
(the queue of his court while it is open, and the Treasury) is a click away, and holding
court takes him there. Each of his tools lives where it belongs:
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
  when he stops sending it.
- **Show me on the map** (his own button, with the crown): while he turns it on, everyone with
  the addon sees a crown where he is, on the world map and the minimap. Off by default (his
  position is on stream); the same button hides it, its tooltip says whether it is on now, and
  the top of the Throne page reminds him while it is.

Every command is checked on each client: it only counts if the sender is the King by name
(the server stamps every sender's name, so nobody else can carry his), or one of the Hands he
named, for what he lends them. No census vote can make anyone else King or silence him. On the
Horde the King is Duskmonkey Boneback, guild master of `<Mudhutters>` (0.9.4): his guild counts
as an Olympus guild there, whatever its name. Answers go to the King alone. Nothing another player sends can put free text on his screen: only names and
Olympus guild names.

### The Treasury (the Treasurer, the King, and the army when the King says so)
A tab with a coin for the Treasurer of Olympus (that exact character, in the guild OLYMPUS),
for the King, and for every member once the King shows the army something of it.
- **The book**: gold the Treasurer receives by trade or mail is a donation, gold he gives by
  trade or mail a payment, each written down by itself (mail when he takes its gold; the
  auction house and cash on delivery don't count).
- **The treasury is the book, not his gold**: an opening balance he sets, plus what came in,
  less what went out. What he earns playing is his. A trade of his items (or his work: an
  enchant, a lock opened) for gold is a sale, of his gold for items a purchase, gold with his
  own characters his own: they go in the book as not counted, and a click on the line counts it
  if it was the treasury's (or stops counting one that wasn't). A payment by mail that comes
  back stops counting by itself.
- **The ranking of donors** (all time) and the week's donations, with a copy for Discord.
- **The guild bank of <Olympus>**: whoever of that guild opens the bank with the addon on takes
  a snapshot of it (each tab's items with icons and counts, the bank's gold, when it was seen);
  the Treasurer's snapshot reaches the King and, with his "book" switch, the army. Hover an
  item for its tooltip. Nothing is ever moved in the bank: it is a picture.
- **Sent by his addon by itself** (every 5 minutes and after a change): the balance, the totals,
  the ranking and the latest lines of the book, on the Olympus channel. Every client checks it
  comes from the Treasurer himself.
- **The King chooses what the army sees**, with three buttons: the balance, the ranking, the
  book. Until he does, only the Treasurer and the King see them (the Treasurer's tab says so).
  With any of them on, the Treasury tab appears for every member with the addon, showing only
  what he turned on (the book behind its own button), and the balance shows under the Treasurer
  in the Realm. The Treasurer's addon repeats the King's latest word, so members who never meet
  the King online get it too. The King always sees all of it, and the balance next to the
  soldiers on top of his window. (The channel can be read by anyone on it: the buttons choose
  what the addon shows, they don't make the numbers secret.)

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
- The round **Olympus** button in the bottom left corner of the map switches markers
  (army per zone, decrees) on and off.

### Everywhere
- **Copy**: every tab produces a ready-to-paste text for Discord.
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
  through the map library into the gamepad map's own state. If the game still says it blocked
  Olympus, a `/reload` clears it; to tell us what it was, open the Olympus window, press its
  help button (left of the X), then **Report a bug**. Don't type `/oly bug` with the gamepad: a
  command typed in the chat there can set the block off again.
- English and Portuguese (follows the game language).

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

## How it works

1. Every guild member can read their own guild's roster: name, level, class, zone, rank,
   online and last seen.
2. Members with the addon find each other through hidden addon messages in guild chat and
   **elect one reporter per guild**. The first name alphabetically wins, and every client
   computes the same answer.
3. The reporter sends a compact summary of its guild about every 3 minutes on the hidden Olympus channel.
4. Every client adds up all the summaries: that is the census.

Nothing leaves the game. There is no server, no website, no account and no tracking.

**Realms vs layers.** A realm (ClassicBetaPvP, ClassicBetaPvP2...) is a separate world
with its own guilds; layers are copies of a zone *inside* one realm. Guilds on the same
realm always see each other, whatever layer they are on. Whether the hidden channel also
reaches another realm is not confirmed yet (the "topology" lines of `/oly bug` say so once
a report from the other realm arrives). Realms whose guilds span each other share one
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
| The Treasurer's book (balance, donations and who gave them, the ranking) and the guild bank of `<Olympus>` (its gold and items) | everyone on the Olympus channel receives the bytes; the addon shows them to the King, and to the army only with his switches | only after the Treasurer says yes (asked once; `/oly treasurer on\|off`), withdrawn at once when he turns it off |
| The King's crown on the map, and with it his zone and layer | everyone on the Olympus channel | only while the King turns it on (Throne tab), whatever he answered to the question |

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
position, no chat, nothing else. He can also ask a player on an old version to update: a fixed
window with the two version numbers and nothing else. Only his character on his realm group
can do either: every addon checks the sender's name, which nobody else can carry. `/oly
rollcall off` refuses both. The addon's error catcher keeps only Olympus's own errors (for
`/oly bug`), never another addon's.

The addon is plain Lua running on each player's computer, so anyone can edit their own
copy. No addon can prevent that. What this one does is make an edited copy useless:

- **Guild traffic is verified by Blizzard's servers.** Guild addon messages only reach
  members of that guild, so the realm key and guild elections can't be faked from outside.
- **Sender names cannot be forged.** The server stamps every message with its sender.
  - **The King and the Treasurer are known by name**, not by vote: only their characters can
    send their commands and the treasury. A report of `<Olympus>` naming anyone else as its
    leader counts for nothing, not even as a vote, so outsiders can't crown one of their own.
    Their names count on their realm group only (Forever's PvP realms): a namesake anywhere
    else is someone else, and there is no King there.
  - A decree counts only if the sender really is the Lord or a Captain of that guild,
    according to that guild's own roster report, or our own roster for our own guild.
    The rank written inside the message is ignored.
  - **Ranks come from the picture most senders agree on.** Every report from the last 30
    minutes is its sender's vote on who leads the guild and who its officers are. One sender
    changing or repeating a report can't move the majority. When two pictures have as many
    senders each, only what both agree on counts. No Crown rank counts in a client's first
    3 minutes, so a guild's own reporters have voted before anyone else can win.
  - A report never proves its own sender's rank: someone else's vote must name them. The
    runner-up of each guild's election also reports every 10 minutes (and answers census
    requests), so a Lord or officer who is the elected reporter is still verified. (An officer
    who is the only one of their guild with the addon is not.)
  - **The Crown** (any guild master, the officers of `<Olympus>`) needs two senders naming them.
  - A sender speaks for one guild only (a player who changed guilds can speak for the new one
    after 15 quiet minutes). A guild is one whatever the capitals a report spells it with: a
    second spelling is a vote on the same guild, never a second guild.
  - **The row everyone sees is the majority's**: a report against the picture most senders
    give is counted as a vote but does not replace what the census shows, so one outsider can't
    rename a Lord or shrink a guild on everyone's screen. A report claiming more members than a
    guild can hold is dropped as forged. A guild not heard from for a day leaves the total.
- **Only our channel counts**: addon messages that arrive on any other chat channel are
  ignored, so the sealed channel really keeps outsiders out.
- **Sealed channel** (`/oly key`): outsiders can't find the channel or join it.
- **Validation**: every number is range checked, names are length limited, and malformed
  messages are dropped. Decrees are rate limited per sender and in total.
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
- `/oly block <name>` ignores a player completely.

Limits, stated honestly:
- Votes are counted per sender name, and nothing the server tells an addon proves which guild
  a sender belongs to. So cooperating characters can still invent a guild with "Olympus" in
  its name (two of them naming a third as its leader), and reach [Lords] and the Crown's
  decrees. So can anyone who really founds such a guild. Against a real guild they need more
  senders than it has reporting (its reporter and runner-up: two at most). On the public
  channel anyone can try; **seal it with `/oly key`** and only members of Olympus guilds can.
- **The Forever beta forgets addon data at every login**: its client saves it but never loads
  it back ([a known beta bug](https://us.forums.blizzard.com/en/wow/t/savedvariables-never-load-in-the-beta-%E2%80%94-all-addon-settings-reset-on-login-69913/2354798)),
  so settings and the realm key reset every session. The census still refills in seconds: a
  client that logs in asks the channel, and each guild's reporter and runner-up answer at once.
- A real Olympus member who edits their copy could still send a wrong report for **their own**
  guild. Their guildmates' reports and the conflict flag make a changed leader, size or officer
  list visible, but it can't be made impossible.

## Built for a crowd of thousands

- One summary per guild about every 3 minutes, not one per player.
- In a full guild only the members who could be elected keep saying hello; the rest go quiet.
- Layers are announced by officers plus a stable 1 in 8 sample who share them, every 10 minutes.
- A layer request goes out once; only about 6 players answer it, each by a whisper to the asker.
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
| `/oly treasurer on\|off` | the Treasurer shares his book and the guild bank, or keeps them private |
| `/oly rollcall on\|off` | answer the author's roll calls (version, client, channel state) or not |
| `/oly inspection on\|off` | take part in the King's Royal Inspection when sampled (a 2-minute patrol reported to him), or not |
| `/oly issuereporter hide\|show` | hide Blizzard's Issue Reporter box (beta clients) at every login, or show it again (also a "Hide" button on it) |
| `/oly helpme [text]` (or **Ask a High Councillor** on the Realm tab) | ask the High Council (the moderators) for help: it goes by whisper to up to three of them online who take requests |
| `/oly council list` · `/oly council help on\|off` | the High Council as your addon knows it; moderators: take help requests or not. The list is signed by the author on his own computer and checked by every client: no name is written in the addon's code, and nobody can forge or change it |
| `/oly council icon` (or **My council icon** on the Realm tab, councillors only) | moderators: a councillor's name in the Olympus chats always carries the High Council's mark (the game's target-frame skull), which nobody can change. An icon of your own after it is optional: pick it from the game's icons, like a macro's. Your addon announces it on the channel (at once, then every 20 minutes), and other clients take it only from a councillor and only as a game icon |
| `/oly hop` | ask for an invite to the King's layer (while he is online) |
| `/oly vox off` · `/oly vox on` | Vox Populi questions in chat only, or in a window |
| `/oly layerhelp on` · `/oly layerhelp off` | get (or not) requests to invite players to your layer |
| `/oly layerauto on` · `/oly layerauto off` | invite layer requests without the window |
| `/oly location on` · `/oly location off` | share (or not) your zone and layer on the Olympus channel |
| `/oly key <secret>` | officers: seal the Olympus channel |
| `/oly block <name>` | ignore a player |
| `/oly map` | zone markers on the world map |
| `/oly sound` | alert sounds on or off |
| `/oly bug` | copyable bug report |
| `/oly status` | diagnostics in chat |

## Reporting a bug

While the addon's author is online, the **Report a bug** window also has a **Send to
Faladoriel Skylance** button: your report goes to him in game, by addon whisper, and nowhere
else (once every 10 minutes at most). It first checks he is really there: the rest follows
only once he answers, and you are told when he got it.

Type `/oly bug` (or press **Report a bug**), copy the text and open an issue on [GitHub](https://github.com/dnl-gentile/olympus-addon/issues). Errors are
also saved in `WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua`.

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


Source code: https://github.com/dnl-gentile/olympus-addon
