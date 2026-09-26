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
- **Ranks of other guilds come from the census**, the picture most reporters agree on. Several
  characters working together can still invent a guild with "Olympus" in its name and reach
  what its Lord could (anyone who really founds such a guild can too). Seal your channel
  with `/oly key` so that only members of Olympus guilds can take part.
- **Nothing on the channel is encrypted.** Everyone on it receives [Olympus], [Captains] and
  [Lords]; the addon only decides what to show. Don't write anything there that must stay
  secret.
- **The channel is an ordinary WoW chat channel.** WoW hands its ownership to one of its members.
  Olympus never uses that power. If someone locks the channel, the addon keeps retrying,
  and an honest owner's addon undoes the lock.
