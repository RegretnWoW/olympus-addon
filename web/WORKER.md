# Olympus Link: the Worker and D1

The detailed reference for Fernmelder, who runs the Olympus Discord bot on Cloudflare (a Worker
and D1). **Start with [`FERN.md`](FERN.md)**: what to add to your bot, in an afternoon, in your
own Worker's terms. This file explains every part and why each check is there.

The split is yours: your bot keeps `/verify`, does every check and gives the role, and adds one
route, `POST /proof`. The page is ours: a static page on this repository's GitHub Pages
(`web/public/`, at `https://dnl-gentile.github.io/olympus-addon/`) that signs the player in with
Discord, reads the link the game made, and posts it to your `/proof`. Every check lives in
`web/worker/link-core.mjs`, plain functions over D1 that your routes call; `web/worker/link-worker.js`
is a complete Worker built on it. The addon side, the page, the key tool (`scripts/link-keys.py`)
and the watcher's inbox tool (`web/tools/read-inbox.mjs`) come ready. Both files, the D1 schema
and the test vectors are at the end of this one, and `node --test web/test` runs that exact code
against the vectors with a local SQLite in place of D1.

## How it works

A player proves that a World of Warcraft character is theirs by typing, in game, a code the
backend signed for their Discord account. Players who are already trusted (a High Councillor
at launch; later, when you allow it, three randomly drawn verified players) confirm it in game:
their addon signs a confirmation with a key of its own, and says how it checked the player's
guild. The finished, signed proof reaches the Worker in one of two ways, and the Worker gives
the Discord role.

```
 Discord /verify (your bot)
   └─> code  OLC2.<R>.<username>.<exp>.<mode>.<T>.<sig>    (signed with the backend key)

 each confirmer's key is one character's, and so is its certificate:
   every one, a High Councillor's or a drawn player's: you make it, the backend key signs its
   certificate, and the confirmer types both in game (step 8)
   (the council authority, a councillor's addon making its own key and the author's client
    certifying it, is off in the addon, and here while LINK_CA_PUBLIC stays out: step 1b)
 confirmers announce themselves in game with it, from that character only:
   DV~1~OLK2.<keyId>.<public key>.<c|p>.<exp>.<Name-Realm>.<sig>

 in game: the player types  /oly discord <code>, sees "@username", clicks Accept
   requester ──DR (with the tag)──> an online confirmer ──DA──> requester
   (the confirmer's key signs OLY4; the requester checks the signature with the certified key)

 the finished proof (OLB5: each confirmation with its certificate), two ways:
   watcher path:  requester ──DB──> your watcher character (a High Councillor, "watcher on"),
                  whose addon checks every confirmation before it keeps it
                  later, read-inbox.mjs uploads the watcher's SavedVariables ──> POST /api/link/inbox
   can't wait:    the page (GitHub Pages) reads the QR code / the link / Olympus.lua, signs the
                  player in with Discord, and posts both ─────────────────────> POST /proof
                  {"text": <the link>, "discordToken": <the player's Discord sign-in>}

 the Worker checks everything, then your promote() gives the role
```

- The code is the player's alone. Its signature is the secret that ties each link to the
  player who typed it (the tag, below): the QR code and the game's copy box never carry it, so
  a stream that shows the QR code gives nobody a link of their own. `/verify` answers in a
  reply only the player sees, and both it and the page tell players to keep the code, and the
  Olympus Link window, off stream.
- Nothing needs you online: confirmations need only confirmers online. The finished proof
  waits in the player's addon until a watcher is online, then in your watcher's SavedVariables
  until you upload them. One rule for how long, counted from the code's expiry (a code lives a
  day): the Worker takes a link until 7 days after it; the addon hands it to a watcher until 5
  days after it, so you have at least 2 days to upload what your watcher got; the watcher keeps
  it until the Worker would refuse it. Upload the inbox every day or two.
- Nothing is lost when the Worker or Discord is down: the page says so, the addon keeps the
  proof, the code is released again, and either path delivers it later.
- The Worker stores only public keys. The backend's private key is a Worker secret; each
  confirmer's private key stays in that confirmer's game (one character's: another character of
  the same account has its own key, or none); the council authority's private key stays in
  the addon author's own game. Confirmer keys can only confirm.

## What you need

- The Worker you already run, and `wrangler`.
- The bot's Discord application: its client id (Developer Portal, OAuth2), with our page as one
  of its OAuth2 redirects (`https://dnl-gentile.github.io/olympus-addon/`); what your `promote()`
  already uses to give the role (the reference Worker's: the bot token, with Manage Roles and its
  own role above the role it gives, the Olympus server id and the role id); its public key
  (General Information) if `/verify` comes over HTTP.
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
  for the addon (`ns.LINK_BACKEND_KEYS` in `Olympus/Link.lua`): the addon refuses any code, and
  any confirmer's certificate, whose signature does not check against one of those keys.
- The same key signs the certificates of the confirmer keys you register (step 8), the High
  Councillors' too. The Worker does it when you register a councillor's key, and a player's once
  it counts. To sign them on your own computer instead (`link-keys.py cert`), keep the seed in a
  file only you can read and give the tool its path; the tool never prints it.
- Rotating it: make a new key, have its public key added to `ns.LINK_BACKEND_KEYS` next to the
  old one (the addon takes two for this), wait until that addon version is out, then switch the
  Worker's `LINK_BACKEND_SEED` and `LINK_BACKEND_PUBLIC` and renew every confirmer's
  certificate (step 8) before the old key leaves the addon. Codes already handed out stay valid
  until they expire.

### 1b. The council authority (off: leave `LINK_CA_PUBLIC` out)

