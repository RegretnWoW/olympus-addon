# Olympus Link: what your bot adds

Hi Fern. Your split works as you wrote it. Your bot keeps `/verify` and the whisper path, adds
`POST /proof`, does every check and gives the role with the same `promote()` you have. Our side is
the addon (the QR code, councillors signing on their own, `/oly discord <code>` and Accept) and a
page that is only a page: static, on GitHub Pages, it signs the player in with Discord, reads the
proof (screen share, phone camera, paste, or a file) and posts it to your `/proof`. It has no
database at all: who is mid-scan stays in the player's browser tab.

Everything below is for your Worker. The checks are already written, in one file you import:
[`web/worker/link-core.mjs`](worker/link-core.mjs) (no npm package, WebCrypto and `fetch` only). A
few things differ from your plan, all small, and [why](#why-these-changes-to-your-plan) comes
right after the steps. [`WORKER.md`](WORKER.md) is the long reference: every check, every format, and a
complete example Worker.

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

### 3. Settings, `LINK_CA_PUBLIC` among them

```toml
[vars]
LINK_BACKEND_PUBLIC = "<the 64 hex of step 2>"
LINK_CA_PUBLIC = "a84125fa433276244fda242a28d2e4208a5d6db26dcb529e3e87af61939e10a7"
LINK_ORIGIN = "https://dnl-gentile.github.io"
DISCORD_CLIENT_ID = "<your Discord application's client id>"
LINK_MODE = "c"                  # councillors only; "a" adds the 3-of-5 draw (step 8)
LINK_GUILD_POLICY = "verified"   # a confirmer saw the player in the guild in game
```

```sh
wrangler secret put LINK_BACKEND_SEED   # the seed of step 2
wrangler secret put LINK_ADMIN_TOKEN    # only for steps 7 and 8: python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

- `LINK_CA_PUBLIC` is the council authority, Daniel's client: it certifies the High Councillors'
  keys, so you never mint or paste theirs.
- `LINK_ORIGIN` is our page's origin: the only one your `/proof` answers to (CORS).
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

### 6. `POST /proof`, then your `promote()`

```js
export default {
	async fetch(request, env, ctx) {
		const url = new URL(request.url);
		const roles = {
			promote: (discordId) => promote(env, discordId), // your grant: throw if Discord refuses
			demote: (discordId) => demote(env, discordId), // optional: a character moved to another account
		};
		if (url.pathname === '/proof') return handleProof(request, env, roles);
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
with a key you registered or one the council authority certified, not revoked, signed within
the code's life; the confirmer is neither the player nor one of the key owner's characters; a
key counts once per code; "1 councillor or 3 of 5" with the draw; the guild check.

One thing worth adding in Cloudflare's dashboard: a rate-limiting rule on `/proof` (say 20
requests a minute per IP). Each `/proof` with a token asks Discord once, and Discord blocks for a
while an address that sends it too many bad tokens; the rule keeps a flood of made-up tokens from
reaching Discord from your Worker.

Rather write the route yourself? `checkProof(env, text, { discordId })` gives the verdict and
writes nothing; `acceptProof(env, text, { discordId, promote, demote })` does the whole link;
`discordUser`, `corsHeaders`, `tooManyProofs` and `logProof` are the rest of `handleProof`.

### 7. Optional: the watcher's inbox (the whisper path)

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

### 8. Optional: player keys, for "3 of 5"

Only when you switch `LINK_MODE` to `"a"`, and at least 8 days before (a player key counts once
it is 7 days old):

```js
if (url.pathname === '/api/link/keys') return handleKeys(request, env);
```

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
- **No minting for High Councillors.** Their addons make their own keys in game, and Daniel's
  client certifies each one when they meet (the council authority, `LINK_CA_PUBLIC`). Your Worker
  takes a councillor's key from the certificate the proof carries and records it the first time
  it helps accept a link. You keep the power that matters: revoking a key, or every key of a
  character (below). `/oly discord key <id> <key>` exists exactly as you wrote it, for the keys
  you do mint (player keys in step 8), followed by one `/oly discord cert` line.
- **`keyId` to public key, not to a secret.** The same table (`keys`, with `revoked` and
  `revoked_at`), holding the public half. Councillors' ids are the first 12 hex of their key's
  hash, so nobody names them; ids you mint are 6 to 16 of a-z and 0-9 (`hc01` is too short).

"1 councillor or 3 of 5" is already the rule, and nobody picks who is drawn: the threshold is
signed into each code. Start with councillors only (`LINK_MODE = "c"`).

## What you send us, what we send you

You send us three things:

1. **Your bot's public key**, the 64 hex of step 2. It goes into the addon's next release; until
   then `/oly discord` says Olympus Link is not open.
2. **Your `/proof` address**, the whole `https://.../proof`.
3. **Your Discord application's client id**, once `https://dnl-gentile.github.io/olympus-addon/`
   is one of its OAuth2 redirects.

And, if you set them: the site token, and the name for "&lt;name&gt;'s watcher" in the game's texts.

We send you:

- The council authority's public key: `LINK_CA_PUBLIC` above.
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

- **A councillor's key** (leaked, or replaced with `/oly discord key new`, which prints the old id
  for them to send you): `{"key_id": "<12 hex>", "revoke": true}` to `/api/link/keys`, or
  `revokeKey(env, '<12 hex>')`. It stops counting at once, seen before or not.
- **A councillor off the High Council**: `{"character": "<Name-Realm>", "revoke": true}`, or
  `revokeCharacter(env, 'Name-Realm')`: every certificate the council authority signed for that
  character until now stops counting, whatever key it names. In Daniel's game,
  `/oly discord certified` lists what his client certified (key id, character, end).
- **A player key**: revoke it the same way; rotate with a new key and `"replace": true`.
- **Your bot's key**: make a new one, send us its public key (the addon takes two while it
  changes), wait for that release, then switch `LINK_BACKEND_SEED` and `LINK_BACKEND_PUBLIC`.
  Codes already handed out stay good until they expire.
