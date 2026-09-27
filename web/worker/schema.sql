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

-- Confirmer public keys. Confirm-only: they sign OLY4 confirmations and nothing else.
CREATE TABLE IF NOT EXISTS keys (
  key_id           TEXT PRIMARY KEY                -- [a-z0-9]{6,16}, never reused
                   CHECK (length(key_id) BETWEEN 6 AND 16 AND key_id NOT GLOB '*[^a-z0-9]*'),
  public_key       TEXT NOT NULL                   -- 64 lowercase hex (Ed25519)
                   CHECK (length(public_key) = 64 AND public_key NOT GLOB '*[^0-9a-f]*'),
  owner_discord_id TEXT NOT NULL                   -- a Discord id: digits only
                   CHECK (length(owner_discord_id) BETWEEN 5 AND 25 AND owner_discord_id NOT GLOB '*[^0-9]*'),
  owner_username   TEXT,
  kind             TEXT NOT NULL CHECK (kind IN ('c', 'p')), -- councillor or drawn player (the certificate's tier)
  bootstrap        INTEGER NOT NULL DEFAULT 0,     -- 1: a councillor key trusted before its owner linked a character
  created          INTEGER NOT NULL,
  cert_exp         INTEGER,                        -- when its latest certificate expires; NULL: none issued
  replaced_at      INTEGER,                        -- a newer key of the same owner came: out of the draw, still checks until revoked
  revoked          INTEGER NOT NULL DEFAULT 0,
  revoked_at       INTEGER
);
-- One active key per Discord account: rotating replaces it, and revoking ends it.
CREATE UNIQUE INDEX IF NOT EXISTS keys_one_per_owner ON keys (owner_discord_id) WHERE revoked = 0 AND replaced_at IS NULL;

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
