# Olympus Link: what your bot adds

Hi Fern. Your split works, with a few changes to your plan, [explained after the
steps](#why-these-changes-to-your-plan). Your bot keeps `/verify` and the whisper path, adds
`POST /proof`, does every check and gives the role with the same `promote()` you have, and you
make every confirmer's key, the High Councillors' too, as you planned (step 6b). Our side is the
addon (the QR code, councillors' addons signing with the keys you give them, `/oly discord
<code>` and Accept) and a page that is only a page: static, on GitHub Pages, it signs the player
in with Discord, reads the proof (screen share, phone camera, paste, or a file) and posts it to
your `/proof`. It has no database at all: who is mid-scan stays in the player's browser tab.

Everything below is for your Worker. The checks are already written, in one file you import:
[`web/worker/link-core.mjs`](worker/link-core.mjs) (no npm package, WebCrypto and `fetch` only).
[`WORKER.md`](WORKER.md) is the long reference: every check, every format, and a complete
example Worker.

## What you add to your bot (an afternoon)

You need your Worker, `wrangler`, and once, on your computer, Python 3 with `cryptography`
(`python3 -m pip install cryptography`) for your bot's key. Copy
`web/worker/link-core.mjs` next to your Worker's entry file.

### 1. The tables: one SQL file

```sh
wrangler d1 create olympus-link
wrangler d1 execute olympus-link --remote --file web/worker/schema.sql
```

```toml
# wrangler.toml
[[d1_databases]]
binding = "LINK_DB"
database_name = "olympus-link"
database_id = "<the id wrangler d1 create printed>"
```

A database of its own, bound as `LINK_DB`: the tables have plain names (`codes`, `keys`,
`members`...) that could meet yours in your bot's database.

### 2. Your bot's key: send us only the public half

```sh
python3 scripts/link-keys.py backend
```

It prints a seed and a public key, once, and writes nothing to disk. The seed is your Worker's
secret (`wrangler secret put LINK_BACKEND_SEED`; keep a copy in a password manager, nowhere
else). The public key (64 hex) is `LINK_BACKEND_PUBLIC` below, and the one thing Daniel puts in
the addon: every player's game checks your codes against it.

### 3. Settings

```toml
[vars]
LINK_BACKEND_PUBLIC = "<the 64 hex of step 2>"
LINK_ORIGIN = "https://dnl-gentile.github.io"
DISCORD_CLIENT_ID = "<your Discord application's client id>"
LINK_MODE = "c"                  # councillors only; "a" adds three drawn players (step 9)
LINK_GUILD_POLICY = "verified"   # a confirmer saw the player in the guild in game
# Leave these two out: the council authority is off (below).
# LINK_CA_PUBLIC = "a84125fa433276244fda242a28d2e4208a5d6db26dcb529e3e87af61939e10a7"
# LINK_COUNCIL_CHARACTERS = "<Name-Realm>, <Name-Realm>"
```

```sh
wrangler secret put LINK_BACKEND_SEED   # the seed of step 2
wrangler secret put LINK_ADMIN_TOKEN    # your admin route (steps 6 to 9): python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

- `LINK_CA_PUBLIC` stays out. It is the council authority, Daniel's client, which could certify
  keys the High Councillors' addons make in game. That path is off in the addon (Konig's
  review: a key made in game comes from a few tens of bits of frame timing, sits in plain text in
  the SavedVariables, and its certificate would last a year), so the councillors' keys are yours
  to make (step 6b), and without `LINK_CA_PUBLIC` your Worker takes none of the authority's
  certificates either. Should Daniel ever turn it on, he tells you, and you decide then: with
  it, a key the authority certifies counts as a councillor's, and one councillor's confirmation
  links a player ([FAQ](#can-the-page-or-daniel-give-anyone-a-role)).
- `LINK_COUNCIL_CHARACTERS` only matters with `LINK_CA_PUBLIC`: the High Councillors' characters
  you accept from the authority, as the game writes them (`Name-Realm`, comma-separated). A
  certificate of the authority for any other character then counts for nothing, whatever it
  signs; set but empty, none counts. Keys you make yourself don't need it.
- `LINK_ORIGIN` is our page's origin: the only one browsers let call your `/proof` (CORS). CORS
  binds browsers only: a script sends any origin it likes.
- In the Developer Portal, OAuth2, add our page as a redirect, exactly:
  `https://dnl-gentile.github.io/olympus-addon/`. The page signs players in with your
  application (scope `identify`), and your Worker checks with Discord that each sign-in is yours.
- Optional: the site token you offered, `wrangler secret put LINK_SITE_TOKEN`. See the
  [FAQ](#what-does-the-site-token-protect) for what it does and does not do.

### 4. Import the core

```js
import { issueCode, handleProof, handleInbox, handleKeys } from './link-core.mjs';
```

### 5. `/verify` gives a code

Where your Worker answers `/verify` today (HTTP interactions):

```js
if (interaction.type === 2 && interaction.data.name === 'verify') {
	const user = interaction.member?.user ?? interaction.user;
	const code = await issueCode(env, { id: user.id, username: user.username });
	return Response.json({ type: 4, data: { flags: 64, content: code.reply } }); // 64: only they see it
}
```

`code.reply` is ready to send: the line `/oly discord OLC2...` to paste in the game (the code is
signed with your key, good for 24 hours and one link), and a reminder to keep it off stream. When
there is no code it says why instead (3 a day per account; an old-style `#1234` username). A
second `/verify` gives the same unused code back while it has 12 hours left.

### 6. `POST /proof`, then your `promote()`; and your admin route

```js
export default {
	async fetch(request, env, ctx) {
		const url = new URL(request.url);
		const roles = {
			promote: (discordId) => promote(env, discordId), // your grant: throw if Discord refuses
			demote: (discordId) => demote(env, discordId), // optional: a character moved to another account
		};
		if (url.pathname === '/proof') return handleProof(request, env, roles);
		if (url.pathname === '/api/link/keys') return handleKeys(request, env); // LINK_ADMIN_TOKEN: revoking (step 7), player keys (step 9)
		// ...your routes
	},
};
```

`handleProof` answers the browser's preflight (`OPTIONS`) and the `POST`, and does, in order:
our origin only (never `*`); your site token, if you set one; the body
`{"text": "<the proof>", "discordToken": "<the player's Discord sign-in>"}`; the proof's form;
who the player is, asked of Discord (`GET /oauth2/@me`: your application, scope `identify`, not
expired; the token is stored nowhere); 10 tries an hour per account; then the checks you
already do plus the new ones (below), then it claims the code, calls your `promote(discordId)`,
and records the character. When `promote` throws (or returns `false`), the code is freed again
and the player can send the same proof a minute later; return `{ ok: false, reason:
'not-in-server' }` when the member is not in the server, and the page tells them to join first.
The answer is JSON with a `status` (`linked`, `rejected`, `error`) and a `reason` the page
explains in English or Portuguese.

The checks, each a few lines in `link-core.mjs`: the proof's tag matches the code's own signature
and the player who typed it (someone who saw the code on a stream gets nothing); the code is
yours, known, unused and not expired, and used once; every confirmation's Ed25519 signature,
with a key you registered or one the council authority certified (for a character on
`LINK_COUNCIL_CHARACTERS`, when you set it), not revoked, signed within the code's life; the
confirmer is neither the player nor one of the key owner's characters; a key counts once per
code; one councillor, or in mode `"a"` three drawn players (the draw is [not 3 of
5](#why-these-changes-to-your-plan)); the guild check.

`handleKeys` is your admin route from day one, behind `LINK_ADMIN_TOKEN`: it is how you register
the High Councillors' keys (step 6b), revoke a key in minutes (step 7), and later register player
keys (step 9).

One thing worth adding in Cloudflare's dashboard: a rate-limiting rule on `/proof` (say 20
requests a minute per IP). Each `/proof` with a token asks Discord once, and Discord blocks for a
while an address that sends it too many bad tokens; the rule keeps a flood of made-up tokens from
reaching Discord from your Worker.

Rather write the route yourself? `checkProof(env, text, { discordId })` gives the verdict and
writes nothing; `acceptProof(env, text, { discordId, promote, demote })` does the whole link;
`discordUser`, `corsHeaders`, `tooManyProofs` and `logProof` are the rest of `handleProof`.

### 6b. The High Councillors' keys: you make them

Every confirmer's key is one you make on your computer, the High Councillors' too: their addons
make no key of their own. For each councillor, once, for the one character that confirms:

```sh
python3 scripts/link-keys.py confirmer <id> c --character "<Name-Realm>" --owner <their Discord id> --username <their username> --bootstrap
```

It prints the `/oly discord key <id> <key>` line, which you send that councillor privately (a
direct message, never a channel), and the `curl` that registers the public key with your
`/api/link/keys`; the answer's `command` is their second line, `/oly discord cert OLK2...`. Both
fit the game's chat line. They type both on that character, in the addon release that carries
your bot's key (before it, the addon keeps neither and says Olympus Link is not open).
`--bootstrap` because at launch nobody has linked a character yet. One key per Discord account;
the certificate lasts 365 days, and `{"key_id": "<id>", "renew": true}` renews it
([WORKER.md](WORKER.md) step 8 has the rest). Daniel sends you the councillors' characters and
Discord accounts, and every change to the High Council.

### 7. Revoking, from day one

A leaked key (a councillor's or a player's: all of them yours) stops counting the moment you
revoke it, even for proofs signed before. With the admin route of step 6:

```sh
curl https://<your worker>/api/link/keys -H "Authorization: Bearer $LINK_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' --data '{"key_id": "<id>", "revoke": true}'
# every key of a character at once: --data '{"character": "<Name-Realm>", "revoke": true}'
```

Or without the route, from a checkout of this repository (the tool prints SQL only):

```sh
python3 scripts/link-keys.py revoke <id> > revoke.sql   # or: revoke --character "<Name-Realm>"
wrangler d1 execute olympus-link --remote --file revoke.sql
```

What each one stops, and how to rotate: [Revocation and rotation](#revocation-and-rotation).

### 8. Optional: the watcher's inbox (the whisper path)

```js
if (url.pathname === '/api/link/inbox') return handleInbox(request, env, roles); // next to /proof
```

On a High Councillor character of yours, `/oly discord watcher on`: players whose proof is ready
hand it to it by whisper, and its addon checks each one before it keeps it. Every day or two,
after a `/reload`:

```sh
LINK_ADMIN_TOKEN=... node web/tools/read-inbox.mjs "<WoW folder>/_classic_beta_/WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua" --post https://<your worker>/api/link/inbox
```

The code's owner is the one linked; a proof that already counted answers `already`.

### 9. Optional: player keys, for three drawn players

Only when you switch `LINK_MODE` to `"a"`, and at least 8 days before (a player key counts once
it is 7 days old). Read [the draw](#why-these-changes-to-your-plan) first: it is 3 of the keys
drawn for each code (20 or more of them, or all while there are fewer), not 3 of 5. The route is
step 6's `/api/link/keys`.

```sh
python3 scripts/link-keys.py confirmer <id> p --character "<Name-Realm>" --owner <their Discord id>
```

It prints the `/oly discord key <id> <key>` line to send the player privately, and the `curl`
that registers the public key with your `/api/link/keys`; once the key counts, that route
answers the second line, `/oly discord cert OLK2...`. Both fit the game's chat line.

## Why these changes to your plan

- **Ed25519, not HMAC** (Konig's security review). Your check stays one line, "verify the
  signature over the confirmation", with a public key instead of a secret. Your D1 then holds only
  public keys, so a leak or a dump forges nothing, and every player's addon (and your watcher's)
  can check each confirmation before it ever reaches you, so made-up proofs never arrive.
- **You mint the High Councillors' keys too, as you planned** (Konig's review). An earlier draft
  had their addons make their own keys in game and Daniel's client certify each one (the council
  authority, `LINK_CA_PUBLIC`), so nobody pasted anything. WoW's Lua has no cryptographic random
  source, so such a key comes from a few tens of bits of frame timing, sits in plain text in the
  SavedVariables, and its certificate would last a year. The addon still carries that path,
  behind a switch Daniel leaves off: no councillor's addon makes a key or asks for a
  certificate, his client signs none, and keys an earlier build made are removed at login. So
  `/oly discord key <id> <key>` exists exactly as you wrote it, for every key you mint (step 6b,
  and player keys in step 9), followed by one `/oly discord cert` line.
- **`keyId` to public key, not to a secret.** The same table (`keys`, with `revoked` and
  `revoked_at`), holding the public half. Ids you mint are 6 to 16 of a-z and 0-9 (`hc01` is too
  short); 12 hex digits are kept for the council authority's keys.
- **The draw: 3 of the drawn keys, not 3 of 5.** In mode `"a"`, each code draws M = max(20, 3%
  of the active player keys): all of them while there are 20 or fewer, 30 of 1000. The draw is
  signed into the code, so nobody picks who is drawn. Any 3 of the drawn keys, from 3 Discord
  accounts, signed within 5 minutes of each other, link. Players' addons ask the drawn keys 5 at
  a time, lowest first, but your Worker takes any 3 of the M. Why more than 5: players confirm
  only while they are online in game, and 3 of 5 keys are rarely online at the same moment. What
  it costs: key holders who agree to confirm for each other are drawn together far more often
  among 20 than among 5, and while there are 20 player keys or fewer, every key is drawn for
  every code, so any 3 of them, from 3 accounts, could confirm anyone. Give player keys only to
  people you trust that far, and stay in mode `"c"` until the pool is large. Rather have your 3
  of 5? The size of the draw is one line, `drawLimit` in `link-core.mjs`: the addon only follows
  the draw your Worker signs into each code, so nothing changes on our side (only the draw's
  test vectors assume 20), and fewer links will find three drawn players online.

Start with councillors only (`LINK_MODE = "c"`).

## What you send us, what we send you

You send us three things:

1. **Your bot's public key**, the 64 hex of step 2. It goes into the addon's next release; until
   then `/oly discord` says Olympus Link is not open.
2. **Your `/proof` address**, the whole `https://.../proof`.
3. **Your Discord application's client id**, once `https://dnl-gentile.github.io/olympus-addon/`
   is one of its OAuth2 redirects.

And, if you set them: the site token, and the name for "&lt;name&gt;'s watcher" in the game's texts.

We send you:

- The High Councillors' characters and Discord accounts, for the keys you make them (step 6b),
  and every change to the High Council after that. (Not the council authority's key: it stays
  off, and `LINK_CA_PUBLIC` out.)
- Our page: `https://dnl-gentile.github.io/olympus-addon/` (the redirect), origin
  `https://dnl-gentile.github.io` (`LINK_ORIGIN`).
- What we do on our side: turn on GitHub Pages (Settings > Pages > Source: GitHub Actions; the
  page then publishes from `main`), put your three things in `web/public/config.js` and the
  page's Content-Security-Policy, and release the addon with your public key.

## Testing

Everything in `link-core.mjs` runs against shared test vectors, with a local SQLite as D1 and
Discord as a stub, from a checkout of this repository (Node 22.13 or newer; nothing touches the
network):

```sh
node --test web/test                        # everything: the page, the core, the example Worker, the tools
node --test web/test/link-core.test.mjs     # the core alone
```

Once deployed, the preflight and the route, with a fake proof from the fixtures:

```sh
curl -i -X OPTIONS https://<your worker>/proof \
  -H 'Origin: https://dnl-gentile.github.io' -H 'Access-Control-Request-Method: POST'
# 204, Access-Control-Allow-Origin: https://dnl-gentile.github.io

curl -i https://<your worker>/proof \
  -H 'Origin: https://dnl-gentile.github.io' -H 'Content-Type: application/json' \
  --data '{"text":"OLB5~Some Player-ClassicBetaPvP~Olympus II~Alliance~0123456789abcdef~7K3M9QX2TB~5f2f66f046a1db8a~1799990100,council01,Test Councillor-ClassicBetaPvP,w,wYG_TW3fCOBxV9hteWMsnq2R8sBus8YaG-Dyb4SePjkl9a9Ub27i1okdpFxUh5aQASIZKKcXQbv0ocuXxvObBA,7IYl-lN-5QRTFG9QwpjrKSJZDGDe17VK3p6FcCpwIZs,c,1830000000,kuaVPJGR4ZwtCf2mtveDYem8nJmMfU-R4I-FndUaJCswUEoqDNECnB_oFNIj3DPMA18UgHkSK7L7X1oWZSMDCQ","discordToken":"not-a-real-discord-token"}'
# 401 {"status":"error","reason":"login",...}: CORS, the proof's form and Discord's check are wired
```

(With a site token set, add `-H 'Authorization: Bearer <the site token>'`, or the answer is
`site`.) The route's path is yours to choose: the page takes the whole address.

With the page, once your three things are in it: open it, choose "Other ways", paste that same
`OLB5~...` text, and sign in with Discord. The page sends it and your Worker answers
`unknown-code` (your D1 never issued that test code): the page, the sign-in, your `/proof` and
your D1, end to end, without the game. Then the real thing: `/verify`, the line in the game, a
High Councillor online, the QR code, and the role.

## Revocation and rotation

Every revocation goes through your admin route or the tool's SQL (step 7).

- **A councillor's key** (leaked or lost; `/oly discord key off` in game prints its id for them
  to send you): `{"key_id": "<id>", "revoke": true}`, or `revokeKey(env, '<id>')`. It stops
  counting at once. Their new key: register it with `"replace": true` and send them the two new
  lines ([WORKER.md](WORKER.md) step 8).
- **A councillor off the High Council**: send `{"character": "<Name-Realm>", "revoke": true}`,
  or `revokeCharacter(env, 'Name-Realm')`: every key you registered for that character stops
  counting (and every certificate the council authority signed for it, should you ever set
  `LINK_CA_PUBLIC`: then take it off `LINK_COUNCIL_CHARACTERS` too).
- **A player key**: revoke it the same way; rotate with a new key and `"replace": true`.
- **Your bot's key**: make a new one and send us its public key (the addon takes two while it
  changes). Once that release is out, switch `LINK_BACKEND_SEED` and `LINK_BACKEND_PUBLIC`, then
  renew every key you registered: `{"key_id": "<id>", "renew": true}` to `/api/link/keys` signs
  its certificate with the new key, and you send that confirmer the new `/oly discord cert` line.
  The keys to renew:
  `wrangler d1 execute olympus-link --remote --command "SELECT key_id, character FROM keys WHERE revoked = 0 AND replaced_at IS NULL AND cert_exp IS NOT NULL"`.
  Tell us when they have their new lines, the High Councillors' included: only then do we take
  the old key out of the addon, since a certificate the old key signed stops checking in
  players' addons once it is gone. Codes already handed out stay good until they expire.
- **The council authority's key** (only if you ever set `LINK_CA_PUBLIC`): it takes two,
  comma-separated, while it changes. If its seed leaked, take the old key out of
  `LINK_CA_PUBLIC` at once: no certificate it signed counts from then on (keys you registered
  yourself still do).

## FAQ

### What if the QR code can't be scanned?

The page takes the same proof four ways: sharing the WoW window, a phone's camera, the link from
the window's copy box (Ctrl+C, then paste), or a screenshot or `Olympus.lua` dropped on it. And a
player who does nothing still gets there: their addon hands the proof to your watcher (step 8).
The proof waits in the game for 7 days either way.

### What does the site token protect?

Less than it sounds. Our page is public, so the token sits in `web/public/config.js` for anyone
to read, and anything that reads it can send it: it does not tell the page's calls from anyone
else's. It is a switch: change `LINK_SITE_TOKEN` and the page stops reaching you at once (until
we put the new one in the page). CORS does not tell them apart either: it binds browsers only,
and a script sends whatever `Origin` it likes (the `curl` in [Testing](#testing) does). What
protects `/proof` is the rest: the player's Discord sign-in checked with Discord (only your
application's, which Discord hands only to the redirect you registered), the signatures in the
proof, one use per code, and 10 tries an hour per account.

### What data is stored, and where?

Only in your D1 (the page stores nothing on any server): the codes (Discord id and username,
when, used or not); the linked characters (name, guild, faction, how the guild was checked, the
Discord id); which confirmer keys counted for which code; confirmer public keys (never a private
key); the revocation lists; and a log of every proof received (source, code, Discord id,
character, result). Never a Discord token, never an IP address.

### How is someone's data deleted?

`forgetUser(env, discordId)` removes that account's linked characters, codes and log lines, and
revokes the confirmer keys it owns. Without code, the same from a checkout of this repository:

```sh
python3 scripts/link-keys.py forget <their Discord id> > forget.sql
wrangler d1 execute olympus-link --remote --file forget.sql
```

Take the role away with your own `demote`. Dropping the `olympus-link` database removes
everything.

### Can the page, or Daniel, give anyone a role?

The page, no. It only forwards what the game signed, your Worker checks all of it, and the addon
never sees your key's secret half.

Daniel, not as it ships: the council authority is off in the addon (a switch only he turns on),
and while `LINK_CA_PUBLIC` stays out your Worker takes none of its certificates, so every key
that counts is one you made. Should he turn it on and you set `LINK_CA_PUBLIC`, then yes, and so
could anyone who copied his council authority's seed (`LinkCA.lua`, which only his own game
loads): a key the authority certifies counts as a High Councillor's, and in mode `"c"` one
councillor's confirmation links.
Without `LINK_COUNCIL_CHARACTERS`, whoever holds that seed can certify a key for a character name
you never heard of, confirm any character with it, and link it to any Discord account whose
`/verify` code they have (their own, an alt's, a friend's); your `promote()` then gives the role.
Without the list, revoking that character does not stick either: a certificate the authority
signs after the revocation counts again. That is the trust `LINK_CA_PUBLIC` asks of you. What
keeps it with you:

- **Limit it**: `LINK_COUNCIL_CHARACTERS` (step 3). Only the councillors you list count, whatever
  the authority signs, now or later. The authority can still certify a new key for one of them
  (that is how a councillor's `/oly discord key new` works), so watch for keys you don't expect.
- **See it**: each key the authority certified is recorded with the first link it helped accept,
  and every link records the keys that counted for it:

  ```sh
  wrangler d1 execute olympus-link --remote --command "SELECT key_id, character, datetime(first_seen, 'unixepoch') FROM council_keys ORDER BY first_seen DESC"
  wrangler d1 execute olympus-link --remote --command "SELECT m.character, m.discord_id, u.key_id, datetime(u.t, 'unixepoch') FROM used u JOIN members m ON m.r = u.r ORDER BY u.t DESC LIMIT 50"
  ```

- **Cut it**: revoke a key or a character (step 7), or take `LINK_CA_PUBLIC` out, and no
  certificate of the authority counts (councillor keys you register yourself still do).
- **Or hold every councillor key yourself**, as you planned and as it ships: leave
  `LINK_CA_PUBLIC` out and mint each councillor's key (step 6b,
  `python3 scripts/link-keys.py confirmer <id> c --character "<Name-Realm>" --owner <their Discord id> --bootstrap`,
  [WORKER.md](WORKER.md) step 8). Each councillor types your two lines in game.

### Our origin is all of `dnl-gentile.github.io`: does that matter?

CORS works on origins, so any page Daniel publishes on GitHub Pages shares it, and CORS binds
browsers only anyway. A call would still need a Discord sign-in made for your application, which
Discord sends only to the redirect you registered, our page. A custom domain for the page would
give it an origin of its own later.
