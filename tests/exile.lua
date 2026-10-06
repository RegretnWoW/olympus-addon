-- 1.1.6: a guild's net-off word with notice (Moderation.lua, O2). Loaded from the net-off
-- block of tests/run.lua with that block's scene (WithNetoff: the Throne's, a council of one, Test
-- Councillor) so these tests drive the real Moderation.lua, its real store and its real dialogs.
local ns, test, eq, H = ...
local M = ns.Moderation
local L = ns.L
local KING, HC = H.KING, H.HC
local WithNetoff, AsSoldier, AsKing, Printed = H.WithNetoff, H.AsSoldier, H.AsKing, H.Printed
local GUILD = "Olympus Zeus"

-- A timed word as a giver's client sends it.
local function O2(on, at, when, guild, by, reason)
	return ("O2~%s~%d~%d~%s~%s~%s"):format(on and "1" or "0", at, when, guild, by, reason or "")
end

-- The scene: no timed word kept yet, and a member of <Olympus Zeus> on this client unless a test
-- says otherwise (AsSoldier: Olympus II). Moderation's draw is put back whatever a test stubbed.
local function WithExile(fn)
	WithNetoff(function(w, K)
		local saved = { timed = ns.rdb.netoffTimed, guild = GetGuildInfo, me = ns.me, council = ns.rdb.council, random = M.random }
		local ok, err = pcall(function()
			ns.rdb.netoffTimed = nil
			ns.ResetHeld()
			w.zeus = function(name)
				GetGuildInfo = function() return GUILD, "Member", 3 end
				ns.me = (name or "Zeus Soldier") .. "-Realm"
			end
			fn(w, K)
		end)
		ns.rdb.netoffTimed, GetGuildInfo, ns.me, ns.rdb.council, M.random = saved.timed, saved.guild, saved.me, saved.council, saved.random
		if not ok then error(err, 0) end
	end)
end

