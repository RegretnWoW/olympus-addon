#!/usr/bin/env python3
"""Signs the High Council's lists for the Olympus addon.

  python3 scripts/council-sign.py keygen                                  # once: ~/.olympus/council-key.json
  python3 scripts/council-sign.py sign "Name One,Name Two" [realm group]  # the names alone: dist/CouncilList.lua
  python3 scripts/council-sign.py council [council.json]                  # names, departments and titles: dist/CouncilList.lua
  python3 scripts/council-sign.py steward "<Name-Realm>" [Alliance|Horde] # mark the King's Steward, then sign as "council"
  python3 scripts/council-sign.py steward --remove "<Name-Realm>"         # end it: sign again without him
  python3 scripts/council-sign.py guild "<Guild Name>" [Alliance|Horde]  # approve a guild of Olympus, then sign as "council"
  python3 scripts/council-sign.py guild --remove "<Guild Name>"          # take it off: sign again without it
  python3 scripts/council-sign.py arbiter [--audit] "<Name-Realm>" [Alliance|Horde] # a signed arena arbiter (1.2), then sign as "council"
  python3 scripts/council-sign.py arbiter --remove "<Name-Realm>"        # end it: sign again without him
  python3 scripts/council-sign.py apostle "<Name-Realm>" [Alliance|Horde] # one of the Church's Twelve Apostles (1.1.6), then sign as "council"
  python3 scripts/council-sign.py apostle --remove "<Name-Realm>"        # end it: sign again without him
  python3 scripts/council-sign.py check [CouncilList.lua]                 # (or --check) read back what was signed

The private key never leaves ~/.olympus. The addon carries only the public key (Sign.lua) and
checks the signature: RSA-2048, e = 3, PKCS#1 v1.5 over SHA-256. CouncilList.lua holds the lists:
it is copied to the author's own game only (never in the repository or the public zip).

"sign" writes the name list alone (HS1, ns.COUNCIL_SIGNED), as before 0.9.9. "council" reads
the council from a JSON file (~/.olympus/council.json unless a path is given):

  {"realm": "optional realm group", "public": false,
   "departments": [{"name": "Department of War", "icon": "INV_Sword_04",
                    "members": [{"name": "First Surname", "title": "Operations Director"}]}],
   "members": [{"name": "First Surname", "title": "optional"}]}

and writes two lists: the names (HS1, every name of the departments and of "members", which
0.9.8 clients read too) and the departments and titles (HT1, ns.COUNCIL_TITLES, 0.9.9):
  HT1~<time>~<realm group>~<public 0|1>~<departments>~<signature>
  <departments>: <name>^<icon>^<First Surname>=<title>,...;...   ("members": the entry with no name)
"members" are the councillors outside any department; a title and a department's icon (a game
icon's name under Interface\\Icons, or its file number) may be left out. "public": whether
everyone sees the council in the census (until then, the councillors and the author alone).

The King's Steward (1.0.0): an optional "stewards" list in the same file names the characters
who name Hands of their own beside the King's, set up for the King what only he could set up
(the treasury's keepers and what the army sees of it) and send the Crown's decrees on every
client:

  "stewards": ["First Surname-Realm", {"name": "First Surname-Realm", "faction": "Horde"}]

A plain name is the Alliance King's Steward; the Horde gets one only when the list names one
for it. The titles list carries them in an entry of its own after the departments, one per
faction ("^steward^<faction>^<First Surname-Realm>,..."): three "^" where a department has two,
so 0.9.9 clients leave it out unread and still take, show and pass on the whole list. At most 3
per faction; a name of letters with one space at most, its realm (that realm's group) or none
(any realm of the list's group). "steward" adds one to the council file (rewritten whole, the
rest kept) and signs the council at once; "steward --remove" takes him off and signs again: the
newer list ends it on every client. "check" (or --check) reads a written CouncilList.lua back,
checks both signatures with the key and prints the names, departments and Stewards it holds.

The approved guilds (1.1): guilds of Asmon's Olympus whose names the addon's name rule leaves out
(it leaves Olympian and Olympia out on purpose) count as Olympus guilds once an optional
"guilds" list in the same file names them:

  "guilds": ["Guild Name", {"name": "Guild Name", "faction": "Horde"}]

A plain name is an Alliance guild. The titles list carries them after the Stewards, one entry per
faction ("^guilds^<faction>^<Guild Name>,..."), three "^" again, so clients before 1.1 leave it out
unread. At most 20 per faction; a name of letters and spaces, 24 characters at most, as the game
allows; each once. "guild" adds one to the council file and signs the council at once; "guild
--remove" takes it off and signs again. Both print the signed titles list whole, for pasting in
game with /oly approved paste: the first member of such a guild has no other way to get it (its
addon hears nothing of Olympus until it holds it); his addon then passes it to his guild.

The Blood Arena's signed arbiters (1.2): an optional "arbiters" list in the same file names the
characters who may arbitrate public fights and direct rehearsals on test builds, whatever the
King's own list says, one faction's at most MAX_ARBITERS; "audit": true also makes one an auditor
(he receives the arena's ledgers):

  "arbiters": ["First Surname-Realm", {"name": "First Surname-Realm", "faction": "Horde", "audit": true}]

The titles list carries them after the approved guilds, one entry per faction
("^arbiter^<faction>^<First Surname-Realm>[+a],..."), three "^" again, so clients before 1.2 leave
it out unread. A name as a Steward's (a realm of the list's group). "arbiter" adds one (with
--audit: an auditor too) and signs the council at once; "arbiter --remove" takes him off and signs
again. No arena file names the author: this entry is how his own character arbitrates too.

The Missionary Church of Olympus's Twelve Apostles (1.1.6): an optional "apostles" list in the same
file names them, at most MAX_APOSTLES per faction, set once here so they hold on every client with
nobody online (the Head of the Church, the King or the author may change them in game later, until
a newer list):

  "apostles": ["First Surname-Realm", {"name": "First Surname-Realm", "faction": "Horde"}]

The titles list carries them after the arbiters, one entry per faction
("^apostles^<faction>^<First Surname-Realm>,..."), three "^" again, so clients before 1.1.6 leave it
out unread. A name as a Steward's (a realm of the list's group). "apostle" adds one and signs the
council at once; "apostle --remove" takes him off and signs again. Asmongold is the immutable
Head of the Church, using the addon's canonical King identity. It is not an assignable Apostle
position. Remove legacy "head": true flags before signing a new list; old signed starred lists
remain readable by the addon but confer no Head authority.

Cross-guild leadership migration (1.2): absent by default, so the documented census behaviour is
unchanged. It is activated only by the deliberately explicit "leadership" object below:

  "leadership": {"mode": "enforce", "epoch": 1, "factions": ["Alliance"],
    "guilds": [{"guild": "Olympus II", "leader": "Lord Name-ClassicBetaPvP",
                "officers": ["Captain One-ClassicBetaPvP2"], "faction": "Alliance"}]}

Every character must carry an exact realm from the signed realm group. Each enforced faction gets
an entry even when its guilds list is empty (the signed empty tombstone). Once a client accepts an
enforcing entry, it remembers that one-way boundary locally: an expired, malformed, lower-epoch or
newer absent entry grants nobody and never reopens census authority. Increase "epoch" for a new
authority generation; ordinary additions/removals may keep it. The manifest lasts 14 days.

Leadership is signed separately from HT1 as one or more HA1 parts in
`ns.COUNCIL_AUTHORITY`. Each part binds the SHA-256 of the complete canonical manifest and is
independently signed. Receivers activate the one-way fail-closed boundary on the first valid part,
but grant roles only after every part of that exact set verifies and the joined digest matches.
Parts split only between guild entries. Older addon versions ignore H2/H3. The set is deliberately
bounded; the signer refuses anything beyond the addon's guild, person, part and byte limits.

Every list gets a newer time than the last one signed with the key (kept in the key file as
"last_at"): clients keep a list only if it is newer than theirs, so two lists signed in the
same second both reach them. Anything the addon would not take is refused here, before anything
is signed: a "~" or "|" or a control character anywhere; a "," in a name; a "^", ";", "=" or
"," in a name, title or department of the titles list; a name or title of more than 48 bytes, a
department of more than 40; more than 30 names, or a name twice; more than 8 departments; an icon
that is not a game icon's name or number; a list longer than the addon takes.
OLYMPUS_COUNCIL_KEY, OLYMPUS_COUNCIL_OUT and OLYMPUS_COUNCIL_JSON give other paths for the key,
the lists and the council (the tests use a throwaway key in a temporary folder).
"""
import hashlib, json, os, re, secrets, sys, time

