# Olympus Link: the Worker and D1

A guide for Fernmelder, who runs the Olympus Discord bot and its site. It adds Olympus Link to
the Cloudflare Worker you already have (Discord login, your pages), with a D1 database. Nothing
here needs a new server: the addon side (Olympus 0.9.10), the page (`web/public/`), the key tool
(`scripts/link-keys.py`) and the watcher's inbox tool (`web/tools/read-inbox.mjs`) come ready.
This guide says what the Worker does, how to set it up, and why each check is there. The
complete reference Worker, the D1 schema and the test vectors are at the end of this file, and
`node --test web/test` runs that exact code against the vectors with a local SQLite in place of
D1.

## How it works

A player proves that a World of Warcraft character is theirs by typing, in game, a code the
backend signed for their Discord account. Players who are already trusted (a High Councillor
at launch; later, when you allow it, three randomly drawn verified players) confirm it in game:
their addon signs a confirmation with a key of its own. The finished, signed proof reaches the
Worker in one of two ways, and the Worker gives the Discord role.

```
 Discord /link, or the page after "Continue with Discord"
   └─> code  OLC1.<R>.<username>.<exp>.<mode>.<sig>        (signed with the backend key)

 in game: the player types  /oly discord <code>, sees "@username", clicks Accept
   requester ──DR──> an online confirmer ──DA──> requester    (the confirmer's key signs OLY4)

 the finished proof (OLB4), two ways:
   watcher path:  requester ──DB──> your watcher character (a High Councillor, "watcher on")
                  later, read-inbox.mjs uploads the watcher's SavedVariables ──> POST /api/link/inbox
   can't wait:    the page reads the QR code / the link / Olympus.lua ─────────> POST /api/link/submit

 the Worker checks everything, then gives ROLE_ID in GUILD_ID
```

- Nothing needs you online: confirmations need only confirmers online. The finished proof
  waits in the player's addon for 7 days until a watcher is online, then in your watcher's
  SavedVariables until you upload them.
- Nothing is lost when the Worker is down: the page says so, the addon keeps the proof, and
  either path delivers it later (the Worker takes a proof up to 7 days after its code expired).
- The Worker stores only public keys. The backend's private key is a Worker secret; each
  confirmer's private key stays in that confirmer's game. Confirmer keys can only confirm.

## What you need

- The Worker you already run, its Discord login, and `wrangler`.
- The bot's Discord application: its bot token (the bot needs Manage Roles, and its own role
  above the role it gives), its public key (Developer Portal, General Information) if the
  `/link` command comes over HTTP, the Olympus server id and the role id.
- Python 3 with the `cryptography` package on the computer where you make keys
  (`python3 -m pip install cryptography`), and Node 18 or newer for the inbox tool (Node 22.13
  or newer to run the tests).

## Setup, step by step

### 1. The backend key

```sh
python3 scripts/link-keys.py backend
```

It prints a seed and a public key, once, and writes nothing to disk.

- The seed goes into the Worker only: `wrangler secret put LINK_BACKEND_SEED`, and paste it.
  Keep a copy in a password manager to recover it; never in a repository, a chat, an issue or a
  screenshot. The Worker imports it into WebCrypto as an Ed25519 JWK (`d` the seed, `x` the
  public key) and checks at the first code that the two belong together.
- The public key (64 hex digits) goes into the Worker var `LINK_BACKEND_PUBLIC`, and to Daniel
  for the addon (`ns.LINK_BACKEND_KEYS` in `Olympus/Link.lua`): the addon refuses any code whose
  signature does not check against one of those keys, before it shows or sends anything.
- Rotating it: make a new key, have its public key added to `ns.LINK_BACKEND_KEYS` next to the
  old one (the addon takes two for this), wait until that addon version is out, then switch the
  Worker's `LINK_BACKEND_SEED` and `LINK_BACKEND_PUBLIC`. Codes already handed out stay valid
  until they expire.

### 2. The database

```sh
wrangler d1 create olympus-link
wrangler d1 execute olympus-link --remote --file web/worker/schema.sql
```

Five tables: `codes` (every code issued, single use), `keys` (confirmer public keys, one
active per Discord account), `used` (the proofs that counted), `members` (linked characters)
and `inbox_uploads` (every bundle received: the audit trail and the page's rate limit). The
full schema is in "The D1 schema" below.

### 3. The code

Copy `web/worker/link-worker.js` next to your Worker's entry file and put it in front of your
router. It answers `/api/link/*` and `/api/discord/interactions` and returns `null` for
everything else:

```js
import { handleLink } from './link-worker.js';
import { sessionUser } from './session.js'; // your login's lookup (step 4)

export default {
	async fetch(request, env, ctx) {
		const link = await handleLink(request, env, ctx, { getUser: sessionUser });
		if (link) return link;
		return yourSite(request, env, ctx); // everything you already serve
	},
};
```

It needs nothing but WebCrypto (Ed25519 and SHA-256), `fetch` and D1: no npm packages.

### 4. Your login

`handleLink` asks `getUser(request, env)` who is signed in. Return the Discord user your login
already knows, with the fields of Discord's `GET /users/@me`, or `null`:

```js
// session.js: an example for a login that sets a "sid" cookie and keeps its sessions in D1.
export async function sessionUser(request, env) {
	const sid = (request.headers.get('Cookie') || '').match(/(?:^|;\s*)sid=([^;]+)/)?.[1];
	if (!sid) return null;
	return env.DB.prepare('SELECT discord_id AS id, username, global_name, avatar FROM sessions WHERE id = ? AND expires > unixepoch()')
		.bind(sid)
		.first();
}
```

- `username` must be the Discord username (the unique, lowercase handle), not the display
  name: it is what the code carries and what the player sees in the game's Accept window.
- The `identify` scope is all the page needs; the page tells players "We only see your Discord
  name and avatar".
- The page calls the Worker on the same origin, with the session cookie. The Worker refuses a
  `POST` whose `Origin` is not `LINK_ORIGIN`, so another site cannot use a player's session.
- The page sends players to `LOGIN?next=<the page's path>` and expects to come back there
  signed in. Your login should follow `next` only when it is a path on your own site (it
  starts with a single `/`), so nobody can use it to send players elsewhere.

### 5. Settings

```toml
# wrangler.toml (your existing file: add these)
[[d1_databases]]
binding = "DB"
database_name = "olympus-link"
database_id = "<from wrangler d1 create>"

[vars]
LINK_MODE = "c"                          # councillors only at launch; "a" when the pool is large enough
LINK_ORIGIN = "https://your.site"        # the page's origin: no path, no trailing slash
LINK_BACKEND_PUBLIC = "<64 hex from link-keys.py backend>"
DISCORD_PUBLIC_KEY = "<Developer Portal > General Information > Public Key>"
GUILD_ID = "<the Olympus server id>"
ROLE_ID = "<the role linked members get>"
```

```sh
wrangler secret put LINK_BACKEND_SEED    # from link-keys.py backend
wrangler secret put LINK_ADMIN_TOKEN     # python3 -c "import secrets; print(secrets.token_urlsafe(32))"
wrangler secret put DISCORD_BOT_TOKEN    # probably there already
```

`LINK_ADMIN_TOKEN` (at least 32 characters) is for your own tools only: the watcher inbox
upload and, if your bot runs on the gateway, its `/link` requests.

### 6. The page

Serve `web/public/` as it is, under a path of your site, for example `https://your.site/link/`
(Workers static assets, or however your site serves files). It is plain HTML, CSS and ES
modules: no build step. Every call it makes goes through `web/public/backend.js`; check its
three constants: `API` (`/api/link`), `LOGIN` (your Discord login, which gets
`?next=<the page>` to come back to) and `LOGOUT`.

The page's final address is what the addon puts in the QR code (`ns.LINK_SITE`, followed by
`#b=` and the signed link): tell Daniel the address, and the name of your watcher's owner for
the game's texts ("Fernmelder's watcher", `ns.LINK_WATCHER_OWNER`). The part after `#` never
reaches a server: a phone that scans the QR code opens the page, which reads the link from its
own address, asks the player to sign in if needed, and sends it.