local function LastSent(w) return w.sent[#w.sent] end

test("1.1.6 exile: a High Councillor exiles a guild with notice; its members see the countdown; at its time every client takes it off, its giver offline", function()
	H.WithUI(function()
		WithExile(function(w)
			-- The giver's client: the word, logged, on the channel; nothing off yet.
			AsSoldier("Test Councillor")
			local t = w.clock
			eq(M.Exile(GUILD, 1800, "treason against the Crown"), true)
			local s = LastSent(w)
			eq(s.dist, "CHANNEL"); eq(s.logged, true, "the logged API, as the net-off words")
			eq(s.msg, O2(true, t, t + 1800, GUILD, HC, "treason against the Crown"))
			assert(#s.msg <= 255)
			eq(M.Guild(GUILD), nil, "nothing is off before its time")
			assert(M.TimedFor(GUILD), "it waits")
			assert(Printed(w, L.NETOFF_EXILE_DONE:format("<" .. GUILD .. ">", date("%H:%M", t + 1800), "treason against the Crown")))

			-- A member of that guild on another client hears it: the chat line and the parchment.
			M.Reset(); ns.rdb.netoffTimed, ns.rdb.netoff = nil, nil
			w.zeus()
			w.printed = {}
			M.Handle("CHANNEL", HC, s.msg) -- (an O2 is no O1: the old handler ignores it)
			eq(M.TimedFor(GUILD), nil, "O1's handler leaves an O2 alone")
			M.HandleTimed("CHANNEL", HC, s.msg)
			local p = assert(M.TimedFor(GUILD), "taken")
			eq(p.by, HC); eq(p.when, t + 1800); eq(p.reason, "treason against the Crown")
			assert(Printed(w, M.ExileText(p)), "the chat line")
			assert(M.ExileText(p):find("High Council is exiling", 1, true) and M.ExileText(p):find("Leave it", 1, true))
			local f = assert(M.NoticeFrame(), "the parchment")
			eq(f:IsShown(), true)
			eq(f.body:GetText(), M.ExileText(p))
			eq(f.left:GetText(), L.NETOFF_EXILE_LEFT:format(30, 0), "its countdown")
			eq(f.editBox, nil, "no edit box on it")
			-- Told once per word: its repeat shows nothing again.
			f:Hide()
			local printed = #w.printed
			M.HandleTimed("CHANNEL", HC, s.msg)
			eq(#w.printed, printed, "a repeat is no news"); eq(f:IsShown(), false)
			-- Its line on the Decrees tab and The Watch's desk opens it again.
			local mine
			for _, l in ipairs(M.Lines()) do if tostring(l.text):find(L.NETOFF_EXILE_YOURS_SHORT:format(date("%H:%M", p.when)), 1, true) then mine = l end end
			assert(mine and mine.onClick, "our guild's line")
			mine.onClick()
			eq(f:IsShown(), true)
			-- The countdown, to the second.
			w.clock = t + 600
			M.RefreshNotice()
			eq(f.left:GetText(), L.NETOFF_EXILE_LEFT:format(20, 0))
			eq(M.Guild(GUILD), nil); eq(M.SelfOff(), nil, "our guild still speaks")
			-- Its time: this client takes the guild off with nobody sending anything (the giver offline).
			local sent = #w.sent
			w.clock = t + 1800
			M.Tick()
			local word = assert(M.Guild(GUILD), "off at its time")
			eq(word.by, HC); eq(word.at, t + 1800); eq(word.reason, "treason against the Crown"); eq(word.off, true)
			eq(#w.sent, sent, "a member's client sends nothing")
			assert(M.SelfOff(), "our guild is off now")
			M.RefreshNotice()
			eq(f:IsShown(), false, "the parchment goes once it applied")
			eq(M.TimedFor(GUILD), nil)
			-- Its giver's own repeat of the O1 word is the same word here.
			M.Handle("CHANNEL", HC, ("O1~g~1~%d~%s~%s~%s"):format(t + 1800, GUILD, HC, "treason against the Crown"))
			eq(M.Guild(GUILD), word, "the same word: a repeat")
		end)
	end)
end)

test("1.1.6 exile: at its time the giver's own client sends the O1 word, for the clients before 1.1.6", function()
	H.WithUI(function()
		WithExile(function(w)
			AsSoldier("Test Councillor")
			local t = w.clock
			assert(M.Exile(GUILD, 3600, "spam guild"))
			eq(LastSent(w).msg, O2(true, t, t + 3600, GUILD, HC, "spam guild"), "60 minutes")
			w.clock = t + 3600
			M.Tick()
			local found
			for _, s in ipairs(w.sent) do if s.msg == ("O1~g~1~%d~%s~%s~spam guild"):format(t + 3600, GUILD, HC) then found = s end end
			assert(found, "the O1 word at its time")
			eq(found.logged, true)
			assert(M.Guild(GUILD))
			-- And it repeats it as its own word later, as any O1 word (after its own draw, at most JITTER).
			w.clock = w.clock + M.REPEAT + M.JITTER + 1
			local before = #w.sent
			M.Tick()
			assert(#w.sent > before and w.sent[#w.sent].msg:find("^O1~g~1~"), "repeated as O1")
		end)
	end)
end)

test("1.1.6 exile: its giver or someone from higher up cancels it before its time; never another as high; a replay never brings it back", function()
	H.WithUI(function()
		WithExile(function(w)
			ns.rdb.council = { at = 1, names = { ["test councillor"] = "Test Councillor", ["other councillor"] = "Other Councillor" } }
			local OTHER = "Other Councillor-Realm"
			w.zeus()
			local t = w.clock
			local set = O2(true, t, t + 1800, GUILD, HC, "treason")
			M.HandleTimed("CHANNEL", HC, set)
			assert(M.TimedFor(GUILD))
			local f = assert(M.NoticeFrame())
			eq(f:IsShown(), true)
			-- Another councillor (as high) can't cancel it, nor replace it with an older word.
			M.HandleTimed("CHANNEL", OTHER, O2(false, t + 5, t + 1800, GUILD, OTHER, ""))
			assert(M.TimedFor(GUILD), "a councillor as high cancels nothing")
			M.HandleTimed("CHANNEL", OTHER, O2(true, t - 1, t + 1799, GUILD, OTHER, "older"))
			eq(M.TimedFor(GUILD).by, HC, "an older word of the same weight changes nothing")
			-- Nor can anyone cancel it in someone else's name (passed on).
			M.HandleTimed("CHANNEL", OTHER, O2(false, t + 5, t + 1800, GUILD, HC, ""))
			assert(M.TimedFor(GUILD), "never passed on")
			-- Its giver cancels it: the members are told and the parchment goes.
			w.printed = {}
			M.HandleTimed("CHANNEL", HC, O2(false, t + 10, t + 1800, GUILD, HC, ""))
			eq(M.TimedFor(GUILD), nil, "cancelled")
			assert(Printed(w, L.NETOFF_EXILE_YOURS_CANCELLED:format(GUILD)))
			eq(f:IsShown(), false)
			-- A replay of the word it cancelled, or of the same cancel, changes nothing.
			M.HandleTimed("CHANNEL", HC, set)
			M.HandleTimed("CHANNEL", HC, O2(false, t + 10, t + 1800, GUILD, HC, ""))
			eq(M.TimedFor(GUILD), nil, "a replay never brings it back")
			w.clock = t + 1800
			M.Tick()
			eq(M.Guild(GUILD), nil, "never applied")
			-- Given again by its giver, after his cancel: it waits again.
			M.HandleTimed("CHANNEL", HC, O2(true, t + 1800, t + 3600, GUILD, HC, "second notice"))
			eq(M.TimedFor(GUILD).reason, "second notice")

			-- The King cancels a councillor's word; a councillor never gives it again over his cancel.
			M.HandleTimed("CHANNEL", KING, O2(false, t + 1801, t + 3600, GUILD, KING, ""))
			eq(M.TimedFor(GUILD), nil, "the King cancels a councillor's word")
			M.HandleTimed("CHANNEL", HC, O2(true, t + 1802, t + 3602, GUILD, HC, "again"))
			eq(M.TimedFor(GUILD), nil, "the King's cancel stands against a councillor")
		end)
	end)
end)

test("1.1.6 exile: a cancel dated before its time that comes after it applied takes back that very word; one dated after its time does not", function()
	H.WithUI(function()
		WithExile(function(w)
			w.zeus()
			local t = w.clock
			M.HandleTimed("CHANNEL", HC, O2(true, t, t + 1800, GUILD, HC, "treason"))
			w.clock = t + 1830
			M.Tick()
			assert(M.Guild(GUILD), "applied here")
			-- Given after its time: too late, the guild stays off (the giver puts it back with /oly neton).
			M.HandleTimed("CHANNEL", HC, O2(false, t + 1820, t + 1800, GUILD, HC, ""))
			assert(M.Guild(GUILD), "a cancel after its time is late")
			-- Given before its time, heard late: this client takes it back, and says so.
			w.printed = {}
			M.HandleTimed("CHANNEL", HC, O2(false, t + 1790, t + 1800, GUILD, HC, ""))
			eq(M.Guild(GUILD), nil, "taken back")
			assert(Printed(w, L.NETOFF_YOUR_GUILD_BACK))
			eq(M.SelfOff(), nil)

			-- A newer word on that guild stays: only the very word the timed one became goes.
			M.Reset(); ns.rdb.netoffTimed, ns.rdb.netoff = nil, nil
			M.HandleTimed("CHANNEL", HC, O2(true, t, t + 1800, GUILD, HC, "treason"))
			w.clock = t + 1830
			M.Tick()
			M.Handle("CHANNEL", KING, ("O1~g~1~%d~%s~%s~%s"):format(t + 1825, GUILD, KING, "the King's own word"))
			eq(M.Guild(GUILD).by, KING)
			M.HandleTimed("CHANNEL", HC, O2(false, t + 1790, t + 1800, GUILD, HC, ""))
			eq(M.Guild(GUILD).by, KING, "the King's word stays")
		end)
	end)
end)

test("1.1.6 exile: the giver's client cancels with a click or /oly neton guild, and once it applied it puts the guild back on for the army", function()
	H.WithUI(function()
		WithExile(function(w)
			AsSoldier("Test Councillor")
			local t = w.clock
			assert(M.Exile(GUILD, 1800, "treason"))
			-- The Decrees tab's line: a click asks, then cancels.
			local line
			for _, l in ipairs(M.Lines()) do if tostring(l.text):find(L.NETOFF_EXILE_AT:format(date("%H:%M", t + 1800)), 1, true) then line = l end end
			assert(line and line.onClick, "its line, with a click for its giver")
			eq(M.MayCancel(M.TimedFor(GUILD)), true)
			SlashCmdList.OLYMPUS("neton guild " .. GUILD)
			eq(M.TimedFor(GUILD), nil, "/oly neton guild cancels the word that waits")
			eq(LastSent(w).msg, O2(false, t, t + 1800, GUILD, HC, ""), "the cancel, sent")
			eq(LastSent(w).logged, true)
			assert(Printed(w, L.NETOFF_EXILE_CANCELLED:format("<" .. GUILD .. ">")))
			eq(M.CancelExile(GUILD), false, "nothing waits any more")
			assert(Printed(w, L.NETOFF_EXILE_NONE:format("<" .. GUILD .. ">")))

			-- /oly netoff guild <name> in 30: reason gives it at once; a third notice is refused.
			SlashCmdList.OLYMPUS("netoff guild " .. GUILD .. " in 45: treason")
			eq(M.TimedFor(GUILD), nil); assert(Printed(w, L.NETOFF_EXILE_DELAY_BAD))
			-- Without its reason either: refused before any question, not after a reason typed for nothing.
			local asked = #w.popups
			w.printed = {}
			SlashCmdList.OLYMPUS("netoff guild " .. GUILD .. " in 45")
			eq(#w.popups, asked, "no question for a notice it does not offer"); assert(Printed(w, L.NETOFF_EXILE_DELAY_BAD))
			SlashCmdList.OLYMPUS("netoff guild " .. GUILD .. " in 60")
			eq(#w.popups, asked + 1, "one it offers asks why"); eq(w.popups[#w.popups].name, "OLYMPUS_EXILE_WHY")
			eq(w.popups[#w.popups].data.delay, 3600)
			w.clock = t + 2
			SlashCmdList.OLYMPUS("netoff guild " .. GUILD .. " in 30: treason")
			local p = assert(M.TimedFor(GUILD), "/oly netoff guild ... in 30")
			eq(p.when - p.at, 1800)
			-- Its time comes; then the King's cancel, dated before it, arrives late: on its giver's client
			-- the guild goes back on for the army (the clients before 1.1.6 follow that O1 word).
			w.clock = p.when
			M.Tick()
			assert(M.Guild(GUILD))
			local before = #w.sent
			M.HandleTimed("CHANNEL", KING, O2(false, p.when - 1, p.when, GUILD, KING, ""))
			eq(M.Guild(GUILD), nil, "back on")
			local back
			for i = before + 1, #w.sent do if w.sent[i].msg:find("^O1~g~0~") then back = w.sent[i] end end
			assert(back, "the giver's client puts it back on for the army")
		end)
	end)
end)

test("1.1.6 exile: only an issuer's own word, with 30 to 60 minutes' notice and a reason, never the King's guild; the word from higher up holds", function()
	H.WithUI(function() WithExile(function(w)
		AsSoldier("Watcher")
		local t = w.clock
		local function Heard(sender, msg) M.HandleTimed("CHANNEL", sender, msg) return M.TimedFor(GUILD) end
		eq(Heard("Random Guy-Realm", O2(true, t, t + 1800, GUILD, "Random Guy-Realm", "spam")), nil, "not an issuer")
		eq(Heard(HC, O2(true, t, t + 1800, GUILD, KING, "spam")), nil, "passed on in the King's name")
		eq(Heard(HC, O2(true, t, t + 600, GUILD, HC, "spam")), nil, "ten minutes is too short a notice")
		eq(Heard(HC, O2(true, t, t + 7200, GUILD, HC, "spam")), nil, "two hours is too long")
		eq(Heard(HC, O2(true, t + M.DATE_AHEAD + 5, t + M.DATE_AHEAD + 1805, GUILD, HC, "spam")), nil, "dated ahead of the server")
		eq(Heard(HC, O2(true, t, t + 1800, GUILD, HC, "")), nil, "a reason is needed")
		M.HandleTimed("CHANNEL", HC, O2(true, t, t + 1800, "Olympus", HC, "the King's"))
		eq(M.TimedFor("Olympus"), nil, "never the King's guild")
		M.HandleTimed("CHANNEL", HC, O2(true, t, t + 1800, "Horde Heroes", HC, "not ours"))
		eq(#M.TimedList(), 0, "never a guild that is not Olympus")
		eq(Heard(HC, O2(true, t - 1800 - M.EXILE_LATE - 1, t - M.EXILE_LATE - 1, GUILD, HC, "spam")), nil, "first heard well past its time")
		eq(Heard(HC, ("O2~1~%d~soon~%s~%s~spam"):format(t, GUILD, HC)), nil, "malformed")
		-- The logged API where the client has it.
		local savedInfo, savedLogged = C_ChatInfo, ns.Comm.DeliveredLogged
		C_ChatInfo = { SendAddonMessageLogged = function() end }
		ns.Comm.DeliveredLogged = function() return false end
		local ok, err = pcall(function() eq(Heard(HC, O2(true, t, t + 1800, GUILD, HC, "spam")), nil, "unlogged") end)
		C_ChatInfo, ns.Comm.DeliveredLogged = savedInfo, savedLogged
		if not ok then error(err, 0) end
		-- The King put the guild back on: a councillor's timed word never applies over it.
		M.Handle("CHANNEL", KING, ("O1~g~1~%d~%s~%s~x"):format(t - 10, GUILD, KING))
		M.Handle("CHANNEL", KING, ("O1~g~0~%d~%s~%s~"):format(t - 5, GUILD, KING))
		eq(Heard(HC, O2(true, t, t + 1800, GUILD, HC, "spam")), nil, "held by the King's word")
		AsSoldier("Test Councillor")
		eq(M.Exile(GUILD, 1800, "spam"), false)
		assert(Printed(w, L.NETOFF_HELD_HIGHER:format("<" .. GUILD .. ">")))
		eq(M.Exile("Olympus", 1800, "the King's"), false)
		assert(Printed(w, L.NETOFF_NOT_KING_GUILD))
		eq(M.Exile("Olympus II", 1800, ""), false, "a reason")
		AsSoldier("Watcher")
		eq(M.Exile("Olympus II", 1800, "spam"), false, "a soldier can't")
		assert(Printed(w, L.NETOFF_ONLY))
		-- A King's timed word: no councillor replaces it, newer or not.
		AsSoldier("Watcher")
		M.HandleTimed("CHANNEL", KING, O2(true, t, t + 3600, "Olympus II", KING, "the King's notice"))
		M.HandleTimed("CHANNEL", HC, O2(true, t + 1, t + 1801, "Olympus II", HC, "sooner"))
		eq(M.TimedFor("Olympus II").by, KING, "no word replaces one from higher up")
	end) end)
end)

test("1.1.6 exile: a giver who no longer gives words by its time: it lapses; a full list never shuts out a word from higher up", function()
	WithExile(function(w)
		AsSoldier("Watcher")
		local t = w.clock
		M.HandleTimed("CHANNEL", HC, O2(true, t, t + 1800, GUILD, HC, "treason"))
		assert(M.TimedFor(GUILD))
		-- Off the signed council list before its time.
		ns.rdb.council = { at = 2, names = {} }
		eq(M.TimedFor(GUILD), nil, "no longer waits")
		w.clock = t + 1800
		M.Tick()
		eq(M.Guild(GUILD), nil, "lapsed: nothing applied")
		ns.rdb.council = { at = 3, names = { ["test councillor"] = "Test Councillor" } }
		-- Full: a councillor's word finds no room among his own; the King's pushes out the oldest.
		ns.rdb.netoffTimed = nil
		local names = {}
		for i = 1, M.EXILE_MAX_KEPT do
			local g = "Olympus " .. string.char(64 + math.floor((i - 1) / 26) + 1) .. string.char(97 + (i - 1) % 26)
			names[#names + 1] = g
			M.HandleTimed("CHANNEL", HC, O2(true, w.clock, w.clock + 1800 + i, g, HC, "flood"))
		end
		eq(#M.TimedList(), M.EXILE_MAX_KEPT, "full")
		M.HandleTimed("CHANNEL", HC, O2(true, w.clock, w.clock + 1800, "Olympus Late", HC, "flood"))
		eq(M.TimedFor("Olympus Late"), nil, "no room")
		M.HandleTimed("CHANNEL", KING, O2(true, w.clock, w.clock + 1800, "Olympus Late", KING, "the King's"))
		assert(M.TimedFor("Olympus Late"), "the King's word finds room")
		eq(M.TimedFor(names[1]), nil, "the soonest of the lower words went")
		eq(#M.TimedList(), M.EXILE_MAX_KEPT)
	end)
end)

test("1.1.6 exile: its giver's client repeats it for late logins until its time, a few a minute; its canceller's, the cancel until the word goes", function()
	WithExile(function(w)
		AsSoldier("Test Councillor")
		M.random = function() return 0 end
		local t = w.clock
		assert(M.Exile(GUILD, 1800, "treason"))
		local word = LastSent(w).msg
		local function Count(msg)
			local n = 0
			for _, s in ipairs(w.sent) do if s.msg == msg then n = n + 1 end end
			return n
		end
		eq(M.Tick(), 0, "just sent")
		w.clock = t + M.EXILE_REPEAT + 1
		M.Tick()
		eq(Count(word), 2, "repeated")
		eq(LastSent(w).logged, true)
		w.clock = w.clock + 10
		M.Tick()
		eq(Count(word), 2, "not again so soon")
		-- A client that never gives words repeats nothing.
		AsSoldier("Watcher")
		w.clock = w.clock + M.EXILE_REPEAT + 1
		M.Tick()
		eq(Count(word), 2)
		-- The cancel, repeated by its canceller (here its giver) until the word goes from the lists:
		-- after its time too, for a client that held the word and was away when the cancel came.
		AsSoldier("Test Councillor")
		assert(M.CancelExile(GUILD))
		local cancel = LastSent(w).msg
		assert(cancel:find("^O2~0~"))
		w.clock = w.clock + M.EXILE_REPEAT + 1
		M.Tick()
		eq(Count(cancel), 2, "the cancel repeated")
		eq(Count(word), 2, "never the word it cancelled")
		w.clock = t + 1800 + M.EXILE_REPEAT + 1
		M.Tick()
		eq(Count(cancel), 3, "after its time too")
		-- Past EXILE_KEEP it is gone from the list, and nothing more goes.
		w.clock = t + 1800 + M.EXILE_KEEP + 1
		M.Tick()
		eq(next(ns.rdb.netoffTimed), nil, "pruned")
		eq(Count(cancel), 3, "none once it went")
	end)
end)

-- The review of 1.1.6: a cancel from higher up that came while the word's giver was away. His
-- client never heard it; it holds the word and, once its time has passed, sends the guild's word it
-- became. That word must not take the guild off where the cancel is held.
test("1.1.6 exile: a cancel its giver never heard holds: where it is held, the word his client sends at its time is refused", function()
	H.WithUI(function()
		WithExile(function(w)
			w.zeus()
			local t = w.clock
			M.HandleTimed("CHANNEL", HC, O2(true, t, t + 1800, GUILD, HC, "treason"))
			assert(M.TimedFor(GUILD))
			-- Ten minutes later the King cancels it, its giver away.
			w.clock = t + 600
			M.HandleTimed("CHANNEL", KING, O2(false, t + 600, t + 1800, GUILD, KING, ""))
			eq(M.TimedFor(GUILD), nil, "cancelled here")
			w.clock = t + 1800
			M.Tick()
			eq(M.Guild(GUILD), nil, "never applied here")
			-- Its giver logs in an hour later: his client sends the guild's word it became.
			w.clock = t + 1800 + 3600
			local refused = M.Stats().refused
			M.Handle("CHANNEL", HC, ("O1~g~1~%d~%s~%s~treason"):format(t + 1800, GUILD, HC))
			eq(M.Guild(GUILD), nil, "the King's cancel holds here")
			eq(M.SelfOff(), nil, "our guild still speaks")
			eq(M.Stats().refused, refused + 1, "refused, and counted")
			-- That word alone: another word of his on that guild is his word as ever (the King puts
			-- it back with /oly neton guild).
			M.Handle("CHANNEL", HC, ("O1~g~1~%d~%s~%s~spam"):format(t + 5400, GUILD, HC))
			eq(M.Guild(GUILD).reason, "spam", "a different word is taken")
		end)
	end)
end)

test("1.1.6 exile: its canceller's client answers its giver's word at once, and repeats the cancel after its time", function()
	WithExile(function(w)
		AsKing()
		M.random = function() return 0 end
		local t = w.clock
		M.HandleTimed("CHANNEL", HC, O2(true, t, t + 1800, GUILD, HC, "treason"))
		assert(M.CancelExile(GUILD), "the King cancels a councillor's word")
		local cancel = LastSent(w).msg
		eq(cancel, O2(false, t, t + 1800, GUILD, KING, ""))
		local function Count()
			local n = 0
			for _, s in ipairs(w.sent) do if s.msg == cancel then n = n + 1 end end
			return n
		end
		w.clock = t + M.EXILE_REPEAT + 1
		M.Tick()
		eq(Count(), 2, "repeated")
		-- Its giver, away when it came, is back before its time: his client repeats the timed word.
		-- Refused here (TakeTimed: "cancelled"), and answered at the next round, not EXILE_REPEAT later.
		w.clock = w.clock + 10
		M.HandleTimed("CHANNEL", HC, O2(true, t, t + 1800, GUILD, HC, "treason"))
		eq(M.TimedFor(GUILD), nil, "still cancelled")
		w.clock = w.clock + 60
		M.Tick()
		eq(Count(), 3, "answered")
		eq(LastSent(w).logged, true)
		-- After its time: still repeated, every EXILE_REPEAT.
		w.clock = t + 1800 + M.EXILE_REPEAT + 1
		M.Tick()
		eq(Count(), 4, "repeated after its time")
		w.clock = w.clock + 10
		M.Tick()
		eq(Count(), 4, "not again so soon")
		-- Its giver's client, back after its time, sends the word it became: refused here too, and
		-- answered at the next round.
		M.Handle("CHANNEL", HC, ("O1~g~1~%d~%s~%s~treason"):format(t + 1800, GUILD, HC))
		eq(M.Guild(GUILD), nil, "refused on the canceller's client")
		w.clock = w.clock + 60
		M.Tick()
		eq(Count(), 5, "answered")
	end)
end)

test("1.1.6 exile: its giver's client, back after its time, waits WARMUP before it applies the word; a cancel that came meanwhile finds it first", function()
	WithExile(function(w)
		AsSoldier("Test Councillor")
		local t = w.clock
		assert(M.Exile(GUILD, 1800, "treason"))
		local function Words(from)
			local n = 0
			for i = from + 1, #w.sent do if w.sent[i].msg:find("^O1~g~1~") then n = n + 1 end end
			return n
		end
		-- He logs off, and logs in again an hour after its time: a new session.
		w.clock = t + 1800 + 3600
		M.Reset(ns.Now())
		local before = #w.sent
		M.Tick()
		eq(M.Guild(GUILD), nil, "not applied before WARMUP")
		eq(Words(before), 0, "nor sent")
		-- The King's cancel, repeated after its time, reaches it meanwhile: it never applies.
		M.HandleTimed("CHANNEL", KING, O2(false, t + 600, t + 1800, GUILD, KING, ""))
		w.clock = w.clock + M.WARMUP + 1
		M.Tick()
		eq(M.Guild(GUILD), nil, "never applied")
		eq(Words(before), 0, "never sent")

		-- With no cancel, it applies once WARMUP passed, and its word goes out for the older addons.
		ns.rdb.netoffTimed, ns.rdb.netoff = nil, nil
		M.Reset()
		t = w.clock
		assert(M.Exile(GUILD, 1800, "treason"))
		w.clock = t + 1800 + 600
		M.Reset(ns.Now())
		before = #w.sent
		M.Tick()
		eq(M.Guild(GUILD), nil, "waits")
		w.clock = w.clock + M.WARMUP
		M.Tick()
		local word = assert(M.Guild(GUILD), "applied")
		eq(word.at, t + 1800)
		eq(Words(before), 1, "and sent")
	end)
end)

test("1.1.6 exile: clients before 1.1.6 leave O2 alone; a saved timed word is checked again at load", function()
	local savedInfo = C_ChatInfo
	local ok, err = pcall(function()
		for _, old in ipairs({ true, false }) do
			local cns, Deliver = H.FreshComm(old)
			local bad, recv = cns.Comm.Stats().bad, cns.Comm.Stats().recv
			Deliver("CHANNEL", KING, O2(true, os.time(), os.time() + 1800, GUILD, KING, "treason"))
			Deliver("CHANNEL", KING, O2(false, os.time(), os.time() + 1800, GUILD, KING, ""))
			eq(cns.Comm.Stats().bad, bad, "not a bad report")
			eq(cns.Comm.Stats().recv, recv + 2, "heard, and left alone")
		end
	end)
	C_ChatInfo = savedInfo
	if not ok then error(err, 0) end
	WithExile(function(w)
		local t = w.clock
		ns.rdb.netoffTimed = {
			["olympus zeus"] = { name = GUILD, at = t, when = t + 1800, by = HC, reason = "kept", heard = 5 },
			["olympus ii"] = { name = "Olympus II", at = t, when = t + 1800, by = HC, reason = "cancelled", cancel = { at = t + 1, by = HC } },
			["olympus storm"] = { name = "Olympus Storm", at = t, when = t + 1800, by = HC, reason = "bad cancel", cancel = { at = t + 4000, by = HC } },
			["olympus gale"] = { name = "Olympus Gale", at = t, when = t + 99999, by = HC, reason = "too long" },
			["wrong key"] = { name = "Olympus Hunters", at = t, when = t + 1800, by = HC, reason = "elsewhere" },
		}
		M.Load()
		local kept = ns.rdb.netoffTimed
		assert(kept["olympus zeus"] and M.TimedFor(GUILD), "a valid word stays")
		assert(kept["olympus ii"] and kept["olympus ii"].cancel and not M.TimedFor("Olympus II"), "its cancel stays with it")
		eq(kept["olympus storm"], nil, "a cancel that no longer reads takes its word with it")
		eq(kept["olympus gale"], nil); eq(kept["wrong key"], nil)
	end)
end)

test("1.1.6 exile with the gamepad UI: guild, time, reason and a last yes in Olympus's own dialogs; nothing is given before that yes", function()
	H.WithUI(function()
		H.LoadUI()
		H.WithGamepadUI(true, function(game)
			WithExile(function(w)
				AsSoldier("Test Councillor")
				for _, l in ipairs(M.Lines()) do if tostring(l.text):find(L.NETOFF_EXILE_ADD, 1, true) then l.onClick() end end
				eq(#game.shown, 0, "never the game's popup"); eq(#w.popups, 0)
				local f = ns.Dialog.Find("OLYMPUS_EXILE_GUILD")
				assert(f and f:IsShown() and f.editBox:IsShown(), "our dialog, with its box")
				f.editBox:SetText(GUILD)
				f.buttons[1]:Click()
				local when = assert(ns.Dialog.Find("OLYMPUS_EXILE_WHEN"), "then how long")
				eq(when.buttons[1]:GetText(), L.NETOFF_EXILE_IN:format(30)); eq(when.buttons[2]:GetText(), L.NETOFF_EXILE_IN:format(60))
				when.buttons[2]:Click()
				local why = assert(ns.Dialog.Find("OLYMPUS_EXILE_WHY"), "then why")
				why.editBox:SetText("treason")
				why.buttons[1]:Click()
				local confirm = assert(ns.Dialog.Find("OLYMPUS_EXILE_CONFIRM"), "then a last yes")
				eq(M.TimedFor(GUILD), nil, "nothing given before the yes")
				confirm.buttons[1]:Click()
				local p = assert(M.TimedFor(GUILD), "given")
				eq(p.when - p.at, 3600); eq(p.reason, "treason")
				eq(#game.shown, 0, "still never the game's popup")
				-- The cancel asks too, in our dialog.
				for _, l in ipairs(M.Lines()) do if l.onClick and tostring(l.text):find(L.NETOFF_EXILE_AT:format(date("%H:%M", p.when)), 1, true) then l.onClick() end end
				local cancel = assert(ns.Dialog.Find("OLYMPUS_EXILE_CANCEL"))
				cancel.buttons[1]:Click()
				eq(M.TimedFor(GUILD), nil, "cancelled")
				eq(#game.shown, 0)
			end)
		end)
	end)
	local src = H.Source("Moderation.lua")
	for _, api in ipairs({ "StaticPopup_Show", "MenuUtil", "GuildUninvite", "GuildRemove", "C_GuildInfo" }) do
		assert(not src:find(api, 1, true), "Moderation.lua uses " .. api)
	end
end)

test("1.1.6 exile: its strings in English and pt-BR, with the same placeholders", function()
	local pt = H.PtBR()
	local keys = { "NETOFF_EXILE_TITLE", "NETOFF_EXILE_YOURS", "NETOFF_EXILE_LEFT", "NETOFF_EXILE_RAID", "NETOFF_EXILE_YOURS_SHORT",
		"NETOFF_EXILE_YOURS_CANCELLED", "NETOFF_EXILE_AT", "NETOFF_EXILE_TIP", "NETOFF_EXILE_CLICK_CANCEL", "NETOFF_EXILE_ADD",
		"NETOFF_EXILE_ADD_TIP", "NETOFF_EXILE_DELAY_BAD", "NETOFF_EXILE_ALREADY_OFF", "NETOFF_EXILE_DONE", "NETOFF_EXILE_NONE",
		"NETOFF_EXILE_CANCELLED", "NETOFF_EXILE_GUILD_PROMPT", "NETOFF_EXILE_WHEN_PROMPT", "NETOFF_EXILE_IN", "NETOFF_EXILE_MINUTES",
		"NETOFF_EXILE_WHY_PROMPT", "NETOFF_EXILE_CONFIRM", "NETOFF_EXILE_CANCEL_CONFIRM", "HELP_NETOFF" }
	for _, k in ipairs(keys) do
		assert(rawget(L, k) and rawget(L, k) ~= k, "English: " .. k)
		assert(rawget(pt, k) and rawget(pt, k) ~= rawget(L, k), "pt-BR: " .. k)
		local a, b = {}, {}
		for p in rawget(L, k):gmatch("%%%d*[sd]") do a[#a + 1] = p end
		for p in rawget(pt, k):gmatch("%%%d*[sd]") do b[#b + 1] = p end
		eq(table.concat(b, ","), table.concat(a, ","), "the same placeholders: " .. k)
	end
	assert(L.NETOFF_EXILE_YOURS:find("Nobody is removed from the guild", 1, true))
	assert(rawget(pt, "NETOFF_EXILE_YOURS"):find("Ninguém é removido da guilda", 1, true))
end)

test("1.1.6: a client taken off the network sends no report to The Watch (Comm's backstop, Moderation.Blocks)", function()
	WithExile(function(w)
		w.zeus()
		local report = ("MR~1~R~1~%d~%s~RealmGroup~Alliance~A~Spammer Guy-Realm~0~spam"):format(w.clock, GUILD)
		eq(M.Blocks(report), false, "while its guild is on")
		M.Handle("CHANNEL", KING, ("O1~g~1~%d~%s~%s~x"):format(w.clock, GUILD, KING))
		assert(M.SelfOff(), "its guild is off")
		eq(M.Blocks(report), true, "held once its guild is off")
		eq(M.Blocks("MR~1~E~1~1~1~A~line"), true)
	end)
end)
