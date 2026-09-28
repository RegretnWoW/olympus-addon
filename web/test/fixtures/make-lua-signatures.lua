-- Writes web/test/fixtures/lua-signatures.json: signatures made by the addon's own Ed25519
-- (Olympus/Ed25519.lua), which web/test/ed25519.test.mjs verifies with node:crypto and compares
-- with the Python vectors. From the repository root:
--
--   luajit web/test/fixtures/make-lua-signatures.lua [path/to/Olympus/Ed25519.lua]
--
-- It signs the "ed25519" vectors of vectors.json (same seed, same message: Ed25519 is
-- deterministic, so the bytes must be Python's) and one message of its own that only a
-- verification can check. Throwaway test seeds only.

local path = arg[1] or "Olympus/Ed25519.lua"
local here = (arg[0]:match("^(.*)[/\\]") or ".") .. "/"

local ns = {}
local chunk = assert(loadfile(path))
chunk("Olympus", ns)
local Ed = assert(ns.Ed25519, "Ed25519.lua did not set ns.Ed25519")

local f = assert(io.open(here .. "vectors.json", "rb"))
local json = f:read("*a")
f:close()

-- The "ed25519" array of vectors.json (written by make-vectors.py: one field per line).
local section = assert(json:match('"ed25519": %[(.-)\n %]'), "no ed25519 section")
local vectors = {}
for entry in section:gmatch("{(.-)}") do
	vectors[#vectors + 1] = {
		name = assert(entry:match('"name": "([^"]*)"')),
		seed = assert(entry:match('"seed_hex": "(%x+)"')),
		message = entry:match('"message_hex": "(%x*)"') or "",
	}
end
assert(#vectors >= 7, "expected at least 7 vectors")

local own = "OLY4~Lua Made-ClassicBetaPvP~Olympus II~r~Alliance~00ff00ff00ff00ff~7K3M9QX2TB~0123456789abcdef~1799990999~council01~Test Councillor-ClassicBetaPvP"
vectors[#vectors + 1] = { name = "made in Lua: an OLY4 confirmation of its own", seed = vectors[4].seed, message = Ed.ToHex(own) }

local out = {
	"{",
	' "about": "Signatures made by Olympus/Ed25519.lua (web/test/fixtures/make-lua-signatures.lua), verified by web/test/ed25519.test.mjs. Throwaway test seeds only.",',
	' "producer": "Olympus/Ed25519.lua",',
	' "signatures": [',
}
for i, v in ipairs(vectors) do
	local seed = assert(Ed.FromHex(v.seed))
	local msg = assert(Ed.FromHex(v.message))
	local pk = Ed.PublicKey(seed)
	local sig = Ed.Sign(seed, msg, pk)
	assert(Ed.Verify(pk, msg, sig), "Lua does not verify its own signature: " .. v.name)
	out[#out + 1] = ('  {"name": "%s", "seed_hex": "%s", "public_hex": "%s", "message_hex": "%s", "signature_b64url": "%s"}%s'):format(
		v.name, v.seed, Ed.ToHex(pk), v.message, Ed.ToB64(sig), i < #vectors and "," or "")
end
out[#out + 1] = " ]"
out[#out + 1] = "}"

local w = assert(io.open(here .. "lua-signatures.json", "wb"))
w:write(table.concat(out, "\n"), "\n")
w:close()
print(here .. "lua-signatures.json: " .. #vectors .. " signatures")