**Off in this release** (Konig's review of 1.0.0). The addon carries it behind a switch its author
leaves off (`ns.LINK_COUNCIL_AUTHORITY = false` in `Olympus/Link.lua`). While it is off, no
councillor's addon makes a key in game or asks for a certificate, the author's client signs none
(even holding the authority's seed), no addon takes a certificate of the authority, and a key an
earlier build made in game is removed at login, with one line. Why: WoW's Lua has no
cryptographic random source, so a key made in game comes from a few tens of bits of frame timing
(the comment above `Link.EntropySample` in `Olympus/Link.lua` says which), it sits in plain text
in the SavedVariables, and its certificate lasts a year. So every High Councillor's key is one you
make (step 8: kind `c`, with `--bootstrap` at launch), exactly like a player's, and
`LINK_CA_PUBLIC` stays out of your settings (step 5): without it this Worker takes none of the
authority's certificates either. Even with the switch on, the addon runs none of it before the
bot's key is in the addon.

The rest of this section is how the path works, for the day the author turns it on: he tells
you, and you decide then whether to set `LINK_CA_PUBLIC` (and `LINK_COUNCIL_CHARACTERS` with it).

With it on, High Councillors do not type keys. The first time a councillor's addon finds its
character on the signed High Council list, it makes a key of its own, in the game, and keeps it for that
character. When that councillor and the addon's author are online at the same time, the
councillor's addon asks the author's addon for a certificate, and his addon signs one by
itself: for that key, that character, a year. From then on the councillor confirms like anyone with a certificate. The
private key never leaves the councillor's computer, and the key that signs these certificates
(the council authority's) never leaves the author's.

The author makes the authority once, on his computer:

```sh
python3 scripts/link-keys.py ca
```

It writes `dist/LinkCA.lua` (the seed, which only the author's own game loads, and which is never
printed, published or committed) and prints a public key. That public key goes into:

- the Worker var `LINK_CA_PUBLIC` (step 5), so this Worker takes those certificates;
- the addon (`ns.LINK_CA_KEYS` in `Olympus/Link.lua`), so every player's addon does too.

What the Worker does with them, in plain words:

- A councillor's key certified this way is never registered with you. Every confirmation in a
  link carries its certificate, so the Worker checks it there: signed by the council authority,
  a councillor's (tier `c`), its id the first 12 hex digits of the SHA-256 of the key itself, still
  valid when the confirmation was signed. It then counts like a registered councillor key.
- The first time a link it confirmed is accepted, the Worker writes down whose it is: the key
  itself (its public key), its id and the councillor's character (the `council_keys` table). It
  writes this with the link, after checking the confirmation's signature and everything else, and
  never for a link it refuses: a certificate for someone else's key, carried with a signature
  nobody made, leaves no trace. From then on, the same key with a certificate naming another
  character is refused. (The author's client never certifies one key for two characters either:
  it keeps a record of every key it certified.)
- What that trusts: whoever holds the authority's seed (the author's game, or anyone who copied
  `dist/LinkCA.lua` from it) can certify a key for any character, and one councillor's
  confirmation links. `LINK_COUNCIL_CHARACTERS` (step 5) keeps that with you: the High
  Councillors' characters you accept (`Name-Realm`, comma-separated). A certificate for any
  other character then counts for nothing, whatever the authority signs (set but empty: none
  counts; left out: every character it certifies). The authority can still certify a new key
  for a character on the list (that is how `/oly discord key new` works), so watch
  `council_keys` (every such key, with `first_seen`) and `used` (the keys that counted for each
  code). Keys you register yourself are not affected by the list, and leaving `LINK_CA_PUBLIC`
  out makes them the only councillor keys.
- A key the councillor no longer uses keeps counting here until you revoke it: this Worker never
  asks the councillor's game, and a certificate lasts a year. Whoever holds that key (a leaked
  one, or the councillor after leaving) could still make links with it outside the game. So:
- Revoking one key (it leaked, or the councillor replaced it): send
  `{"key_id": "<the 12 hex digits>", "revoke": true}` to `/api/link/keys` (or run the SQL of
  `python3 scripts/link-keys.py revoke <id>`). It goes on the revocation list (`revoked_keys`) at
  once, whether a link used it already or not, and its confirmations stop counting. `/oly discord
  status` in the councillor's game shows the current key's id; `/oly discord key new` (a new key,
  whose certificate comes from the author's client the next time they meet) and `/oly discord key
  off` print the old key's id for them to send you, and say it counts until you revoke it.
- Revoking a councillor (the author took them off the signed list, or you can't name all their
  keys): send `{"character": "<Name-Realm>", "revoke": true}` (or run the SQL of `python3
  scripts/link-keys.py revoke --character <Name-Realm>`). Every certificate the council authority
  signed for that character until now stops counting, whatever key it names, seen here or not
  (keys they rotated away included), and so do the keys you registered for that character. The
  answer lists those keys, and the authority's keys seen for that character. A certificate the
  authority signs for it afterwards counts (a councillor back on the list, whose addon makes a new
  key with `/oly discord key new` after you revoked), unless the character is off
  `LINK_COUNCIL_CHARACTERS`: that is how you keep one out for good. So revoke only the old key's
  id when a councillor just rotated a leaked key: revoking the character would stop the new one
  too, until another `key new`.
- Taking a councillor off the signed list stops them in game at once: their addon stops
  confirming, and nobody's addon asks them or keeps a link that counts on them. It does not stop
  them here (this Worker never sees the signed list): revoke the character too.
- What the council authority signed: in the author's game, `/oly discord certified` prints every
  certificate his client signed (the key id, the character, the end), which his SavedVariables
  keep (`OlympusDB.discord.certified`). He sends you that list when a councillor leaves or a key
  leaks, and you revoke by key id or by character.
- One councillor's key never confirms codes of their own Discord account or its characters, once
  their character is linked (the Worker looks it up in `members`).

You can still register a councillor's key yourself (step 8, `--bootstrap`) for a councillor who
wants one made on a computer: both kinds work side by side.

### 2. The database

```sh
wrangler d1 create olympus-link
wrangler d1 execute olympus-link --remote --file web/worker/schema.sql
```

A database of its own, bound as `LINK_DB` (step 5): the tables have plain names (`codes`, `keys`,
`members`...) that could meet yours. `link-core.mjs` reads `LINK_DB`, or `DB` when there is no
`LINK_DB`. Eight tables: `codes` (every code issued, single use, with its draw threshold), `keys`
(confirmer public keys you registered, one certified per Discord account, each for one
character, with the end of their certificate), `council_keys` (High Councillors' keys the council
authority certified, recorded with the first link each one helped accept), `revoked_keys` (the council
authority's keys you revoked), `revoked_characters` (characters whose keys you revoked all at
once), `used` (the proofs that counted), `members` (linked characters,
with how their guild was checked) and `inbox_uploads` (every bundle received: the audit trail and
the page's rate limit). The full schema is in "The D1 schema" below.

### 3. The code

Copy `web/worker/link-core.mjs` next to your Worker's entry file. It needs nothing but WebCrypto
(Ed25519 and SHA-256), `fetch` and D1: no npm packages. Your routes call it:

```js
import { handleProof, handleInbox, handleKeys } from './link-core.mjs';

export default {
	async fetch(request, env, ctx) {
		const { pathname } = new URL(request.url);
		const roles = { promote: (id) => promote(env, id), demote: (id) => demote(env, id) }; // yours
		if (pathname === '/proof') return handleProof(request, env, roles);
		if (pathname === '/api/link/inbox') return handleInbox(request, env, roles);
		if (pathname === '/api/link/keys') return handleKeys(request, env);
		return yourBot(request, env, ctx); // everything you already answer, /verify included (step 7)
	},
};
```

- `promote(discordId, verdict)` is yours: it gives the role. Resolve when it did; throw (or
  return `false`) when Discord refused, and the code is freed so the same link works on the next
  try; `{ ok: false, reason: 'not-in-server' }` tells the player to join the server first.
  `demote(discordId)` (optional) takes the role from an account whose only linked character
  moved to another account.
- `acceptProof(env, text, { discordId, promote, demote })` is the whole link, for routes you write
  yourself: the checks ("What the Worker checks"), then it claims the code, calls `promote`, and
  records the character. `checkProof(env, text, { discordId })` gives the same verdict, reading
  only. `handleProof` is `acceptProof` with the page's CORS, the sign-in check, the rate limit and
  the audit trail around it.
- `web/worker/link-worker.js` is a complete Worker on the same functions (its `discordRole` is a
  `promote`), with its routes under `/api/link/`.

### 4. Who is sending

The page is on another origin (GitHub Pages) and has no cookie of yours. It sends the player's
Discord sign-in in the body, and `handleProof` asks Discord who that is (`discordUser`):

- The page signs the player in on Discord's own page (OAuth2, the implicit grant, scope
  `identify`, your application's client id, a random `state` it checks when Discord comes back),
  keeps the access token in that browser tab only, and sends it as `discordToken`, with the link
  as `text`.
- The Worker asks `GET https://discord.com/api/v10/oauth2/@me` with it: the token must be your
  application's (`application.id` is `DISCORD_CLIENT_ID`), with `identify`, and not expired. A token
  another site got for its own application counts for nothing. The token goes to Discord only and
  is stored nowhere. Its user is the account that must own the link's code (`other-user` if not).
- CORS: only `LINK_ORIGIN` (`https://dnl-gentile.github.io`, exactly: never `*`, and no
  credentials) gets `Access-Control-Allow-Origin`. `OPTIONS` (the browser's preflight) answers 204
  for it and 403 for anyone else, and a `POST` from another origin, or with none, is refused
  (`origin`).
- `LINK_SITE_TOKEN`, when you set it: the page sends it as `Authorization: Bearer <it>`. It sits in
  the page's `config.js` for anyone to read: a switch that cuts the page off the moment you change
  it, not a secret.
- `username` in a code is the Discord username (the unique, lowercase handle), not the display
  name: it is what the player sees in the game's Accept window.
- Same-site variant: a page served from your own site, behind your own login, can use the
  reference Worker's `/api/link/me`, `/api/link/code` and `/api/link/submit` instead, with
  `sessionUser` (its `ADAPT` function) connected to that login. The GitHub Pages page never uses
  them.

### 5. Settings

```toml
# wrangler.toml (your existing file: add these)
[[d1_databases]]
binding = "LINK_DB"
database_name = "olympus-link"
database_id = "<from wrangler d1 create>"

[vars]
LINK_MODE = "c"                          # councillors only at launch; "a" when the pool is large enough
LINK_GUILD_POLICY = "verified"           # or "claimed": see "The guild check" below
LINK_ORIGIN = "https://dnl-gentile.github.io"         # the page's origin: no path, no trailing slash
DISCORD_CLIENT_ID = "<your application's client id>"  # the page's sign-in must be for it
LINK_BACKEND_PUBLIC = "<64 hex from link-keys.py backend>"
# The council authority is off (step 1b): leave these two out.
# LINK_CA_PUBLIC = "a84125fa433276244fda242a28d2e4208a5d6db26dcb529e3e87af61939e10a7"
# LINK_COUNCIL_CHARACTERS = "<Name-Realm>, <Name-Realm>"  # with it: the High Councillors you accept
DISCORD_PUBLIC_KEY = "<Developer Portal > General Information > Public Key>"      # only for /verify over HTTP
```

```sh
wrangler secret put LINK_BACKEND_SEED    # from link-keys.py backend
wrangler secret put LINK_ADMIN_TOKEN     # python3 -c "import secrets; print(secrets.token_urlsafe(32))"
wrangler secret put LINK_SITE_TOKEN      # optional (step 4)
```

`LINK_ADMIN_TOKEN` (at least 32 characters) is for your own tools only: the watcher inbox
upload and the confirmer keys (`/api/link/keys`), and in the reference Worker a gateway bot's
code requests. The reference Worker's own role also reads `DISCORD_BOT_TOKEN`, `GUILD_ID` and
`ROLE_ID`.

### 6. The page

The page is ours, on this repository's GitHub Pages: `https://dnl-gentile.github.io/olympus-addon/`,
published from `web/public/` by `.github/workflows/pages.yml`. It is plain HTML, CSS and ES modules,
no build step, and every address in it is relative. Its settings are one file,
`web/public/config.js`: your `/proof` address (`PROOF_URL`), your application's client id
(`DISCORD_CLIENT_ID`), the site token if you gave one (`SITE_TOKEN`), and the command that gives a
code (`VERIFY_COMMAND`, `/verify`). Until those are filled in, it says Olympus Link is not open yet.

The page's address is what the addon puts in the QR code (`ns.LINK_SITE`, followed by `#b=` and
the signed link). The part after `#` never reaches a server: a phone that scans the QR code opens
the page, which reads the link from its own address, asks the player to sign in with Discord if
needed, and sends it. Its one request is `POST <PROOF_URL>` with `{"text", "discordToken"}` (no
cookie, no referrer); it loads nothing but its own files and Google Fonts (its
Content-Security-Policy says so, and its `connect-src` names your Worker's origin once `PROOF_URL`
is set), and it shows nothing to click inside another page's frame.

The code step tells the player to use `/verify` in the Olympus server and to keep the code, and
the game's Olympus Link window, off stream and out of screenshots. `?demo=code` (and `wait`,
`screen`, `scanning`, `phone`, `other`, `pick`, `scanned`, `found`, `done`, `error`, `closed`) shows
each step with made-up data and never calls anything; `&lang=pt` shows the Portuguese page (it is
chosen from the browser's language otherwise).

Tell Daniel the name of your watcher's owner for the game's texts ("Fernmelder's watcher",
`ns.LINK_WATCHER_OWNER`).

### 7. `/verify` in Discord

A player types `/verify` in the Olympus server and gets their code in a reply only they see (it
also tells them to keep it off stream):

```js
const code = await issueCode(env, { id: user.id, username: user.username }); // the member's Discord user
// code.reply: the line to paste in the game, or why there is none (3 codes a day; an old-style username)
```

- **Over HTTP** (the application's Interactions Endpoint URL): answer
  `{ type: 4, data: { flags: 64, content: code.reply } }` (64: only they see it). The reference
  Worker's `/api/discord/interactions` checks Discord's signature on every request with
  `DISCORD_PUBLIC_KEY` and answers `/verify` itself. Do not point the endpoint there if your bot
  receives its commands over the gateway: Discord sends them to one place only.
- **Over the gateway** (discord.js, discord.py...): the bot asks the Worker and replies (the
  reference Worker's `/api/link/bot-code` runs `issueCode`):

```js
// discord.js v14
client.on('interactionCreate', async (interaction) => {
	if (!interaction.isChatInputCommand() || interaction.commandName !== 'verify') return;
	const res = await fetch('https://<your worker>/api/link/bot-code', {
		method: 'POST',
		headers: { Authorization: `Bearer ${process.env.LINK_ADMIN_TOKEN}`, 'Content-Type': 'application/json' },
		body: JSON.stringify({ id: interaction.user.id, username: interaction.user.username }),
	});
	const data = await res.json();
	await interaction.reply({ content: data.reply || data.message, flags: 64 }); // 64: only they see it
});
```

If `/verify` is new, register it once (a `POST` adds or updates this one command and leaves your
others):

```sh
curl -X POST "https://discord.com/api/v10/applications/$APP_ID/guilds/$GUILD_ID/commands" \
  -H "Authorization: Bot $DISCORD_BOT_TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"verify","description":"Get your Olympus Link code for the game","type":1}'
```

### 8. Confirmer keys

Each confirmer you register has a key of their own, made on your computer, for one of their
characters, and a certificate for it signed with the backend key that names that character. The
confirmer types two lines in game, on that character: the key, then the certificate. That is every
confirmer, the High Councillors included: their addons make no key of their own (step 1b). The
addon keeps neither line until the release that carries your bot's key (`ns.LINK_BACKEND_KEYS`).

```sh
python3 scripts/link-keys.py confirmer <id> c --character "<Name-Realm>" --owner <their Discord id> --username <their username> --bootstrap
python3 scripts/link-keys.py confirmer <id> p --character "<Name-Realm>" --owner <their Discord id> --username <their username>
```

- `<id>`: 6 to 16 of a-z and 0-9, never reused (it is part of what they sign); 12 hex digits are
  kept for the council authority's keys.
- `--character`: the one character that confirms with this key, as the game writes it
  (`Name-Realm`). Only that character's addon announces the key and signs with it; players'
  addons ask it only from that character, and the Worker counts a confirmation only when its
  certificate is the one registered for the key and names the confirming character. An alt of
  the same account needs its own key (or confirms nothing).
- `c` is a High Councillor, `p` a player for the draw (mode `a`). The character must be one of the
  key owner's linked characters (the Worker refuses the key otherwise, `character-not-linked`,
  and checks it again for every confirmation); `--bootstrap` lifts that for the first councillor
  keys, since at launch nobody has linked a character yet.
- The tool prints the line the confirmer types in game (`/oly discord key <id> <seed>`), which
  you send them privately (a direct message, never a channel); the public key; and two ways to
  register it:
  - **With the Worker** (the backend seed stays in the Worker): the tool prints the `curl`
    that posts the key to `POST /api/link/keys` with your admin token. For a councillor key,
    the answer's `command` is the second line for the confirmer: `/oly discord cert
    <certificate>`. For a player key, the answer's `cert_from` says when to ask for it (below).
  - **In D1 directly**: the `INSERT` it prints, then the certificate with
    `python3 scripts/link-keys.py cert <id> <public key> <c|p> <days> --character "<Name-Realm>" --backend-seed-file <file>`
    (or `LINK_BACKEND_SEED_FILE` / `LINK_BACKEND_SEED` in the environment), which prints the
    `/oly discord cert` line and the `UPDATE` that records the certificate's end in D1. A player
    key's also takes `--created <its created> --owner <its owner_discord_id>`: `confirmer`
    prints that command, filled in. Given the backend seed the same way, `confirmer` prints a
    councillor key's certificate at once.
- In game, `/oly discord key` shows the id and the public key, to compare with yours; the addon
  checks that the certificate names the public half of the key typed before it, and this
  character. It never prints, sends or logs the seed. Both lines fit the game's chat (under 255
  characters), and so does the announcement that carries the certificate (`DV~1~<certificate>`).
- **A player key gets its certificate only once it counts.** Every player's addon asks the
  player keys with a valid certificate that a code's `T` draws, and cannot tell how old a key
  is. The Worker counts a player key only for codes issued once it was 7 days old and its
  owner's Discord account 30 days old, and a code stays open for a day. So a player key is
  certified only when it counts for every code still open: 8 days and 5 minutes after you
  registered it at the soonest (7 days, a day for the codes already handed out, 5 minutes of
  clock difference), and 31 days and 5 minutes after the owner's Discord account was made when
  that is later. Until then it is not in the draw, and nobody asks it. `cert_from` in the
  Worker's answer is that time: from then on, `{"key_id": "<id>", "renew": true}` answers the
  certificate line (before, `too-early` with `cert_from`), and you send the confirmer both lines
  together. `link-keys.py cert` refuses a player certificate before that time too. A
  councillor's key is certified at once: councillors count without the draw.
- The certificate is how every player's addon knows, without the bot, that a confirmer's key
  is registered and whether it is a councillor's: it asks only confirmers with a valid,
  unexpired certificate (a `c` one only from a councillor of the signed list), and checks each
  confirmation's signature with the certified key before it counts it. It lasts 365 days for a
  councillor and 90 for a player by default (`days` in the request, `--days` for the tool):
  renew it before it ends (`{"key_id": "<id>", "renew": true}`, or `link-keys.py cert` again),
  and the confirmer types the new `/oly discord cert` line. A key whose certificate has ended
  leaves the draw. A player's is shorter because the addons cannot learn that you revoked a
  key or replaced it: they keep asking it, when the draw picks it, until its certificate ends,
  and the Worker refuses what it signs. A replaced or revoked key gets no new certificate.
- One certified key per Discord account: the database refuses a second. **Rotating** (a new key
  for the same person): register the new one with `"replace": true`. Its first certificate
  replaces the old key: a councillor's at once; a player's once it counts (above), so until
  then the old key keeps counting, and the confirmer keeps using it. In D1, run the `UPDATE ...
  replaced_at` that `link-keys.py cert` prints before its `UPDATE ... cert_exp` (for a
  councillor key certified at once, the one `confirmer` prints before its `INSERT`). A
  replaced key leaves the draw (a player key no longer counts for codes issued after that) but
  still checks the confirmations it signed, so links waiting for the watcher keep counting.
  Send the confirmer the new lines as soon as you have the certificate: while their addon still
  announces the old player key, requesters may ask it in vain. Once they typed the new lines in
  game, revoke the old key. In that order: rotate the key in game first, then revoke.
  **Revoking**: `{"key_id": "<id>", "revoke": true}`, or `python3 scripts/link-keys.py revoke
  <id>`, and the confirmer types `/oly discord key off` (every key of one character at once:
  `{"character": "<Name-Realm>", "revoke": true}`, step 1b). A revoked key's confirmations stop
  counting at once, including ones not delivered yet: a leaked key is revoked at once, without
  waiting. A link carries up to two councillor confirmations, so one revoked councillor key
  does not sink it; the Worker counts any three valid player confirmations of the up to four a
  link carries. `python3 scripts/link-keys.py public < seed.txt` prints the public key of a seed.
- Keys only confirm: they cannot issue codes, a player key cannot link anyone alone, and the
  addon signs on its own only within its limits (one proof a minute and 5 a day per requesting
  character, 30 a minute in all, never for its own account's characters, never across
  factions, only for Olympus guilds).

### 9. Your watcher

On one of your High Councillor characters, type `/oly discord watcher on`. While it is online,
players whose proof is ready deliver it to it, and it keeps them in its SavedVariables
(`OlympusDB.discord.inbox`, 500 at most). Its addon first checks every confirmation of a link
with the certificate the link carries (and that together they are enough), so made-up links never
take a place. It keeps one link per character (its latest) and no cap per code: a code's `R` is
public on a stream and only this Worker can check the tag, so a character that got a councillor's
real confirmation for itself with someone's `R` takes its own place (you will see it refused as
`tag`), never the real requester's. An entry stays until the Worker can no longer take it (7 days
after its code expired). WoW writes that file on `/reload`, logout or quit. Then, every day or two:

```sh
# macOS
LINK_ADMIN_TOKEN=... node web/tools/read-inbox.mjs "/Applications/World of Warcraft/_classic_beta_/WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua" --post https://<your worker>/api/link/inbox
# Windows (PowerShell)
$env:LINK_ADMIN_TOKEN="..."; node web/tools/read-inbox.mjs "C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF\Account\<ACCOUNT>\SavedVariables\Olympus.lua" --post https://<your worker>/api/link/inbox
```

Without `--post` it prints the same JSON (`{"bundles": [...]}`, oldest first) for you to look
at or send another way. It reads the file with a small SavedVariables parser (no packages),
takes every inbox entry however the addon keys it (by code, or by code and sender), sends each
link once, skips malformed entries, and prints the inbox only: never the confirmer key kept in
the same file. Uploading twice is harmless: a link that already counted answers `already`. It
only posts over `https` (or to `localhost`), since the admin token rides along.

### 10. From councillors only to drawn players

Launch with `LINK_MODE = "c"`: only councillor confirmations count, and every code says so (the
addon then asks councillors only). When enough verified players have keys, set it to `"a"`:
new codes also accept three drawn players when no councillor is online, and each carries the
draw's threshold `T`, so the addon asks the players this Worker's draw picks. Since a player
key is certified only once the Worker counts it (step 8), every certified key a code draws
counts, but for one you revoked or replaced while its certificate runs: the addons cannot learn
that, may still ask it, and the Worker refuses what it signs, so a link then needs three other
drawn players, or a councillor. Codes already issued keep the mode and `T` they were signed
with. Register the first player keys at least 8 days before you switch: a player key gets its
certificate only then (step 8), and until some have one, only councillors confirm.

The rule is three of the M keys drawn for each code (M = max(20, 3% of the pool), "The
formats"), not three of five: the addon asks five at a time, but the Worker takes any three drawn
keys. While there are 20 player keys or fewer, every key is drawn for every code, so any three
key holders from three accounts could confirm anyone: give the first player keys only to people
you trust that far, or wait until the pool is large. `drawLimit` in `link-core.mjs` sets M (the
addon follows the `T` each code carries).

## The guild check

Each confirmation says how the confirmer checked the guild the player claims, and signs it:

- `r`: the claimed guild is the confirmer's own guild, and its roster, read by the confirmer's
  addon, lists the player;
- `w`: the confirmer's game ran a `/who` less than 15 minutes ago that showed the player in
  exactly that guild;
- `c`: claimed only. The confirmer still checked that it is an Olympus guild of its own
  faction, but could not see the player in it.

The player's addon keeps asking other confirmers (within their limits) to get at least one `r`
or `w`, and carries up to four confirmations. `LINK_GUILD_POLICY` says what the Worker needs:

- `"verified"` (the default): at least one confirmation that counts (a councillor's, or a drawn
  player's in mode `a`) checked the guild (`r` or `w`). At launch only councillors confirm, so
  in practice this links the members of the councillors' own guild (Olympus I), found in its
  roster, and anyone a councillor saw in a `/who` in the last 15 minutes. A player of another
  Olympus guild who was not seen is told to type the code again while a councillor is around
  (answer `guild-unverified`: the code stays unused).
- `"claimed"`: any valid confirmation. The character is still proved to be the player's (that
  is what the confirmations sign), but the guild on the role is taken as the player named it.
  More players get through at launch; fewer guarantees about the guild.

Either way, `members.gv` records how the guild was checked (`r`, `w` or `c`), so you can tell
the two apart later or switch the policy without losing track.

## The API

All JSON. The page's call carries the player's Discord sign-in in its body (and your site token,
if any, in `Authorization`); the tools' carry the admin token. The paths are the reference
Worker's: in your own Worker they are wherever your routes put them (the page takes `/proof`'s
whole address in `config.js`).

| Route | Who | Body | Answer |
|---|---|---|---|
| `POST /proof` (`handleProof`; the reference Worker's `/api/link/proof`) | the page, from `LINK_ORIGIN` | `{"text": "OLB5~... or its address", "discordToken": "<access token>"}` | `200 {"status", "reason", "message", "R", "username", "character", "guild", "faction", "guildCheck", "guildKnown", "characters"}`; `401 {"reason": "login" \| "site"}`, `403 {"reason": "origin"}`, `400 {"reason": "format"}` (no text or token), `429 {"reason": "limit"}` after 10 an hour; `OPTIONS`: `204` with the CORS headers for `LINK_ORIGIN` only |
| `POST /api/link/inbox` (`handleInbox`) | watcher tool | `{"bundles": [{"R", "bundle", "from", "t"}]}` (500 at most) | `200 {"results": [{"R", "status", "reason", "message"}]}` |
| `POST /api/link/keys` (`handleKeys`) | you | `{"key_id", "public_key", "owner_discord_id", "owner_username", "character", "kind", "bootstrap", "days", "replace"}`, or `{"key_id", "renew": true, "days"}`, or `{"key_id", "revoke": true}`, or `{"character", "revoke": true}` | `200 {"status": "ok", "key_id", "kind", "character", "public_key", "cert", "cert_exp", "cert_from", "command", "replaced"}`: a new player key's `cert`, `cert_exp` and `command` are `null` (with a `message`) until `cert_from`, when `renew` gives them (`{"status": "ok", "revoked": true}` for a revoke, with `"council": true` and the councillor's `character`, once seen, for a key of the council authority's; `{"status": "ok", "character", "revoked": true, "keys", "council_keys"}` for a character: the registered keys it revoked, the authority's keys seen for it); `409 {"reason": "key-id-used" \| "public-key-used" \| "owner-has-key" \| "character-not-linked" \| "revoked" \| "replaced" \| "too-early"}` (`too-early` with `cert_from`), `404 {"reason": "unknown-key"}`, `400 {"reason": "format"}` |
| `POST /api/link/bot-code` | gateway bot | `{"id", "username"}` | `200 {"token", "command", "exp", "mode", "reply"}` |
| `POST /api/discord/interactions` | Discord | an interaction | `PING`, or `/verify` answered ephemerally |
| `GET /api/link/me`, `POST /api/link/code`, `POST /api/link/submit` | a same-site page only (step 4) | as `/proof`, with your login's cookie and `{"bundle"}` | the same answers |

`status` is `linked` (reason `linked`, or `already` when that link had already counted),
`rejected` (reason `format`, `unknown-code`, `other-user`, `tag`, `code-used`, `expired`,
`not-enough`, `guild-unverified`, `not-in-server`: the code stays unused) or `error` (`login`,
`origin`, `site`, `limit`, `discord`, `server`: nothing was used, try again). `PROOF_REASONS` in
`link-core.mjs` lists them, and the page shows each one in English or Portuguese with what to do
next.

The page's request lives in `web/public/backend.js` (`proofRequest`), its settings in
`web/public/config.js`.

## The formats

- **Code token** (the backend signs it, the player pastes it):
  `OLC2.<R>.<username>.<exp>.<mode>.<T>.<sig>`. `R`: 10 characters of Crockford base32
  (`0123456789ABCDEFGHJKMNPQRSTVWXYZ`) from `crypto.getRandomValues`, single use. `username`:
  the Discord username, `[a-z0-9_.]{2,32}` (it may hold dots: read the token from both ends).
  `exp`: unix time, 24 hours after issue. `mode`: `c` or `a`. `T`: the draw's threshold, 8
  lowercase hex (below), `00000000` in mode `c`. `sig`: base64url without padding (86
  characters) of the backend's Ed25519 signature over the ASCII bytes
  `OLC2.<R>.<username>.<exp>.<mode>.<T>`. `/oly discord <token>` is 172 bytes at most, within
  the game's 255. The addon also takes it after `/oly discord` or `/olympus discord` pasted
  into its code box.
- **The draw**: a player key's prefix for code `R` is the first 8 hex of
  `SHA-256(R + "~" + keyId)`. When it issues a code in mode `a`, the Worker sorts the prefixes of
  the active player keys (not revoked or replaced, a certificate that has not ended, 7 days old,
  and a Discord account 30 days old) and signs `T`: the prefix at index M, counting from 0, with
  M = max(20, ceil(3% of those keys)), or `ffffffff` when there are M keys or fewer. A key is
  drawn for `R` when its prefix is below `T` (compared as text): the M lowest. The addon asks
  only drawn, online, certified player keys, lowest first, five at once; the Worker certifies a
  player key only once it counts for every open code (step 8).
- **Key certificate**: `OLK2.<keyId>.<public key>.<tier>.<exp>.<Name-Realm>.<sig>`. The public
  key in base64url (43 characters), `tier` `c` or `p`, `exp` unix time, `Name-Realm` the one
  character that confirms with the key (it may hold dots: read the certificate from both ends),
  `sig` an Ed25519 signature over the UTF-8 bytes of everything before the last dot: the
  backend's (a key you registered: the confirmer types it), or, for a High Councillor's key
  (tier `c`) whose id is the first 12 hex of SHA-256 of its 32 bytes, the council authority's
  (the author's addon whispers it to the councillor's; only with that path on, off as the addon
  ships: step 1b). At most 240 bytes: the confirmer's addon announces it as
  `DV~1~<certificate>`, and only from that character.
- **Tag**: the first 16 lowercase hex of `SHA-256(<the code token's sig> + "~" + <requester>)`,
  the requester as `Name-Realm`. The requester's addon makes it from the command it was given
  and sends it with its request; the Worker makes it again from the token it stored.
- **Confirmation** (a confirmer's addon signs it, UTF-8):
  `OLY4~<requester>~<guild>~<gv>~<faction>~<nonce>~<R>~<tag>~<issued>~<keyId>~<confirmer>`.
  Names are `Name-Realm` as the game writes them (the requester as the game server stamped its
  whisper, the confirmer itself); guild at most 40 bytes, an Olympus guild; `gv` `r`, `w` or
  `c` ("The guild check"); faction `Alliance` or `Horde`, the confirmer's own; nonce 16
  lowercase hex digits; issued the confirmer's server time.
- **Bundle**: `OLB5~<requester>~<guild>~<faction>~<nonce>~<R>~<tag>~<p1>;<p2>;...`, each proof
  `<issued>,<keyId>,<confirmer>,<gv>,<sig>,<public key>,<tier>,<cert exp>,<cert sig>`: the last
  four are its key's certificate, `OLK2.<keyId>.<public key>.<tier>.<cert exp>.<confirmer>.<cert
  sig>`, so a watcher and this Worker check it without having heard it. 1 to 4 proofs, 2400 bytes
  at most. A field holds no `~`, `;`, `,`, `|` or control character; a name is at most 64 bytes
  and its realm (after the last dash) has no dash or space.
- **Link** (the QR code and the game's copy box): `<the page's address>#b=<bundle,
  percent-encoded>`. It never holds the token.

## What the Worker checks

For every bundle, from the page or the inbox (`checkProof` reads, `acceptProof` then links):

1. It is well formed (the rules above; the page and the addon read exactly the same).
2. The code `R` exists. From the page, it belongs to the account the player's Discord sign-in
   names (checked with Discord, step 4; else `other-user`); from the inbox, the
   account is the code's owner. The tag is the one made from that code's own token and the
   bundle's requester (else `tag`: whoever saw `R` in a QR code cannot use it for another
   character). The code is unused (a link that already counted answers `already`).
3. Its confirmations were signed within the code's life (from issue, less 5 minutes of clock
   difference, to `exp`), none more than 5 minutes ahead of the Worker's clock (the requester's
   addon refuses the same). The bundle may arrive up to 7 days after `exp`: the addon hands it to
   a watcher until 5 days after `exp`, which leaves the watcher's keeper 2 days to upload it;
   after that it is `expired`.
4. For each proof, its key: a key registered here, not revoked, whose certificate (the one the
   proof carries) names its public key, its tier and the confirming character as registered; or
   (only with `LINK_CA_PUBLIC` set, step 1b) a High Councillor's key the council authority
   certified (the certificate checks with `LINK_CA_PUBLIC`, tier `c`, the id the key's hash, valid
   when the proof was signed), for a character on `LINK_COUNCIL_CHARACTERS` when you set that
   list, not on the revocation list, not
   signed (its end less a year) at or before a revocation of its character, and not recorded for
   another character. Then: its owner is not the code's account;
   the Worker rebuilds the exact `OLY4` text and verifies the Ed25519 signature with the key
   (WebCrypto: a non-canonical signature fails); the confirmer is one of the key owner's linked
   characters (except bootstrap and council authority keys: their certificate names the
   character); the requester is neither the confirmer nor one of the key owner's characters; and
   (R, keyId) never counted before.
5. It accepts with **one valid councillor proof**. In mode `a` it also accepts **three valid
   player proofs** from three different owners, none the requester, signed within 5 minutes of
   each other, each key drawn for this code (its prefix below the `T` stored with the code),
   and, when the code was issued, each key at least 7 days old, not yet replaced, and each
   owner's Discord account at least 30 days old (read from the Discord id).
6. With `LINK_GUILD_POLICY = "verified"`, one of the proofs that count (a councillor's, or a
   drawn player's in mode `a`) checked the guild (`r` or `w`), else `guild-unverified`.
7. Then it claims the code (so two deliveries cannot both count), calls your `promote()` to give
   the role, and records the character in `members`, moving it if it was linked to another
   account (your `demote()` takes the role from that account when it has no character left),
   with the proofs that counted (`used`) and the council authority's keys whose proofs checked
   (`council_keys`): nothing is written for a proof before the whole link is accepted. If
   `promote()` fails (the player is not in the server, Discord is down, the network fails), or
   D1 cannot record the link, the code is released and nothing is recorded, so the same link
   works on the next try.

Why the draw and these limits stop anyone packing the random pool: R comes from the backend's
random generator and only the M lowest prefixes of `SHA-256(R~keyId)` over the whole pool can
count, so an attacker cannot pick the keys that confirm a code and needs a large share of the
pool to hold three of those places, with only 3 codes a day per Discord account to try. `T` is
fixed and signed when the code is issued, and a key counts only if it was 7 days old by then,
so keys registered after seeing `R` cannot join the draw. One key per Discord account, keys at
least 7 days old, accounts at least 30 days old and signatures within 5 minutes make that
share slow and costly to build and stop a few friends from signing for each other at leisure,
while councillors-only mode keeps the pool out of play until it is large.

Limits and logs: 3 codes per Discord account a day (`/verify` again gets the same unused code
back); the page may submit 10 times an hour per account; every bundle received is logged in
`inbox_uploads` (never the Discord token); the admin and site tokens are compared in constant
time; a Worker whose
`LINK_BACKEND_SEED` and `LINK_BACKEND_PUBLIC` do not match refuses to issue codes and
certificates.

## Test vectors

These come from `web/test/fixtures/vectors.json`, made by `web/test/fixtures/make-vectors.py`
with Python's `cryptography`. They are throwaway keys whose seeds are the SHA-256 of public
labels (`"olympus-link-test:" + label`, the label being the key id, `backend`, `ca` or
`council03`, the same rule as the addon's `tests/fixtures/make-link-vectors.py`, so both sides
hold the same keys): never register one, nor put one in `LINK_CA_PUBLIC`. The same vectors check the addon (`Olympus/Ed25519.lua` signs the `ed25519` ones
byte for byte: `web/test/fixtures/lua-signatures.json`), the page and this Worker, whose tests
(`web/test/worker.test.mjs`) load the schema into SQLite, insert these codes and keys, and send
these bundles; `web/test/addon-fixtures.test.mjs` checks the addon's own sample codes,
certificates and links the same way. Ed25519 is deterministic: any correct implementation
gives these exact signatures from these seeds. `must_fail` has a non-canonical S (S + L) that
every check must refuse.

To check your Worker by hand: insert the `codes` (with their `draw_t` and `token`) and `keys`
below (for the players' bundle, also each confirmer character in `members` under its key's
owner), set `LINK_CA_PUBLIC` to `council_authority.public_hex` (its key is never inserted), set
the Worker's clock between the proofs' `issued` and `exp`, and `checkProof` answers `ok` for
each bundle (`acceptProof` then links it; `web/test/link-core.test.mjs` does exactly this). `tag_of` is the text whose SHA-256 starts with the tag;
`draw.thresholds` gives `T` for pools of keys `pool0000`, `pool0001`... of several sizes.

<!-- block: vectors -->
```json
{
  "backend": {
    "public_hex": "070a599da007dbca7a54999daeab8eec7bd9e1cd4dd53659322552bc33f2225b",
    "token": "OLC2.7K3M9QX2TB.some.player.1800000000.c.00000000.TmJVCJJtjs5W_sOXnQm3G10J3y5xwVQkii6zRhi0EO-5AmL__PtEg1Ao7VaiUivi1Jslf4i1OJUxMDDNXtG4Ag",
    "signed": "OLC2.7K3M9QX2TB.some.player.1800000000.c.00000000"
  },
  "codes": [
    {
      "R": "7K3M9QX2TB",
      "discord_id": "200000000000000001",
      "username": "some.player",
      "mode": "c",
      "draw_t": "00000000",
      "created": 1799913600,
      "exp": 1800000000,
      "token": "OLC2.7K3M9QX2TB.some.player.1800000000.c.00000000.TmJVCJJtjs5W_sOXnQm3G10J3y5xwVQkii6zRhi0EO-5AmL__PtEg1Ao7VaiUivi1Jslf4i1OJUxMDDNXtG4Ag"
    },
    {
      "R": "H4N8PZ6R1B",
      "discord_id": "200000000000000002",
      "username": "tester.two",
      "mode": "a",
      "draw_t": "ffffffff",
      "created": 1799913600,
      "exp": 1800000000,
      "token": "OLC2.H4N8PZ6R1B.tester.two.1800000000.a.ffffffff.j00E_PzaPZ9AqZY3Dwq1RX_D-q5Geaq5E67Rsm-j_5XMJxkoepPoSoqi4GCQiEv9j-EkMYDFnzACydM3bATvAQ"
    }
  ],
  "keys": [
    {
      "key_id": "council01",
      "kind": "c",
      "bootstrap": 1,
      "owner_discord_id": "100000000000000001",
      "character": "Test Councillor-ClassicBetaPvP",
      "created": 1780000000,
      "public_hex": "ec8625fa537ee50453146f50c298eb2922590c60ded7b54ade9e85702a70219b",
      "cert_exp": 1830000000,
      "cert": "OLK2.council01.7IYl-lN-5QRTFG9QwpjrKSJZDGDe17VK3p6FcCpwIZs.c.1830000000.Test Councillor-ClassicBetaPvP.kuaVPJGR4ZwtCf2mtveDYem8nJmMfU-R4I-FndUaJCswUEoqDNECnB_oFNIj3DPMA18UgHkSK7L7X1oWZSMDCQ"
    },
    {
      "key_id": "player01",
      "kind": "p",
      "bootstrap": 0,
      "owner_discord_id": "100000000000000011",
      "character": "Other Player-ClassicBetaPvP",
      "created": 1780000000,
      "public_hex": "6237dcc3647b0995f0815a34a06541548363f74da2a4f7541415d582245d421a",
      "cert_exp": 1830000000,
      "cert": "OLK2.player01.Yjfcw2R7CZXwgVo0oGVBVINj902ipPdUFBXVgiRdQho.p.1830000000.Other Player-ClassicBetaPvP.VVCteYcVvEC94tf4AYXgFoqVIMF3lwmT0Oa_wHjjDReZqnCqwc3dBRyRa2_lsdC82VETV6yC1ynAfYkO0218Aw"
    },
    {
      "key_id": "player02",
      "kind": "p",
      "bootstrap": 0,
      "owner_discord_id": "100000000000000012",
      "character": "Third Player-ClassicBetaPvP2",
      "created": 1780000000,
      "public_hex": "86dcd40827cbcb608b4419cc4afb1a68eb36b8002b208f05998a0dba2b4f4cba",
      "cert_exp": 1830000000,
      "cert": "OLK2.player02.htzUCCfLy2CLRBnMSvsaaOs2uAArII8FmYoNuitPTLo.p.1830000000.Third Player-ClassicBetaPvP2.AhXwg-IeO7pvCaCiMB99vAmq4z4LEIC2jOfExrd_baQIEOcGeh9O_oyPxJKQqioKuXc3Am3z_o4BsMtEa-EnAg"
    },
    {
      "key_id": "player03",
      "kind": "p",
      "bootstrap": 0,
      "owner_discord_id": "100000000000000013",
      "character": "Fourth Player-ClassicBetaPvP",
      "created": 1780000000,
      "public_hex": "24b7aace15afb8c48409285ea8e2baac0884b6e8e6aa644189259ac57c607c7d",
      "cert_exp": 1830000000,
      "cert": "OLK2.player03.JLeqzhWvuMSECSheqOK6rAiEtujmqmRBiSWaxXxgfH0.p.1830000000.Fourth Player-ClassicBetaPvP.C-wMIwi74DAQG3gPlNQTdiJZctpBv1fZWJs8XEPKWtOn6YjuNoZAOgYpIaGdnfUtQhdltBlfutRcejytbpdmAQ"
    }
  ],
  "council_authority": {
    "public_hex": "482fa6ee7b8220b00c1b0df468065f66cd5d1b87e46d66c00eafa63a0ba91740",
    "keys": [
      {
        "key_id": "60d7d2f2c939",
        "character": "Third Councillor-ClassicBetaPvP",
        "public_hex": "4d6120fca76fdb3bf6fe180e215b1b0a316c3a2c47f929fe8197837a3f17d1e2",
        "cert_exp": 1830000000,
        "cert": "OLK2.60d7d2f2c939.TWEg_Kdv2zv2_hgOIVsbCjFsOixH-Sn-gZeDej8X0eI.c.1830000000.Third Councillor-ClassicBetaPvP.5wTsFv1jb3Q7WjgtwG1pX3dzfgOiD3KqB7o_TBeENqexSXDTGC1HMjdBi-1Eiyng12a8oSnurl0RnkcqfxEICg"
      }
    ]
  },
  "bundles": [
    {
      "name": "one councillor",
      "tag": "5f2f66f046a1db8a",
      "tag_of": "TmJVCJJtjs5W_sOXnQm3G10J3y5xwVQkii6zRhi0EO-5AmL__PtEg1Ao7VaiUivi1Jslf4i1OJUxMDDNXtG4Ag~Some Player-ClassicBetaPvP",
      "bundle": "OLB5~Some Player-ClassicBetaPvP~Olympus II~Alliance~0123456789abcdef~7K3M9QX2TB~5f2f66f046a1db8a~1799990100,council01,Test Councillor-ClassicBetaPvP,w,wYG_TW3fCOBxV9hteWMsnq2R8sBus8YaG-Dyb4SePjkl9a9Ub27i1okdpFxUh5aQASIZKKcXQbv0ocuXxvObBA,7IYl-lN-5QRTFG9QwpjrKSJZDGDe17VK3p6FcCpwIZs,c,1830000000,kuaVPJGR4ZwtCf2mtveDYem8nJmMfU-R4I-FndUaJCswUEoqDNECnB_oFNIj3DPMA18UgHkSK7L7X1oWZSMDCQ",
      "signed": [
        "OLY4~Some Player-ClassicBetaPvP~Olympus II~w~Alliance~0123456789abcdef~7K3M9QX2TB~5f2f66f046a1db8a~1799990100~council01~Test Councillor-ClassicBetaPvP"
      ]
    },
    {
      "name": "three drawn players, non-ASCII requester",
      "tag": "9c5ac51afcd0bbee",
      "tag_of": "j00E_PzaPZ9AqZY3Dwq1RX_D-q5Geaq5E67Rsm-j_5XMJxkoepPoSoqi4GCQiEv9j-EkMYDFnzACydM3bATvAQ~Tëst Plâyer-ClassicBetaPvP",
      "bundle": "OLB5~Tëst Plâyer-ClassicBetaPvP~Olympus Vanguard~Horde~a1b2c3d4e5f60718~H4N8PZ6R1B~9c5ac51afcd0bbee~1799990200,player01,Other Player-ClassicBetaPvP,r,jRr01ESNDrVEohLRRZYhLAVPD9ue32uDrRA2GQByQq2dsCQ-6o79nFWcL__shopaQ2Umy1aV9f8sDIaMQLzyBw,Yjfcw2R7CZXwgVo0oGVBVINj902ipPdUFBXVgiRdQho,p,1830000000,VVCteYcVvEC94tf4AYXgFoqVIMF3lwmT0Oa_wHjjDReZqnCqwc3dBRyRa2_lsdC82VETV6yC1ynAfYkO0218Aw;1799990245,player02,Third Player-ClassicBetaPvP2,c,K7sW12b4A_uTxycWnR8rRE1Ip3wzAxA2GYOgNMitKtbx1KfI6IxWMJLEu2oEoJ042TuWxlbk_RU6k81b4kuEAA,htzUCCfLy2CLRBnMSvsaaOs2uAArII8FmYoNuitPTLo,p,1830000000,AhXwg-IeO7pvCaCiMB99vAmq4z4LEIC2jOfExrd_baQIEOcGeh9O_oyPxJKQqioKuXc3Am3z_o4BsMtEa-EnAg;1799990301,player03,Fourth Player-ClassicBetaPvP,c,7sEYRUmeAZOZyqJUGu8_hZ_O2Mn8mFuWIKdWMTJ_0Zs4KYzelPEDfnjfq3bcU-uYal7tiPtuBY6zijo0mJCqDQ,JLeqzhWvuMSECSheqOK6rAiEtujmqmRBiSWaxXxgfH0,p,1830000000,C-wMIwi74DAQG3gPlNQTdiJZctpBv1fZWJs8XEPKWtOn6YjuNoZAOgYpIaGdnfUtQhdltBlfutRcejytbpdmAQ",
      "signed": [
        "OLY4~Tëst Plâyer-ClassicBetaPvP~Olympus Vanguard~r~Horde~a1b2c3d4e5f60718~H4N8PZ6R1B~9c5ac51afcd0bbee~1799990200~player01~Other Player-ClassicBetaPvP",
        "OLY4~Tëst Plâyer-ClassicBetaPvP~Olympus Vanguard~c~Horde~a1b2c3d4e5f60718~H4N8PZ6R1B~9c5ac51afcd0bbee~1799990245~player02~Third Player-ClassicBetaPvP2",
        "OLY4~Tëst Plâyer-ClassicBetaPvP~Olympus Vanguard~c~Horde~a1b2c3d4e5f60718~H4N8PZ6R1B~9c5ac51afcd0bbee~1799990301~player03~Fourth Player-ClassicBetaPvP"
      ]
    },
    {
      "name": "a councillor certified by the council authority",
      "tag": "5f2f66f046a1db8a",
      "tag_of": "TmJVCJJtjs5W_sOXnQm3G10J3y5xwVQkii6zRhi0EO-5AmL__PtEg1Ao7VaiUivi1Jslf4i1OJUxMDDNXtG4Ag~Some Player-ClassicBetaPvP",
      "bundle": "OLB5~Some Player-ClassicBetaPvP~Olympus II~Alliance~0123456789abcdef~7K3M9QX2TB~5f2f66f046a1db8a~1799990120,60d7d2f2c939,Third Councillor-ClassicBetaPvP,w,sXCNKxKUl-QJK2jYzERR7iX3bmGOqCUrMkbN4fuAj3QASQYP_YMMhvlLylLsNuVKGFMhO8DaH17AxRF1g0AxCw,TWEg_Kdv2zv2_hgOIVsbCjFsOixH-Sn-gZeDej8X0eI,c,1830000000,5wTsFv1jb3Q7WjgtwG1pX3dzfgOiD3KqB7o_TBeENqexSXDTGC1HMjdBi-1Eiyng12a8oSnurl0RnkcqfxEICg",
      "signed": [
        "OLY4~Some Player-ClassicBetaPvP~Olympus II~w~Alliance~0123456789abcdef~7K3M9QX2TB~5f2f66f046a1db8a~1799990120~60d7d2f2c939~Third Councillor-ClassicBetaPvP"
      ]
    }
  ],
  "draw": {
    "R": "H4N8PZ6R1B",
    "prefix": {
      "player01": "feffce2f",
      "player02": "86382936",
      "player03": "99930512",
      "player04": "758d883f",
      "player05": "abd28f09",
      "abcdef": "ce741b41",
      "zz9999zz": "0b540f3c",
      "player000042": "3034d2c2"
    },
    "pool": "pool%04d",
    "thresholds": [
      {
        "n": 5,
        "M": 20,
        "T": "ffffffff",
        "drawn": 5
      },
      {
        "n": 20,
        "M": 20,
        "T": "ffffffff",
        "drawn": 20
      },
      {
        "n": 21,
        "M": 20,
        "T": "f569a39a",
        "drawn": 20
      },
      {
        "n": 400,
        "M": 20,
        "T": "0c109a37",
        "drawn": 20
      },
      {
        "n": 700,
        "M": 21,
        "T": "08e4d52a",
        "drawn": 21
      },
      {
        "n": 1000,
        "M": 30,
        "T": "069cb5ea",
        "drawn": 30
      }
    ]
  },
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
      "seed_hex": "f8b562176148cbec194b0b09e63cf8f6bb0e156e6ea8620e8d2a7b53c4e5e77e",
      "public_hex": "070a599da007dbca7a54999daeab8eec7bd9e1cd4dd53659322552bc33f2225b",
      "message": "OLC2.7K3M9QX2TB.some.player.1800000000.c.00000000",
      "signature_b64url": "TmJVCJJtjs5W_sOXnQm3G10J3y5xwVQkii6zRhi0EO-5AmL__PtEg1Ao7VaiUivi1Jslf4i1OJUxMDDNXtG4Ag"
    },
    {
      "name": "councillor key, OLY4 confirmation",
      "seed_hex": "a8d5c4d53573bdff5005fdfa934dc9b8b322fcc91ec40e299e9e4ccb3e7b5497",
      "public_hex": "ec8625fa537ee50453146f50c298eb2922590c60ded7b54ade9e85702a70219b",
      "message": "OLY4~Some Player-ClassicBetaPvP~Olympus II~w~Alliance~0123456789abcdef~7K3M9QX2TB~5f2f66f046a1db8a~1799990100~council01~Test Councillor-ClassicBetaPvP",
      "signature_b64url": "wYG_TW3fCOBxV9hteWMsnq2R8sBus8YaG-Dyb4SePjkl9a9Ub27i1okdpFxUh5aQASIZKKcXQbv0ocuXxvObBA"
    },
    {
      "name": "player key, OLY4 with non-ASCII requester",
      "seed_hex": "88a9e14163bcd02a9c2f77cdaacdfdb9a417591fbe216fbbdeeba29cc2806574",
      "public_hex": "6237dcc3647b0995f0815a34a06541548363f74da2a4f7541415d582245d421a",
      "message": "OLY4~Tëst Plâyer-ClassicBetaPvP~Olympus Vanguard~r~Horde~a1b2c3d4e5f60718~H4N8PZ6R1B~9c5ac51afcd0bbee~1799990200~player01~Other Player-ClassicBetaPvP",
      "signature_b64url": "jRr01ESNDrVEohLRRZYhLAVPD9ue32uDrRA2GQByQq2dsCQ-6o79nFWcL__shopaQ2Umy1aV9f8sDIaMQLzyBw"
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
  draw_t     TEXT NOT NULL                         -- T, signed in the token: a player key is drawn when its prefix < T
             CHECK (length(draw_t) = 8 AND draw_t NOT GLOB '*[^0-9a-f]*'),
  created    INTEGER NOT NULL,
  exp        INTEGER NOT NULL,
  token      TEXT NOT NULL,                        -- the signed token: its signature makes each link's tag, keep it private
  source     TEXT NOT NULL,                        -- 'site' or 'discord'
  used       INTEGER                               -- when it linked a character; NULL until then
);
CREATE INDEX IF NOT EXISTS codes_by_user ON codes (discord_id, created);

-- Confirmer public keys registered here. Confirm-only: they sign OLY4 confirmations and nothing
-- else, each from the one character its certificate names.
CREATE TABLE IF NOT EXISTS keys (
  key_id           TEXT PRIMARY KEY                -- [a-z0-9]{6,16}, never reused
                   CHECK (length(key_id) BETWEEN 6 AND 16 AND key_id NOT GLOB '*[^a-z0-9]*'),
  public_key       TEXT NOT NULL                   -- 64 lowercase hex (Ed25519)
                   CHECK (length(public_key) = 64 AND public_key NOT GLOB '*[^0-9a-f]*'),
  owner_discord_id TEXT NOT NULL                   -- a Discord id: digits only
                   CHECK (length(owner_discord_id) BETWEEN 5 AND 25 AND owner_discord_id NOT GLOB '*[^0-9]*'),
  owner_username   TEXT,
  character        TEXT NOT NULL                   -- the one character that confirms with it ("Name-Realm"), named in its certificate
                   CHECK (length(character) BETWEEN 3 AND 64),
  kind             TEXT NOT NULL CHECK (kind IN ('c', 'p')), -- councillor or drawn player (the certificate's tier)
  bootstrap        INTEGER NOT NULL DEFAULT 0,     -- 1: a councillor key trusted before its owner linked a character
  created          INTEGER NOT NULL,
  cert_exp         INTEGER,                        -- when its latest certificate expires; NULL: none issued yet (a player key waits until it counts)
  replaced_at      INTEGER,                        -- the owner's newer key got its certificate: out of the draw, still checks until revoked
  revoked          INTEGER NOT NULL DEFAULT 0,
  revoked_at       INTEGER
);
-- One certified key per Discord account. A new key may wait for its certificate next to it (a
-- player key until it counts); its first certificate replaces the older one, and revoking ends a key.
CREATE UNIQUE INDEX IF NOT EXISTS keys_one_per_owner ON keys (owner_discord_id) WHERE revoked = 0 AND replaced_at IS NULL AND cert_exp IS NOT NULL;

-- High Councillors' keys made in game and certified by the council authority (the author's
-- client; LINK_CA_PUBLIC), never registered: each recorded, by the key itself, for the character
-- its certificate names, in the same write as the first link it confirmed (so only once a
-- signature of that key has checked). Their id is the first 12 hex of SHA-256 of the key.
CREATE TABLE IF NOT EXISTS council_keys (
  public_key TEXT PRIMARY KEY                      -- 64 lowercase hex (Ed25519): the key itself
             CHECK (length(public_key) = 64 AND public_key NOT GLOB '*[^0-9a-f]*'),
  key_id     TEXT NOT NULL                         -- its id: the first 12 hex of SHA-256 of it
             CHECK (length(key_id) = 12 AND key_id NOT GLOB '*[^0-9a-f]*'),
  character  TEXT NOT NULL,                        -- the councillor ("Name-Realm")
  cert_exp   INTEGER NOT NULL,                     -- the latest end of its certificate seen
  first_seen INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS council_keys_by_id ON council_keys (key_id);
CREATE INDEX IF NOT EXISTS council_keys_by_character ON council_keys (character);

-- The revocation list of the council authority's keys: a key id here counts no more, whether a
-- link carried it before or not (POST /api/link/keys {"key_id", "revoke": true}).
CREATE TABLE IF NOT EXISTS revoked_keys (
  key_id     TEXT PRIMARY KEY,
  revoked_at INTEGER NOT NULL
);

-- Characters whose keys were all revoked at once (POST /api/link/keys {"character", "revoke":
-- true}): a council authority certificate for one of them signed at or before revoked_at (its end
-- less CA_DAYS) counts no more, whatever key it names; the keys registered for it were revoked too.
CREATE TABLE IF NOT EXISTS revoked_characters (
  character  TEXT PRIMARY KEY,                     -- "Name-Realm"
  revoked_at INTEGER NOT NULL
);

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
  gv         TEXT NOT NULL DEFAULT 'c'             -- how the guild was checked in game: 'r' roster, 'w' /who, 'c' claimed
             CHECK (gv IN ('r', 'w', 'c')),
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

## The core

`web/worker/link-core.mjs`, the whole module: every check, and the functions your routes call
(step 3).

<!-- block: web/worker/link-core.mjs -->
```js
// Olympus Link: the core, for the Olympus bot's Worker. Everything the bot needs to issue codes,
// check the proofs the game makes, give the role through your own promote(), and keep the
// confirmers' keys, as plain functions over a D1 database. No framework, no npm package: WebCrypto
// (Ed25519, SHA-256) and fetch only, so it runs on Cloudflare Workers and on Node 20 or newer.
// web/FERN.md says how to wire it in, web/WORKER.md explains every check, web/worker/link-worker.js
// is a complete Worker built on it, and web/test runs all of it against the shared vectors.
//
// What it reads from `env` (your Worker's bindings):
//   LINK_DB              the D1 database with web/worker/schema.sql (DB when there is no LINK_DB)
//   LINK_BACKEND_SEED    secret: your bot's Ed25519 seed, base64url (scripts/link-keys.py backend)
//   LINK_BACKEND_PUBLIC  its public key, 64 hex: the addon holds the same one (ns.LINK_BACKEND_KEYS)
//   LINK_CA_PUBLIC       the council authority's public key, 64 hex (two, comma-separated, while it
//                        changes): the addon author's client certifies High Councillors' keys with it
//   LINK_COUNCIL_CHARACTERS  optional: the High Councillors' characters you accept ("Name-Realm",
//                        comma-separated). Set, a council authority certificate for any other
//                        character counts for nothing (set but empty: none counts); unset, every
//                        character the authority certifies is a councillor here
//   LINK_MODE            "c" councillors only (launch), "a" one councillor or three drawn players
//   LINK_GUILD_POLICY    "verified" (the default) or "claimed" (web/WORKER.md, "The guild check")
//   LINK_ORIGIN          the page's origin, "https://dnl-gentile.github.io" (CORS of POST /proof)
//   DISCORD_CLIENT_ID    your Discord application's id: a sign-in the page sends must be for it
//   LINK_SITE_TOKEN      optional: the token the page sends with POST /proof (a switch, not a secret)
//   LINK_ADMIN_TOKEN     secret, 32 characters or more: your own tools' (watcher inbox, keys)
//
// The functions, by what they are for:
//   codes      issueCode(env, user) -> { ok, token, command, reply }        (your /verify)
//   proofs     checkProof(env, text, { discordId })   reads only: the verdict
//              acceptProof(env, text, { discordId, promote, demote })   checks, claims the code,
//              calls your promote(discordId), records the link (and frees the code if promote fails)
//              handleProof(request, env, { promote, demote })   the whole POST /proof, CORS included
//   watcher    acceptInbox(env, body, { promote }) / handleInbox(request, env, { promote })
//   keys       manageKeys(env, body) / handleKeys(request, env), registerKey, renewKey, revokeKey,
//              revokeCharacter, councilCharacters(env)
//   people     discordUser(accessToken, { clientId }), forgetUser(env, discordId)
//   answers    httpStatus(answer), respond(answer, headers), corsHeaders(request, env)

export const LINK = {
	TOKEN_LIFE: 24 * 3600, // a code works for a day...
	REUSE_LEFT: 12 * 3600, // ...and is handed out again while it has this long left
	CODES_PER_DAY: 3,
	DELIVERY_GRACE: 7 * 24 * 3600, // a link is taken until its code's expiry + this: the addon hands it to a
	// watcher until 5 days after the expiry, so the watcher's keeper has 2 days to upload it
	CLOCK_SKEW: 300, // game server clock vs ours
	WINDOW: 300, // three player proofs within 5 minutes of each other
	PLAYERS_NEEDED: 3,
	KEY_MIN_AGE: 7 * 24 * 3600, // a player key counts for codes issued 7 days after it...
	ACCOUNT_MIN_AGE: 30 * 24 * 3600, // ...and its owner's Discord account is 30 days older than the code
	SUBMITS_PER_HOUR: 10,
	MAX_BUNDLES: 500,
	CERT_DAYS: 365, // a councillor key's certificate life, unless the request says otherwise...
	CERT_DAYS_PLAYER: 90, // ...a player key's: a revoked or replaced one stays in the addons' draw until it ends...
	CERT_DAYS_MAX: 3650, // ...up to this
	CA_DAYS: 365, // the life of a council authority's certificate (the addon's Link.CA_DAYS): one
	// ending at exp was signed at exp - this, which is how a character's revocation finds the older ones
};

// Every reason POST /proof can answer (web/public/i18n.js has words for each, in both languages).
export const PROOF_REASONS = [
	'linked', // status "linked": done
	'already', // status "linked": that link had counted before, nothing new
	'format', // "rejected" from here on: the code stays unused
	'unknown-code',
	'other-user',
	'tag',
	'code-used',
	'expired',
	'not-enough',
	'guild-unverified',
	'not-in-server',
	'login', // "error" from here on: nothing was used, the same link works again
	'origin',
	'site',
	'limit',
	'discord',
	'server',
];

const R_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const R_RE = /^[0-9A-HJKMNP-TV-Z]{10}$/;
const USERNAME_RE = /^[a-z0-9_.]{2,32}$/;
const DISCORD_ID_RE = /^[0-9]{5,25}$/;
const KEYID_RE = /^[a-z0-9]{6,16}$/;
const NONCE_RE = /^[0-9a-f]{16}$/;
const TAG_RE = /^[0-9a-f]{16}$/;
const ISSUED_RE = /^[1-9][0-9]{0,11}$/;
const SIG_RE = /^[A-Za-z0-9_-]{86}$/;
const PUBLIC_HEX_RE = /^[0-9a-f]{64}$/;
const PUBLIC_B64_RE = /^[A-Za-z0-9_-]{43}$/;
const ACCESS_TOKEN_RE = /^[A-Za-z0-9._~+/-]{10,256}={0,2}$/;
const FORBIDDEN = /[|~;,\u0000-\u001f\u007f]/;
const GV_RE = /^[rwc]$/; // how a confirmer checked the guild: r its own roster, w a recent /who, c claimed only
const CHECKED = (gv) => gv === 'r' || gv === 'w';
const GUILD_KNOWN = { r: 'roster', w: 'who', c: 'claimed' };
const CA_KEYID_RE = /^[0-9a-f]{12}$/; // a council authority's key: the first 12 hex of SHA-256 of the key
const MAX_PROOFS = 4;
const MAX_BUNDLE_BYTES = 2400; // four proofs, each with its certificate (the addon's Link.MAX_BUNDLE)
const MAX_CERT_BYTES = 240; // a certificate fits one chat line: DV~1~<certificate> (the addon's Link.MAX_CERT)
const NO_DRAW = '00000000'; // T of a mode "c" code: no player key is drawn
const ALL_DRAWN = 'ffffffff'; // T when there are M player keys or fewer
const DISCORD_API = 'https://discord.com/api/v10';

const enc = new TextEncoder();
const now = () => Math.floor(Date.now() / 1000);
const database = (env) => env.LINK_DB || env.DB;

// ---------------------------------------------------------------------------
// Answers: { ok, status, reason, message, ... }. status "rejected" (the link is refused, the code
// stays unused) or "error" (nothing happened: try again); a success has ok: true.

export function reject(reason, message, R) {
	return { ok: false, status: 'rejected', reason, message, R: R || null };
}

export function failure(reason, message, extra = {}) {
	return { ok: false, status: 'error', reason, message, ...extra };
}

const HTTP = {
	format: 400,
	username: 400,
	auth: 401,
	login: 401,
	site: 401,
	origin: 403,
	'unknown-key': 404,
	method: 405,
	'key-id-used': 409,
	'public-key-used': 409,
	'owner-has-key': 409,
	'character-not-linked': 409,
	revoked: 409,
	replaced: 409,
	'too-early': 409,
	limit: 429,
	server: 500,
};

// The HTTP status of an answer: 200 for anything but an error of the request itself (a refused or
// failed link is a 200 with its reason, so the page reads it).
export function httpStatus(answer) {
	if (!answer || answer.status !== 'error') return 200;
	return HTTP[answer.reason] || 200;
}

// An answer as a JSON Response, with its HTTP status and extra headers (CORS, for the page).
export function respond(answer, headers = {}, status = httpStatus(answer)) {
	return new Response(JSON.stringify(answer), {
		status,
		headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...headers },
	});
}

// ---------------------------------------------------------------------------
// Codes: your /verify. The player pastes "/oly discord <token>" in the game; the addon checks the
// token with your public key and shows "@username" before the player accepts.
//   const code = await issueCode(env, { id: user.id, username: user.username });
//   reply ephemerally with code.reply (it holds the command, or why there is none)
// { ok: true, token, command, exp, mode, reply } or { ok: false, reason: 'login' | 'username' | 'limit', message, reply }.

export async function issueCode(env, user, source = 'discord') {
	const id = String(user && user.id);
	const username = String(user && user.username);
	if (!DISCORD_ID_RE.test(id)) return codeFailure('login');
	if (!USERNAME_RE.test(username)) return codeFailure('username');
	const DB = database(env);
	const t = now();
	const open = await DB.prepare('SELECT token, exp, mode FROM codes WHERE discord_id = ? AND username = ? AND used IS NULL AND exp > ? ORDER BY created DESC LIMIT 1')
		.bind(id, username, t + LINK.REUSE_LEFT)
		.first();
	if (open) return codeSuccess({ token: open.token, exp: open.exp, mode: open.mode });
	const count = await DB.prepare('SELECT COUNT(*) AS n FROM codes WHERE discord_id = ? AND created > ?').bind(id, t - 86400).first();
	if (count && count.n >= LINK.CODES_PER_DAY) return codeFailure('limit');
	const mode = env.LINK_MODE === 'a' ? 'a' : 'c';
	const exp = t + LINK.TOKEN_LIFE;
	const pool = mode === 'a' ? await drawPool(env, t) : null;
	for (let attempt = 0; attempt < 5; attempt++) {
		const R = randomR();
		const T = pool ? await thresholdOf(R, pool) : NO_DRAW;
		const payload = `OLC2.${R}.${username}.${exp}.${mode}.${T}`;
		const token = `${payload}.${await backendSign(env, payload)}`;
		try {
			await DB.prepare('INSERT INTO codes (r, discord_id, username, mode, draw_t, created, exp, token, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
				.bind(R, id, username, mode, T, t, exp, token, source)
				.run();
			return codeSuccess({ token, exp, mode, R, T });
		} catch (err) {
			if (!/unique|constraint/i.test(String(err && err.message))) throw err; // an R taken: draw again
		}
	}
	throw new Error('could not draw a free code');
}

function codeSuccess(r) {
	const out = { ok: true, status: 'ok', ...r, command: `/oly discord ${r.token}` };
	out.reply = codeReply(out);
	return out;
}

function codeFailure(reason) {
	const message = codeError(reason);
	return { ok: false, status: 'error', reason, message, reply: message };
}

function randomR() {
	const bytes = crypto.getRandomValues(new Uint8Array(10));
	return Array.from(bytes, (b) => R_ALPHABET[b & 31]).join(''); // 256 = 8 * 32: no bias
}

// The reply to /verify, for the player's eyes only (an ephemeral message).
export function codeReply(r) {
	const hours = Math.max(1, Math.round((r.exp - now()) / 3600));
	return [
		'Your Olympus Link code. Paste this line in the WoW chat, press Enter, then click Accept:',
		'```',
		`/oly discord ${r.token}`,
		'```',
		`It works once, for your account only, for the next ${hours} h. Keep it to yourself: not on stream, not in a screenshot, and neither the game's Olympus Link window. The confirmations happen in game; your role arrives when the link reaches the bot.`,
	].join('\n');
}

export function codeError(reason) {
	if (reason === 'limit') return 'You already got 3 codes today: use the last one, or try again tomorrow.';
	if (reason === 'username') return 'Your Discord username cannot be used in a code. Change it to the new style (lowercase, no #1234) and try again.';
	return 'Sign in with Discord first.';
}

// The signature at the end of a code token: what each link's tag is made from.
function tokenSig(token) {
	return String(token).slice(String(token).lastIndexOf('.') + 1);
}

// ---------------------------------------------------------------------------
// The draw: a player key's prefix for code R is the first 8 hex of SHA-256(R~keyId). At issue,
// T is the prefix at index M (0-based) of the active player keys' sorted prefixes, with
// M = max(20, ceil(3% of them)), or "ffffffff" when there are M keys or fewer: the key is drawn
// when its prefix < T. T is signed into the code and stored with it, and the addon asks every
// certified player key T draws, so a player key is certified only once it counts (certFrom).

export async function drawPrefix(R, keyId) {
	return (await sha256Hex(`${R}~${keyId}`)).slice(0, 8);
}

export function drawLimit(activePlayerKeys) {
	return Math.max(20, Math.ceil((activePlayerKeys * 3) / 100));
}

// The active player keys at time t: not revoked or replaced, a certificate valid now, old
// enough and from an old enough Discord account (the ones that could count for a new code).
export async function drawPool(env, t) {
	const rows = (
		await database(env)
			.prepare("SELECT key_id, owner_discord_id, created FROM keys WHERE kind = 'p' AND revoked = 0 AND replaced_at IS NULL AND cert_exp > ?")
			.bind(t)
			.all()
	).results || [];
	return rows.filter((k) => !tooYoung(k, t)).map((k) => k.key_id);
}

export async function thresholdOf(R, keyIds) {
	const prefixes = (await Promise.all(keyIds.map((id) => drawPrefix(R, id)))).sort();
	const m = drawLimit(prefixes.length);
	return prefixes.length > m ? prefixes[m] : ALL_DRAWN;
}

export async function drawThreshold(env, R, t = now()) {
	return thresholdOf(R, await drawPool(env, t));
}

// Why a player key is too young to count at time `at` (a code's issue), or null.
function tooYoung(key, at) {
	if (key.created + LINK.KEY_MIN_AGE > at) return 'key younger than 7 days';
	if (snowflakeTime(key.owner_discord_id) + LINK.ACCOUNT_MIN_AGE * 1000 > at * 1000) return 'Discord account younger than 30 days';
	return null;
}

export function snowflakeTime(id) {
	return Number((BigInt(id) >> 22n) + 1420070400000n);
}

// When a key may get its first certificate. The addon asks every player key with a valid
// certificate that a code's T draws, and cannot tell a key this Worker would refuse as too
// young: so a player key is certified only once it counts for every code a proof signed from
// then on can belong to, the oldest one still open included (issued TOKEN_LIFE earlier, and
// CLOCK_SKEW more for a game clock behind ours): 7 days old and its owner's account 30 days old
// at that code's issue. A councillor's key counts at once.
export function certFrom(key) {
	if (key.kind !== 'p') return key.created;
	const account = Math.ceil(snowflakeTime(key.owner_discord_id) / 1000) + LINK.ACCOUNT_MIN_AGE;
	return Math.max(key.created + LINK.KEY_MIN_AGE, account) + LINK.TOKEN_LIFE + LINK.CLOCK_SKEW;
}

// ---------------------------------------------------------------------------
// Links (bundles): what the game's QR code, copy box and SavedVariables carry.

// The link in whatever the page read: the bundle itself (OLB5~...), the address of the QR code or
// of the game's copy box (<page>#b=<bundle, percent-encoded>), or that fragment alone. Null when
// there is none. (The page reads Olympus.lua itself and sends only the link the player picked.)
export function proofText(input) {
	if (typeof input !== 'string') return null;
	let s = input.trim();
	const at = s.indexOf('#b=');
	if (at >= 0) s = s.slice(at + 3);
	else if (s.startsWith('b=')) s = s.slice(2);
	s = s.split('&')[0].trim();
	if (/%[0-9A-Fa-f]{2}/.test(s) || s.includes('+')) {
		try {
			s = decodeURIComponent(s.replace(/\+/g, ' '));
		} catch {
			return null;
		}
	}
	s = s.trim();
	return s.startsWith('OLB5~') ? s : null;
}

// What the addon's Link.Parse reads (Olympus/Link.lua; the page's web/public/core.js reads the
// same). Whether the proofs count is the check's call below: a key or owner is counted once.
// Each proof carries its key's certificate for its confirmer: <public key>,<tier>,<cert exp>,<cert sig>.
export function parseBundle(text) {
	if (typeof text !== 'string' || !text.startsWith('OLB5~')) return { ok: false, error: 'prefix' };
	if (enc.encode(text).length > MAX_BUNDLE_BYTES) return { ok: false, error: 'size' };
	const f = text.split('~');
	if (f.length !== 8) return { ok: false, error: 'fields' };
	const [, requester, guild, faction, nonce, R, tag, proofText] = f;
	if (!validCharacter(requester)) return { ok: false, error: 'requester' };
	if (!field(guild, 40)) return { ok: false, error: 'guild' };
	if (faction !== 'Alliance' && faction !== 'Horde') return { ok: false, error: 'faction' };
	if (!NONCE_RE.test(nonce)) return { ok: false, error: 'nonce' };
	if (!R_RE.test(R)) return { ok: false, error: 'code' };
	if (!TAG_RE.test(tag)) return { ok: false, error: 'tag' };
	const parts = proofText ? proofText.split(';') : [];
	if (parts.length < 1 || parts.length > MAX_PROOFS) return { ok: false, error: 'proofs' };
	const proofs = [];
	for (const part of parts) {
		const p = part.split(',');
		if (p.length !== 9) return { ok: false, error: 'proof' };
		const [issued, keyId, confirmer, gv, sig, pub, tier, certExp, certSig] = p;
		if (!ISSUED_RE.test(issued) || !KEYID_RE.test(keyId) || !validCharacter(confirmer) || !GV_RE.test(gv)) return { ok: false, error: 'proof' };
		if (!SIG_RE.test(sig) || b64urlEncode(b64urlDecode(sig)) !== sig) return { ok: false, error: 'sig' };
		if (!PUBLIC_B64_RE.test(pub) || b64urlEncode(b64urlDecode(pub)) !== pub || (tier !== 'c' && tier !== 'p') || !ISSUED_RE.test(certExp)) return { ok: false, error: 'cert' };
		if (!SIG_RE.test(certSig) || b64urlEncode(b64urlDecode(certSig)) !== certSig) return { ok: false, error: 'cert' };
		proofs.push({ issued: Number(issued), keyId, confirmer, gv, sig, pub, tier, certExp: Number(certExp), certSig });
	}
	return { ok: true, bundle: { requester, guild, faction, nonce, R, tag, proofs } };
}

// A field of the signed text: not empty, at most `max` bytes, no separator, pipe or control.
function field(s, max) {
	return typeof s === 'string' && s !== '' && !FORBIDDEN.test(s) && enc.encode(s).length <= max;
}

// "Name-Realm": the realm follows the last dash and has no dash or space.
function validCharacter(s) {
	return field(s, 64) && /^[^-].*-[^- ]+$/s.test(s);
}

// The exact text a confirmer's addon signed for one proof.
export function signedMessage(b, p) {
	return ['OLY4', b.requester, b.guild, p.gv, b.faction, b.nonce, b.R, b.tag, p.issued, p.keyId, p.confirmer].join('~');
}

// The certificate a proof carries: its key's, for its confirmer (a parsed certificate, below).
export function proofCertificate(p) {
	return parseCertificate(`OLK2.${p.keyId}.${p.pub}.${p.tier}.${p.certExp}.${p.confirmer}.${p.certSig}`);
}

// The tag that binds a link to the command it was made with: the first 16 hex of
// SHA-256(<the token's sig>~<requester>). The QR code and the copy box never carry the token,
// so whoever sees them cannot make a link of their own with the code.
export async function linkTag(sig, requester) {
	return (await sha256Hex(`${sig}~${requester}`)).slice(0, 16);
}

export function guildPolicy(env) {
	return env.LINK_GUILD_POLICY === 'claimed' ? 'claimed' : 'verified';
}

// ---------------------------------------------------------------------------
// The check

// The verdict on a link, reading only: nothing is written, nobody gets a role. opts.discordId: the
// signed-in Discord account, who must own the code (the page's POST /proof); leave it out for the
// watcher's inbox (the code's owner is the one linked). The link may come as the bundle, the QR
// code's address, or its fragment (proofText). Either
//   { ok: true, already, R, discordId, username, character, guild, faction, guildCheck, guildKnown,
//     by, confirmers, message }
// (guildCheck "r" the guild's roster, "w" a /who, "c" claimed; guildKnown the same in words; by
// "councillor" or "players"; already: this exact link counted before, nothing more to do), or a
// refusal { ok: false, status: 'rejected', reason, message, R } (PROOF_REASONS).
export async function checkProof(env, text, opts = {}) {
	return (await examine(env, text, opts)).verdict;
}

async function examine(env, input, opts = {}) {
	const t = opts.t || now();
	const DB = database(env);
	const text = proofText(input) || (typeof input === 'string' ? input.trim() : '');
	const parsed = parseBundle(text);
	if (!parsed.ok) return { verdict: reject('format', `This is not a complete Olympus link (${parsed.error}).`) };
	const b = parsed.bundle;
	const code = await DB.prepare('SELECT * FROM codes WHERE r = ?').bind(b.R).first();
	if (!code) return { verdict: reject('unknown-code', 'This link was made with a code the bot never issued.', b.R) };
	const userId = opts.discordId === undefined || opts.discordId === null ? null : String(opts.discordId);
	if (userId && code.discord_id !== userId) return { verdict: reject('other-user', 'This link was made with a code of another Discord account.', b.R) };
	if (b.tag !== (await linkTag(tokenSig(code.token), b.requester))) {
		return { verdict: reject('tag', 'This link was not made by the player who typed this code in the game.', b.R) };
	}
	if (code.used !== null && code.used !== undefined) {
		const same = await DB.prepare('SELECT guild, gv, faction FROM members WHERE character = ? AND discord_id = ? AND r = ?').bind(b.requester, code.discord_id, b.R).first();
		if (same) {
			const verdict = linkVerdict(code, b, same.gv, [], `${b.requester} is already linked.`);
			return { verdict: { ...verdict, already: true, guild: same.guild, faction: same.faction, by: null }, b, code };
		}
		return { verdict: reject('code-used', 'This code was already used.', b.R) };
	}
	if (t > code.exp + LINK.DELIVERY_GRACE) return { verdict: reject('expired', 'This code expired more than 7 days ago.', b.R) };

	const checks = [];
	for (const p of b.proofs) checks.push(await checkConfirmation(env, b, p, code, t));
	const valid = checks.filter((c) => c.ok);
	let why = checks.filter((c) => !c.ok).map((c) => `${c.proof.keyId}: ${c.why}`);
	// Councillors: one is enough (one that checked the guild is recorded first). Every
	// councillor and every drawn player that could count vouches for the guild.
	const councillors = valid.filter((c) => c.key.kind === 'c').sort((x, y) => CHECKED(y.proof.gv) - CHECKED(x.proof.gv));
	let counted = councillors.length ? [councillors[0]] : null;
	let vouching = councillors;
	if (code.mode === 'a') {
		const drawn = await drawnPlayers(code, valid.filter((c) => c.key.kind === 'p'));
		vouching = vouching.concat(drawn.eligible);
		if (!counted) {
			counted = drawn.picked;
			why = why.concat(drawn.why);
		}
	}
	if (!counted) {
		const need = code.mode === 'a' ? `one councillor or ${LINK.PLAYERS_NEEDED} drawn players` : 'one councillor';
		return { verdict: reject('not-enough', `Not enough valid confirmations (needs ${need}).${why.length ? ` ${why.join('; ')}.` : ''}`, b.R) };
	}
	const checked = vouching.find((c) => CHECKED(c.proof.gv));
	const gv = checked ? checked.proof.gv : 'c';
	if (!checked && guildPolicy(env) === 'verified') {
		return {
			verdict: reject('guild-unverified', `None of the confirmations checked ${b.guild} in game (a confirmer of that guild with its roster, or one who saw the player in it in a /who).`, b.R),
		};
	}
	const verdict = linkVerdict(code, b, gv, counted, `${b.requester} can be linked to @${code.username}.`);
	return { verdict, b, code, counted, valid, gv };
}

function linkVerdict(code, b, gv, counted, message) {
	return {
		ok: true,
		status: 'ok',
		already: false,
		R: b.R,
		discordId: code.discord_id,
		username: code.username,
		character: b.requester,
		guild: b.guild,
		faction: b.faction,
		guildCheck: gv,
		guildKnown: GUILD_KNOWN[gv] || 'claimed',
		by: counted.length ? (counted[0].key.kind === 'c' ? 'councillor' : 'players') : null,
		confirmers: counted.map((c) => c.proof.confirmer),
		message,
	};
}

// The check, then the link: claims the code (two deliveries of the same link may race), calls
// promote(discordId, verdict) to give the role, then records the character. When promote fails,
// or the record does, the code is freed again, so the same link works on the next try.
//   promote(discordId, verdict): yours. Resolve (with nothing, true or { ok: true }) when the role is
//     given; throw, or return false or { ok: false }, when it is not ({ ok: false, reason:
//     'not-in-server' } when the member is not in the server: the player is told to join first).
//   demote(discordId): optional. Called when the character was linked to another account that has
//     no other linked character left: take that account's role away. Its errors are only logged.
// Answers { ok, status: 'linked' | 'rejected' | 'error', reason, message, R, and for a link:
// discordId, username, character, guild, faction, guildCheck, guildKnown, characters }.
export async function acceptProof(env, text, opts = {}) {
	const { promote, demote } = opts;
	if (typeof promote !== 'function') throw new TypeError('Olympus Link: acceptProof needs promote(discordId), your function that gives the role');
	const t = opts.t || now();
	const DB = database(env);
	const x = await examine(env, text, { discordId: opts.discordId, t });
	const v = x.verdict;
	if (!v.ok) return v;
	const { b, code } = x;
	if (v.already) {
		return { ...linkedAnswer(v, 'already', v.message), characters: await charactersOf(env, code.discord_id) };
	}

	// Claim the code first (two deliveries of the same link may race), then the role. Anything
	// that fails after the claim releases it, so the same link works on the next try.
	const claim = await DB.prepare('UPDATE codes SET used = ? WHERE r = ? AND used IS NULL').bind(t, b.R).run();
	if (!claim.meta || claim.meta.changes !== 1) return reject('code-used', 'This code was already used.', b.R);
	const release = async () => {
		try {
			await DB.prepare('UPDATE codes SET used = NULL WHERE r = ? AND used = ?').bind(b.R, t).run();
		} catch (err) {
			console.error('olympus-link: could not release code', b.R, err && err.stack ? err.stack : err);
		}
	};
	const role = await promoted(promote, code.discord_id, v);
	if (!role.ok) {
		await release();
		if (role.reason === 'not-in-server') return reject('not-in-server', 'Join the Olympus Discord server first, then send the link again.', b.R);
		return failure('discord', 'Discord did not take the role change: try again in a minute.', { R: b.R });
	}
	let previous;
	try {
		previous = await DB.prepare('SELECT discord_id FROM members WHERE character = ?').bind(b.requester).first();
		await DB.batch([
			...x.counted.map((c) => DB.prepare('INSERT OR IGNORE INTO used (r, key_id, t) VALUES (?, ?, ?)').bind(b.R, c.proof.keyId, t)),
			// The council authority's keys whose proofs checked in this link: recorded now, not before.
			...x.valid.filter((c) => c.key.council).map((c) => recordCouncilKey(DB, c, t)),
			DB.prepare(
				'INSERT INTO members (character, discord_id, guild, gv, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?, ?) ' +
					'ON CONFLICT(character) DO UPDATE SET discord_id = excluded.discord_id, guild = excluded.guild, gv = excluded.gv, faction = excluded.faction, r = excluded.r, linked = excluded.linked',
			).bind(b.requester, code.discord_id, b.guild, x.gv, b.faction, b.R, t),
		]);
	} catch (err) {
		console.error('olympus-link: could not record the link', b.R, err && err.stack ? err.stack : err);
		await release();
		return failure('server', 'The link could not be recorded: send it again in a minute.', { R: b.R });
	}
	if (previous && previous.discord_id !== code.discord_id && typeof demote === 'function') {
		const left = await DB.prepare('SELECT COUNT(*) AS n FROM members WHERE discord_id = ?').bind(previous.discord_id).first();
		if (!left || left.n === 0) {
			// The character moved away, and the old account has no other.
			try {
				await demote(previous.discord_id);
			} catch (err) {
				console.error('olympus-link: demote failed for', previous.discord_id, err && err.stack ? err.stack : err);
			}
		}
	}
	return { ...linkedAnswer(v, 'linked', `${b.requester} is now linked to @${code.username}.`), characters: await charactersOf(env, code.discord_id) };
}

function linkedAnswer(v, reason, message) {
	const { discordId, username, character, guild, faction, guildCheck, guildKnown, R } = v;
	return { ok: true, status: 'linked', reason, message, R, discordId, username, character, guild, faction, guildCheck, guildKnown };
}

// promote()'s outcome as { ok } or { ok: false, reason }: it may resolve with nothing, a
// boolean or { ok, reason }, or throw.
async function promoted(promote, discordId, verdict) {
	let r;
	try {
		r = await promote(discordId, verdict);
	} catch (err) {
		console.error('olympus-link: promote failed for', discordId, err && err.stack ? err.stack : err);
		return { ok: false, reason: err && err.reason === 'not-in-server' ? 'not-in-server' : 'discord' };
	}
	if (r === false) return { ok: false, reason: 'discord' };
	if (r && typeof r === 'object' && r.ok === false) return { ok: false, reason: r.reason === 'not-in-server' ? 'not-in-server' : 'discord' };
	return { ok: true };
}

// One proof, checked whole (its key, time, signature and who confirms), reading only:
// { ok, proof, key } or { ok: false, proof, why }.
async function checkConfirmation(env, b, p, code, t) {
	const DB = database(env);
	const bad = (why) => ({ ok: false, proof: p, why });
	const found = await proofKey(env, p);
	if (found.why) return bad(found.why);
	const key = found.key;
	if (key.owner_discord_id && key.owner_discord_id === code.discord_id) return bad("the requester's own key");
	if (p.issued < code.created - LINK.CLOCK_SKEW || p.issued > code.exp) return bad('signed outside the code\'s life');
	if (p.issued > t + LINK.CLOCK_SKEW) return bad('signed in the future');
	if (!(await ed25519Verify(key.public_key, b64urlDecode(p.sig), enc.encode(signedMessage(b, p))))) return bad('bad signature');
	if (!key.council && !(key.kind === 'c' && key.bootstrap)) {
		const mine = await DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ?').bind(p.confirmer, key.owner_discord_id).first();
		if (!mine) return bad("the confirmer is not a linked character of the key's owner");
	}
	if (p.confirmer === b.requester) return bad('the confirmer is the requester');
	if (key.owner_discord_id) {
		const own = await DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ?').bind(b.requester, key.owner_discord_id).first();
		if (own) return bad("the requester is the key owner's own character");
	}
	const reused = await DB.prepare('SELECT 1 AS x FROM used WHERE r = ? AND key_id = ?').bind(b.R, p.keyId).first();
	if (reused) return bad('already counted');
	return { ok: true, proof: p, key };
}

// The key a proof is checked with: { key } or { why }. It only reads: nothing about a proof is
// written before the whole link is accepted (acceptProof). A key registered here (keys) is D1's:
// the certificate the proof carries must name its public key, tier and character, and D1 says
// whether it is revoked. A key this Worker never registered counts only as a High Councillor's
// certified by the council authority (the author's client, LINK_CA_PUBLIC): the certificate the
// proof carries is then checked here (tier c, the key's id the first 12 hex of SHA-256 of it,
// valid when the proof was signed), its character on LINK_COUNCIL_CHARACTERS when you set that
// list, the revocation lists can end it (revoked_keys by its id, revoked_characters every
// certificate of a character signed before its revocation), and a key already recorded for
// another character (council_keys, by the key itself) is refused. The record is written with the
// first link it confirmed, once its signature checked: a certificate for someone else's public
// key, carried with a signature nobody made, records nothing.
async function proofKey(env, p) {
	const DB = database(env);
	const cert = proofCertificate(p);
	if (!cert) return { why: 'a certificate that does not read' };
	const row = await DB.prepare('SELECT * FROM keys WHERE key_id = ?').bind(p.keyId).first();
	if (row) {
		if (row.revoked) return { why: 'revoked key' };
		if (row.public_key !== cert.publicHex || row.kind !== cert.tier || row.character !== cert.character) {
			return { why: "its certificate is not the one registered for this key (public key, tier and character)" };
		}
		return { key: row };
	}
	if (!CA_KEYID_RE.test(p.keyId)) return { why: 'unknown key' };
	if (await DB.prepare('SELECT 1 AS x FROM revoked_keys WHERE key_id = ?').bind(p.keyId).first()) return { why: 'revoked key' };
	if (!(await councilCertificate(env, cert))) return { why: 'unknown key (not certified by the council authority)' };
	if (p.issued >= cert.exp) return { why: 'signed after its certificate ended' };
	// Your say over who is a councillor here: when you list them, the authority certifies no one else.
	const listed = councilCharacters(env);
	if (listed && !listed.has(cert.character)) return { why: 'its character is not on LINK_COUNCIL_CHARACTERS' };
	// Its character revoked (a councillor off the list, or keys of theirs you can't name): every
	// certificate for it signed before then, whatever key it names.
	const gone = await DB.prepare('SELECT revoked_at FROM revoked_characters WHERE character = ?').bind(cert.character).first();
	if (gone && cert.exp - LINK.CA_DAYS * 86400 <= gone.revoked_at) return { why: 'its character was revoked (a certificate from before)' };
	const known = await DB.prepare('SELECT character FROM council_keys WHERE public_key = ?').bind(cert.publicHex).first();
	if (known && known.character !== cert.character) return { why: 'a council key recorded for another character' };
	// Its owner, when the councillor's character is linked: never confirms that account's codes or characters.
	const owner = await DB.prepare('SELECT discord_id FROM members WHERE character = ?').bind(cert.character).first();
	return {
		key: {
			key_id: p.keyId,
			public_key: cert.publicHex,
			kind: 'c',
			bootstrap: 1,
			council: true,
			character: cert.character,
			cert_exp: cert.exp,
			owner_discord_id: owner ? owner.discord_id : null,
		},
	};
}

// The record of a council authority's key whose proof checked, written with the link it helped
// accept: its character the first time, a later end of its certificate after (never another
// character's: that stays the first one's).
function recordCouncilKey(DB, c, t) {
	return DB.prepare(
		'INSERT INTO council_keys (public_key, key_id, character, cert_exp, first_seen) VALUES (?, ?, ?, ?, ?) ' +
			'ON CONFLICT(public_key) DO UPDATE SET cert_exp = MAX(council_keys.cert_exp, excluded.cert_exp) WHERE council_keys.character = excluded.character',
	).bind(c.key.public_key, c.key.key_id, c.key.character, c.key.cert_exp, t);
}

// Mode "a": three drawn players from three owners, signed within 5 minutes of each other. A
// player key counts when it was 7 days old and its owner's Discord account 30 days old when the
// code was issued, it was not replaced before that, and it is drawn: its prefix < the code's T.
async function drawnPlayers(code, valid) {
	const why = [];
	const eligible = [];
	for (const c of valid) {
		const young = tooYoung(c.key, code.created);
		if (young) why.push(`${c.proof.keyId}: ${young}`);
		else if (c.key.replaced_at && c.key.replaced_at <= code.created) why.push(`${c.proof.keyId}: replaced by a newer key`);
		else if (!((await drawPrefix(code.r, c.proof.keyId)) < code.draw_t)) why.push(`${c.proof.keyId}: not drawn for this code`);
		else eligible.push(c);
	}
	const inDraw = [...eligible].sort((a, b) => a.proof.issued - b.proof.issued);
	for (let i = 0; i < inDraw.length; i++) {
		const picked = [];
		const owners = new Set();
		for (let j = i; j < inDraw.length && inDraw[j].proof.issued - inDraw[i].proof.issued <= LINK.WINDOW; j++) {
			if (owners.has(inDraw[j].key.owner_discord_id)) continue;
			owners.add(inDraw[j].key.owner_discord_id);
			picked.push(inDraw[j]);
			if (picked.length === LINK.PLAYERS_NEEDED) return { picked, eligible, why };
		}
	}
	if (inDraw.length >= LINK.PLAYERS_NEEDED) why.push('the player confirmations are more than 5 minutes apart');
	return { picked: null, eligible, why };
}

// The characters linked to a Discord account, oldest first.
export async function charactersOf(env, discordId) {
	const rows = (await database(env).prepare('SELECT character FROM members WHERE discord_id = ? ORDER BY linked').bind(String(discordId)).all()).results || [];
	return rows.map((r) => r.character);
}

// The page's limit: SUBMITS_PER_HOUR links an hour per Discord account (counted in inbox_uploads).
export async function tooManyProofs(env, discordId, t = now()) {
	const recent = await database(env)
		.prepare("SELECT COUNT(*) AS n FROM inbox_uploads WHERE source = 'site' AND discord_id = ? AND uploaded > ?")
		.bind(String(discordId), t - 3600)
		.first();
	return !!recent && recent.n >= LINK.SUBMITS_PER_HOUR;
}

// The audit trail: every link received, from the page ('site') or the watcher's inbox ('watcher'),
// and what became of it. extra: { discordId, from, received, uploaded }.
export async function logProof(env, source, text, result, extra = {}) {
	const DB = database(env);
	const parsed = parseBundle(typeof text === 'string' ? proofText(text) || text.trim() : '');
	const b = parsed.ok ? parsed.bundle : null;
	const code = b ? await DB.prepare('SELECT discord_id FROM codes WHERE r = ?').bind(b.R).first() : null;
	await DB.prepare(
		'INSERT INTO inbox_uploads (source, r, discord_id, requester, from_character, received, uploaded, status, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
	)
		.bind(source, b ? b.R : null, extra.discordId || (code && code.discord_id) || null, b ? b.requester : null, extra.from || null, extra.received || null, extra.uploaded || now(), result.status, result.reason || null)
		.run();
}

// ---------------------------------------------------------------------------
// The page: POST /proof, from the static page on GitHub Pages
//
// Body {"text": "<the link: OLB5~... or its address>", "discordToken": "<the player's Discord
// access token>"}; the page sends "Authorization: Bearer <LINK_SITE_TOKEN>" when you gave it one.
// The token is only shown to Discord (GET /oauth2/@me), never stored: it must be for your
// application (DISCORD_CLIENT_ID) with the identify scope, and it says who the player is.

// The CORS headers for a request from the page's origin (LINK_ORIGIN, exactly; several may be
// listed, comma-separated, while a new address comes in), or null for any other origin.
export function corsHeaders(request, env) {
	const origin = request.headers.get('Origin');
	if (!origin || !allowedOrigins(env).includes(origin)) return null;
	return {
		'Access-Control-Allow-Origin': origin,
		'Access-Control-Allow-Methods': 'POST',
		'Access-Control-Allow-Headers': 'Authorization, Content-Type',
		Vary: 'Origin',
	};
}

export function allowedOrigins(env) {
	return String((env && env.LINK_ORIGIN) || '')
		.split(/[\s,]+/)
		.filter((o) => /^https?:\/\/[^/]+$/.test(o));
}

// Who a Discord access token belongs to, asked of Discord itself: { ok: true, user: { id,
// username, global_name, avatar } }, or an error answer (reason "login": sign in again;
// "discord": Discord did not answer). Only a token made for your application (clientId) with the
// identify scope counts: a token another site got for its own application does not.
export async function discordUser(accessToken, { clientId, fetchImpl = globalThis.fetch } = {}) {
	if (!DISCORD_ID_RE.test(String(clientId || ''))) throw new Error('Olympus Link: set DISCORD_CLIENT_ID to your Discord application\'s id');
	if (typeof accessToken !== 'string' || !ACCESS_TOKEN_RE.test(accessToken)) return failure('login', 'Sign in with Discord first.');
	let res;
	try {
		res = await fetchImpl(`${DISCORD_API}/oauth2/@me`, { headers: { Authorization: `Bearer ${accessToken}` } });
	} catch (err) {
		console.error('olympus-link: Discord oauth2/@me fetch failed:', err && err.message ? err.message : err);
		return failure('discord', 'Discord did not answer: try again in a minute.');
	}
	if (res.status === 401 || res.status === 403) return failure('login', 'Your Discord sign-in expired: sign in again.');
	if (!res.ok) return failure('discord', 'Discord did not answer: try again in a minute.');
	let info = null;
	try {
		info = await res.json();
	} catch {
		info = null;
	}
	const app = info && info.application;
	const u = info && info.user;
	if (!app || String(app.id) !== String(clientId)) return failure('login', 'This Discord sign-in is not for the Olympus bot: sign in again on the Olympus Link page.');
	if (!Array.isArray(info.scopes) || !info.scopes.includes('identify') || !u || !DISCORD_ID_RE.test(String(u.id)) || typeof u.username !== 'string') {
		return failure('login', 'Sign in with Discord again.');
	}
	if (info.expires && Date.parse(info.expires) <= Date.now()) return failure('login', 'Your Discord sign-in expired: sign in again.');
	return { ok: true, user: { id: String(u.id), username: u.username, global_name: u.global_name ?? null, avatar: u.avatar ?? null } };
}

// The whole POST /proof, CORS preflight included, as a Response: the origin, your site token
// (when you set LINK_SITE_TOKEN), the body, the link's form, who the player is (discordUser), 10
// links an hour per account, then acceptProof with your promote, and the audit trail.
//   if (url.pathname === '/proof') return handleProof(request, env, { promote, demote });
export async function handleProof(request, env, { promote, demote, fetchImpl } = {}) {
	const cors = corsHeaders(request, env);
	const reply = (answer) => respond(answer, cors || { Vary: 'Origin' });
	try {
		if (request.method === 'OPTIONS') {
			return new Response(null, { status: cors ? 204 : 403, headers: cors ? { ...cors, 'Access-Control-Max-Age': '600' } : { Vary: 'Origin' } });
		}
		if (request.method !== 'POST') return reply(failure('method', 'POST only.'));
		if (!cors) return reply(failure('origin', 'Wrong origin.'));
		if (env.LINK_SITE_TOKEN && !(await sameSecret(bearer(request), env.LINK_SITE_TOKEN))) {
			return reply(failure('site', 'This page is not allowed to send links right now.'));
		}
		const body = await readJson(request, 8 * 1024);
		if (!body || typeof body.text !== 'string' || typeof body.discordToken !== 'string') {
			return reply(failure('format', 'Send {"text": "<the link>", "discordToken": "<the Discord sign-in>"}.'));
		}
		const text = proofText(body.text);
		if (!text || !parseBundle(text).ok) {
			const why = text ? parseBundle(text).error : 'prefix';
			return reply(reject('format', `This is not a complete Olympus link (${why}).`));
		}
		const who = await discordUser(body.discordToken, { clientId: env.DISCORD_CLIENT_ID, fetchImpl });
		if (!who.ok) return reply(who);
		const t = now();
		if (await tooManyProofs(env, who.user.id, t)) return reply(failure('limit', 'Too many tries: wait a while and send it again.'));
		const result = await acceptProof(env, text, { discordId: who.user.id, promote, demote, t });
		try {
			await logProof(env, 'site', text, result, { discordId: who.user.id, uploaded: t });
		} catch (err) {
			console.error('olympus-link: could not log', err && err.stack ? err.stack : err);
		}
		return reply(pageAnswer(result));
	} catch (err) {
		console.error('olympus-link: /proof', err && err.stack ? err.stack : err);
		return reply(failure('server', 'Something went wrong on our side.'));
	}
}

// What the page gets back: the answer without the Discord id.
function pageAnswer(r) {
	const { discordId, ...rest } = r;
	return rest;
}

// ---------------------------------------------------------------------------
// The watcher (the whisper path): many links at once, from a High Councillor's inbox, uploaded by
// web/tools/read-inbox.mjs with your admin token. The Discord account is each code's owner.
//   body: {"bundles": [{"R", "bundle", "from", "t"}, ...]} (500 at most; a bare string is a bundle)
// { ok: true, status: 'ok', results: [{ R, status, reason, message }] } or a format error.
export async function acceptInbox(env, body, { promote, demote } = {}) {
	if (typeof promote !== 'function') throw new TypeError('Olympus Link: acceptInbox needs promote(discordId), your function that gives the role');
	const list = body && Array.isArray(body.bundles) ? body.bundles : null;
	if (!list || list.length > LINK.MAX_BUNDLES) return failure('format', `Send {"bundles": [...]} with at most ${LINK.MAX_BUNDLES}.`);
	const results = [];
	for (const item of list) {
		const entry = item && typeof item === 'object' ? item : {};
		const text = (typeof item === 'string' ? item : typeof entry.bundle === 'string' ? entry.bundle : '').trim();
		const t = now();
		const parsed = parseBundle(text);
		let result;
		try {
			result =
				parsed.ok && typeof entry.R === 'string' && entry.R !== parsed.bundle.R
					? reject('format', 'The inbox key does not match the link.', parsed.bundle.R)
					: await acceptProof(env, text, { t, promote, demote });
		} catch (err) {
			// One link that fails on our side does not stop the others: this one is sent again later.
			console.error('olympus-link: inbox entry', err && err.stack ? err.stack : err);
			result = failure('server', 'Something went wrong on our side: send it again.', { R: parsed.ok ? parsed.bundle.R : null });
		}
		try {
			await logProof(env, 'watcher', text, result, {
				from: typeof entry.from === 'string' ? entry.from.slice(0, 100) : null,
				received: Number.isFinite(entry.t) ? Math.floor(entry.t) : null,
				uploaded: t,
			});
		} catch (err) {
			console.error('olympus-link: inbox log', err && err.stack ? err.stack : err);
		}
		results.push({ R: result.R || (typeof entry.R === 'string' ? entry.R : null), status: result.status, reason: result.reason, message: result.message });
	}
	return { ok: true, status: 'ok', results };
}

// POST <your inbox route> for read-inbox.mjs --post: the admin token, then acceptInbox.
export async function handleInbox(request, env, { promote, demote } = {}) {
	if (!(await adminAuthorized(request, env))) return respond(failure('auth', 'Wrong admin token.'));
	const body = await readJson(request, 2 * 1024 * 1024);
	return respond(await acceptInbox(env, body, { promote, demote }));
}

// ---------------------------------------------------------------------------
// Confirmer keys and their certificates
//
// A certificate tells every requester's addon, without the bot online, that a key is
// certified, whether it is a councillor's (c) or a drawn player's (p), and for which character:
//   OLK2.<keyId>.<public key, 43 base64url>.<tier>.<exp>.<Name-Realm>.<sig>
// sig: Ed25519 over the UTF-8 bytes of everything before the last dot, by the backend key (a
// key registered here), or, tier c only and for a key whose id is the first 12 hex of SHA-256 of
// it, by the council authority's (a High Councillor's key made in game, certified by the
// author's client). The character is read from both ends (it may hold dots). Only that character
// announces it and confirms with it, and every proof carries it in the link.

export async function makeCertificate(env, keyId, publicHex, tier, exp, character) {
	const payload = `OLK2.${keyId}.${b64urlEncode(hexToBytes(publicHex))}.${tier}.${exp}.${character}`;
	return `${payload}.${await backendSign(env, payload)}`;
}

// { keyId, publicHex, tier, exp, character, sig, payload } or null.
export function parseCertificate(text) {
	const s = String(text);
	const m = /^OLK2\.([a-z0-9]{6,16})\.([A-Za-z0-9_-]{43})\.([cp])\.([1-9][0-9]{0,11})\.(.+)\.([A-Za-z0-9_-]{86})$/s.exec(s);
	if (!m || enc.encode(s).length > MAX_CERT_BYTES) return null;
	const [, keyId, pub, tier, exp, character, sig] = m;
	if (!validCharacter(character) || b64urlEncode(b64urlDecode(pub)) !== pub || b64urlEncode(b64urlDecode(sig)) !== sig) return null;
	return { keyId, publicHex: bytesToHex(b64urlDecode(pub)), tier, exp: Number(exp), character, sig, payload: s.slice(0, s.length - sig.length - 1) };
}

// The certificate when the key `publicHex` (the backend's, or the council authority's) signed
// it, else null.
export async function verifyCertificate(publicHex, text) {
	const c = typeof text === 'string' ? parseCertificate(text) : text;
	if (!c || !(await ed25519Verify(publicHex, b64urlDecode(c.sig), enc.encode(c.payload)))) return null;
	return c;
}

// The council authority's public keys (LINK_CA_PUBLIC: one, or two while it changes).
export function councilAuthorityKeys(env) {
	return String((env && env.LINK_CA_PUBLIC) || '')
		.split(/[\s,]+/)
		.map((k) => k.toLowerCase())
		.filter((k) => PUBLIC_HEX_RE.test(k));
}

// The High Councillors' characters you accept from the council authority (LINK_COUNCIL_CHARACTERS:
// "Name-Realm" as the game writes it, comma-separated), as a Set, or null when the setting is
// absent: then every character the authority certifies counts. Set but empty, none does. Keys you
// register yourself (keys) are yours already: the list does not apply to them.
export function councilCharacters(env) {
	const list = env ? env.LINK_COUNCIL_CHARACTERS : undefined;
	if (list === undefined || list === null) return null;
	return new Set(
		String(list)
			.split(/[,\n]/)
			.map((c) => c.trim())
			.filter((c) => c !== ''),
	);
}

// The id of a key the council authority certifies: the first 12 hex of SHA-256 of its 32 bytes.
export async function councilKeyId(publicHex) {
	return bytesToHex(new Uint8Array(await crypto.subtle.digest('SHA-256', hexToBytes(publicHex)))).slice(0, 12);
}

// A parsed certificate the council authority signed for a High Councillor's key, else null.
export async function councilCertificate(env, c) {
	if (!c || c.tier !== 'c' || c.keyId !== (await councilKeyId(c.publicHex))) return null;
	for (const pk of councilAuthorityKeys(env)) {
		if (await verifyCertificate(pk, c)) return c;
	}
	return null;
}

// Your key tool: register a confirmer's public key for one character, get its certificate (a
// player key's once it counts: certFrom), renew it, or revoke a key (a High Councillor's key the
// council authority certified too: its id goes on the revocation list, seen here or not), or every
// key of a character (a councillor off the signed list: every council authority certificate for
// that character signed until now, and its registered keys). The seed never comes here: it stays
// with the confirmer.
//   {"key_id", "public_key", "owner_discord_id", "owner_username", "character", "kind", "bootstrap", "days", "replace"}
//   {"key_id", "renew": true, "days"}
//   {"key_id", "revoke": true}
//   {"character", "revoke": true}
// { ok: true, status: 'ok', ... } or { ok: false, status: 'error', reason, message } (httpStatus).
export async function manageKeys(env, body, t = now()) {
	const DB = database(env);
	const fail = (reason, message, extra = {}) => failure(reason, message, extra);
	if (body && typeof body === 'object' && body.revoke === true && body.key_id === undefined && body.character !== undefined) {
		return revokeCharacter(env, body.character, t);
	}
	if (!body || typeof body !== 'object' || typeof body.key_id !== 'string' || !KEYID_RE.test(body.key_id)) return fail('format', 'key_id: 6 to 16 of a-z and 0-9.');
	const keyId = body.key_id;
	if (body.days !== undefined && (!Number.isInteger(body.days) || body.days < 1 || body.days > LINK.CERT_DAYS_MAX)) {
		return fail('format', `days: a whole number from 1 to ${LINK.CERT_DAYS_MAX}.`);
	}
	const certExp = (kind) => t + (body.days !== undefined ? body.days : kind === 'p' ? LINK.CERT_DAYS_PLAYER : LINK.CERT_DAYS) * 86400;
	const existing = await DB.prepare('SELECT * FROM keys WHERE key_id = ?').bind(keyId).first();

	if (body.revoke === true) {
		if (!existing) {
			// A councillor's key the council authority certified (never registered here): on the
			// revocation list at once, whether a link has used it yet or not.
			if (!CA_KEYID_RE.test(keyId)) return fail('unknown-key', 'No such key.');
			await DB.prepare('INSERT OR IGNORE INTO revoked_keys (key_id, revoked_at) VALUES (?, ?)').bind(keyId, t).run();
			const known = await DB.prepare('SELECT character FROM council_keys WHERE key_id = ?').bind(keyId).first();
			return { ok: true, status: 'ok', key_id: keyId, revoked: true, council: true, character: known ? known.character : null };
		}
		await DB.prepare('UPDATE keys SET revoked = 1, revoked_at = ? WHERE key_id = ? AND revoked = 0').bind(t, keyId).run();
		return { ok: true, status: 'ok', key_id: keyId, revoked: true };
	}
	if (body.renew === true) {
		if (!existing) return fail('unknown-key', 'No such key.');
		if (existing.revoked) return fail('revoked', 'This key is revoked: make a new one.');
		if (existing.replaced_at !== null && existing.replaced_at !== undefined) return fail('replaced', 'This key was replaced by a newer one of the same account: certify that one.');
		const from = certFrom(existing);
		if (t < from) return fail('too-early', `This player key counts from ${when(from)}: ask for its certificate then.`, { cert_from: from });
		const exp = certExp(existing.kind);
		const cert = await makeCertificate(env, keyId, existing.public_key, existing.kind, exp, existing.character);
		const first = existing.cert_exp === null || existing.cert_exp === undefined;
		// A key's first certificate replaces the older key of its owner (a rotation).
		const older = first ? await activeKeys(env, existing.owner_discord_id, keyId) : [];
		await DB.batch([
			...older.map((k) => DB.prepare('UPDATE keys SET replaced_at = ? WHERE key_id = ?').bind(t, k.key_id)),
			DB.prepare('UPDATE keys SET cert_exp = ? WHERE key_id = ?').bind(exp, keyId),
		]);
		return keyAnswer(existing, cert, exp, replacedId(older));
	}

	const pub = typeof body.public_key === 'string' ? publicKeyHex(body.public_key) : null;
	const owner = String(body.owner_discord_id || '');
	const username = body.owner_username === undefined || body.owner_username === null ? null : String(body.owner_username);
	const kind = body.kind;
	const bootstrap = body.bootstrap === true ? 1 : 0;
	const character = typeof body.character === 'string' ? body.character : '';
	if (CA_KEYID_RE.test(keyId)) return fail('format', 'key_id: 12 hex digits name the council authority\'s keys: pick another id.');
	if (!pub) return fail('format', 'public_key: 64 hex digits (or 43 of base64url).');
	if (!DISCORD_ID_RE.test(owner)) return fail('format', "owner_discord_id: the confirmer's Discord id.");
	if (username !== null && !USERNAME_RE.test(username)) return fail('format', 'owner_username: a Discord username.');
	if (!validCharacter(character)) return fail('format', 'character: the one character that confirms with this key, "Name-Realm" as the game writes it.');
	if (kind !== 'c' && kind !== 'p') return fail('format', 'kind: "c" (a High Councillor) or "p" (a drawn player).');
	if (bootstrap && kind !== 'c') return fail('format', 'Only a councillor key can be a bootstrap key.');
	if (existing) return fail('key-id-used', 'This key id exists already: ids are never reused.');
	if (await DB.prepare('SELECT 1 AS x FROM keys WHERE public_key = ?').bind(pub).first()) return fail('public-key-used', 'This public key is registered already.');
	// The character confirms for its owner: one of the owner's linked characters (a bootstrap
	// councillor key excepted: at launch nobody has linked one yet).
	if (!bootstrap && !(await DB.prepare('SELECT 1 AS x FROM members WHERE character = ? AND discord_id = ?').bind(character, owner).first())) {
		return fail('character-not-linked', `${character} is not a linked character of this Discord account: a key confirms from one of its owner's linked characters.`);
	}
	const mine = await activeKeys(env, owner, keyId);
	if (mine.length && body.replace !== true) {
		return fail('owner-has-key', `This account's key is ${replacedId(mine)}: send "replace": true to rotate it.`);
	}
	const key = { key_id: keyId, public_key: pub, owner_discord_id: owner, character, kind, created: t, cert_exp: null };
	const ready = t >= certFrom(key);
	const exp = ready ? certExp(kind) : null;
	const cert = ready ? await makeCertificate(env, keyId, pub, kind, exp, character) : null;
	// Rotating: the older key is replaced when the new one gets its certificate (a councillor's at
	// once, a player's once it counts): until then the confirmer has only the old one in game, and
	// it keeps counting. A replaced key leaves the draw and still checks the proofs it signed until
	// you revoke it, once the confirmer typed the new key and certificate in game. A new key that
	// never got its certificate is replaced at once.
	const older = ready ? mine : mine.filter((k) => k.cert_exp === null);
	await DB.batch([
		...older.map((k) => DB.prepare('UPDATE keys SET replaced_at = ? WHERE key_id = ?').bind(t, k.key_id)),
		DB.prepare('INSERT INTO keys (key_id, public_key, owner_discord_id, owner_username, character, kind, bootstrap, created, cert_exp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
			.bind(keyId, pub, owner, username, character, kind, bootstrap, t, exp),
	]);
	return keyAnswer(key, cert, exp, ready ? replacedId(older) : null);
}

// The same, one thing each.
export function registerKey(env, key, t) {
	const { renew, revoke, ...body } = key || {};
	return manageKeys(env, body, t);
}

export function renewKey(env, keyId, days, t) {
	return manageKeys(env, days === undefined ? { key_id: keyId, renew: true } : { key_id: keyId, renew: true, days }, t);
}

export function revokeKey(env, keyId, t) {
	return manageKeys(env, { key_id: keyId, revoke: true }, t);
}

// Every key of a character, at once: the council authority's certificates for it signed until now
// (whatever key they name, seen here or not: the ones a councillor rotated away included) stop
// counting, and so do the keys registered for it. A certificate the authority signs for it later
// counts again (a councillor back on the list, after /oly discord key new).
export async function revokeCharacter(env, character, t = now()) {
	const DB = database(env);
	if (typeof character !== 'string' || !validCharacter(character)) return failure('format', 'character: "Name-Realm" as the game writes it.');
	const registered = (await DB.prepare('SELECT key_id FROM keys WHERE character = ? AND revoked = 0').bind(character).all()).results || [];
	await DB.batch([
		DB.prepare('INSERT INTO revoked_characters (character, revoked_at) VALUES (?, ?) ON CONFLICT(character) DO UPDATE SET revoked_at = excluded.revoked_at').bind(character, t),
		DB.prepare('UPDATE keys SET revoked = 1, revoked_at = ? WHERE character = ? AND revoked = 0').bind(t, character),
	]);
	const council = (await DB.prepare('SELECT key_id FROM council_keys WHERE character = ? ORDER BY first_seen').bind(character).all()).results || [];
	return { ok: true, status: 'ok', character, revoked: true, keys: registered.map((k) => k.key_id), council_keys: council.map((k) => k.key_id) };
}

// POST <your keys route>: the admin token, then manageKeys.
export async function handleKeys(request, env) {
	if (!(await adminAuthorized(request, env))) return respond(failure('auth', 'Wrong admin token.'));
	return respond(await manageKeys(env, await readJson(request, 4 * 1024)));
}

// The owner's keys neither revoked nor replaced, but `except`: the certified one first.
async function activeKeys(env, owner, except) {
	const rows = (await database(env).prepare('SELECT key_id, cert_exp FROM keys WHERE owner_discord_id = ? AND key_id <> ? AND revoked = 0 AND replaced_at IS NULL').bind(owner, except).all()).results || [];
	return rows.sort((a, b) => (a.cert_exp === null) - (b.cert_exp === null));
}

function replacedId(keys) {
	return keys.length ? keys[0].key_id : null;
}

function keyAnswer(key, cert, certExp, replaced) {
	const from = certFrom(key);
	const answer = {
		ok: true,
		status: 'ok',
		key_id: key.key_id,
		kind: key.kind,
		character: key.character,
		public_key: key.public_key,
		cert,
		cert_exp: certExp,
		cert_from: from,
		command: cert ? `/oly discord cert ${cert}` : null,
		replaced,
	};
	if (!cert) {
		answer.message = `A player key gets its certificate once it counts: from ${when(from)}, send {"key_id": "${key.key_id}", "renew": true} and give the confirmer both lines.`;
	}
	return answer;
}

// A time for people, rounded up to the minute: "2027-01-31 18:05 UTC".
function when(t) {
	return `${new Date(Math.ceil(t / 60) * 60000).toISOString().slice(0, 16).replace('T', ' ')} UTC`;
}

function publicKeyHex(s) {
	const t = s.trim();
	if (PUBLIC_HEX_RE.test(t.toLowerCase())) return t.toLowerCase();
	if (PUBLIC_B64_RE.test(t) && b64urlEncode(b64urlDecode(t)) === t) return bytesToHex(b64urlDecode(t));
	return null;
}

// ---------------------------------------------------------------------------
// People

// Everything kept about one Discord account, gone: its linked characters, its codes and its lines
// in the audit trail; the confirmer keys it owns are revoked (their rows stay, with no username,
// so an id is never used twice). Take its role away yourself. { ok, status, discord_id,
// characters, keys }. `python3 scripts/link-keys.py forget <id>` prints the same as SQL.
export async function forgetUser(env, discordId, t = now()) {
	const id = String(discordId);
	if (!DISCORD_ID_RE.test(id)) return failure('format', 'A Discord id: digits only.');
	const DB = database(env);
	const characters = await charactersOf(env, id);
	const keys = (await DB.prepare('SELECT key_id FROM keys WHERE owner_discord_id = ? AND revoked = 0').bind(id).all()).results || [];
	await DB.batch([
		DB.prepare('DELETE FROM members WHERE discord_id = ?').bind(id),
		DB.prepare('DELETE FROM codes WHERE discord_id = ?').bind(id),
		DB.prepare('DELETE FROM inbox_uploads WHERE discord_id = ?').bind(id),
		DB.prepare('UPDATE keys SET revoked = 1, revoked_at = COALESCE(revoked_at, ?), owner_username = NULL WHERE owner_discord_id = ?').bind(t, id),
	]);
	return { ok: true, status: 'ok', discord_id: id, characters, keys: keys.map((k) => k.key_id) };
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

export async function sha256Hex(text) {
	return bytesToHex(new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(text))));
}

// ---------------------------------------------------------------------------
// Small helpers

// The token after "Bearer " in the Authorization header ('' when there is none).
export function bearer(request) {
	return (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
}

// Two secrets compared in constant time (their SHA-256).
export async function sameSecret(given, expected) {
	if (typeof given !== 'string' || typeof expected !== 'string' || !given || !expected) return false;
	const [a, b] = await Promise.all([given, expected].map((s) => crypto.subtle.digest('SHA-256', enc.encode(s))));
	const x = new Uint8Array(a);
	const y = new Uint8Array(b);
	let diff = 0;
	for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
	return diff === 0;
}

// Your tools' requests: "Authorization: Bearer <LINK_ADMIN_TOKEN>" (32 characters at least).
export async function adminAuthorized(request, env) {
	if (!env.LINK_ADMIN_TOKEN || env.LINK_ADMIN_TOKEN.length < 32) return false;
	return sameSecret(bearer(request), env.LINK_ADMIN_TOKEN);
}

// The request's JSON body, or null (too big, or not JSON).
export async function readJson(request, limit) {
	const text = await request.text();
	if (text.length > limit) return null;
	try {
		return JSON.parse(text);
	} catch {
		return null;
	}
}

export function hexToBytes(hex) {
	const out = new Uint8Array(hex.length / 2);
	for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
	return out;
}

export function bytesToHex(bytes) {
	return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

export function b64urlEncode(bytes) {
	let out = '';
	for (let i = 0; i < bytes.length; i += 3) {
		const n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
		const chars = i + 2 < bytes.length ? 4 : i + 1 < bytes.length ? 3 : 2;
		for (let j = 0; j < chars; j++) out += B64[(n >> (18 - 6 * j)) & 63];
	}
	return out;
}

export function b64urlDecode(s) {
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

## The reference Worker

`web/worker/link-worker.js`, the whole module: a complete Worker on the core, with the Discord role
as its `promote()`. The `ADAPT` comment marks the one function a same-site page would connect to
its login (step 4); the GitHub Pages page never needs it.

<!-- block: web/worker/link-worker.js -->
```js
// Olympus Link: the reference Cloudflare Worker (D1 + Discord), complete, built on link-core.mjs
// (every check lives there). web/FERN.md is the short way into your own bot, web/WORKER.md
// explains every part; the tests in web/test run this exact file against the shared vectors.
//
// Bindings and settings (wrangler.toml / dashboard): link-core.mjs lists what it reads, and
//   DISCORD_BOT_TOKEN    secret: the bot that gives the role (Manage Roles, above ROLE_ID)
//   DISCORD_PUBLIC_KEY   var: the application's public key, for the /verify slash command over HTTP
//   GUILD_ID, ROLE_ID    vars: the Olympus server and the role linked members get
//
// Routes:
//   POST /api/link/proof             the page (static, on GitHub Pages): {"text", "discordToken"}, CORS
//   POST /api/link/inbox             your watcher's inbox (read-inbox.mjs --post), admin token
//   POST /api/link/keys              the confirmer keys, admin token
//   POST /api/link/bot-code          a gateway bot asking for a member's code, admin token
//   POST /api/discord/interactions   /verify over HTTP interactions (Discord signs every request)
//   GET /api/link/me, POST /api/link/code, POST /api/link/submit: only for a page served from
//   this Worker's own site behind your own login (sessionUser); the GitHub Pages page uses /proof.
// Anything else returns null from handleLink, so it can sit in front of an existing router.

import {
	acceptProof,
	codeError,
	failure,
	handleInbox,
	handleKeys,
	handleProof,
	issueCode,
	logProof,
	readJson,
	adminAuthorized,
	allowedOrigins,
	ed25519Verify,
	hexToBytes,
	tooManyProofs,
	respond,
} from './link-core.mjs';

export {
	LINK,
	PROOF_REASONS,
	issueCode,
	checkProof,
	acceptProof,
	acceptInbox,
	parseBundle,
	proofText,
	signedMessage,
	proofCertificate,
	linkTag,
	guildPolicy,
	drawPrefix,
	drawLimit,
	drawPool,
	thresholdOf,
	drawThreshold,
	snowflakeTime,
	certFrom,
	makeCertificate,
	parseCertificate,
	verifyCertificate,
	councilAuthorityKeys,
	councilKeyId,
	councilCertificate,
	manageKeys,
	ed25519Verify,
} from './link-core.mjs';

const enc = new TextEncoder();
const now = () => Math.floor(Date.now() / 1000);

// ---------------------------------------------------------------------------
// Entry points

export default {
	async fetch(request, env, ctx) {
		return (await handleLink(request, env, ctx)) || new Response('Not found', { status: 404 });
	},
};

// ADAPT (only for the same-site routes /me, /code and /submit): the signed-in Discord user of this
// request, from YOUR login, as { id, username, global_name, avatar } - the fields of Discord's
// GET /users/@me - or null when nobody is signed in. The GitHub Pages page never needs it: it sends
// the player's Discord token to /proof, which asks Discord (web/WORKER.md, "Who is sending").
export async function sessionUser(request, env) {
	throw new Error('Olympus Link: connect sessionUser() to your Discord login (web/WORKER.md, "Who is sending")');
}

// The role, given and taken by the bot (your promote() and demote(), in the terms of acceptProof).
export const giveRole = (env) => (discordId) => discordRole(env, 'PUT', discordId);
export const takeRole = (env) => (discordId) => discordRole(env, 'DELETE', discordId);

export async function handleLink(request, env, ctx, { getUser = sessionUser } = {}) {
	const url = new URL(request.url);
	const route = `${request.method} ${url.pathname.replace(/\/+$/, '')}`;
	const roles = { promote: giveRole(env), demote: takeRole(env) };
	try {
		switch (route) {
			case 'OPTIONS /api/link/proof':
			case 'POST /api/link/proof':
				return await handleProof(request, env, roles);
			case 'POST /api/link/inbox':
				return await handleInbox(request, env, roles);
			case 'POST /api/link/keys':
				return await handleKeys(request, env);
			case 'POST /api/link/bot-code':
				return await routeBotCode(request, env);
			case 'POST /api/discord/interactions':
				return await routeInteractions(request, env);
			case 'GET /api/link/me':
				return await routeMe(request, env, getUser);
			case 'POST /api/link/code':
				return await routeCode(request, env, getUser);
			case 'POST /api/link/submit':
				return await routeSubmit(request, env, getUser);
			default:
				return null;
		}
	} catch (err) {
		console.error('olympus-link', route, err && err.stack ? err.stack : err);
		return respond(failure('server', 'Something went wrong on our side.'), {}, 500);
	}
}

// acceptProof with this Worker's role: the old name, kept for the tests and tools that use it.
// opts.userId: the signed-in user, who must own the code (the page); absent for the watcher.
export function acceptBundle(env, text, opts = {}) {
	return acceptProof(env, text, { discordId: opts.userId, t: opts.t, promote: giveRole(env), demote: takeRole(env) });
}

// ---------------------------------------------------------------------------
// Routes

// For a gateway bot (discord.js, discord.py...) instead of HTTP interactions: it asks the Worker
// for the member's code and replies with it, ephemeral.
async function routeBotCode(request, env) {
	if (!(await adminAuthorized(request, env))) return respond(failure('auth', 'Wrong admin token.'));
	const body = await readJson(request, 4 * 1024);
	if (!body || typeof body.id !== 'string' || typeof body.username !== 'string') return respond(failure('format', 'Send {"id", "username"}.'));
	const r = await issueCode(env, { id: body.id, username: body.username }, 'discord');
	if (!r.ok) return respond(r, {}, r.reason === 'limit' ? 429 : 400);
	return respond({ token: r.token, command: r.command, exp: r.exp, mode: r.mode, reply: r.reply });
}

// /verify over HTTP interactions (Discord signs every request). /link is answered the same way.
async function routeInteractions(request, env) {
	const sig = request.headers.get('X-Signature-Ed25519') || '';
	const ts = request.headers.get('X-Signature-Timestamp') || '';
	const body = await request.text();
	if (!/^[0-9a-fA-F]{128}$/.test(sig) || !/^[0-9]{1,20}$/.test(ts)) return new Response('Bad request signature', { status: 401 });
	if (!(await ed25519Verify(env.DISCORD_PUBLIC_KEY, hexToBytes(sig), enc.encode(ts + body)))) {
		return new Response('Bad request signature', { status: 401 });
	}
	const i = JSON.parse(body);
	if (i.type === 1) return respond({ type: 1 }); // PING
	if (i.type === 2 && i.data && (i.data.name === 'verify' || i.data.name === 'link')) {
		const user = (i.member && i.member.user) || i.user;
		const r = user ? await issueCode(env, user, 'discord') : { reply: codeError('login') };
		return respond({ type: 4, data: { flags: 64, content: r.reply } });
	}
	return respond({ type: 4, data: { flags: 64, content: 'Unknown command.' } });
}

// The same-site variant: a page served by this Worker's own site, with your login's cookie.
async function routeMe(request, env, getUser) {
	const user = await getUser(request, env);
	if (!user) return respond({ user: null }, {}, 401);
	const { id, username, global_name = null, avatar = null } = user;
	return respond({ user: { id, username, global_name, avatar } });
}

async function routeCode(request, env, getUser) {
	if (!sameOrigin(request, env)) return respond(failure('origin', 'Wrong origin.'));
	const user = await getUser(request, env);
	if (!user) return respond(failure('login', 'Sign in with Discord first.'));
	const r = await issueCode(env, user, 'site');
	if (!r.ok) return respond(r, {}, r.reason === 'limit' ? 429 : 400);
	return respond({ token: r.token, command: r.command, exp: r.exp, mode: r.mode });
}

async function routeSubmit(request, env, getUser) {
	if (!sameOrigin(request, env)) return respond(failure('origin', 'Wrong origin.'));
	const user = await getUser(request, env);
	if (!user) return respond(failure('login', 'Sign in with Discord first.'));
	const body = await readJson(request, 8 * 1024);
	if (!body || typeof body.bundle !== 'string') return respond(failure('format', 'No link in the request.'));
	const t = now();
	if (await tooManyProofs(env, user.id, t)) return respond(failure('limit', 'Too many tries: wait a while and send it again.'));
	const result = await acceptBundle(env, body.bundle.trim(), { userId: String(user.id), t });
	await logProof(env, 'site', body.bundle, result, { discordId: String(user.id), uploaded: t });
	return respond(result, {}, 200);
}

// The same-site page's POSTs carry the session cookie: only the page's own origin may send them.
function sameOrigin(request, env) {
	const origin = request.headers.get('Origin');
	const allowed = env.LINK_ORIGIN ? allowedOrigins(env) : [new URL(request.url).origin];
	return !!origin && allowed.includes(origin);
}

// ---------------------------------------------------------------------------
// Discord

// { ok } or { ok: false, reason }: never throws (a network error is Discord being down).
async function discordRole(env, method, discordId) {
	let res;
	try {
		res = await fetch(`https://discord.com/api/v10/guilds/${env.GUILD_ID}/members/${discordId}/roles/${env.ROLE_ID}`, {
			method,
			headers: { Authorization: `Bot ${env.DISCORD_BOT_TOKEN}`, 'X-Audit-Log-Reason': 'Olympus Link' },
		});
	} catch (err) {
		console.error('olympus-link: Discord role', method, 'fetch failed:', err && err.message ? err.message : err);
		return { ok: false, reason: 'discord' };
	}
	if (res.ok) return { ok: true };
	let code = 0;
	try {
		code = (await res.json()).code;
	} catch {}
	if (res.status === 404 && code === 10007) return { ok: false, reason: 'not-in-server' }; // Unknown Member
	console.error('olympus-link: Discord role', method, res.status, code);
	return { ok: false, reason: 'discord' };
}

```

## Running the tests

```sh
node --test web/test          # from the repository root (Node 22.13 or newer)
```

They run the page's logic and its one request, the core and this Worker (D1 is `node:sqlite`
with the schema above, Discord a stub, `promote()` a recorder), the key tool, the inbox tool and
the QR reading against the shared vectors, and nothing touches the network
(`web/test/link-core.test.mjs` is the core's alone). Where the addon's `tests/fixtures` are in the checkout, they also check
the addon's sample codes, certificates and links; `OLYMPUS_ADDON_FIXTURES=<folder>` points at
another copy of them.
