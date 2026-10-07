# Security

## Reporting a problem

If you find a way to abuse Olympus (pass yourself off as the King or the Treasurer, forge
ranks, lock the channel, read or send what your rank shouldn't, break other players'
clients), please tell the author privately first:

- on GitHub, **Security → Report a vulnerability** (a private advisory only the author sees), or
- on Discord, a direct message to the author (Faladoriel).

Please don't post a working exploit publicly before a fix ships. Reporters are credited in
the release notes, unless they'd rather not be.

Bugs that are not about security, and ideas, are welcome as
[issues](https://github.com/dnl-gentile/olympus-addon/issues) and pull requests.

## What an addon can and cannot do

Olympus is plain Lua, run by World of Warcraft's addon sandbox, the same for every addon:

- It **can't** read or write any file except its own saved data
  (`WTF/Account/<account>/SavedVariables/Olympus.lua`), open a network connection, reach
  the internet, see your password, your Battle.net account or anything else on your
  computer, or start programs. The game doesn't give addons any of that.
- It talks only **inside the game**, with addon messages: its hidden chat channel, your
  guild's addon messages, and whispers to one player.
- It never moves items or gold, and it never sends chat for you unless you type it.

The code is public (MIT). The download on CurseForge is this repository's `Olympus` folder at
the release tag; each GitHub release carries the same zip.

## What it sends

See [Privacy](README.md#privacy) in the README: what goes out, to whom, and what is off
until you turn it on.

## The trust model, briefly

- **Sender names can't be forged.** Blizzard's server stamps every message with its sender.
- **The King and the Treasurer are fixed characters.** Their commands count only when they
  come from those exact characters, so nobody else can issue them, whatever the census says.
  Since 1.0.0 the King's decrees and [Lords] lines count by his name too, with no census.
- **The King's Steward (1.0.0) is the author's signature.** The High Council's titles list,
  signed by the author's key like the council, can mark a character the Steward of his
  faction's King (on the list's realm group). Every client takes from him, by his name, a list
  of Hands of his own beside the King's (sent by his client alone; nobody changes anyone else's
  list; his Hands have the same Crown for `<Olympus>` on the other guilds' clients as the
  King's, and the King can't take them back: he does, or the author by removing him), what the
  King alone set before: the treasury's keepers and what the army sees of it
  (dated; the newest wins and the King's newer word always wins), and the Crown's decrees for
  `<Olympus>` on every client. He sees the whole treasury as the King does (the balance, the
  ranking, every keeper's shared book and the guild bank, whatever the switches), and every
  keeper is told so before sharing. Never the King's own list of Hands, his crown on the map,
  his court, writs, pardons, the untabarded list, or his own book of the treasury and his yes to
  share it. No name is written in the code and no census vote makes one; a newer signed list
  without him ends it at once, and the Hands he named with it on every client (named again
  later, he starts from none, as long as his addon saw the list without him on any of his
  characters there: it forgets what it kept of his list then). A word of the
  treasury dated more than a minute ahead of the server's clock is not taken. The trust this
  adds is in the author's key: whoever holds it can make a character act for the King in these,
  as it can name the High Council.
- **Ranks of other guilds come from the census**, the picture most senders agree on, and a
  census report is its sender's word: nothing the server tells an addon proves which guild a
  sender belongs to. So a few characters working together can, today (1.0.0):
  - make one of them the Lord of a made-up Olympus guild with two characters, even two alts of
    one account logged in one after the other: [Lords] lines and the Crown's decrees (raid
    warnings) on every client;
  - make Captains of a made-up guild with one report, and with six of them fill the army's
    flood guard (6 decrees a minute), so that every other decree a census rank vouches for is
    dropped for that minute;
  - leave a real guild contested with two senders (its Lord and officers lose their rank on
    every other client while they vote), or take its picture with three (its reporter and
    runner-up are two votes at most);
  - show other numbers for a guild with one report that copies its leader and officers (800
    members as 1, the King offline), and add up to 1,000 soldiers to the army's total for a day
    with each made-up guild;
  - have a made-up Captain's party invite accepted for a player who asked for a layer hop, and
    put an innocent player on the King's untabarded list with his inspection report.

  What 1.0.0 hardened: the King's decrees and [Lords] lines need no census, nor the Hands'
  for `<Olympus>` (the word of the King, or of the Steward whose own list names them); those,
  the Steward's and your own guild's officers' decrees never wait behind
  the flood guard; a decree speaks for one guild per sender, as the chats do, and its
  words go out with Blizzard's logged addon-message function; and the officers of `<Olympus>`,
  whom three outsiders' reports could add to the Crown on every client outside `<Olympus>`
  before 1.0.0, are of the Crown only on its own members' clients (their roster), and
  elsewhere only the Hands the King's list or a Steward's own list names (their word, never a
  vote; the King can't take back a Steward's Hand: that Steward does, or the author by
  removing him). The README's
  [What colluding characters can reach](README.md#what-colluding-characters-can-reach) has
  each outcome. A full structural fix would require **signed leadership**: ranks that come
  with a signature every client checks, instead of a count of votes. Meanwhile seal your
  channel with `/oly key`, so that only members of Olympus guilds can take part.

  The 1.2 code contains a deliberately dormant migration reader for such a list. An ordinary
  signed titles list has exactly the behaviour above. Only an explicit author-signed `enforce`
  manifest changes a client to signed ranks; once accepted for a faction and realm group, that
  boundary is kept locally and an expired, malformed, revoked or later absent manifest grants
  nobody instead of falling back to census votes. The current titles carrier is capped at 3,000
  bytes and cannot hold a complete leadership snapshot for the live federation, so enforcement
  is not activated. Older clients ignore the extension and continue using census ranks, so a
  mixed-version realm would not enforce one authority boundary either. This limitation remains
  open until a complete, scalable distribution and revocation protocol, plus its client migration,
  is reviewed and deployed.
- **Nothing on the channel is encrypted.** Everyone on it receives [Olympus], [Captains] and
  [Lords]; the addon only decides what to show. Don't write anything there that must stay
  secret.
- **The channel is an ordinary WoW chat channel.** WoW hands its ownership to one of its members.
  Olympus never uses that power. If someone locks the channel, the addon keeps retrying,
  and an honest owner's addon undoes the lock.
