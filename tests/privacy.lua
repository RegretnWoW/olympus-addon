-- Final-send permissions and transfer lifetimes, using the real communication queue.
local ns, test, eq = ...
local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\]run%.lua$") or "./"
local KING = ns.KING_CHARACTER.Alliance .. "-Realm"
local TREASURER = ns.TREASURER .. "-Realm"

local function WithTransport(fn)
	local fields = { "db", "rdb", "me", "Now", "After", "Every", "On", "Fire", "Print", "Log", "RegisterEvent", "Comm", "splitNames" }
	local globals = { "GetGuildInfo", "GetTime", "GetChannelName", "JoinChannelByName", "C_ChatInfo", "GetServerTime" }
	local saved, g = {}, {}
	for _, key in ipairs(fields) do saved[key] = ns[key] end
	for _, key in ipairs(globals) do g[key] = _G[key] end
	local w = { clock = 1800000000, mono = 1000, guild = "Olympus", rank = 1, sent = {}, timers = {}, errors = {} }
	local ok, err = pcall(function()
		ns.db, ns.rdb = {}, { treasuryEpoch = ns.Treasury.EPOCH }
		ns.me, ns.splitNames = TREASURER, true
		ns.Now = function() return w.clock end
		GetTime = function() return w.mono end
		GetServerTime = function() return w.clock end
		GetGuildInfo = function() return w.guild, "Officer", w.rank end
		GetChannelName = function() return 5, "OlympusNet" end
		JoinChannelByName = function() end
		ns.Fire, ns.Print, ns.Log, ns.RegisterEvent, ns.On, ns.Every = function() end, function() end, function() end, function() end, function() end, function() end
		ns.After = function(delay, _, run) w.timers[#w.timers + 1] = { at = w.mono + delay, run = run } end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function(_, msg, dist, to)
			w.sent[#w.sent + 1] = { msg = msg, dist = dist, to = to, at = w.mono }
			return not w.fail
		end }
		assert(loadfile(ROOT .. "Olympus/Comm.lua"))("Olympus", ns)
		ns.Treasury.Reset(); ns.Dues.Reset(); ns.Bank.Reset()
		ns.db.keeperShares = { [TREASURER:lower()] = true }
		ns.Comm.JoinChannel()
		function w.step(n)
			for _ = 1, n or 1 do
				w.clock, w.mono = w.clock + 1.2, w.mono + 1.2
				local later = w.timers
				w.timers = {}
				for _, timer in ipairs(later) do
					if timer.at <= w.mono then timer.run() else w.timers[#w.timers + 1] = timer end
				end
				ns.Comm.Pump()
			end
		end
		function w.count(prefix)
			local count = 0
			for _, entry in ipairs(w.sent) do if entry.msg:sub(1, #prefix) == prefix then count = count + 1 end end
			return count
		end
		fn(w, ns.Treasury, ns.Dues, ns.Bank)
		ns.Treasury.Reset(); ns.Dues.Reset(); ns.Bank.Reset()
	end)
	for _, key in ipairs(fields) do ns[key] = saved[key] end
	for _, key in ipairs(globals) do _G[key] = g[key] end
	if not ok then error(err, 0) end
end

test("privacy: consent withdrawal cancels queued and partly sent private books", function()
	WithTransport(function(w, T)
		assert(T.Private(KING, "TB", "TB~" .. string.rep("private", 100)))
		w.step()
		eq(w.count("TW~"), 1, "first fragment actually sent")
		T.SetConsent(false)
		w.step(100)
		eq(w.count("TW~"), 1, "no queued fragment after withdrawal")
		eq(T.PrivateState().sentTo[KING], nil, "an incomplete book is not marked delivered")
		assert(w.count("TX~") >= 1, "withdrawal still sent")
	end)
end)
test("privacy: a revoked timer cannot revive after consent is given again", function()
	WithTransport(function(w, T)
		for i = 1, 6 do ns.Comm.Whisper(KING, "Q1~busy" .. i) end
		assert(T.Private(KING, "TB", "TB~old-private-snapshot"))
		T.SetConsent(false)
		-- SetConsent(true) creates fresh snapshots; isolate the older timer's lifetime here.
		ns.db.keeperShares[TREASURER:lower()] = true
		w.step(100)
		eq(w.count("TW~"), 0, "old deferred transfer stays cancelled")
	end)
end)

test("privacy: keeper removal stops a queued transfer before its next fragment", function()
	WithTransport(function(w, T)
		local keeper = "Test Keeper-Realm"
		ns.rdb.treasuryKeepers = { at = w.clock - 1, names = { keeper }, from = KING }
		assert(T.Private(keeper, "TB", "TB~" .. string.rep("private", 100)))
		w.step()
		T.TakeKeepers(w.clock, "", KING)
		w.step(100)
		eq(w.count("TW~"), 1)
		eq(T.PrivateState().sentTo[keeper], nil)
	end)
end)

test("privacy: sister bank withdrawal cancels its independent transfer lifetime", function()
	WithTransport(function(w, T, _, B)
		w.guild = "Olympus II"
		ns.me = "Sister Officer-Realm"
		ns.Comm.CheckMembership()
		B.SetSisterConsent(true)
		assert(T.Private(KING, "TS", "TS~Olympus II~" .. string.rep("private", 100)))
		w.step(2) -- the guild transition's Q1 uses the first slot
		eq(w.count("TW~TS~"), 1, "a bank fragment is already in flight")
		B.SetSisterConsent(false)
		w.step(100)
		eq(w.count("TW~TS~"), 1)
		eq(T.PrivateState().sentTo[KING], nil)
	end)
end)

test("privacy: guild changes invalidate waiting private snapshots", function()
	WithTransport(function(w, T)
		assert(T.Private(KING, "TB", "TB~" .. string.rep("private", 100)))
		w.guild = "Olympus II"
		w.step(100)
		eq(w.count("TW~"), 0)
		eq(T.PrivateState().sentTo[KING], nil)
	end)
end)

test("privacy: queued public snapshots respect current consent and public switches", function()
	WithTransport(function(w, T)
		ns.rdb.treasuryFlags = { balance = true, ranking = true, book = true }
		T.Share(true)
		T.SetConsent(false)
		w.step(5)
		eq(w.count("TB~"), 0, "queued book cannot follow withdrawal")
		eq(w.count("T8~"), 0, "the legacy copy is withdrawn too")
		ns.db.keeperShares[TREASURER:lower()] = true
		local book = T.BookOf(TREASURER, true)
		book.lines, book.sums = {}, nil
		for i = 1, 15 do
			book.lines[i] = { name = "Private Donor" .. string.char(65 + i), money = 0,
				t = w.clock, item = 2589, count = i, how = "trade" }
		end
		assert(#T.Message() > 250, "a fragmented real book")
		T.Share(true)
		ns.rdb.treasuryFlags = { balance = false, ranking = false, book = false }
		local before = #w.sent
		w.step(100)
		eq(#w.sent, before, "old public payload cannot outlive the King's switches")
	end)
end)

test("privacy: withdrawing treasury consent drops both dues queues", function()
	WithTransport(function(w, T, D)
		local book = T.BookOf(TREASURER, true)
		book.opening, book.lines, book.sums = 0, {}, nil
		for i = 1, 60 do
			local name = "Private Donor" .. string.char(65 + math.floor(i / 26), 65 + i % 26)
			book.lines[i] = { name = name, money = 10000, t = w.clock, wk = D.Week(), guild = "Olympus II", gv = true }
		end
		D.HandleAsk("WHISPER", KING, "FQ~" .. D.Week() .. "~Olympus II~0")
		assert(#D.Outbox() > 0, "remaining answer pieces in the dues outbox")
		assert(ns.Comm.QueueSize() > 0, "first answer piece already in Comm")
		T.SetConsent(false)
		for _ = 1, 30 do D.Pump(); w.step() end
		eq(w.count("FA~"), 0)
		eq(#D.Outbox(), 0)
	end)
end)

test("privacy: recipient permission is checked when a dues answer actually sends", function()
	WithTransport(function(w, _, D)
		local saved = ns.Roster.RankOf
		local allowed = true
		ns.Roster.RankOf = function() return allowed and 1 or 3 end
		local ok, err = pcall(function()
			D.HandleAsk("WHISPER", "Captain-Realm", "FQ~" .. D.Week() .. "~Olympus~0")
			assert(ns.Comm.QueueSize() > 0)
			allowed = false
			w.step(5)
			eq(w.count("FA~"), 0)
		end)
		ns.Roster.RankOf = saved
		if not ok then error(err, 0) end
	end)
end)

test("privacy: a failed private transfer is not cached as delivered and can be sent again", function()
	WithTransport(function(w, T)
		local msg = "TB~" .. string.rep("private", 100)
		assert(T.Private(KING, "TB", msg))
		eq(T.PrivateState().sentTo[KING], nil, "queue admission is not delivery")
		w.fail = true
		w.step()
		eq(T.PrivateState().sentTo[KING], nil, "API failure never completes the book")
		w.fail = false
		assert(T.Private(KING, "TB", msg), "the same book is eligible after failure")
		w.step(30)
		local sent = T.PrivateState().sentTo[KING]
		assert(sent and sent.TB and sent.TB.msg == msg, "cached only after all send APIs succeed")
		eq(T.Private(KING, "TB", msg), false, "a completed unchanged book is still deduplicated")
	end)
end)

test("privacy: long early-supporter lists retain every TE piece across bounded batches", function()
	WithTransport(function(w, T)
		local pieces = {}
		for i = 1, 65 do pieces[i] = ("TE~Olympus~1799990000~%d~65~Early Friend"):format(i) end
		local msg = table.concat(pieces, "\n")
		assert(T.Private(KING, "TE", msg, "TE", pieces))
		w.step(30)
		eq(w.count("TE~"), 30, "first bounded batch")
		eq(T.PrivateState().sentTo[KING], nil, "not complete at the segment boundary")
		w.step(70)
		eq(w.count("TE~"), #pieces)
		local got = {}
		for _, entry in ipairs(w.sent) do
			if entry.msg:sub(1, 3) == "TE~" then got[#got + 1] = entry.msg end
		end
		eq(table.concat(got, "\n"), msg, "wire bytes and order unchanged")
		eq(T.PrivateState().sentTo[KING].TE.msg, msg)
	end)
end)

test("privacy: sharing again restores an unchanged book that withdrawal removed", function()
	WithTransport(function(w, T)
		T.HandleAsk("CHANNEL", KING, "TA~Olympus~0")
		w.step(20)
		local before = w.count("TW~TB~")
		assert(before > 0, "the first shared book completed")
		T.SetConsent(false)
		w.step(10)
		T.SetConsent(true)
		w.step(30)
		assert(w.count("TW~TB~") > before, "fresh consent restores the withdrawn book immediately")
	end)
end)

test("privacy: a busy queue defers a whole private transfer instead of forcing admission", function()
	WithTransport(function(w, T)
		T.Heard(KING); T.MarkReader(KING)
		for i = 1, 6 do ns.Comm.Whisper(KING, "Q1~busy" .. i) end
		assert(T.Private(KING, "TB", T.Message()))
		for i = 1, 260 do
			w.step()
			ns.Comm.Whisper(KING, "Q1~busy" .. i)
		end
		eq(w.count("TW~"), 0, "no forced batch after the admission deadline")
		assert(T.PrivateState().held, "normal sharing retains the pending update")
		eq(T.PrivateState().sending, nil, "the failed admission releases its transfer")
		w.step(10)
		T.FlushPrivate()
		w.step(30)
		assert(w.count("TW~TB~") > 0, "a quiet queue lets the normal share retry deliver")
	end)
end)