The page loads nothing but its own files, Google Fonts and Discord avatars (its
Content-Security-Policy says so). `?demo=login` (and `scanned`, `start`, `code`, `wait`, `screen`,
`scanning`, `phone`, `other`, `pick`, `found`, `done`, `error`) shows each step with made-up
data and never calls the Worker; `&lang=pt` shows the Portuguese page (it is chosen from the
browser's language otherwise).

### 7. The `/link` command in Discord (the watcher path's code)

A player who never opens the site types `/link` in the Olympus server and gets their code in a
reply only they see. Two ways, depending on how your bot receives commands:

- **Over HTTP** (the application's Interactions Endpoint URL): set it to
  `https://your.site/api/discord/interactions`. The Worker checks Discord's signature on every
  request with `DISCORD_PUBLIC_KEY` and answers `/link` itself. Do not do this if your bot
  receives its commands over the gateway: Discord sends them to one place only.
- **Over the gateway** (discord.js, discord.py...): the bot asks the Worker and replies:

```js
// discord.js v14
client.on('interactionCreate', async (interaction) => {
	if (!interaction.isChatInputCommand() || interaction.commandName !== 'link') return;
	const res = await fetch('https://your.site/api/link/bot-code', {
		method: 'POST',
		headers: { Authorization: `Bearer ${process.env.LINK_ADMIN_TOKEN}`, 'Content-Type': 'application/json' },
		body: JSON.stringify({ id: interaction.user.id, username: interaction.user.username }),
	});
	const data = await res.json();
	await interaction.reply({ content: data.reply || data.message, flags: 64 }); // 64: only they see it
});
```

Register the command once (a `POST` adds or updates this one command and leaves your others):

```sh
curl -X POST "https://discord.com/api/v10/applications/$APP_ID/guilds/$GUILD_ID/commands" \
  -H "Authorization: Bot $DISCORD_BOT_TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"link","description":"Get your Olympus Link code for the game","type":1}'
```

### 8. Confirmer keys

Each confirmer has a key of their own, made on your computer and registered in D1:

```sh
python3 scripts/link-keys.py confirmer <id> c --owner <their Discord id> --username <their username> --bootstrap
python3 scripts/link-keys.py confirmer <id> p --owner <their Discord id> --username <their username>
```

- `<id>`: 6 to 16 of a-z and 0-9, never reused (it is part of what they sign).
- `c` is a High Councillor, `p` a player for the draw (mode `a`). A confirmation counts only when
  the confirming character is one of the key owner's linked characters; `--bootstrap` lifts that
  for the first councillor keys, since at launch nobody has linked a character yet.
- The tool prints the line the confirmer types in game (`/oly discord key <id> <seed>`), which
  you send them privately (a direct message, never a channel); the public key; and the SQL that
  registers it (`wrangler d1 execute olympus-link --remote --command "..."`). In game,
  `/oly discord key` shows them the id and the public key, to compare with yours. The addon
  never prints, sends or logs the seed.
- One active key per Discord account: the database refuses a second. Rotating: the tool also
  prints the `UPDATE keys SET revoked = 1 ...` to run first, in the same batch. Revoking:
  `python3 scripts/link-keys.py revoke <id>`, and the confirmer types `/oly discord key off`.
  A revoked key's confirmations stop counting at once, including ones not delivered yet.
  `python3 scripts/link-keys.py public < seed.txt` prints the public key of a seed.
- Keys only confirm: they cannot issue codes, a player key cannot link anyone alone, and the
  addon signs on its own only within its limits (one proof a minute and 5 a day per requesting
  character, 30 a minute in all, never for its own account's characters, never across
  factions, only for Olympus guilds).

### 9. Your watcher

On one of your High Councillor characters, type `/oly discord watcher on`. While it is online,
players whose proof is ready deliver it to it, and it keeps up to 500 in its SavedVariables
(`OlympusDB.discord.inbox`). WoW writes that file on `/reload`, logout or quit. Then:

```sh
# macOS
LINK_ADMIN_TOKEN=... node web/tools/read-inbox.mjs "/Applications/World of Warcraft/_classic_beta_/WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua" --post https://your.site/api/link/inbox
# Windows (PowerShell)
$env:LINK_ADMIN_TOKEN="..."; node web/tools/read-inbox.mjs "C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF\Account\<ACCOUNT>\SavedVariables\Olympus.lua" --post https://your.site/api/link/inbox
```

Without `--post` it prints the same JSON (`{"bundles": [...]}`, oldest first) for you to look
at or send another way. It reads the file with a small SavedVariables parser (no packages),
skips malformed entries, and prints the inbox only: never the confirmer key kept in the same
file. Uploading twice is harmless: a link that already counted answers `already`. It only
posts over `https` (or to `localhost`), since the admin token rides along.

### 10. From councillors only to drawn players

Launch with `LINK_MODE = "c"`: only councillor confirmations count, and every code says so (the
addon then asks councillors only). When enough verified players have keys, set it to `"a"`:
new codes also accept three drawn players when no councillor is online. Codes already issued
keep the mode they were signed with.

## The API

All JSON. The page's calls carry the session cookie; the tools' carry the admin token.

| Route | Who | Body | Answer |
|---|---|---|---|
| `GET /api/link/me` | page | | `200 {"user": {id, username, global_name, avatar}}`, or `401 {"user": null}` |
| `POST /api/link/code` | page | `{}` | `200 {"token", "command", "exp", "mode"}`; `401` not signed in, `429 {"reason": "limit"}`, `400 {"reason": "username"}` |
| `POST /api/link/submit` | page | `{"bundle": "OLB4~..."}` | `200 {"status", "reason", "message", "R", "characters"}`; `429` after 10 an hour |
| `POST /api/link/inbox` | watcher tool | `{"bundles": [{"R", "bundle", "from", "t"}]}` (500 at most) | `200 {"results": [{"R", "status", "reason", "message"}]}` |
| `POST /api/link/bot-code` | gateway bot | `{"id", "username"}` | `200 {"token", "command", "exp", "mode", "reply"}` |
| `POST /api/discord/interactions` | Discord | an interaction | `PING`, or `/link` answered ephemerally |

`status` is `linked` (reason `linked`, or `already` when that link had already counted),
`rejected` (reason `format`, `unknown-code`, `other-user`, `code-used`, `expired`,
`not-enough`, `not-in-server`) or `error` (`discord`, `server`: nothing was used, try again).
The page shows each one in English or Portuguese with what to do next.

The page's four calls live in `web/public/backend.js`: `me()`, `code()`, `submit(bundle)` and
`loginUrl()`. Change them there if your routes differ.

## The formats

- **Code token** (the backend signs it, the player pastes it):
  `OLC1.<R>.<username>.<exp>.<mode>.<sig>`. `R`: 10 characters of Crockford base32
  (`0123456789ABCDEFGHJKMNPQRSTVWXYZ`) from `crypto.getRandomValues`, single use. `username`:
  the Discord username, `[a-z0-9_.]{2,32}` (it may hold dots: read the token from both ends).
  `exp`: unix time, 24 hours after issue. `mode`: `c` or `a`. `sig`: base64url without padding
  (86 characters) of the backend's Ed25519 signature over the ASCII bytes
  `OLC1.<R>.<username>.<exp>.<mode>`. `/oly discord <token>` is 163 bytes at most, within the
  game's 255.
- **Confirmation** (a confirmer's addon signs it, UTF-8):
  `OLY4~<requester>~<guild>~<faction>~<nonce>~<R>~<issued>~<keyId>~<confirmer>`. Names are
  `Name-Realm` as the game writes them (the requester as the game server stamped its whisper,
  the confirmer itself); guild at most 40 bytes, an Olympus guild; faction `Alliance` or
  `Horde`, the confirmer's own; nonce 16 lowercase hex digits; issued the confirmer's server
  time.
- **Bundle**: `OLB4~<requester>~<guild>~<faction>~<nonce>~<R>~<p1>;<p2>;...`, each proof
  `<issued>,<keyId>,<confirmer>,<sig>`, 1 to 4 proofs, 1600 bytes at most. A field holds no
  `~`, `;`, `,`, `|` or control character; a name is at most 64 bytes and its realm (after the
  last dash) has no dash or space.
- **Link** (the QR code and the game's copy box): `<the page's address>#b=<bundle,
  percent-encoded>`.

## What the Worker checks

For every bundle, from the page or the inbox:

1. It is well formed (the rules above; the page and the addon read exactly the same).
2. The code `R` exists. From the page, it belongs to the signed-in account; from the inbox, the
   account is the code's owner. It is unused (a link that already counted answers `already`).
3. Its confirmations were signed within the code's life (from issue, less 5 minutes of clock
   difference, to `exp`), none more than 5 minutes ahead of the Worker's clock. The bundle may
   arrive up to 7 days after `exp`, since the addon keeps it that long for the watcher; after
   that it is `expired`.
4. For each proof: the key exists and is not revoked; its owner is not the code's account; the
   Worker rebuilds the exact `OLY4` text and verifies the Ed25519 signature with the stored
   public key (WebCrypto: a non-canonical signature fails); the confirmer is one of the key
   owner's linked characters (except bootstrap councillor keys); the requester is not one of
   the key owner's characters; and (R, keyId) never counted before.
5. It accepts with **one valid councillor proof**. In mode `a` it also accepts **three valid
   player proofs** from three different owners, none the requester, signed within 5 minutes of
   each other, each key at least 7 days old, each owner's Discord account at least 30 days old
   (read from the Discord id), and each key ranked below M in this code's draw: all active
   player keys sorted by `SHA-256(R + "~" + keyId)` (hex, lowest first),
   M = max(20, ceil(3% of the active player keys)). The addon asks online players in that same
   order.
6. Then it claims the code (so two deliveries cannot both count), gives `ROLE_ID` in
   `GUILD_ID`, and records the character in `members`, moving it if it was linked to another
   account (which loses the role when it has no character left). If Discord refuses (the
   player is not in the server, or Discord is down), the code is released and nothing is
   recorded, so the same link works on the next try.

Why the draw and these limits stop anyone packing the random pool: R comes from the backend's
random generator and only the M lowest-ranked keys of `SHA-256(R~keyId)` over the whole pool can
count, so an attacker cannot pick the keys that confirm a code and needs a large share of the
pool to hold three of those places, with only 3 codes a day per Discord account to try. One key
per Discord account, keys at least 7 days old, accounts at least 30 days old and signatures
within 5 minutes make that share slow and costly to build and stop a few friends from signing
for each other at leisure, while councillors-only mode keeps the pool out of play until it is
large.

Limits and logs: 3 codes per Discord account a day (a reload gets the same unused code back);
the page may submit 10 times an hour per account; every bundle received is logged in
`inbox_uploads`; the admin token is compared in constant time; a Worker whose
`LINK_BACKEND_SEED` and `LINK_BACKEND_PUBLIC` do not match refuses to issue codes.

## Test vectors

These come from `web/test/fixtures/vectors.json`, made by `web/test/fixtures/make-vectors.py`
with Python's `cryptography`. They are throwaway keys whose seeds are the SHA-256 of public
labels (`"olympus-link test key: " + label`): never register one. The same vectors check the
addon (`Olympus/Ed25519.lua` signs the `ed25519` ones byte for byte:
`web/test/fixtures/lua-signatures.json`), the page and this Worker, whose tests
(`web/test/worker.test.mjs`) load the schema into SQLite, insert these codes and keys, and send
these bundles. Ed25519 is deterministic: any correct implementation gives these exact
signatures from these seeds. `must_fail` has a non-canonical S (S + L) that every check must
refuse.

To check your Worker by hand: insert the `codes` and `keys` below (for the players' bundle,
also each confirmer character in `members` under its key's owner), set the Worker's clock
between the proofs' `issued` and `exp`, and `acceptBundle` answers `linked` for each bundle.

<!-- block: vectors -->
```json
{
  "backend": {
    "public_hex": "bb0f6260296c0709dfd2ac13d98880b7b17e817fdf13a78752f095d26601094e",
    "token": "OLC1.7K3M9Q2XWD.some_player.1790086400.c.CeE2kc8l85hCPotkn6GNumGOUJCM0G1kN97OTqT8Hkr7hnSBhx055DnfAlmzDWERDq_bCYPSLZtWydonBTTcCA",
    "signed": "OLC1.7K3M9Q2XWD.some_player.1790086400.c"
  },
  "codes": [
    {
      "R": "7K3M9Q2XWD",
      "discord_id": "200000000000000001",
      "username": "some_player",
      "mode": "c",
      "created": 1790000000,
      "exp": 1790086400
    },
    {
      "R": "H4N8PZ6R1B",
      "discord_id": "200000000000000002",
      "username": "tester.two",
      "mode": "a",
      "created": 1790000000,
      "exp": 1790086400
    }
  ],
  "keys": [
    {
      "key_id": "testcouncil1",
      "kind": "c",
      "bootstrap": 1,
      "owner_discord_id": "100000000000000001",
      "created": 1780000000,
      "public_hex": "27ee00698f0fa7c47c6a44514afe41b9e80bce0451a35a6d02a8b229d28a6836"
    },
    {
      "key_id": "testplayer01",
      "kind": "p",
      "bootstrap": 0,
      "owner_discord_id": "100000000000000011",
      "created": 1780000000,
      "public_hex": "d4d525c6c10192ebb2a30cd23be812530b299c233658515bef9792608280ba80"
    },
    {
      "key_id": "testplayer02",
      "kind": "p",
      "bootstrap": 0,
      "owner_discord_id": "100000000000000012",
      "created": 1780000000,
      "public_hex": "92e3613f58e15b53cd152d3e699fa8c4ab556c6f98070e99f0ba009bae2eb971"
    },
    {
      "key_id": "testplayer03",
      "kind": "p",
      "bootstrap": 0,
      "owner_discord_id": "100000000000000013",
      "created": 1780000000,
      "public_hex": "59ddc2f44373e9fc9140dfd98c63369c8f9d074ddafc612ea19061665f40de79"
    }
  ],
  "bundles": [
    {
      "name": "one councillor",
      "bundle": "OLB4~Some Player-ClassicBetaPvP~Olympus~Alliance~0123456789abcdef~7K3M9Q2XWD~1790000123,testcouncil1,Test Councillor-ClassicBetaPvP,G6DtgIOM0e9eDraq2p4SV-Zi7yRX2Qssl4ybESmA-shCD18yJrG8EamXrJoJVPX2kM80PuaerPujc7xwcSeIDA",
      "signed": [
        "OLY4~Some Player-ClassicBetaPvP~Olympus~Alliance~0123456789abcdef~7K3M9Q2XWD~1790000123~testcouncil1~Test Councillor-ClassicBetaPvP"
      ]
    },
    {
      "name": "three drawn players, non-ASCII requester",
      "bundle": "OLB4~Tëst Plâyer-ClassicBetaPvP~Olympus Vanguard~Horde~a1b2c3d4e5f60718~H4N8PZ6R1B~1790000200,testplayer01,Other Player-ClassicBetaPvP,Ohu-x_Mzg8_DpTBh-LCsII_dTZf6m2aVAbxFzpiUMQoHWlPTtqTOO6oi5sfB1hYaqVvpAtPElk86xejnIewUCA;1790000245,testplayer02,Third Player-ClassicBetaPvP2,Vpe_hh5ndX01NifSGOA-wP4ZNmDLs38w8WyOc7Kvp14RLQ0XXDv7_zFzvyev7S-gVnJhU3DncZLLHubyq0UjAQ;1790000301,testplayer03,Fourth Player-ClassicBetaPvP,3yGfTMxDRTV0vp_GOjVJfAHscRJTnNGTABcV3tMKKYwYVwHQdd4QbdGc_Ev2pqy84_PEFVD-KlPSFnTPbTWBAA",
      "signed": [
        "OLY4~Tëst Plâyer-ClassicBetaPvP~Olympus Vanguard~Horde~a1b2c3d4e5f60718~H4N8PZ6R1B~1790000200~testplayer01~Other Player-ClassicBetaPvP",
        "OLY4~Tëst Plâyer-ClassicBetaPvP~Olympus Vanguard~Horde~a1b2c3d4e5f60718~H4N8PZ6R1B~1790000245~testplayer02~Third Player-ClassicBetaPvP2",
        "OLY4~Tëst Plâyer-ClassicBetaPvP~Olympus Vanguard~Horde~a1b2c3d4e5f60718~H4N8PZ6R1B~1790000301~testplayer03~Fourth Player-ClassicBetaPvP"
      ]
    }
  ],
  "ed25519": [
    {
      "name": "seed 00..1f, empty message",
      "seed_hex": "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
      "public_hex": "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8",
      "message": "",
      "signature_b64url": "nKU1eVMGVNXD33cInvRe2mE-L-32cOlr7axGOVBOWEXvS5XVeTB3Iz3RaBeyUy6cVSWHKnOkrXS3WTaangXBAg"
    },
    {
      "name": "seed 1f..00, one byte",
      "seed_hex": "1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100",
      "public_hex": "712651f450ba05b63898b99ef5f7ba45632e8e2527f7f715cd671ec4024cc51e",
      "message": "O",
      "signature_b64url": "WGSgpdAZ1xS-5rMYUAdI_XhjMnFJDJdLuzD_akvyzWDpxZwv3D82H_XlAgPC_afxoK8JvIXz88HZWL6sdIOIAA"
    },
    {
      "name": "backend key, code token",
      "seed_hex": "66c9370fb53f6de55b6dd1e44fbb59af4017cde20766aadcafc4d97aff585625",
      "public_hex": "bb0f6260296c0709dfd2ac13d98880b7b17e817fdf13a78752f095d26601094e",
      "message": "OLC1.7K3M9Q2XWD.some_player.1790086400.c",
      "signature_b64url": "CeE2kc8l85hCPotkn6GNumGOUJCM0G1kN97OTqT8Hkr7hnSBhx055DnfAlmzDWERDq_bCYPSLZtWydonBTTcCA"
    },
    {
      "name": "councillor key, OLY4 confirmation",
      "seed_hex": "cab94e6fdde165424b69948a51a63d08f40ece0e5c378eb65bccd34582f4b9b0",
      "public_hex": "27ee00698f0fa7c47c6a44514afe41b9e80bce0451a35a6d02a8b229d28a6836",
      "message": "OLY4~Some Player-ClassicBetaPvP~Olympus~Alliance~0123456789abcdef~7K3M9Q2XWD~1790000123~testcouncil1~Test Councillor-ClassicBetaPvP",
      "signature_b64url": "G6DtgIOM0e9eDraq2p4SV-Zi7yRX2Qssl4ybESmA-shCD18yJrG8EamXrJoJVPX2kM80PuaerPujc7xwcSeIDA"
    },
    {
      "name": "player key, OLY4 with non-ASCII requester",
      "seed_hex": "e60782cfce4b5e9a952befe95bd9279a3fa0a4f94ab389cbe4a9c1bd243e03bf",
      "public_hex": "d4d525c6c10192ebb2a30cd23be812530b299c233658515bef9792608280ba80",
      "message": "OLY4~Tëst Plâyer-ClassicBetaPvP~Olympus Vanguard~Horde~a1b2c3d4e5f60718~H4N8PZ6R1B~1790000200~testplayer01~Other Player-ClassicBetaPvP",
      "signature_b64url": "Ohu-x_Mzg8_DpTBh-LCsII_dTZf6m2aVAbxFzpiUMQoHWlPTtqTOO6oi5sfB1hYaqVvpAtPElk86xejnIewUCA"
    }
  ],
  "must_fail": {
    "name": "non-canonical S (S + L)",
    "public_hex": "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8",
    "message_hex": "",
    "signature_hex": "9ca53579530654d5c3df77089ef45eda613e2fedf670e96bedac4639504e5845dc1f8b329493897b136e60ba904d0db15525872a73a4ad74b759369a9e05c112"
  }
}
```

## The D1 schema

`web/worker/schema.sql`:

<!-- block: web/worker/schema.sql -->
```sql
-- Olympus Link: the D1 schema (web/WORKER.md). Times are unix seconds.
-- wrangler d1 execute <database> --remote --file web/worker/schema.sql

-- Codes the backend issued: one row per code, single use.
CREATE TABLE IF NOT EXISTS codes (
  r          TEXT PRIMARY KEY,                     -- 10 Crockford base32 characters
  discord_id TEXT NOT NULL,                        -- whose code it is
  username   TEXT NOT NULL,                        -- their Discord username, as signed in the token
  mode       TEXT NOT NULL CHECK (mode IN ('c', 'a')),
  created    INTEGER NOT NULL,
  exp        INTEGER NOT NULL,
  token      TEXT NOT NULL,                        -- the signed token (public: the player pastes it)
  source     TEXT NOT NULL,                        -- 'site' or 'discord'
  used       INTEGER                               -- when it linked a character; NULL until then
);
CREATE INDEX IF NOT EXISTS codes_by_user ON codes (discord_id, created);

-- Confirmer public keys. Confirm-only: they sign OLY4 confirmations and nothing else.
CREATE TABLE IF NOT EXISTS keys (
  key_id           TEXT PRIMARY KEY                -- [a-z0-9]{6,16}, never reused
                   CHECK (length(key_id) BETWEEN 6 AND 16 AND key_id NOT GLOB '*[^a-z0-9]*'),
  public_key       TEXT NOT NULL                   -- 64 lowercase hex (Ed25519)
                   CHECK (length(public_key) = 64 AND public_key NOT GLOB '*[^0-9a-f]*'),
  owner_discord_id TEXT NOT NULL                   -- a Discord id: digits only
                   CHECK (length(owner_discord_id) BETWEEN 5 AND 25 AND owner_discord_id NOT GLOB '*[^0-9]*'),
  owner_username   TEXT,
  kind             TEXT NOT NULL CHECK (kind IN ('c', 'p')), -- councillor or drawn player
  bootstrap        INTEGER NOT NULL DEFAULT 0,     -- 1: a councillor key trusted before its owner linked a character
  created          INTEGER NOT NULL,
  revoked          INTEGER NOT NULL DEFAULT 0,
  revoked_at       INTEGER
);
-- One active key per Discord account: rotating is "revoke the old one, insert the new one".
CREATE UNIQUE INDEX IF NOT EXISTS keys_one_per_owner ON keys (owner_discord_id) WHERE revoked = 0;

-- Proofs already counted: (code, key) pairs.
CREATE TABLE IF NOT EXISTS used (
  r      TEXT NOT NULL,
  key_id TEXT NOT NULL,
  t      INTEGER NOT NULL,
  PRIMARY KEY (r, key_id)
);

-- Linked characters: one Discord account per character ("Name-Realm").
CREATE TABLE IF NOT EXISTS members (
  character  TEXT PRIMARY KEY,
  discord_id TEXT NOT NULL,
  guild      TEXT NOT NULL,
  faction    TEXT NOT NULL,
  r          TEXT NOT NULL,                        -- the code that linked it
  linked     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS members_by_user ON members (discord_id);

-- Every bundle received, from the page ('site') or the watcher tool ('watcher'): the audit
-- trail, and the page's rate limit.
CREATE TABLE IF NOT EXISTS inbox_uploads (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  source         TEXT NOT NULL,
  r              TEXT,
  discord_id     TEXT,
  requester      TEXT,
  from_character TEXT,                             -- the watcher's record of who delivered it
  received       INTEGER,                          -- when the watcher got it (its "t")
  uploaded       INTEGER NOT NULL,
  status         TEXT NOT NULL,
  reason         TEXT
);
CREATE INDEX IF NOT EXISTS uploads_by_user ON inbox_uploads (discord_id, uploaded);
```

## The reference Worker

`web/worker/link-worker.js`, the whole module. The `ADAPT` comment marks the one function to
connect to your login (step 4).

<!-- block: web/worker/link-worker.js -->
```js
// Olympus Link: the reference Cloudflare Worker (D1 + Discord). web/WORKER.md explains every
// part; the tests in web/test/worker.test.mjs run this exact file against the shared vectors.
//
// Bindings and settings (wrangler.toml / dashboard):
//   DB                   D1 database with web/worker/schema.sql
//   LINK_BACKEND_SEED    secret: the backend's Ed25519 seed, base64url (scripts/link-keys.py backend)
//   LINK_BACKEND_PUBLIC  var: its public key, 64 hex (the same one is in the addon's ns.LINK_BACKEND_KEYS)
//   LINK_MODE            var: "c" councillors only (launch), "a" councillors or three drawn players
//   LINK_ORIGIN          var: the page's origin, e.g. "https://example.org" (checked on the page's POSTs)
//   LINK_ADMIN_TOKEN     secret: bearer token of the watcher tool (/inbox) and of a gateway bot (/bot-code)
//   DISCORD_BOT_TOKEN    secret: the bot that gives the role (Manage Roles, above ROLE_ID)
//   DISCORD_PUBLIC_KEY   var: the application's public key, for the /link slash command over HTTP
//   GUILD_ID, ROLE_ID    vars: the Olympus server and the role linked members get
//
// Routes: GET /api/link/me, POST /api/link/code, POST /api/link/submit, POST /api/link/inbox,
// POST /api/link/bot-code, POST /api/discord/interactions. Anything else returns null from
// handleLink, so it can sit in front of an existing Worker's router.

export const LINK = {
	TOKEN_LIFE: 24 * 3600, // a code works for a day...
	REUSE_LEFT: 12 * 3600, // ...and is handed out again while it has this long left
	CODES_PER_DAY: 3,
	DELIVERY_GRACE: 7 * 24 * 3600, // the addon holds a finished link 7 days for the watcher
	CLOCK_SKEW: 300, // game server clock vs ours
	WINDOW: 300, // three player proofs within 5 minutes of each other
	PLAYERS_NEEDED: 3,
	KEY_MIN_AGE: 7 * 24 * 3600,
	ACCOUNT_MIN_AGE: 30 * 24 * 3600,
	SUBMITS_PER_HOUR: 10,
	MAX_BUNDLES: 500,
};

const R_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const R_RE = /^[0-9A-HJKMNP-TV-Z]{10}$/;
const USERNAME_RE = /^[a-z0-9_.]{2,32}$/;
const DISCORD_ID_RE = /^[0-9]{5,25}$/;
const KEYID_RE = /^[a-z0-9]{6,16}$/;
const NONCE_RE = /^[0-9a-f]{16}$/;
const ISSUED_RE = /^[1-9][0-9]{0,11}$/;
const SIG_RE = /^[A-Za-z0-9_-]{86}$/;
const FORBIDDEN = /[|~;,\u0000-\u001f\u007f]/;
const MAX_PROOFS = 4;
const MAX_BUNDLE_BYTES = 1600;

const enc = new TextEncoder();
const now = () => Math.floor(Date.now() / 1000);

// ---------------------------------------------------------------------------
// Entry points

export default {
	async fetch(request, env, ctx) {
		return (await handleLink(request, env, ctx)) || new Response('Not found', { status: 404 });
	},
};

// ADAPT: the signed-in Discord user of this request, from YOUR login (the one your site
// already has), as { id, username, global_name, avatar } - the fields of Discord's
// GET /users/@me - or null when nobody is signed in. See web/WORKER.md, "Your login".
export async function sessionUser(request, env) {
	throw new Error('Olympus Link: connect sessionUser() to your Discord login (web/WORKER.md, "Your login")');
}

export async function handleLink(request, env, ctx, { getUser = sessionUser } = {}) {
	const url = new URL(request.url);
	const route = `${request.method} ${url.pathname.replace(/\/+$/, '')}`;
	try {
		switch (route) {
			case 'GET /api/link/me':
				return await routeMe(request, env, getUser);
			case 'POST /api/link/code':
				return await routeCode(request, env, getUser);
			case 'POST /api/link/submit':
				return await routeSubmit(request, env, getUser);
			case 'POST /api/link/inbox':
				return await routeInbox(request, env);
			case 'POST /api/link/bot-code':
				return await routeBotCode(request, env);
			case 'POST /api/discord/interactions':
				return await routeInteractions(request, env);
			default:
				return null;
		}
	} catch (err) {
		console.error('olympus-link', route, err && err.stack ? err.stack : err);
		return json({ status: 'error', reason: 'server', message: 'Something went wrong on our side.' }, 500);
	}
}

// ---------------------------------------------------------------------------
// Routes

async function routeMe(request, env, getUser) {
	const user = await getUser(request, env);
	if (!user) return json({ user: null }, 401);
	const { id, username, global_name = null, avatar = null } = user;
	return json({ user: { id, username, global_name, avatar } });
}

async function routeCode(request, env, getUser) {
	if (!sameOrigin(request, env)) return json({ status: 'error', reason: 'origin', message: 'Wrong origin.' }, 403);
	const user = await getUser(request, env);
	if (!user) return json({ status: 'error', reason: 'login', message: 'Sign in with Discord first.' }, 401);
	const r = await issueCode(env, user, 'site');
	if (r.error) return json({ status: 'error', reason: r.error, message: codeError(r.error) }, r.error === 'limit' ? 429 : 400);
	return json({ token: r.token, command: `/oly discord ${r.token}`, exp: r.exp, mode: r.mode });
}

async function routeSubmit(request, env, getUser) {
	if (!sameOrigin(request, env)) return json({ status: 'error', reason: 'origin', message: 'Wrong origin.' }, 403);
	const user = await getUser(request, env);
	if (!user) return json({ status: 'error', reason: 'login', message: 'Sign in with Discord first.' }, 401);
	const body = await readJson(request, 8 * 1024);
	if (!body || typeof body.bundle !== 'string') return json({ status: 'error', reason: 'format', message: 'No link in the request.' }, 400);
	const t = now();
	const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM inbox_uploads WHERE source = 'site' AND discord_id = ? AND uploaded > ?")
		.bind(String(user.id), t - 3600)
		.first();
	if (recent && recent.n >= LINK.SUBMITS_PER_HOUR) {
		return json({ status: 'error', reason: 'limit', message: 'Too many tries: wait a while and send it again.' }, 429);
	}
	const result = await acceptBundle(env, body.bundle.trim(), { userId: String(user.id), t });
	await logUpload(env, 'site', body.bundle, result, { discordId: String(user.id), uploaded: t });
	return json(result);
}

// The watcher tool: many bundles at once, from a High Councillor's inbox. The Discord user
// comes from each code (codes.discord_id).
async function routeInbox(request, env) {
	if (!(await adminAuthorized(request, env))) return json({ status: 'error', reason: 'auth' }, 401);
	const body = await readJson(request, 2 * 1024 * 1024);
	const list = body && Array.isArray(body.bundles) ? body.bundles : null;
	if (!list || list.length > LINK.MAX_BUNDLES) return json({ status: 'error', reason: 'format', message: `Send {"bundles": [...]} with at most ${LINK.MAX_BUNDLES}.` }, 400);
	const results = [];
	for (const item of list) {
		const entry = item && typeof item === 'object' ? item : {};
		const text = (typeof item === 'string' ? item : typeof entry.bundle === 'string' ? entry.bundle : '').trim();
		const t = now();
		const parsed = parseBundle(text);
		const result =
			parsed.ok && typeof entry.R === 'string' && entry.R !== parsed.bundle.R
				? reject('format', 'The inbox key does not match the link.', parsed.bundle.R)
				: await acceptBundle(env, text, { t });
		await logUpload(env, 'watcher', text, result, {
			from: typeof entry.from === 'string' ? entry.from.slice(0, 100) : null,
			received: Number.isFinite(entry.t) ? Math.floor(entry.t) : null,
			uploaded: t,
		});
		results.push({ R: result.R || (typeof entry.R === 'string' ? entry.R : null), status: result.status, reason: result.reason, message: result.message });
	}
	return json({ results });
}

// For a bot that runs on the gateway (discord.js, discord.py...) instead of HTTP interactions:
// it asks the Worker for the member's code and replies with it, ephemeral.
async function routeBotCode(request, env) {
	if (!(await adminAuthorized(request, env))) return json({ status: 'error', reason: 'auth' }, 401);
	const body = await readJson(request, 4 * 1024);
	if (!body || typeof body.id !== 'string' || typeof body.username !== 'string') return json({ status: 'error', reason: 'format' }, 400);
	const r = await issueCode(env, { id: body.id, username: body.username }, 'discord');
	if (r.error) return json({ status: 'error', reason: r.error, message: codeError(r.error) }, r.error === 'limit' ? 429 : 400);
	return json({ token: r.token, command: `/oly discord ${r.token}`, exp: r.exp, mode: r.mode, reply: codeReply(r) });
}

// The /link slash command over HTTP interactions (Discord signs every request).
async function routeInteractions(request, env) {
	const sig = request.headers.get('X-Signature-Ed25519') || '';
	const ts = request.headers.get('X-Signature-Timestamp') || '';
	const body = await request.text();
	if (!/^[0-9a-fA-F]{128}$/.test(sig) || !/^[0-9]{1,20}$/.test(ts)) return new Response('Bad request signature', { status: 401 });
	if (!(await ed25519Verify(env.DISCORD_PUBLIC_KEY, hexToBytes(sig), enc.encode(ts + body)))) {
		return new Response('Bad request signature', { status: 401 });
	}
	const i = JSON.parse(body);
	if (i.type === 1) return json({ type: 1 }); // PING
	if (i.type === 2 && i.data && i.data.name === 'link') {
		const user = (i.member && i.member.user) || i.user;
		const r = user ? await issueCode(env, user, 'discord') : { error: 'login' };
		return json({ type: 4, data: { flags: 64, content: r.error ? codeError(r.error) : codeReply(r) } });
	}
	return json({ type: 4, data: { flags: 64, content: 'Unknown command.' } });
}

// ---------------------------------------------------------------------------
// Codes

export async function issueCode(env, user, source) {
	const id = String(user && user.id);
	const username = String(user && user.username);
	if (!DISCORD_ID_RE.test(id)) return { error: 'login' };
	if (!USERNAME_RE.test(username)) return { error: 'username' };
	const t = now();
	const open = await env.DB.prepare('SELECT token, exp, mode FROM codes WHERE discord_id = ? AND username = ? AND used IS NULL AND exp > ? ORDER BY created DESC LIMIT 1')
		.bind(id, username, t + LINK.REUSE_LEFT)
		.first();
	if (open) return { token: open.token, exp: open.exp, mode: open.mode };
	const count = await env.DB.prepare('SELECT COUNT(*) AS n FROM codes WHERE discord_id = ? AND created > ?').bind(id, t - 86400).first();
	if (count && count.n >= LINK.CODES_PER_DAY) return { error: 'limit' };
	const mode = env.LINK_MODE === 'a' ? 'a' : 'c';
	const exp = t + LINK.TOKEN_LIFE;
	for (let attempt = 0; attempt < 5; attempt++) {
		const R = randomR();
		const payload = `OLC1.${R}.${username}.${exp}.${mode}`;
		const token = `${payload}.${await backendSign(env, payload)}`;
		try {
			await env.DB.prepare('INSERT INTO codes (r, discord_id, username, mode, created, exp, token, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
				.bind(R, id, username, mode, t, exp, token, source)
				.run();
			return { token, exp, mode, R };
		} catch (err) {
			if (!/unique|constraint/i.test(String(err && err.message))) throw err; // an R taken: draw again
		}
	}
	throw new Error('could not draw a free code');
}

function randomR() {
	const bytes = crypto.getRandomValues(new Uint8Array(10));
	return Array.from(bytes, (b) => R_ALPHABET[b & 31]).join(''); // 256 = 8 * 32: no bias
}

function codeReply(r) {
	const hours = Math.max(1, Math.round((r.exp - now()) / 3600));
	return [
		'Your Olympus Link code. Paste this line in the WoW chat, press Enter, then click Accept:',
		'```',
		`/oly discord ${r.token}`,
		'```',
		`It works once, for your account only, for the next ${hours} h. The confirmations happen in game; your role arrives when the link reaches the bot.`,
	].join('\n');
}

function codeError(reason) {
	if (reason === 'limit') return 'You already got 3 codes today: use the last one, or try again tomorrow.';
	if (reason === 'username') return 'Your Discord username cannot be used in a code. Change it to the new style (lowercase, no #1234) and try again.';
	return 'Sign in with Discord first.';
}

// ---------------------------------------------------------------------------
// Bundles

// What the addon's Link.Parse reads (Olympus/Link.lua; the page's web/public/core.js reads the
// same). Whether the proofs count is acceptBundle's call: a key or owner is counted once.
export function parseBundle(text) {
	if (typeof text !== 'string' || !text.startsWith('OLB4~')) return { ok: false, error: 'prefix' };
	if (enc.encode(text).length > MAX_BUNDLE_BYTES) return { ok: false, error: 'size' };
	const f = text.split('~');
	if (f.length !== 7) return { ok: false, error: 'fields' };
	const [, requester, guild, faction, nonce, R, proofText] = f;
	if (!validCharacter(requester)) return { ok: false, error: 'requester' };
	if (!field(guild, 40)) return { ok: false, error: 'guild' };
	if (faction !== 'Alliance' && faction !== 'Horde') return { ok: false, error: 'faction' };
	if (!NONCE_RE.test(nonce)) return { ok: false, error: 'nonce' };
	if (!R_RE.test(R)) return { ok: false, error: 'code' };
	const parts = proofText ? proofText.split(';') : [];
	if (parts.length < 1 || parts.length > MAX_PROOFS) return { ok: false, error: 'proofs' };
	const proofs = [];
	for (const part of parts) {
		const p = part.split(',');
		if (p.length !== 4) return { ok: false, error: 'proof' };
		const [issued, keyId, confirmer, sig] = p;
		if (!ISSUED_RE.test(issued) || !KEYID_RE.test(keyId) || !validCharacter(confirmer)) return { ok: false, error: 'proof' };
		if (!SIG_RE.test(sig) || b64urlEncode(b64urlDecode(sig)) !== sig) return { ok: false, error: 'sig' };
		proofs.push({ issued: Number(issued), keyId, confirmer, sig });
	}
	return { ok: true, bundle: { requester, guild, faction, nonce, R, proofs } };
}

// A field of the signed text: not empty, at most `max` bytes, no separator, pipe or control.
function field(s, max) {
	return typeof s === 'string' && s !== '' && !FORBIDDEN.test(s) && enc.encode(s).length <= max;
}

// "Name-Realm": the realm follows the last dash and has no dash or space.
function validCharacter(s) {
	return field(s, 64) && /^[^-].*-[^- ]+$/s.test(s);
}

export function signedMessage(b, p) {
	return ['OLY4', b.requester, b.guild, b.faction, b.nonce, b.R, p.issued, p.keyId, p.confirmer].join('~');
}

// The whole check. Returns { status: 'linked' | 'rejected', reason, message, R, characters }.
// opts.userId: the signed-in user, who must own the code (the page); absent for the watcher.
export async function acceptBundle(env, text, opts = {}) {
	const t = opts.t || now();
	const parsed = parseBundle(text);
	if (!parsed.ok) return reject('format', `This is not a complete Olympus link (${parsed.error}).`);
	const b = parsed.bundle;
	const code = await env.DB.prepare('SELECT * FROM codes WHERE r = ?').bind(b.R).first();
	if (!code) return reject('unknown-code', 'This link was made with a code the bot never issued.', b.R);
	if (opts.userId && code.discord_id !== opts.userId) return reject('other-user', 'This link was made with a code of another Discord account.', b.R);
	if (code.used !== null && code.used !== undefined) {
		const same = await env.DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ? AND r = ?').bind(b.requester, code.discord_id, b.R).first();
		if (same) return { status: 'linked', reason: 'already', message: `${b.requester} is already linked.`, R: b.R, characters: await charactersOf(env, code.discord_id) };
		return reject('code-used', 'This code was already used.', b.R);
	}
	if (t > code.exp + LINK.DELIVERY_GRACE) return reject('expired', 'This code expired more than 7 days ago.', b.R);

	const checks = [];
	for (const p of b.proofs) checks.push(await checkProof(env, b, p, code, t));
	const valid = checks.filter((c) => c.ok);
	const councillor = valid.find((c) => c.key.kind === 'c');
	let counted = councillor ? [councillor] : null;
	let why = checks.filter((c) => !c.ok).map((c) => `${c.proof.keyId}: ${c.why}`);
	if (!counted && code.mode === 'a') {
		const drawn = await drawnPlayers(env, b.R, valid.filter((c) => c.key.kind === 'p'), t);
		counted = drawn.picked;
		why = why.concat(drawn.why);
	}
	if (!counted) {
		const need = code.mode === 'a' ? `one councillor or ${LINK.PLAYERS_NEEDED} drawn players` : 'one councillor';
		return reject('not-enough', `Not enough valid confirmations (needs ${need}).${why.length ? ` ${why.join('; ')}.` : ''}`, b.R);
	}

	// Claim the code first (two deliveries of the same link may race), then the role.
	const claim = await env.DB.prepare('UPDATE codes SET used = ? WHERE r = ? AND used IS NULL').bind(t, b.R).run();
	if (!claim.meta || claim.meta.changes !== 1) return reject('code-used', 'This code was already used.', b.R);
	const role = await discordRole(env, 'PUT', code.discord_id);
	if (!role.ok) {
		await env.DB.prepare('UPDATE codes SET used = NULL WHERE r = ?').bind(b.R).run();
		if (role.reason === 'not-in-server') return reject('not-in-server', 'Join the Olympus Discord server first, then send the link again.', b.R);
		return { status: 'error', reason: 'discord', message: 'Discord did not take the role change: try again in a minute.', R: b.R };
	}
	const previous = await env.DB.prepare('SELECT discord_id FROM members WHERE character = ?').bind(b.requester).first();
	await env.DB.batch([
		...counted.map((c) => env.DB.prepare('INSERT OR IGNORE INTO used (r, key_id, t) VALUES (?, ?, ?)').bind(b.R, c.proof.keyId, t)),
		env.DB.prepare(
			'INSERT INTO members (character, discord_id, guild, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?) ' +
				'ON CONFLICT(character) DO UPDATE SET discord_id = excluded.discord_id, guild = excluded.guild, faction = excluded.faction, r = excluded.r, linked = excluded.linked',
		).bind(b.requester, code.discord_id, b.guild, b.faction, b.R, t),
	]);
	if (previous && previous.discord_id !== code.discord_id) {
		const left = await env.DB.prepare('SELECT COUNT(*) AS n FROM members WHERE discord_id = ?').bind(previous.discord_id).first();
		if (!left || left.n === 0) await discordRole(env, 'DELETE', previous.discord_id); // the character moved away
	}
	return {
		status: 'linked',
		reason: 'linked',
		message: `${b.requester} is now linked to @${code.username}.`,
		R: b.R,
		characters: await charactersOf(env, code.discord_id),
	};
}

async function checkProof(env, b, p, code, t) {
	const bad = (why) => ({ ok: false, proof: p, why });
	const key = await env.DB.prepare('SELECT * FROM keys WHERE key_id = ?').bind(p.keyId).first();
	if (!key) return bad('unknown key');
	if (key.revoked) return bad('revoked key');
	if (key.owner_discord_id === code.discord_id) return bad("the requester's own key");
	if (p.issued < code.created - LINK.CLOCK_SKEW || p.issued > code.exp) return bad('signed outside the code\'s life');
	if (p.issued > t + LINK.CLOCK_SKEW) return bad('signed in the future');
	if (!(await ed25519Verify(key.public_key, b64urlDecode(p.sig), enc.encode(signedMessage(b, p))))) return bad('bad signature');
	if (!(key.kind === 'c' && key.bootstrap)) {
		const mine = await env.DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ?').bind(p.confirmer, key.owner_discord_id).first();
		if (!mine) return bad("the confirmer is not a linked character of the key's owner");
	}
	const own = await env.DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ?').bind(b.requester, key.owner_discord_id).first();
	if (own) return bad("the requester is the key owner's own character");
	const reused = await env.DB.prepare('SELECT 1 AS x FROM used WHERE r = ? AND key_id = ?').bind(b.R, p.keyId).first();
	if (reused) return bad('already counted');
	return { ok: true, proof: p, key };
}

// Mode "a": three drawn players, all of them old enough, ranked < M in this code's draw, from
// three owners, signed within 5 minutes of each other.
async function drawnPlayers(env, R, valid, t) {
	const why = [];
	const old = [];
	for (const c of valid) {
		if (t - c.key.created < LINK.KEY_MIN_AGE) why.push(`${c.proof.keyId}: key younger than 7 days`);
		else if (t * 1000 - snowflakeTime(c.key.owner_discord_id) < LINK.ACCOUNT_MIN_AGE * 1000) why.push(`${c.proof.keyId}: Discord account younger than 30 days`);
		else old.push(c);
	}
	if (old.length < LINK.PLAYERS_NEEDED) return { picked: null, why };
	const rank = await drawRanks(env, R);
	const limit = drawLimit(rank.size);
	const inDraw = [];
	for (const c of old) {
		const r = rank.get(c.proof.keyId);
		if (r === undefined || r >= limit) why.push(`${c.proof.keyId}: not drawn for this code`);
		else inDraw.push(c);
	}
	inDraw.sort((a, b) => a.proof.issued - b.proof.issued);
	for (let i = 0; i < inDraw.length; i++) {
		const picked = [];
		const owners = new Set();
		for (let j = i; j < inDraw.length && inDraw[j].proof.issued - inDraw[i].proof.issued <= LINK.WINDOW; j++) {
			if (owners.has(inDraw[j].key.owner_discord_id)) continue;
			owners.add(inDraw[j].key.owner_discord_id);
			picked.push(inDraw[j]);
			if (picked.length === LINK.PLAYERS_NEEDED) return { picked, why };
		}
	}
	if (inDraw.length >= LINK.PLAYERS_NEEDED) why.push('the player confirmations are more than 5 minutes apart');
	return { picked: null, why };
}

// Every active player key's place in the draw of R: SHA-256(R .. "~" .. keyId), lowest first.
export async function drawRanks(env, R) {
	const rows = (await env.DB.prepare("SELECT key_id FROM keys WHERE kind = 'p' AND revoked = 0").all()).results || [];
	const hashed = await Promise.all(rows.map(async (row) => [row.key_id, await sha256Hex(`${R}~${row.key_id}`)]));
	hashed.sort((a, b) => (a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0));
	return new Map(hashed.map(([id], i) => [id, i]));
}

export function drawLimit(activePlayerKeys) {
	return Math.max(20, Math.ceil(activePlayerKeys * 0.03));
}

export function snowflakeTime(id) {
	return Number((BigInt(id) >> 22n) + 1420070400000n);
}

async function charactersOf(env, discordId) {
	const rows = (await env.DB.prepare('SELECT character FROM members WHERE discord_id = ? ORDER BY linked').bind(discordId).all()).results || [];
	return rows.map((r) => r.character);
}

function reject(reason, message, R) {
	return { status: 'rejected', reason, message, R: R || null };
}

async function logUpload(env, source, text, result, extra) {
	let b = null;
	const parsed = parseBundle(typeof text === 'string' ? text.trim() : '');
	if (parsed.ok) b = parsed.bundle;
	const code = b ? await env.DB.prepare('SELECT discord_id FROM codes WHERE r = ?').bind(b.R).first() : null;
	await env.DB.prepare(
		'INSERT INTO inbox_uploads (source, r, discord_id, requester, from_character, received, uploaded, status, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
	)
		.bind(source, b ? b.R : null, extra.discordId || (code && code.discord_id) || null, b ? b.requester : null, extra.from || null, extra.received || null, extra.uploaded, result.status, result.reason || null)
		.run();
}

// ---------------------------------------------------------------------------
// Discord

async function discordRole(env, method, discordId) {
	const res = await fetch(`https://discord.com/api/v10/guilds/${env.GUILD_ID}/members/${discordId}/roles/${env.ROLE_ID}`, {
		method,
		headers: { Authorization: `Bot ${env.DISCORD_BOT_TOKEN}`, 'X-Audit-Log-Reason': 'Olympus Link' },
	});
	if (res.ok) return { ok: true };
	let code = 0;
	try {
		code = (await res.json()).code;
	} catch {}
	if (res.status === 404 && code === 10007) return { ok: false, reason: 'not-in-server' }; // Unknown Member
	console.error('olympus-link: Discord role', method, res.status, code);
	return { ok: false, reason: 'discord' };
}

// ---------------------------------------------------------------------------
// Crypto (WebCrypto Ed25519: Workers and Node 20+)

let backendKey = null;

async function backendSign(env, payload) {
	const id = `${env.LINK_BACKEND_SEED}.${env.LINK_BACKEND_PUBLIC}`;
	if (!backendKey || backendKey.id !== id) {
		const x = b64urlEncode(hexToBytes(env.LINK_BACKEND_PUBLIC));
		const jwk = { kty: 'OKP', crv: 'Ed25519', d: env.LINK_BACKEND_SEED, x, ext: false };
		const key = await crypto.subtle.importKey('jwk', jwk, { name: 'Ed25519' }, false, ['sign']);
		// A seed and a public key that do not belong together would sign codes nobody accepts.
		const probe = enc.encode('olympus-link self-check');
		const sig = new Uint8Array(await crypto.subtle.sign('Ed25519', key, probe));
		if (!(await ed25519Verify(env.LINK_BACKEND_PUBLIC, sig, probe))) throw new Error('LINK_BACKEND_SEED and LINK_BACKEND_PUBLIC do not match');
		backendKey = { id, key };
	}
	return b64urlEncode(new Uint8Array(await crypto.subtle.sign('Ed25519', backendKey.key, enc.encode(payload))));
}

export async function ed25519Verify(publicHex, sig, message) {
	if (typeof publicHex !== 'string' || !/^[0-9a-fA-F]{64}$/.test(publicHex) || sig.length !== 64) return false;
	try {
		const key = await crypto.subtle.importKey('raw', hexToBytes(publicHex), { name: 'Ed25519' }, false, ['verify']);
		return await crypto.subtle.verify('Ed25519', key, sig, message);
	} catch {
		return false;
	}
}

async function sha256Hex(text) {
	return bytesToHex(new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(text))));
}

// ---------------------------------------------------------------------------
// Small helpers

function json(data, status = 200) {
	return new Response(JSON.stringify(data), {
		status,
		headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
	});
}

async function readJson(request, limit) {
	const text = await request.text();
	if (text.length > limit) return null;
	try {
		return JSON.parse(text);
	} catch {
		return null;
	}
}

// The page's POSTs carry the session cookie: only the page's own origin may send them.
function sameOrigin(request, env) {
	const origin = request.headers.get('Origin');
	return !!origin && origin === (env.LINK_ORIGIN || new URL(request.url).origin);
}

async function adminAuthorized(request, env) {
	const given = (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
	if (!env.LINK_ADMIN_TOKEN || env.LINK_ADMIN_TOKEN.length < 32 || !given) return false;
	const [a, b] = await Promise.all([given, env.LINK_ADMIN_TOKEN].map((s) => crypto.subtle.digest('SHA-256', enc.encode(s))));
	const x = new Uint8Array(a);
	const y = new Uint8Array(b);
	let diff = 0;
	for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
	return diff === 0;
}

function hexToBytes(hex) {
	const out = new Uint8Array(hex.length / 2);
	for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
	return out;
}

function bytesToHex(bytes) {
	return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

function b64urlEncode(bytes) {
	let out = '';
	for (let i = 0; i < bytes.length; i += 3) {
		const n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
		const chars = i + 2 < bytes.length ? 4 : i + 1 < bytes.length ? 3 : 2;
		for (let j = 0; j < chars; j++) out += B64[(n >> (18 - 6 * j)) & 63];
	}
	return out;
}

function b64urlDecode(s) {
	const out = new Uint8Array(Math.floor((s.length * 6) / 8));
	let bits = 0;
	let acc = 0;
	let o = 0;
	for (const c of s) {
		acc = ((acc << 6) | B64.indexOf(c)) & 0xffffff;
		bits += 6;
		if (bits >= 8) {
			bits -= 8;
			out[o++] = (acc >> bits) & 255;
		}
	}
	return out;
}
```

## Running the tests

```sh
node --test web/test          # from the repository root (Node 22.13 or newer)
```

They run the page's logic, this Worker (D1 is `node:sqlite` with the schema above, Discord a
stub), the key tool, the inbox tool and the QR reading against the shared vectors, and nothing
touches the network.
