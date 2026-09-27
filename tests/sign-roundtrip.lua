-- The lists scripts/council-sign.py wrote with a throwaway key (tests/sign-roundtrip.sh runs
-- this): each loads as the addon loads it, its signature holds with that key, each is newer
-- than the one before, and any change to one is refused.
--   luajit tests/sign-roundtrip.lua <repo root> <key file> <a time ahead of the clock> <list.lua>...
local root, keyPath, future = arg[1], arg[2], tonumber(arg[3])
local ns = {}
assert(loadfile(root .. "/Olympus/Sign.lua"))("Olympus", ns)
local Sign = ns.Sign

local failed = 0
local function check(cond, what)
	if cond then print("ok: " .. what) else print("FAIL: " .. what); failed = failed + 1 end
end

-- The public half of the test key (the private half stays in the file).
local f = assert(io.open(keyPath, "r"))
local keyText = f:read("*a")
f:close()
local n, mu = keyText:match('"n"%s*:%s*"0x(%x+)"'), keyText:match('"mu"%s*:%s*"0x(%x+)"')
local k = tonumber(keyText:match('"k"%s*:%s*(%d+)'))
assert(n and mu and k, "the key file has n, mu and k")

-- Each list file as the game loads it: (addon name, the addon's table).
local lists = {}
for i = 4, #arg do
	local lns = {}
	assert(loadfile(arg[i]))("Olympus", lns)
	lists[#lists + 1] = lns.COUNCIL_SIGNED
end
assert(#lists == 3, "three lists")
local function Parts(blob)
	local text, at, realm, names, sig = blob:match("^(HS1~(%d+)~([^~]*)~([^~]*))~(%x+)$")
	return text, tonumber(at), realm, names, sig
end

Sign.WithKey(n, mu, k, function()
	local last = 0
	for i, blob in ipairs(lists) do
		local text, at, _, _, sig = Parts(blob)
		check(text ~= nil and #sig == 512, "list " .. i .. " has the form the addon reads")
		check(text ~= nil and Sign.Verify(text, sig), "list " .. i .. " verifies with the test key")
		check(at and at > last, "list " .. i .. " is newer than the one before")
		last = at or last
	end
	local text1, at1, realm1, names1, sig1 = Parts(lists[1])
	local text2, _, _, _, sig2 = Parts(lists[2])
	local _, at3, realm3 = Parts(lists[3])
	check(names1 == "Test Councillor,Other Mod,F\195\160ladoriel Test", "names trimmed, an accented one byte for byte: " .. names1)
	check(realm1 == "Realm" and realm3 == "ClassicBetaPvP+ClassicBetaPvP2", "the realm group given, or Forever's")
	check(at3 > future, "newer than the last list the key signed, even ahead of the clock")
	-- Any change is refused.
	check(not Sign.Verify((text1:gsub("Other Mod", "Other Mad")), sig1), "a changed name is refused")
	check(not Sign.Verify(text1 .. ",Faker Guy", sig1), "an added name is refused")
	check(not Sign.Verify((text1:gsub("^HS1~%d+", "HS1~" .. (at1 + 1))), sig1), "a changed time is refused")
	check(not Sign.Verify((text1:gsub("~" .. realm1 .. "~", "~Other~")), sig1), "a changed realm group is refused")
	local digit = sig1:sub(-1)
	check(not Sign.Verify(text1, sig1:sub(1, -2) .. (digit == "0" and "1" or "0")), "a changed signature is refused")
	check(not Sign.Verify(text1, sig2), "another list's signature is refused")
	check(not Sign.Verify(text1, sig1:sub(2)) and not Sign.Verify(text1, "0" .. sig1), "a signature of another length is refused")
end)
-- Back to the author's key: the test key's lists are nobody's.
local text1, _, _, _, sig1 = Parts(lists[1])
check(not Sign.Verify(text1, sig1), "the author's key refuses a list of the test key")

if failed > 0 then
	print(("%d signing round trip check(s) failed"):format(failed))
	os.exit(1)
end
print("signing round trip passed")