KEY = os.environ.get("OLYMPUS_COUNCIL_KEY") or os.path.expanduser("~/.olympus/council-key.json")
OUT = os.environ.get("OLYMPUS_COUNCIL_OUT") or os.path.join("dist", "CouncilList.lua")
COUNCIL = os.environ.get("OLYMPUS_COUNCIL_JSON") or os.path.expanduser("~/.olympus/council.json")
REALM = "ClassicBetaPvP+ClassicBetaPvP2"
PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")
BASE, BITS = 1 << 24, 2048
MAX_NAMES, MAX_NAME, MAX_BLOB = 30, 48, 2000 # what the addon takes (Workshop.TakeCouncil)
MAX_TITLE, MAX_DEPT, MAX_DEPTS, MAX_TITLES_BLOB = 48, 40, 8, 3000 # and of the titles (Workshop.TakeTitles)
MAX_STEWARDS, MAX_REALM, FACTIONS = 3, 40, ("Alliance", "Horde") # the King's Steward (Core.lua: ns.ReadStewards)
MAX_GUILDS, MAX_GUILD_CHARS, MAX_GUILD_BYTES = 20, 24, 72 # the approved guilds (Core.lua: ns.ReadApprovedGuilds)
MAX_ARBITERS = 5 # the arena's signed arbiters per faction (Core.lua: ns.ReadArbiters, 1.2)
MAX_APOSTLES = 12 # the Church's Twelve Apostles per faction (Church.lua: Church.ReadApostles, 1.1.6)
MAX_LEADER_GUILDS, MAX_LEADERS_EACH, MAX_LEADERS_TOTAL = 128, 25, 512 # Authority.lua
MAX_LEADERS_EPOCH = 2 ** 31 - 1
LEADERS_DAYS = 14
MAX_AUTH_PARTS, MAX_AUTH_BODY = 8, 5000
SIG_LEN = 512 # hex digits of a signature, always (Sign.Verify)

def is_prime(n, rounds=40):
    if n < 2: return False
    for p in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        if n % p == 0: return n == p
    d, r = n - 1, 0
    while d % 2 == 0: d //= 2; r += 1
    for _ in range(rounds):
        a = secrets.randbelow(n - 3) + 2
        x = pow(a, d, n)
        if x in (1, n - 1): continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1: break
        else: return False
    return True

def prime(bits):
    while True:
        p = secrets.randbits(bits) | (1 << (bits - 1)) | 1
        if p % 3 == 2 and is_prime(p): return p

def limbs(n):
    k = 0
    while BASE ** k <= n: k += 1
    return k

