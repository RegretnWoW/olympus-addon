# Working on Olympus

## Scope and context

- Keep changes focused on the requested task and follow nearby Lua patterns.
- Read `README.md` for addon behaviour and development commands. Runtime code is
  in `Olympus/`; `Olympus/Olympus.toc` declares supported interfaces and load order.
- Use the existing offline harness in `tests/run.lua` and fixtures in
  `tests/fixtures/` when adding coverage.

## Tests for changes

- For every bug fix, add a regression test that fails for the original bug and
  passes with the fix. Verify this against the pre-fix code or by temporarily
  removing the fix in a scratch copy, when practical.
- For new or changed behaviour, add or update tests covering the expected result
  and relevant failure cases. Check whether existing coverage already exercises it.
- Exercise the actual addon functions and assert observable outcomes. Avoid
  duplicating the implementation inside a test.
- Change assertions or mocks to reflect intended behaviour or verified client
  behaviour, and explain those changes. Do not weaken them just to make a test pass.
- If the offline harness cannot reproduce a bug, explain that limitation and give
  concrete in-game reproduction steps and expected results in the PR.
- For documentation-only changes, validate referenced paths, commands and claims.

## Checks

For code or test changes, run `bash scripts/check.sh` from the repository root when
that script is present. Otherwise run the commands below. Both routes require
LuaJIT and Bash.

```sh
luajit tests/run.lua
bash scripts/lint-globals.sh
```

The lint script checks for globals that share a name with a local in the same file.
See `README.md` for packaging and deployment commands when relevant to the task.

## Registering a gamepad integration

Players use Blizzard's gamepad UI and no release is tried with a controller first, so the checks
stand in. Code that touches the game's own UI (its frames, popups, menus, tooltips, chat box,
bindings, tables or globals, or its restricted calls) is an integration with the gamepad gate:

1. Add an entry to `Olympus/GamepadRegistry.lua` (or extend one): what the game does with it, and
   what it does at a login with the gamepad UI on and at each switch between the two modes.
2. Tag every site with `-- gp:<id>` (end of the line, on the line above the statement, or on the
   first line of a function to cover its own body). `<id>!hook` marks a site only that id's
   `Gate.Hooks` runs; `<id>!undo`, one that gives back what the id took, in both modes.
3. Ask the gate before the first touch: `if not ns.Gate.Allowed("<id>") then return end`, also as
   the first line of every function handed to the game.
4. When it leaves something on the game's side, give it `ns.Gate.Hooks("<id>", { install = ...,
   park = ..., leftover = ... })`.
5. Exercise it in the gamepad pass, `tests/gamepad.lua`, and name it there with
   `GP.Covers("<id>")`: a gamepad login, a switch each way, and what it must leave.
6. Run `bash scripts/check.sh`. `scripts/gamepad-audit.lua` fails on an untagged reach, a tag with
   no entry, a write to a global that is not Olympus's, a gate entry's site with no gate check
   before it, a stale entry, an entry no test covers, and GameTooltip or chat-window uses above
   `scripts/gamepad-baseline.txt` (raise a line there only in the same change, so review sees it).

The gamepad pass loads every addon file into a model of Forever's client, whose globals, members,
events, widget methods and templates are only those in `tests/fixtures/forever-api.lua`. A model
may not offer what the client lacks, and each model part cites the Blizzard file it follows. When
the addon reads a name the fixture doesn't list, or the Forever build changes, regenerate it with
`luajit scripts/forever-api.lua <Interface folder>` and check the registry's source pins with
`luajit scripts/forever-pins.lua <Interface folder>`; the extracted UI source is not in the
repository. Tests switch the gamepad UI through its input style (`WithGamepadUI`,
`GamepadStyle`), never by replacing `ns.GamepadUI` or `ns.Gate`.

## Client compatibility and handoff

- Follow existing client compatibility guards and verify any newly used WoW API
  against the supported client. A method provided by a mock does not establish
  that the real client provides it.
- Offline tests use simulated WoW APIs and UI frames. Include specific in-game
  checks for client-dependent behaviour such as chat routing, UI interaction and
  communication between players.
- Report the commands run and their results, any checks skipped and why, and the
  in-game verification still needed. Claim an in-game check passed only if observed.
