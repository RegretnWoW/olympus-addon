-- 1.2, the fights part: the profile (ArenaProfile.lua) and its Edit in the core window (ProfileEdit.lua), on the
-- test world: the pickers, the view model, "preview as others see me", the person card's rows.
-- Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local N = World.NAMES

local function PE(w, c) return W3.M(w, c, "ProfileEdit") end
local function Prof(w, c) return W3.M(w, c, "ArenaProfile") end

-- The global belt won by `winner` in a public title fight (the core's title fights).
local function Belt(w, cast, winner, loser, to)
	local A = cast.arbiter.ns.Arena
	local e = table.concat({ "1", "Fzz" .. winner.short:sub(1, 1):lower(), A.B36(w.clock - 600), "A", "1", A.GK(winner.guid), winner.short, "-",
		A.GK(loser.guid), loser.short, "-", "1:0", "A", "K", "3c", A.GK(cast.arbiter.guid), "prtb" }, "~")
	for _, c in ipairs(to) do w:As(c, function() c.ns.Arena.Inject("CHANNEL", cast.arbiter.name, "AE~L1~" .. e) end) end
end

print("ProfileEdit: the Edit in the core window")

test("1.2 the fights part: with the live switch off and the companion not loaded, a frame and a title picked in the Edit change the pick and the profile goes out (AP)", function()
	-- (The belt won while the switch was on: an L entry is refused while it is off.)
	local w, cast = W3.New()
	local A = cast.A
	Belt(w, cast, A, cast.B, { A, cast.spectator })
	W3.Live(w, cast.king, { live = 0 })
	w:Run(3)
	eq(A.ns.ArenaRoles.Live(), false); eq(A.companion.loaded, nil)
	local before = #w:Sent{ from = A, type = "AP" }
	eq(PE(w, A).PickFrame("none"), true)
	w:Run(0)
	eq(A.ns.ArenaProfile.Pick().frame, "none")
	eq(#w:Sent{ from = A, type = "AP", dist = "CHANNEL" }, before + 1, "sent in L whatever the live switch")
	eq(PE(w, A).PickFrame("arena-champion"), true)
	eq(PE(w, A).PickTitle("none"), true)
	w:Run(0)
	local pick = A.ns.ArenaProfile.Pick()
	eq(pick.frame, "arena-champion"); eq(pick.title, nil)
	eq(PE(w, A).PickTitle("arena-champion"), true)
	w:Run(0)
	-- What a viewer sees: the same pick, verified.
	local v = w:As(cast.spectator, cast.spectator.ns.HonorsNet.Verified, A.name, A.guid)
	eq(v.frame, "arena-champion"); eq(v.title, "arena-champion")
	eq(A.companion.loaded, nil, "the companion still not loaded")
	-- A frame he does not hold: refused, the pick unchanged.
	local ok, why = PE(w, A).PickFrame("oracle-1")
	eq(ok, false); eq(why, "frame")
	W3.NoErrors(w)
end)

test("1.2 the fights part: the Edit's view model: the rank's frame, none, every frame held; none and every title held; the nickname from the lists; 'preview as others see me' is what a viewer's Verified shows", function()
	local w, cast = W3.New()
	local A = cast.A
	Belt(w, cast, A, cast.B, { A })
	w:Run(3)
	local vm = PE(w, A).ViewModel()
	eq(vm.frames[1].key, "rank"); eq(vm.frames[2].key, "none")
	eq(vm.frames[3].key, "arena-champion"); eq(vm.frames[3].art, "gryphon-gold"); eq(vm.frames[3].shape, "winged")
	eq(vm.frames[3].selected, true, "switched on when earned")
	eq(vm.titles[1].key, "none"); eq(vm.titles[2].label, "Arena Champion")
	eq(vm.preview.frame, "arena-champion"); eq(vm.preview.titleText, "Arena Champion")
	eq(vm.preview.frameTexture, "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold")
	eq(vm.preview.markTexture, "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold-mark")
	eq(#vm.letters, 1, "the King's letter, to read again")
	-- The nickname: a step through each list, words only from them.
	eq(PE(w, A).NickStep("a", 1), true)
	eq(PE(w, A).NickStep("n", 1), true)
	vm = PE(w, A).ViewModel()
	eq(vm.nick.a, 1); eq(vm.nick.n, 2); eq(vm.nick.text, "the Unbroken Hammer", "the first epithet (a list stepped from none takes both firsts), then the next beast")
	eq(Prof(w, A).SetNick(33, 1), false, "past the list")
	eq(Prof(w, A).NickText("0.0"), nil); eq(Prof(w, A).NickText("32.32"), "the Last Murloc"); eq(Prof(w, A).NickText("x.1"), nil)
	-- The emblem: the game's icons only (ns.CouncilIconValue).
	eq(PE(w, A).Emblem("Spell_Holy_SealOfMight"), true)
	eq(PE(w, A).Emblem("bad|name"), false)
	eq(A.ns.ArenaProfile.Mine().emblem, "Spell_Holy_SealOfMight")
	-- The history switch: its Consent line (unanswered is private).
	eq(PE(w, A).ViewModel().pub, false)
	eq(PE(w, A).SetPublic(true), true)
	eq(A.ns.ArenaProfile.Mine().pub, true)
	eq(w:As(A, A.ns.Consent.Answer, "arenaHistory"), true)
	local historyItem
	for _, item in ipairs(w:As(A, A.ns.Consent.Items, "profile")) do if item.key == "arenaHistory" then historyItem = item end end
	assert(historyItem, "the real history choice is reachable in the Profile section")
	eq(w:As(A, historyItem.shown), true, "the real history choice is visible")
	local beforeRevoke = #w:Sent{ from = A, type = "AP" }
	local revoked = w:As(A, A.ns.Consent.Choose, "arenaHistory", false)
	eq(A.ns.ArenaProfile.Mine().pub, false, "the registered setter ran")
	eq(revoked, true, "the privacy page uses the real setter")
	w:Run(0)
	eq(A.ns.ArenaProfile.Mine().pub, false, "No revokes history sharing")
	eq(w:As(A, A.ns.Consent.Answer, "arenaHistory"), false)
	eq(#w:Sent{ from = A, type = "AP" }, beforeRevoke + 1, "revocation publishes the changed profile word")
	W3.NoErrors(w)
end)

test("1.2 the fights part: the Edit opens as Olympus's own panel, made on first open only, beside the Olympus window (buttons only, 24 px, Escape through ns.EscapeCloses); the icon picker inside it lists the player's honour marks first, then the game's icons", function()
	local w, cast = W3.New()
	local A = cast.A
	Belt(w, cast, A, cast.B, { A })
	w:Run(3)
	local frames = w:Frames(A, true)
	eq(A.ns.ProfileEdit.frame, nil, "nothing made before it opens")
	eq(PE(w, A).Open(), true)
	local made = w:Frames(A, true) - frames
	eq(made > 0, true)
	eq(PE(w, A).IsOpen(), true)
	PE(w, A).Close()
	PE(w, A).Open()
	eq(w:Frames(A, true) - frames, made, "made once")
	-- The chat icon's list: his honour's mark first. (The emblem's is the game's icons only: an
	-- emblem is a game icon on both ends, the design, so no honour mark is offered there; review.)
	local list = PE(w, A).IconList("icon")
	eq(type(list[1]), "table"); eq(list[1].key, "gryphon-gold"); eq(list[1].texture, "Interface\\AddOns\\Olympus\\media\\honors\\gryphon-gold-mark")
	for _, icon in ipairs(PE(w, A).IconList("emblem")) do eq(type(icon) ~= "table", true, "no honour mark as an emblem") end
	-- No game popup anywhere in the core's arena files (the source rule).
	for _, f in ipairs({ "ProfileEdit", "HonorsNet", "ArenaProfile", "ArenaFights", "ArenaLedger", "ArenaTourney" }) do
		local src = io.open(H.ADDON_DIR .. f .. ".lua"):read("*a"):gsub("%-%-[^\n]*", "")
		assert(not src:find("StaticPopup", 1, true), f)
		assert(not src:find("UISpecialFrames", 1, true), f)
	end
	W3.NoErrors(w)
end)

print("ArenaProfile: the person card, the profile's word")

test("1.2 the fights part: the person card's rows (UI.personRows): 'Rank · Title' when a verified title shows; the arena's line when the ledger knows him; nothing for an unheld title", function()
	local w, cast = W3.New()
	local viewer = cast.spectator
	Belt(w, cast, cast.A, cast.B, { viewer, cast.A })
	eq(Prof(w, cast.A).SetPick("arena-champion", "arena-champion"), true)
	w:Run(0)
	local rows = { "|cffffd200Knight|r" }
	w:As(viewer, viewer.ns.ArenaProfile.PersonRows, { name = cast.A.short, realm = cast.A.realm, rank = "Knight" }, rows)
	eq(rows[1], "|cffffd200Knight · Arena Champion|r")
	-- Without a rank row: its own row.
	rows = {}
	w:As(viewer, viewer.ns.ArenaProfile.PersonRows, { name = cast.A.short, realm = cast.A.realm }, rows)
	eq(rows[1], "|cffffd200Arena Champion|r")
	-- A forged title on someone who holds none: nothing.
	rows = { "|cffffd200Knight|r" }
	w:As(viewer, function()
		viewer.ns.Arena.Inject("CHANNEL", cast.B.name, "AP~L1~" .. table.concat({ "-", "WA", "1", "2", "60", "0.0", "-", "0", "-", "arena-champion",
			viewer.ns.Arena.B36(w.clock) }, "~"))
	end)
	w:As(viewer, viewer.ns.ArenaProfile.PersonRows, { name = cast.B.short, realm = cast.B.realm, rank = "Knight" }, rows)
	eq(rows[1], "|cffffd200Knight|r")
	eq(rows[2], viewer.ns.L.ARENA_PERSON_PROFILE, "a profile heard: the arena's line")
	viewer.ns.db.arenaOff = true
	rows = { "|cffffd200Knight|r" }
	w:As(viewer, viewer.ns.ArenaProfile.PersonRows, { name = cast.A.short, realm = cast.A.realm, rank = "Knight" }, rows)
	eq(#rows, 1, "Arena-only rows are absent while the core Arena is disabled")
	viewer.ns.db.arenaOff = nil
	viewer.ns.Arena.companionRefused = "version"
	rows = { "|cffffd200Knight|r" }
	w:As(viewer, viewer.ns.ArenaProfile.PersonRows, { name = cast.A.short, realm = cast.A.realm, rank = "Knight" }, rows)
	eq(#rows, 1, "Arena-only rows are absent after an older companion was refused")
	viewer.ns.Arena.companionRefused = nil
	W3.NoErrors(w)
end)

test("1.2 the fights part: AP carries only public-safe fields (no zone, no gold); a sender whose gk the game gives to another character is refused; one per 5 minutes per sender (a change after a minute passes)", function()
	local w, cast = W3.New()
	local A = cast.A
	eq(Prof(w, A).SetNick(3, 7), true)
	w:Run(0)
	local sent = w:Sent{ from = A, type = "AP" }
	local body = sent[#sent].msg
	local fields = {}
	for f in (body .. "~"):gmatch("([^~]*)~") do fields[#fields + 1] = f end
	eq(#fields, 13, "AP~L1~ and 11 fields")
	assert(not body:lower():find("zone", 1, true))
	eq(fields[8], "3.7")
	-- A viewer whose game says that GUID is another's: refused (past the 5 minutes since the one heard).
	local viewer = cast.spectator
	w:Run(301)
	viewer.globals.GetPlayerInfoByGUID = function() return "Mage", "MAGE", "Human", "Human", 2, "Other Person", "" end
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", A.name, body) end)
	eq(viewer.ns.ArenaProfile.Stats().refused.gk, 1)
	viewer.globals.GetPlayerInfoByGUID = function() return "Warrior", "WARRIOR", "Human", "Human", 2, "Torvin Hale", "" end
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", A.name, body) end)
	local p = w:As(viewer, viewer.ns.ArenaProfile.Of, A.name)
	eq(p.verified, true); eq(p.nick, "3.7")
	-- Again at once, the same: dropped (the rate).
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", A.name, body) end)
	eq(viewer.ns.ArenaProfile.Stats().refused.rate, 1)
	W3.NoErrors(w)
end)

test("1.2 the fights part: profile cards keep partial identity dense and carry only observed guild metadata, normalized sex and a verified worn honour, with provenance", function()
	local w, cast = W3.New()
	local viewer, A = cast.spectator, cast.A
	viewer.ns.Roster.guild = viewer.guild
	viewer.ns.Roster.members = { { full = A.name, rank = "Knight" } }
	viewer.ns.Roster.byName = { [A.name] = 3 }
	local body = table.concat({ "-", "-", "2", "3", "-", "0.0", "-", "0", "-", "-", viewer.ns.Arena.B36(w.clock) }, "~")
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", A.name, "AP~L1~" .. body) end)
	local card = Prof(w, viewer).Card(A.name)
	eq(card.class, nil); eq(card.level, nil)
	eq(card.race.v, 2); eq(card.race.src, "own")
	eq(card.gender.v, 3); eq(card.gender.src, "own")
	eq(card.sex.v, 3); eq(card.sex.src, "own")
	eq(card.guild.v, viewer.guild); eq(card.guild.src, "seen")
	eq(card.guildRank.v, "Knight"); eq(card.guildRank.src, "seen")
	eq(card.honour, nil, "an unknown or rank frame is not invented as an honour")
	local unknownBody = table.concat({ "-", "WA", "-", "1", "60", "0.0", "-", "0", "-", "-", viewer.ns.Arena.B36(w.clock) }, "~")
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", cast.B.name, "AP~L1~" .. unknownBody) end)
	local unknown = Prof(w, viewer).Card(cast.B.name)
	eq(unknown.gender, nil); eq(unknown.sex, nil, "the client's unknown UnitSex value is not promoted to a gender")
	eq(unknown.guildRank, nil, "a numeric or absent rank is not invented as a rank name")
	-- The companion's real model used to pass holes to table.concat when only race was known.
	eq(W3.Companion(w, viewer), true)
	local model = w:As(viewer, viewer.companion.own.ArenaUI.ProfileModel, A.name)
	eq(model.class, nil); eq(model.race, 2); eq(model.level, nil); eq(model.gender, 3)
	eq(#model.lines > 0, true)
	-- Own server facts and a frame this viewer has verified are separately tagged.
	A.globals.UnitSex = function() return 3 end
	Belt(w, cast, A, cast.B, { A })
	eq(Prof(w, A).SetPick("arena-champion", nil), true)
	w:Run(0)
	local own = Prof(w, A).Card(A.name)
	eq(own.gender.v, 3); eq(own.gender.src, "own")
	eq(own.guild.v, A.guild); eq(own.guildRank.v, A.rankName)
	eq(own.guild.src, "seen"); eq(own.guildRank.src, "seen")
	eq(own.honour.v, "arena-champion"); eq(own.honour.src, "verified")
	W3.NoErrors(w)
end)

-- The owner's UFC card (2026-10-04): the ledger's rating, its peak, the duels fled and the streak reach
-- the real person card, and from it the Tale of the tape.
test("1.2 the tale of the tape from the ledger: the rating and its peak, a fled duel and the streak on the real person card", function()
	local w, cast = W3.New()
	local viewer, A, B = cast.spectator, cast.A, cast.B
	local Ar = cast.arbiter.ns.Arena
	-- Two rated fights: A knocks B out, then flees the rematch (A's rating falls from its peak).
	local function Fight(fid, ago, winner, method)
		local e = table.concat({ "1", fid, Ar.B36(w.clock - ago), "A", "1", Ar.GK(A.guid), A.short, "-", Ar.GK(B.guid), B.short, "-", "1:0",
			winner, method, "3c", Ar.GK(cast.arbiter.guid), "pr" }, "~")
		w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", cast.arbiter.name, "AE~L1~" .. e) end)
	end
	eq(W3.Companion(w, viewer), true) -- (the ledger's entries live in the companion's tables)
	Fight("Fzzk1", 900, "A", "K")
	Fight("Fzzr2", 600, "B", "R")
	-- (his profile word heard, its GUID his as the game says: the card finds his ledger key through it)
	viewer.globals.GetPlayerInfoByGUID = function(guid) if guid == A.guid then return "Warrior", "WARRIOR", "Human", "Human", 2, A.short, "" end end
	local body = table.concat({ Ar.GK(A.guid), "WA", "1", "2", "60", "0.0", "-", "0", "-", "-", viewer.ns.Arena.B36(w.clock) }, "~")
	w:As(viewer, function() viewer.ns.Arena.Inject("CHANNEL", A.name, "AP~L1~" .. body) end)
	local card = Prof(w, viewer).Card(A.name)
	assert(card.record and card.rating and card.peak, "the record, the rating and the peak")
	eq(card.peak.src, "ledger")
	assert(card.peak.v > card.rating.v, "his peak (after the win) above his rating now: " .. card.peak.v .. " / " .. card.rating.v)
	eq(card.record.v.fled, 1); eq(card.record.v.streak, -1)
	local UI = viewer.companion.own.ArenaUI
	local f = w:As(viewer, UI.Card.Fighter, A.name)
	eq(f.rating, card.rating.v); eq(f.peak, card.peak.v); eq(f.fled, 1); eq(f.streak, -1)
	local found = {}
	for _, r in ipairs(w:As(viewer, UI.Card.Rows, f, "g", "window")) do found[r.label] = r.value end
	assert(found.rating and found.rating:find(tostring(card.peak.v), 1, true), "the rating row names the peak: " .. tostring(found.rating))
	eq(found.fled, "1")
	assert(found.streak and found.streak:find("L1", 1, true), tostring(found.streak))
	W3.NoErrors(w)
end)
