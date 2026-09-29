-- The roll call as an Olympus 0.9.8 client answers it, for tests/run.lua: HandleRoll and what it
-- reads, copied unchanged from Olympus/Workshop.lua at the v0.9.8 tag (lines 81-85, 137-139,
-- 171-174 and 222-237 of `git show v0.9.8:Olympus/Workshop.lua`). The rest it calls
-- (Workshop.IsAuthor, Answers, Flags, Client, random, after, ROLL_GAP, ROLL_SPREAD) is the same
-- in 0.9.9 and comes from the module loaded by the tests, with their stand-ins.
--   local old = loadfile("tests/fixtures/rollcall-0.9.8.lua")(ns, ns.Workshop)
--   old.HandleRoll(dist, sender, text)
local ns, current = ...
local Workshop = setmetatable({}, { __index = current })

local lastRollAnswer = -math.huge
local answeredRoll    -- the roll call id we answered last
local authorAt, authorName -- the author's last presence, and his full name

-- His name, on his realm group (Forever's PvP realms).
local function IsAuthorName(name)
	if type(name) ~= "string" or ns.ShortName(name) ~= ns.AUTHOR then return false end
	local realm = ns.RealmOf(ns.FullName(name))
	return realm ~= nil and ns.GroupOf(realm) == ns.GroupOf(ns.AUTHOR_REALM)
end

-- Plain text: no separators, escape codes, Discord markup (` @) or control characters.
local function Clean(s, max)
	return (tostring(s or ""):gsub("[~|`@%c]", "")):sub(1, max or 40)
end

local function Answer(id)
	local flags = Workshop.Flags():gsub("[^crk]", "")
	return ("V2~%d~%s~~%s~~%s~0~0~"):format(id, Clean(ns.VERSION, 12), Workshop.Client(), flags)
end

function Workshop.HandleRoll(dist, sender, text)
	if dist ~= "CHANNEL" or not IsAuthorName(sender) or Workshop.IsAuthor() or not Workshop.Answers() then return end
	local id, share = text:match("^V1~(%d+)~(%d+)$")
	id, share = tonumber(id), tonumber(share)
	if not id or not share then return end
	authorAt, authorName = ns.Now(), ns.FullName(sender)
	local now = ns.Now()
	if id == answeredRoll or now - lastRollAnswer < Workshop.ROLL_GAP then return end
	answeredRoll = id
	if Workshop.random(1, 100) > math.max(1, math.min(100, share)) then return end
	lastRollAnswer = now
	-- Spread over ROLL_SPREAD: a thousand answers do not arrive in the same second.
	Workshop.after(1 + Workshop.random() * Workshop.ROLL_SPREAD, "roll call answer", function()
		ns.Comm.Whisper(ns.FullName(sender), Answer(id), "rollanswer")
	end)
end

return Workshop
