-- The High Council's titles list as an Olympus 0.9.9 client takes it, for tests/run.lua: copied
-- unchanged from Olympus/Workshop.lua at the last 0.9.9 commit to that file (lines 1098-1114 and
-- 1150-1207 of `git show 88a2c3c:Olympus/Workshop.lua`): the signature budget (MayVerify,
-- RememberFalse), ReadDepartments, TakeTitles and HandleTitles, which registers the "HT" type on
-- ns.Comm. The rest it reads (ns.Sign, ns.CouncilIconValue, Workshop.COUNCIL_MAX, ns.Log...) is the
-- same in 0.9.9 and comes from the namespace and the module the tests hand it.
--   local old = loadfile("tests/fixtures/titles-0.9.9.lua")(ns, ns.Workshop)
--   old.TakeTitles(blob, sender)
local ns, current = ...
local Workshop = setmetatable({}, { __index = current })

Workshop.VERIFY_GAP, Workshop.VERIFY_MAX = 60, 6
local verifiedFrom, verifyTimes, falseLists, falseCount = {}, {}, {}, 0
local function MayVerify(sender, kind, blob, now)
	if falseLists[blob] then return false end
	local key = sender and (sender .. "~" .. kind)
	if key and now - (verifiedFrom[key] or -math.huge) < Workshop.VERIFY_GAP then return false end
	for i = #verifyTimes, 1, -1 do if now - verifyTimes[i] >= 60 then table.remove(verifyTimes, i) end end
	if #verifyTimes >= Workshop.VERIFY_MAX then return false end
	if key then verifiedFrom[key] = now end
	verifyTimes[#verifyTimes + 1] = now
	return true
end
local function RememberFalse(blob)
	if falseCount >= 100 then wipe(falseLists); falseCount = 0 end
	falseLists[blob], falseCount = true, falseCount + 1
end
function Workshop.ResetVerify() wipe(verifiedFrom); wipe(verifyTimes); wipe(falseLists); falseCount = 0 end -- tests

-- The departments and titles (0.9.9): what the addon keeps of them, whatever the list says. A
-- signed list never breaks these (the signing script refuses it first); past them, the rest is
-- left out: TITLES_BLOB bytes in all (or none of it), COUNCIL_MAX councillors, DEPTS_MAX named
-- departments of DEPT_NAME bytes, titles of TITLE_MAX bytes; a councillor once, the first time.
Workshop.TITLES_BLOB, Workshop.DEPTS_MAX, Workshop.DEPT_NAME, Workshop.TITLE_MAX = 3000, 8, 40, 48
local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function ReadDepartments(text)
	local depts, named, count, seen = {}, 0, 0, {}
	for entry in text:gmatch("[^;]+") do
		local name, icon, list = entry:match("^([^%^]*)%^([^%^]*)%^([^%^]*)$")
		name = name and Trim(name)
		if name and #name <= Workshop.DEPT_NAME and (name == "" or named < Workshop.DEPTS_MAX) then
			if name ~= "" then named = named + 1 end
			local d = { name = name, icon = ns.CouncilIconValue(icon), members = {} }
			for m in list:gmatch("[^,]+") do
				local who, title = m:match("^([^=]*)=([^=]*)$")
				who, title = who and Trim(who), title and Trim(title)
				if who and who ~= "" and #who <= 48 and #title <= Workshop.TITLE_MAX and not seen[who:lower()]
					and count < Workshop.COUNCIL_MAX then
					seen[who:lower()], count = true, count + 1
					d.members[#d.members + 1] = { name = who, title = title ~= "" and title or nil }
				end
			end
			depts[#depts + 1] = d
		end
	end
	return depts, count
end

-- A signed titles list, from the author's file or the channel: checked and kept like the names
-- (only a newer one; the same budget of signature checks).
function Workshop.TakeTitles(blob, sender)
	if type(blob) ~= "string" or #blob > Workshop.TITLES_BLOB then return false end
	local text, at, realm, public, list, sig = blob:match("^(HT1~(%d+)~([^~]*)~([01])~([^~]*))~(%x+)$")
	at = tonumber(at)
	if not at then return false end
	local t = ns.rdb.councilTitles
	if type(t) == "table" and (tonumber(t.at) or 0) >= at then return false end
	if sender and not MayVerify(sender, "HT", blob, ns.Now()) then return false end
	if not ns.Sign or not ns.Sign.Verify(text, sig) then
		if sender then
			RememberFalse(blob)
			ns.Log("High Council: a titles list from %s failed its signature", tostring(sender))
		end
		return false
	end
	local depts, n = ReadDepartments(list)
	ns.rdb.councilTitles = { at = at, public = public == "1", realm = realm ~= "" and realm or nil, depts = depts, blob = blob }
	ns.Log("High Council: a signed titles list of %d names in %d parts (%s)", n, #depts, tostring(at))
	ns.Fire("DATA_CHANGED")
	return true
end

function Workshop.HandleTitles(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" then return end
	Workshop.TakeTitles(text:match("^HT~(HT1~.*)$") or text, ns.FullName(sender))
end
ns.Comm.Handle("HT", function(...) Workshop.HandleTitles(...) end)

return Workshop
