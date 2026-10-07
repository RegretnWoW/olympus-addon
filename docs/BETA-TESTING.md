# Testing an Olympus beta

An automated pass and an in-game pass are different evidence. Record both. A green
repository check means the Lua, fixtures and package invariants passed offline; it does not mean
that a World of Warcraft client, gamepad flow or exchange between real players was observed.

## 1. Build gate (automated)

Start from the exact commit to be tested, in a clean Git worktree. `package.sh` refuses tracked
changes and any untracked or ignored file under `Olympus/` or `Olympus_Arena/` that could enter a
zip.

```bash
git status --short
git diff --check
bash tests/check-scripts.sh
bash scripts/check.sh
node --test web/test/*.test.mjs
scripts/package.sh --test N
```

The last command writes four tester artifacts:

- `dist/Olympus-<version>-testN.zip`
- `dist/Olympus-<version>-testN.files.txt`, the sorted files in that zip
- `dist/Olympus-<version>-testN.sha256`, the zip's SHA-256
- `dist/Olympus-<version>-testN.txt`, install and rollback instructions

Review the manifest before distributing the zip. On macOS verify it from `dist/` with
`shasum -a 256 -c Olympus-<version>-testN.sha256`; on Linux use `sha256sum -c`.
Keep the test zip and its sidecars together. Test builds expire, identify their build and commit
in game, stay in their test group, and are not release files.

## 2. One Windows client (observed)

1. Quit World of Warcraft. Back up both addon folders and
   `WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua`.
2. Verify the downloaded zip in PowerShell. The printed hash must equal the first field of the
   supplied `.sha256` file:

   ```powershell
   (Get-FileHash .\Olympus-<version>-testN.zip -Algorithm SHA256).Hash
   ```

3. Turn off automatic updates for Olympus while testing. Delete the installed `Olympus` and
   `Olympus_Arena` folders, then extract the zip directly into
   `<WoW flavor>\Interface\AddOns\`. Do not leave an extra zip-named directory around them.
4. Restart the game. Confirm the addon list shows the test number and `/oly arena status` shows
   the expected build, base version, lane and commit. Record any Lua error before continuing.
5. Walk the main windows at the tester's normal resolution and UI scale, then at one smaller
   scale. Check tabs, Back, scroll areas, hover help, overlays, portraits, close/reopen and combat
   transitions. Run the built-in simulation/UI tour where it is available.
6. Repeat the critical path with gamepad mode on, then turn it off during the same session. No
   protected game window should be forced and no taint or blocked-action error should appear.
7. Check `enUS`, `ptBR`, and at least one locale that intentionally falls back to English. Look
   for clipped labels, broken format placeholders and buttons narrower than their text.
8. `/reload`, relog, and restart the client. Record what persisted and what the client discarded.
   Use `/oly bug` and, after a reload or logout, `WOW_HOST=user@pc scripts/logs.sh` for the evidence.

Rollback is also an observed gate: quit the game, remove both test folders, reinstall the current
release from the addon app, restore saved data only if needed, restart, and confirm the release
version loads without errors.

## 3. Mixed-version and multi-account session (observed)

Use the same zip and SHA-256 on every tester. Start with practice currency and a party or raid;
move to any real-value rehearsal only after the practice ledger reconciles.

The minimum useful session has two participants, the people responsible for directing and
settling the session, a spectator, and one client on the previous public release. Also keep one
non-participant outside the group. Record each character, version, role, client flavor, gamepad
state and join/leave time.

Exercise a complete successful cycle before the hostile cases. Then cover, without bypassing the
buttons and functions players really use:

- a late join, leave and rejoin; `/reload` and a client disconnect during an open session;
- an older client in the group and an older client outside it;
- an unauthorized action, a repeated click, duplicate result and attempted double settlement;
- a stale or delayed action, actions arriving in a different order, and a session closed early;
- insufficient balance, an unavailable responsible player, cancellation, refund and recovery;
- gamepad and keyboard users together, combat/instance transitions, ignore/block and rate limits;
- a ten-minute burst/soak with several simultaneous users, watching queues, memory and errors.

After each money-moving scenario, reconcile the opening balance, accepted inputs, refunds, fees,
payouts and closing balance independently on both sides. An unexplained difference is a failed
gate, even when the UI looked correct.

The in-addon Director checklist is the session record. Mark each item Pass, Fail or Skip with a
short observation, then copy its test report. A skip is not a pass.

## Evidence and promotion

Keep one small table for every candidate:

| Gate | Evidence | Result |
|---|---|---|
| Repository and package | commit, command log, manifest, SHA-256 | Pass / Fail |
| Windows client | client build, screenshots, `/oly bug`, saved log | Pass / Fail / Not run |
| Gamepad, locales and UI | client build and observations | Pass / Fail / Not run |
| Mixed-version session | roster, versions and report | Pass / Fail / Not run |
| Multi-account/adversarial | roster, ledger reconciliation and report | Pass / Fail / Not run |
| Rollback | release restored and restarted | Pass / Fail / Not run |

Do not describe a client or multiplayer gate as passed until somebody observed it. Do not promote
a candidate with an unexplained Lua error, an unintended recipient, a missing recovery path, an
unreconciled balance or a rollback failure.

A [CurseForge Beta file](https://support.curseforge.com/support/solutions/articles/9000197242-file-types-and-additional-fields)
is a public, opt-in distribution. Use it only after the build is safe to publish. Named or closed
testers receive the expiring test zip and its checksum directly; that test zip is not uploaded to
CurseForge or GitHub.