def keygen():
    if os.path.exists(KEY): sys.exit("key exists: " + KEY)
    os.makedirs(os.path.dirname(os.path.abspath(KEY)), mode=0o700, exist_ok=True)
    while True:
        p, q = prime(BITS // 2), prime(BITS // 2)
        n = p * q
        if p != q and n.bit_length() == BITS: break
    lam = (p - 1) * (q - 1)
    d = pow(3, -1, lam)
    k = limbs(n)
    mu = BASE ** (2 * k) // n
    with open(os.open(KEY, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as f:
        json.dump({"n": hex(n), "d": hex(d), "mu": hex(mu), "k": k}, f)
    print("N =", format(n, "x")); print("MU =", format(mu, "x")); print("K =", k)

# The key file, rewritten whole or not at all (it holds the private key), readable by its owner only.
def save_key(key):
    tmp = KEY + ".tmp"
    if os.path.exists(tmp): os.unlink(tmp)
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as f:
        json.dump(key, f)
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, KEY)

# What the addon keeps of a name or a realm group: anything else would be dropped, cut or
# stripped on the way ("|" and control characters never cross the channel), and the list
# would no longer match its signature, or name someone else.
def plain(s, extra=""):
    return not any(c in "~|" + extra or ord(c) < 32 or ord(c) == 127 for c in s)

def check(names, realm):
    if len(names) > MAX_NAMES: sys.exit("%d names: the addon takes %d" % (len(names), MAX_NAMES))
    seen = set()
    for x in names:
        if not plain(x, ",") or len(x.encode()) > MAX_NAME: sys.exit("not a name the addon takes: %r" % x)
        if x.lower() in seen: sys.exit("named twice: %r" % x)
        seen.add(x.lower())
    if not plain(realm): sys.exit("not a realm group the addon takes: %r" % realm)

# Newer than the last list this key signed, whatever the clock says.
def next_at(key, at=None):
    return max(int(time.time() if at is None else at), int(key.get("last_at", 0)) + 1)

# A signed list must fit what the addon takes, its signature included (always SIG_LEN digits).
def fits(text, limit, what):
    if len(text.encode()) + 1 + SIG_LEN > limit: sys.exit("%s is too long for the addon (%d bytes at most)" % (what, limit))

def signature(text, key):
    n, d = int(key["n"], 16), int(key["d"], 16)
    h = hashlib.sha256(text.encode()).digest()
    em = b"\x00\x01" + b"\xff" * (256 - 3 - len(PREFIX) - len(h)) + b"\x00" + PREFIX + h
    return format(pow(int.from_bytes(em, "big"), d, n), "0%dx" % SIG_LEN)

def sign(names, realm=REALM, at=None):
    with open(KEY) as f: key = json.load(f)
    names = [x.strip() for x in names.split(",") if x.strip()]
    check(names, realm)
    at = next_at(key, at)
    text = "HS1~%d~%s~%s" % (at, realm, ",".join(names))
    fits(text, MAX_BLOB, "the list")
    sig = signature(text, key)
    key["last_at"] = at
    save_key(key)
    return text, sig

# The council file (see the top): every field checked as the addon reads it, before anything is
# signed. Returns the realm group, public, the councillors outside any department and the
# departments, as ([(name, title)], [(department, icon, [(name, title)])]).
def text_field(v, what, limit, required):
    if v is None: v = ""
    if not isinstance(v, str): sys.exit("%s is not text: %r" % (what, v))
    v = v.strip()
    if required and not v: sys.exit("%s is empty" % what)
    # Separators of the titles list: "^" between a department's parts, ";" between departments,
    # "=" and "," inside a department's list of names.
    if not plain(v, "^;=,") or len(v.encode()) > limit: sys.exit("not a %s the addon takes: %r" % (what, v))
    return v

# A game icon as ns.CouncilIconValue takes it: a file number (1 to 2^31 - 1), or a plain name.
def icon_field(v, what):
    if v is None or v == "": return ""
    if isinstance(v, int) and not isinstance(v, bool): v = str(v)
    if isinstance(v, str) and re.fullmatch(r"[0-9]+", v):
        if len(v) <= 10 and 1 <= int(v) < 2 ** 31: return str(int(v))
    elif isinstance(v, str) and re.fullmatch(r"[A-Za-z0-9_]{1,64}", v): return v
    sys.exit("not an icon the addon takes (a game icon's name or file number): %s %r" % (what, v))

def fields(obj, what, allowed):
    if not isinstance(obj, dict): sys.exit("%s is not an object: %r" % (what, obj))
    extra = sorted(set(obj) - set(allowed))
    if extra: sys.exit("%s: unknown field %r (a typo?)" % (what, extra[0]))
    return obj

def people(v, what):
    if v is None: return []
    if not isinstance(v, list): sys.exit("%s is not a list" % what)
    out = []
    for m in v:
        fields(m, what, ("name", "title"))
        out.append((text_field(m.get("name"), "name", MAX_NAME, True), text_field(m.get("title"), "title", MAX_TITLE, False)))
    return out

# A Steward's name as the addon takes it (Core.lua, StewardName): "First Surname-Realm" or
# "First Surname"; the name letters with one space at most (48 bytes), the realm letters and
# digits (40 bytes). Returned trimmed.
def steward_name(v):
    if not isinstance(v, str): sys.exit("a Steward is a name, not %r" % (v,))
    v = v.strip()
    short, dash, realm = v.partition("-")
    words = short.split(" ")
    good = plain(v, "^;=,") and 1 <= len(words) <= 2 and all(w and all(c.isalpha() for c in w) for w in words)
    good = good and len(short.encode()) <= MAX_NAME
    if dash: good = good and realm != "" and all(c.isalnum() for c in realm) and len(realm.encode()) <= MAX_REALM
    if not good: sys.exit("not a Steward's name the addon takes (First Surname-Realm): %r" % v)
    return v

# The council file's "stewards": each a name (the Alliance King's) or {"name", "faction"}.
# Returns {faction: [names]}, each faction MAX_STEWARDS at most, nobody twice, each realm one of
# the list's realm group (a Steward elsewhere would be nobody's on every client).
def read_stewards(v, realm):
    if v is None: return {}
    if not isinstance(v, list): sys.exit("stewards is not a list")
    out, seen = {}, set()
    for s in v:
        if isinstance(s, dict):
            fields(s, "a steward", ("name", "faction"))
            name, faction = s.get("name"), s.get("faction", "Alliance")
        else:
            name, faction = s, "Alliance"
        name = steward_name(name)
        if faction not in FACTIONS: sys.exit("a Steward's faction is Alliance or Horde, not %r" % (faction,))
        home = name.partition("-")[2]
        if home and realm and home not in realm.split("+"):
            sys.exit("%r is not of the list's realm group (%s)" % (name, realm))
        if name.lower() in seen: sys.exit("a Steward twice: %r" % name)
        seen.add(name.lower())
        out.setdefault(faction, []).append(name)
        if len(out[faction]) > MAX_STEWARDS: sys.exit("more than %d Stewards for the %s" % (MAX_STEWARDS, faction))
    return out

# An approved guild's name as the addon takes it (Core.lua, ApprovedName): letters and spaces, a
# letter first, 24 characters (72 bytes) at most. Returned trimmed.
def guild_name(v):
    if not isinstance(v, str): sys.exit("an approved guild is a name, not %r" % (v,))
    v = v.strip()
    good = v != "" and plain(v, "^;=,") and v[0].isalpha() and all(c.isalpha() or c == " " for c in v)
    good = good and len(v) <= MAX_GUILD_CHARS and len(v.encode()) <= MAX_GUILD_BYTES
    if not good: sys.exit("not a guild name the addon takes (letters and spaces, 24 at most): %r" % v)
    return v

# The council file's "guilds": each a name (an Alliance guild) or {"name", "faction"}. Returns
# {faction: [names]}, each faction MAX_GUILDS at most, each guild once.
def read_guilds(v):
    if v is None: return {}
    if not isinstance(v, list): sys.exit("guilds is not a list")
    out, seen = {}, set()
    for g in v:
        if isinstance(g, dict):
            fields(g, "a guild", ("name", "faction"))
            name, faction = g.get("name"), g.get("faction", "Alliance")
        else:
            name, faction = g, "Alliance"
        name = guild_name(name)
        if faction not in FACTIONS: sys.exit("a guild's faction is Alliance or Horde, not %r" % (faction,))
        if (faction, name.casefold()) in seen: sys.exit("a guild twice: %r" % name)
        seen.add((faction, name.casefold()))
        out.setdefault(faction, []).append(name)
        if len(out[faction]) > MAX_GUILDS: sys.exit("more than %d approved guilds for the %s" % (MAX_GUILDS, faction))
    return out

# The council file's "arbiters" (1.2): each a name (an Alliance arbiter) or {"name", "faction",
# "audit"}. Returns {faction: ["Name-Realm" or "Name-Realm+a"]}, each faction MAX_ARBITERS at most,
# nobody twice, each realm one of the list's realm group.
def read_arbiters(v, realm):
    if v is None: return {}
    if not isinstance(v, list): sys.exit("arbiters is not a list")
    out, seen = {}, set()
    for a in v:
        if isinstance(a, dict):
            fields(a, "an arbiter", ("name", "faction", "audit"))
            name, faction, audit = a.get("name"), a.get("faction", "Alliance"), a.get("audit", False)
        else:
            name, faction, audit = a, "Alliance", False
        if not isinstance(name, str): sys.exit("an arbiter is a name, not %r" % (name,))
        name = steward_name(name)
        if faction not in FACTIONS: sys.exit("an arbiter's faction is Alliance or Horde, not %r" % (faction,))
        if not isinstance(audit, bool): sys.exit("audit is true or false, not %r" % (audit,))
        home = name.partition("-")[2]
        if home and realm and home not in realm.split("+"):
            sys.exit("%r is not of the list's realm group (%s)" % (name, realm))
        if name.lower() in seen: sys.exit("an arbiter twice: %r" % name)
        seen.add(name.lower())
        out.setdefault(faction, []).append(name + ("+a" if audit else ""))
        if len(out[faction]) > MAX_ARBITERS: sys.exit("more than %d arbiters for the %s" % (MAX_ARBITERS, faction))
    return out

# The council file's "apostles" (1.1.6): each a name (an Alliance Apostle) or {"name", "faction",
# "head"}. Returns {faction: ["Name-Realm"]}; legacy head flags are refused, not a nomination.
# Each faction MAX_APOSTLES at most, nobody twice, each realm one of the list's realm
# group. A name of the Church's (Church.lua's WireName): 30 bytes at most.
def read_apostles(v, realm):
    if v is None: return {}
    if not isinstance(v, list): sys.exit("apostles is not a list")
    out, seen = {}, set()
    for a in v:
        head = False
        if isinstance(a, dict):
            fields(a, "an apostle", ("name", "faction", "head"))
            name, faction, head = a.get("name"), a.get("faction", "Alliance"), a.get("head", False)
            if not isinstance(head, bool): sys.exit("an apostle's head is true or false, not %r" % (head,))
        else:
            name, faction = a, "Alliance"
        if not isinstance(name, str): sys.exit("an apostle is a name, not %r" % (name,))
        name = steward_name(name)
        if len(name.partition("-")[0].encode()) > 30: sys.exit("an apostle's name is 30 bytes at most: %r" % name)
        if faction not in FACTIONS: sys.exit("an apostle's faction is Alliance or Horde, not %r" % (faction,))
        home = name.partition("-")[2]
        if home and realm and home not in realm.split("+"):
            sys.exit("%r is not of the list's realm group (%s)" % (name, realm))
        if name.partition("-")[0].lower() in seen: sys.exit("an apostle twice: %r" % name)
        seen.add(name.partition("-")[0].lower())
        if head: sys.exit("Asmongold is Head of the Church; remove legacy head flags before signing")
        out.setdefault(faction, []).append(name)
        if len(out[faction]) > MAX_APOSTLES: sys.exit("more than %d apostles for the %s" % (MAX_APOSTLES, faction))
    return out

# The dormant signed leadership migration. Absence means legacy census behaviour; only the
# explicit mode "enforce" activates the one-way client boundary. Its first character is the guild
# master (rank 0), followed by officers (rank 1). Every identity has an exact realm; nobody may
# occur twice in a faction, including under another guild. issued/expires use the wall clock, not
# HT1's monotonic ordering time (last_at can intentionally be ahead after a clock correction).
def read_leadership(v, realm):
    if v is None: return None, None, {}, None, None
    fields(v, "leadership", ("mode", "epoch", "factions", "guilds"))
    if v.get("mode") != "enforce": sys.exit("leadership mode is 'enforce'")
    epoch = v.get("epoch")
    if isinstance(epoch, bool) or not isinstance(epoch, int) or not 1 <= epoch <= MAX_LEADERS_EPOCH:
        sys.exit("leadership epoch is an integer from 1 to %d" % MAX_LEADERS_EPOCH)
    factions = v.get("factions")
    if not isinstance(factions, list) or not factions: sys.exit("leadership factions is a non-empty list")
    if any(f not in FACTIONS for f in factions): sys.exit("leadership factions contain only Alliance or Horde")
    if len(set(factions)) != len(factions): sys.exit("a leadership faction is named twice")
    listed = v.get("guilds")
    if not isinstance(listed, list): sys.exit("leadership guilds is not a list")
    realms = set(realm.split("+")) if realm else set()
    if not realms: sys.exit("signed leadership requires a realm group")
    out, guild_seen, people_seen, total = {}, set(), set(), 0
    for e in listed:
        fields(e, "a guild's leaders", ("guild", "leader", "officers", "faction"))
        guild = guild_name(e.get("guild"))
        faction = e.get("faction", "Alliance")
        if faction not in FACTIONS: sys.exit("a guild's leaders faction is Alliance or Horde, not %r" % (faction,))
        if faction not in factions: sys.exit("%r has leadership but its faction is not enforced" % guild)
        gkey = (faction, guild.casefold())
        if gkey in guild_seen: sys.exit("a guild's leaders twice: %r" % guild)
        guild_seen.add(gkey)
        officers = e.get("officers") or []
        if not isinstance(officers, list): sys.exit("officers of %r is not a list" % guild)
        if len(officers) + 1 > MAX_LEADERS_EACH: sys.exit("more than %d signed leaders of %r" % (MAX_LEADERS_EACH, guild))
        raw = [e.get("leader")] + officers
        names = []
        for value in raw:
            name = steward_name(value)
            home = name.partition("-")[2]
            if not home: sys.exit("a signed leader needs an exact realm: %r" % name)
            if home not in realms: sys.exit("%r is not of the list's realm group (%s)" % (name, realm))
            pkey = (faction, name.casefold())
            if pkey in people_seen: sys.exit("a signed leader twice: %r" % name)
            people_seen.add(pkey)
            names.append(name)
            total += 1
            if total > MAX_LEADERS_TOTAL: sys.exit("more than %d signed leaders" % MAX_LEADERS_TOTAL)
        out.setdefault(faction, []).append((guild, names))
        if len(out[faction]) > MAX_LEADER_GUILDS: sys.exit("more than %d guild leadership entries for the %s" % (MAX_LEADER_GUILDS, faction))
    issued = int(time.time())
    return epoch, factions, out, issued, issued + LEADERS_DAYS * 86400

def read_council(data):
    fields(data, "the council", ("realm", "public", "departments", "members", "stewards", "guilds", "arbiters", "apostles", "leadership"))
    realm = data.get("realm", REALM)
    if not isinstance(realm, str): sys.exit("not a realm group the addon takes: %r" % (realm,))
    public = data.get("public", False)
    if not isinstance(public, bool): sys.exit("public is true or false, not %r" % (public,))
    loose = people(data.get("members"), "members")
    listed = data.get("departments") or []
    if not isinstance(listed, list): sys.exit("departments is not a list")
    if len(listed) > MAX_DEPTS: sys.exit("%d departments: the addon takes %d" % (len(listed), MAX_DEPTS))
    depts, seen = [], set()
    for d in listed:
        fields(d, "a department", ("name", "icon", "members"))
        name = text_field(d.get("name"), "department", MAX_DEPT, True)
        if name.lower() in seen: sys.exit("a department twice: %r" % name)
        seen.add(name.lower())
        depts.append((name, icon_field(d.get("icon"), name), people(d.get("members"), name)))
    leaders_epoch, leaders_factions, leaders, issued, expires = read_leadership(data.get("leadership"), realm)
    return (realm, public, loose, depts, read_stewards(data.get("stewards"), realm), read_guilds(data.get("guilds")),
        read_arbiters(data.get("arbiters"), realm), leaders_epoch, leaders_factions, leaders, issued, expires,
        read_apostles(data.get("apostles"), realm))

def load_council(path):
    try:
        with open(path, encoding="utf-8") as f: data = json.load(f)
    except (OSError, ValueError) as e: sys.exit("cannot read the council file %s: %s" % (path, e))
    return data

# Both lists from the council file: the names (HS1) and, one second newer, the titles (HT1).
def sign_council(path):
    return sign_council_data(load_council(path))

def sign_authority(at, realm, epoch, factions, leaders, issued, expires, key):
    """Return independently signed HA1 parts, split only between complete guild entries."""
    out = []
    for faction in factions or []:
        entries = ["%s=%s" % (guild, ",".join(names)) for guild, names in leaders.get(faction, [])]
        full = "!".join(entries) or "-"
        root = hashlib.sha256(full.encode()).hexdigest()
        bodies = []
        if full == "-":
            bodies = [full]
        else:
            current = []
            for entry in entries:
                candidate = "!".join(current + [entry])
                if len(candidate.encode()) > MAX_AUTH_BODY:
                    if not current: sys.exit("one leadership guild entry exceeds %d bytes" % MAX_AUTH_BODY)
                    bodies.append("!".join(current)); current = [entry]
                else:
                    current.append(entry)
            if current: bodies.append("!".join(current))
        if len(bodies) > MAX_AUTH_PARTS:
            sys.exit("leadership needs %d signed parts; the addon takes %d" % (len(bodies), MAX_AUTH_PARTS))
        for index, body in enumerate(bodies, 1):
            text = "HA1~%d~%s~%s~enforce~%d~%d~%d~%s~%d~%d~%s" % (
                at, realm, faction, epoch, issued, expires, root, index, len(bodies), body)
            # H2~ plus chunk headers must stay under Codec's 30 * 220 logical payload bound.
            if len(text.encode()) + 1 + SIG_LEN > 6200:
                sys.exit("a signed authority part exceeds 6200 bytes")
            out.append(text + "~" + signature(text, key))
    return out

def sign_council_data(data):
    realm, public, loose, depts, stewards, guilds, arbiters, leaders_epoch, leaders_factions, leaders, leaders_issued, leaders_expires, apostles = read_council(data)
    names = [m[0] for m in loose] + [m[0] for d in depts for m in d[2]]
    check(names, realm)
    with open(KEY) as f: key = json.load(f)
    at = next_at(key)
    names_text = "HS1~%d~%s~%s" % (at, realm, ",".join(names))
    entries = ["^^" + ",".join("%s=%s" % m for m in loose)] if loose else []
    entries += ["%s^%s^%s" % (name, icon, ",".join("%s=%s" % m for m in members)) for name, icon, members in depts]
    # The King's Stewards after the departments: an entry per faction with three "^".
    entries += ["^steward^%s^%s" % (faction, ",".join(stewards[faction])) for faction in FACTIONS if stewards.get(faction)]
    # The approved guilds (1.1) after them, the same way.
    entries += ["^guilds^%s^%s" % (faction, ",".join(guilds[faction])) for faction in FACTIONS if guilds.get(faction)]
    # The arena's signed arbiters (1.2) after them, the same way.
    entries += ["^arbiter^%s^%s" % (faction, ",".join(arbiters[faction])) for faction in FACTIONS if arbiters.get(faction)]
    # The Church's Twelve Apostles (1.1.6) after them, the same way.
    entries += ["^apostles^%s^%s" % (faction, ",".join(apostles[faction])) for faction in FACTIONS if apostles.get(faction)]
    titles_text = "HT1~%d~%s~%d~%s" % (at + 1, realm, 1 if public else 0, ";".join(entries))
    fits(names_text, MAX_BLOB, "the name list")
    fits(titles_text, MAX_TITLES_BLOB, "the titles list")
    authority = sign_authority(at + 2, realm, leaders_epoch, leaders_factions, leaders, leaders_issued, leaders_expires, key) if leaders_factions else []
    signed = names_text + "~" + signature(names_text, key), titles_text + "~" + signature(titles_text, key), authority
    key["last_at"] = at + (2 if authority else 1)
    save_key(key)
    return signed

# A Lua string literal of s, byte for byte: Lua 5.1 has no \u escapes (an accented name
# written as JSON's "\u00e0" would reach the game as "u00e0", and its signature fail).
def lua_string(s):
    return '"' + "".join(chr(b) if 32 <= b < 127 and chr(b) not in '"\\' else "\\%03d" % b for b in s.encode()) + '"'

def write_out(names, titles=None, authority=None):
    if os.path.dirname(OUT): os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write("-- Local only: the High Council's lists, signed. Never commit or publish this file.\n")
        f.write("local _, ns = ...\nns.COUNCIL_SIGNED = %s\n" % lua_string(names))
        if titles: f.write("ns.COUNCIL_TITLES = %s\n" % lua_string(titles))
        if authority:
            f.write("ns.COUNCIL_AUTHORITY = {\n")
            for blob in authority: f.write(" %s,\n" % lua_string(blob))
            f.write("}\n")

# The council file rewritten whole or not at all, readable by its owner as before.
def save_council(path, data):
    tmp = path + ".tmp"
    if os.path.exists(tmp): os.unlink(tmp)
    mode = os.stat(path).st_mode & 0o777 if os.path.exists(path) else 0o600
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)

# steward <Name-Realm> [faction] | steward --remove <Name-Realm>: the council file's "stewards"
# changed, the council signed from it at once (nothing written if anything is refused).
def steward(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if len(args) not in (1, 2) or (remove and len(args) != 1): sys.exit(__doc__)
    name, faction = steward_name(args[0]), args[1] if len(args) == 2 else "Alliance"
    if faction not in FACTIONS: sys.exit("a Steward's faction is Alliance or Horde, not %r" % faction)
    data = load_council(path)
    listed = data.get("stewards") or []
    if not isinstance(listed, list): sys.exit("stewards is not a list")
    def who(s): return (s.get("name") if isinstance(s, dict) else s) or ""
    kept = [s for s in listed if not (isinstance(who(s), str) and who(s).strip().lower() == name.lower())]
    if remove and len(kept) == len(listed): sys.exit("not a Steward in %s: %r" % (path, name))
    if not remove:
        if len(kept) != len(listed): sys.exit("already a Steward: %r" % name)
        kept.append(name if faction == "Alliance" else {"name": name, "faction": faction})
    data["stewards"] = kept
    signed = sign_council_data(data)
    write_out(*signed)
    save_council(path, data)
    return signed

# guild <Guild Name> [faction] | guild --remove <Guild Name>: the council file's "guilds" changed,
# the council signed from it at once (nothing written if anything is refused).
def guild(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if len(args) not in (1, 2) or (remove and len(args) != 1): sys.exit(__doc__)
    name, faction = guild_name(args[0]), args[1] if len(args) == 2 else "Alliance"
    if faction not in FACTIONS: sys.exit("a guild's faction is Alliance or Horde, not %r" % faction)
    data = load_council(path)
    listed = data.get("guilds") or []
    if not isinstance(listed, list): sys.exit("guilds is not a list")
    def who(g): return (g.get("name") if isinstance(g, dict) else g) or ""
    def side(g): return (g.get("faction", "Alliance") if isinstance(g, dict) else "Alliance")
    same = lambda g: isinstance(who(g), str) and who(g).strip().casefold() == name.casefold() and (remove or side(g) == faction)
    kept = [g for g in listed if not same(g)]
    if remove and len(kept) == len(listed): sys.exit("not an approved guild in %s: %r" % (path, name))
    if not remove:
        if len(kept) != len(listed): sys.exit("already approved: %r" % name)
        kept.append(name if faction == "Alliance" else {"name": name, "faction": faction})
    data["guilds"] = kept
    signed = sign_council_data(data)
    write_out(*signed)
    save_council(path, data)
    return signed

# arbiter [--audit] <Name-Realm> [faction] | arbiter --remove <Name-Realm>: the council file's
# "arbiters" changed (1.2), the council signed from it at once (nothing written if refused).
def arbiter(args, path=COUNCIL):
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    audit = not remove and bool(args) and args[0] == "--audit"
    if audit: args = args[1:]
    if len(args) not in (1, 2) or (remove and len(args) != 1): sys.exit(__doc__)
    name, faction = steward_name(args[0]), args[1] if len(args) == 2 else "Alliance"
    if faction not in FACTIONS: sys.exit("an arbiter's faction is Alliance or Horde, not %r" % faction)
    data = load_council(path)
    listed = data.get("arbiters") or []
    if not isinstance(listed, list): sys.exit("arbiters is not a list")
    def who(a): return (a.get("name") if isinstance(a, dict) else a) or ""
    kept = [a for a in listed if not (isinstance(who(a), str) and who(a).strip().lower() == name.lower())]
    if remove and len(kept) == len(listed): sys.exit("not an arbiter in %s: %r" % (path, name))
    if not remove:
        if len(kept) != len(listed): sys.exit("already an arbiter: %r" % name)
        if faction == "Alliance" and not audit: kept.append(name)
        else:
            entry = {"name": name}
            if faction != "Alliance": entry["faction"] = faction
            if audit: entry["audit"] = True
            kept.append(entry)
    data["arbiters"] = kept
    signed = sign_council_data(data)
    write_out(*signed)
    save_council(path, data)
    return signed

# apostle <Name-Realm> [faction] | apostle --remove <Name-Realm>:
# the council file's "apostles" changed (1.1.6), the council signed from it at once (nothing written
# if anything is refused). The Head is canonical and cannot be nominated.
def apostle(args, path=COUNCIL):
    if args and args[0] == "--head": sys.exit("Asmongold is Head of the Church; this position cannot be nominated")
    remove = bool(args) and args[0] == "--remove"
    if remove: args = args[1:]
    if len(args) not in (1, 2) or (remove and len(args) != 1): sys.exit(__doc__)
    name, faction = steward_name(args[0]), args[1] if len(args) == 2 else "Alliance"
    if faction not in FACTIONS: sys.exit("an apostle's faction is Alliance or Horde, not %r" % faction)
    data = load_council(path)
    listed = data.get("apostles") or []
    if not isinstance(listed, list): sys.exit("apostles is not a list")
    def who(a): return (a.get("name") if isinstance(a, dict) else a) or ""
    short = name.partition("-")[0].lower()
    kept = [a for a in listed if not (isinstance(who(a), str) and who(a).strip().partition("-")[0].lower() == short)]
    if remove and len(kept) == len(listed): sys.exit("not an apostle in %s: %r" % (path, name))
    entry = name if faction == "Alliance" else {"name": name, "faction": faction}
    if not remove:
        if len(kept) != len(listed): sys.exit("already an apostle: %r" % name)
        kept.append(entry)
    data["apostles"] = kept
    signed = sign_council_data(data)
    write_out(*signed)
    save_council(path, data)
    return signed

# A Lua string literal as lua_string writes it (plain bytes and \ddd), back to its text.
def lua_unstring(s):
    out, i = bytearray(), 0
    while i < len(s):
        if s[i] == "\\":
            out.append(int(s[i + 1:i + 4])); i += 4
        else:
            out += s[i].encode(); i += 1
    return out.decode()

def verified(text, sig, n):
    if len(sig) != SIG_LEN or re.fullmatch(r"[0-9a-fA-F]+", sig) is None:
        return False
    h = hashlib.sha256(text.encode()).digest()
    em = b"\x00\x01" + b"\xff" * (256 - 3 - len(PREFIX) - len(h)) + b"\x00" + PREFIX + h
    return pow(int(sig, 16), 3, n) == int.from_bytes(em, "big")

# check [CouncilList.lua]: what a written file holds, each list's signature checked with the key.
def check_out(path=OUT):
    try:
        with open(path, encoding="utf-8") as f: lua = f.read()
    except OSError as e: sys.exit("cannot read %s: %s" % (path, e))
    with open(KEY) as f: n = int(json.load(f)["n"], 16)
    lists = {k: lua_unstring(v) for k, v in re.findall(r'^ns\.(COUNCIL_SIGNED|COUNCIL_TITLES) = "((?:[^"\\]|\\[0-9]{3})*)"$', lua, re.M)}
    authority = []
    authority_declared = re.search(r'^ns\.COUNCIL_AUTHORITY\s*=', lua, re.M) is not None
    authority_block = re.search(r'^ns\.COUNCIL_AUTHORITY = \{\n(.*?)^\}$', lua, re.M | re.S)
    if authority_block:
        authority = [lua_unstring(v) for v in re.findall(r'^ "((?:[^"\\]|\\[0-9]{3})*)",$', authority_block.group(1), re.M)]
        written = [line for line in authority_block.group(1).splitlines() if line.strip()]
        if len(written) != len(authority):
            sys.exit("%s holds a malformed signed authority table" % path)
    elif authority_declared:
        sys.exit("%s holds a malformed signed authority table" % path)
    if "COUNCIL_SIGNED" not in lists: sys.exit("%s holds no name list" % path)
    bad = False
    for kind in ("COUNCIL_SIGNED", "COUNCIL_TITLES"):
        blob = lists.get(kind)
        if blob is None: continue
        text, _, sig = blob.rpartition("~")
        good = verified(text, sig, n)
        bad = bad or not good
        parts = text.split("~")
        print("%s: %s, time %s, realm group %s" % ("names" if kind == "COUNCIL_SIGNED" else "titles",
            "signature good" if good else "SIGNATURE BAD", parts[1], parts[2] or "(any)"))
        if kind == "COUNCIL_SIGNED":
            print("  names:", parts[3] or "-")
            continue
        print("  public:", parts[3] == "1")
        stewards, guilds, arbiters, leaders, apostles = {}, {}, {}, {}, {}
        for entry in parts[4].split(";"):
            if entry.startswith("^steward^"):
                _, _, faction, names = entry.split("^", 3)
                stewards[faction] = names
            elif entry.startswith("^guilds^"):
                _, _, faction, names = entry.split("^", 3)
                guilds[faction] = names
            elif entry.startswith("^arbiter^"):
                _, _, faction, names = entry.split("^", 3)
                arbiters[faction] = names
            elif entry.startswith("^apostles^"):
                _, _, faction, names = entry.split("^", 3)
                apostles[faction] = names
            elif entry.startswith("^leaders^"):
                _, _, faction, mode, epoch, issued, expires, names = entry.split("^", 7)
                leaders[faction] = "%s (mode %s, epoch %s, issued %s, expires %s)" % (names, mode, epoch, issued, expires)
            elif entry:
                part = entry.split("^")
                print("  %s: %s" % (part[0] or "(outside any department)", part[-1] or "-"))
        for faction in FACTIONS:
            print("  the %s King's Steward: %s" % (faction, stewards.get(faction) or "none"))
        for faction in FACTIONS:
            print("  the %s's approved guilds: %s" % (faction, guilds.get(faction) or "none"))
        for faction in FACTIONS:
            print("  the %s's arena arbiters (+a: auditor): %s" % (faction, arbiters.get(faction) or "none"))
        for faction in FACTIONS:
            print("  the %s's signed leadership: %s" % (faction, leaders.get(faction) or "none"))
        for faction in FACTIONS:
            print("  the %s's Church Apostles (* the Head): %s" % (faction, apostles.get(faction) or "none"))
    sets = {}
    for blob in authority:
        text, _, sig = blob.rpartition("~")
        good = verified(text, sig, n)
        bad = bad or not good
        parts = text.split("~", 11)
        if len(parts) != 12 or parts[0] != "HA1":
            print("authority: malformed"); bad = True; continue
        _, at, realm, faction, mode, epoch, issued, expires, root, index, count, body = parts
        try:
            at_n, epoch_n, issued_n, expires_n, index_n, count_n = map(
                int, (at, epoch, issued, expires, index, count))
        except ValueError:
            print("authority: malformed numbers"); bad = True; continue
        shape = (mode == "enforce" and faction in FACTIONS and at_n >= 1577836800
            and 1 <= epoch_n <= MAX_LEADERS_EPOCH and issued_n >= 1577836800
            and issued_n < expires_n and expires_n - issued_n <= 31 * 86400
            and re.fullmatch(r"[0-9a-f]{64}", root) is not None
            and 1 <= count_n <= MAX_AUTH_PARTS and 1 <= index_n <= count_n
            and 0 < len(body.encode()) <= MAX_AUTH_BODY
            and (body != "-" or (index_n == 1 and count_n == 1)))
        if not shape:
            print("authority %s: malformed" % (faction or "?")); bad = True; continue
        key = (at, realm, faction, epoch, issued, expires, root, count)
        bodies = sets.setdefault(key, {})
        if index_n in bodies:
            print("authority %s: duplicate part %d" % (faction, index_n)); bad = True; continue
        bodies[index_n] = body
        print("authority %s %s/%s: %s" % (faction, index, count, "signature good" if good else "SIGNATURE BAD"))
    for key, bodies in sets.items():
        at, realm, faction, epoch, issued, expires, root, count = key
        count = int(count)
        if len(bodies) != count or any(i not in bodies for i in range(1, count + 1)):
            print("authority %s: PARTIAL" % faction); bad = True; continue
        full = bodies[1] if count == 1 and bodies[1] == "-" else "!".join(bodies[i] for i in range(1, count + 1))
        digest = hashlib.sha256(full.encode()).hexdigest()
        good = digest == root
        bad = bad or not good
        print("authority %s: %d part(s), epoch %s, digest %s, %d bytes" % (
            faction, count, epoch, "good" if good else "BAD", len(full.encode())))
    if bad: sys.exit("a signature does not hold with %s" % KEY)

if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "keygen": keygen()
    elif len(sys.argv) >= 3 and sys.argv[1] == "sign":
        text, sig = sign(sys.argv[2], *sys.argv[3:4])
        write_out(text + "~" + sig)
        print(OUT, "written:", text)
    elif len(sys.argv) in (2, 3) and sys.argv[1] == "council":
        names, titles, authority = sign_council(sys.argv[2] if len(sys.argv) == 3 else COUNCIL)
        write_out(names, titles, authority)
        print(OUT, "written:", names[:-SIG_LEN - 1])
        print("and:", titles[:-SIG_LEN - 1])
        if authority: print("and %d signed authority part(s)" % len(authority))
    elif len(sys.argv) >= 3 and sys.argv[1] == "steward":
        signed = steward(sys.argv[2:]); names, titles = signed[:2]
        print(COUNCIL, "updated;", OUT, "written:", names[:-SIG_LEN - 1])
        print("and:", titles[:-SIG_LEN - 1])
    elif len(sys.argv) >= 3 and sys.argv[1] == "guild":
        signed = guild(sys.argv[2:]); names, titles = signed[:2]
        print(COUNCIL, "updated;", OUT, "written:", names[:-SIG_LEN - 1])
        print("and:", titles[:-SIG_LEN - 1])
        # Whole, for the first member of an approved guild to paste in game (/oly approved paste).
        print("to paste in game with /oly approved paste:")
        print(titles)
    elif len(sys.argv) >= 3 and sys.argv[1] == "arbiter":
        signed = arbiter(sys.argv[2:]); names, titles = signed[:2]
        print(COUNCIL, "updated;", OUT, "written:", names[:-SIG_LEN - 1])
        print("and:", titles[:-SIG_LEN - 1])
    elif len(sys.argv) >= 3 and sys.argv[1] == "apostle":
        signed = apostle(sys.argv[2:]); names, titles = signed[:2]
        print(COUNCIL, "updated;", OUT, "written:", names[:-SIG_LEN - 1])
        print("and:", titles[:-SIG_LEN - 1])
    elif len(sys.argv) in (2, 3) and sys.argv[1] in ("check", "--check"):
        check_out(sys.argv[2] if len(sys.argv) == 3 else OUT)
    else: sys.exit(__doc__)