- **The council authority's key**: `LINK_CA_PUBLIC` takes two, comma-separated, while it changes.

## FAQ

### What if the QR code can't be scanned?

The page takes the same proof four ways: sharing the WoW window, a phone's camera, the link from
the window's copy box (Ctrl+C, then paste), or a screenshot or `Olympus.lua` dropped on it. And a
player who does nothing still gets there: their addon hands the proof to your watcher (step 7).
The proof waits in the game for 7 days either way.

### What does the site token protect?

Less than it sounds: our page is public, so the token sits in `web/public/config.js` for anyone to
read. It is a switch: change `LINK_SITE_TOKEN` and the page stops reaching you at once (until we
put the new one in the page), and it tells the page's calls from anyone else's in your logs. What protects `/proof` is the
rest: the player's Discord sign-in checked with Discord (only your application's, which Discord
hands only to the redirect you registered), the signatures in the proof, one use per code, 10
tries an hour, and CORS for our origin.

### What data is stored, and where?

Only in your D1 (the page stores nothing on any server): the codes (Discord id and username,
when, used or not); the linked characters (name, guild, faction, how the guild was checked, the
Discord id); which confirmer keys counted for which code; confirmer public keys (never a private
key); the revocation lists; and a log of every proof received (source, code, Discord id,
character, result). Never a Discord token, never an IP address.

### How is someone's data deleted?

`forgetUser(env, discordId)` removes that account's linked characters, codes and log lines, and
revokes the confirmer keys it owns; take the role away with your own `demote`. Dropping the
`olympus-link` database removes everything.

### Can the page, or Daniel, give anyone a role?

No. Only your `promote()`, after your Worker's checks. The page only forwards what the game
signed, and the addon never sees your key's secret half.

### Our origin is all of `dnl-gentile.github.io`: does that matter?

CORS works on origins, so any page Daniel publishes on GitHub Pages shares it. It would still need
a Discord sign-in made for your application, which Discord sends only to the redirect you
registered, our page. A custom domain for the page would give it an origin of its own later.
