# Contributing to Olympus

Read [AGENTS.md](AGENTS.md) first: it says how changes are tested and checked. Every change runs
`bash scripts/check.sh` from the repository root (LuaJIT and Bash).

## Touching the game's own windows

Anything that reaches into the game's UI (its frames, popups, menus, tooltips, chat box, bindings,
tables or globals) goes through the gamepad gate: an entry in `Olympus/GamepadRegistry.lua`, a
`-- gp:<id>` tag on each site, `ns.Gate.Allowed("<id>")` before it, and a test in the gamepad pass
(`tests/gamepad.lua`). The steps are in [AGENTS.md](AGENTS.md) ("Registering a gamepad
integration"); `bash scripts/check.sh` runs `scripts/gamepad-audit.lua`, which names the file and
line of anything left out, and the offline suite runs the gamepad pass.

## Adding or finishing a language

Olympus shows its text in the game's language when it has lines for it. English
(`Olympus/Locales.lua`, the `L.KEY = "..."` lines at the top) is the reference, and Portuguese
(the `ptBR` block in the same file) is complete. Spanish, French and German (1.1) have files of
their own under `Olympus/Locales/` and cover the main screens, the alerts and decrees, the Join
screen and its whisper, the chats and the privacy questions. Any line a language leaves out stays
English, so a language can grow a few lines at a time.

Only the text on the player's screen changes with the language. Nothing sent between players
does: messages carry codes, and the census, the chats and the decrees read the same on every
client. So adding a language can't break anyone else's addon.

### A new language

1. Find the game's code for it: what `GetLocale()` returns in that client (`deDE`, `esES`,
   `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`).
2. Copy `Olympus/Locales/frFR.lua` to `Olympus/Locales/<code>.lua` and change its
   `ns.Locale("frFR", {` line to your code. Several codes can share one file:
   `ns.Locale({ "esES", "esMX" }, {`.
3. Translate the values. Keep each key as it is, and translate as many or as few lines as you
   like: the rest stays English.
4. Add the file to `Olympus/Olympus.toc`, right after the other `Locales\...` lines and before
   `Core.lua`, and to the list of files `tests/run.lua` loads at its top (`"Locales/<code>"`).
5. Add it to the language tests in `tests/run.lua` (search for "1.1 languages": the table of
   codes and files), then run `bash scripts/check.sh`.

### Rules for each line

- **Format codes stay, in the same order.** `%s`, `%d`, `%02d` and `%%` are where the addon puts
  a name, a number or a percent sign. Lua can't reorder them, so the translation must keep them
  in the English order, even when the sentence reads more naturally another way.
- **Escape codes stay too.** `|cffe6c35c` starts a colour and `|r` ends it; `|T...|t` is an icon.
  Keep them, in the same order, around the same words.
- **`\n` is a line break.** Keep the blank lines of the long questions.
- **Commands stay in English.** `/oly location on`, `/oly key <secret>` and the like are what
  the player types: translate the words around them (`<secret>` may become `<segredo>`), never
  the command itself.
- **Names stay.** Olympus, Discord, CurseForge and WowUp are names; so is `<Olympus>`, the King's
  guild.
- **Short lines stay short.** Tab names, buttons and list lines have a fixed width: keep them
  about as long as the English one.

A line that breaks the first two rules is left out when the game loads (it shows in English), and
`/oly status` lists it on its `language:` line; the tests in `tests/run.lua` fail on it, so
`bash scripts/check.sh` finds it before anyone plays.

### Checking it in game

Set the game (or the Battle.net launcher) to your language, restart the game, and check:

- `/oly status`: its `language:` line names your code and how many lines were taken, and lists
  none left out;
- the Census, the Realm, the Decrees and the Tabards tabs, and the Join screen (on a character
  outside an Olympus guild);
- a decree preview (`/oly arms test`), and the privacy question for the Olympus chats (your first
  line in each of them).

Open a pull request with the file, the TOC and test lines, and what you checked in game.
