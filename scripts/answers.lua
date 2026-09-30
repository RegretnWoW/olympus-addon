-- The answer bank (1.1.2): docs/answers.json is the source, Olympus/AnswerBank.lua the file the
-- addon loads (the game has no JSON reader). This script writes the one from the other.
--   luajit scripts/answers.lua           write Olympus/AnswerBank.lua
--   luajit scripts/answers.lua --check   compare only: exit 1 when the file is not what it would write
-- From the repository root. tests/run.lua loads it as a module (Answers.Decode, Answers.Render) and
-- checks the same thing.

local M = {}

M.SOURCE = "docs/answers.json"
M.TARGET = "Olympus/AnswerBank.lua"
M.IN_GAME_MAX = 200 -- a chat line with room to spare (255 bytes), and no "|" (the chat's escape)
M.ANSWER_MAX = 280  -- Discord's short reply

---------------------------------------------------------------------------
-- A small JSON reader: objects, arrays, strings (with \u escapes), numbers, true, false, null.
---------------------------------------------------------------------------

local function Utf8(cp)
	if cp < 0x80 then return string.char(cp) end
	if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
	if cp < 0x10000 then
		return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
	end
	return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
		0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

function M.Decode(text)
	local pos = 1
	local function Fail(what) error(("answers.json: %s at byte %d"):format(what, pos), 0) end
	local function Space() pos = text:find("[^ \t\r\n]", pos) or #text + 1 end
	local Value
	local function String()
		pos = pos + 1
		local out = {}
		while true do
			local c = text:sub(pos, pos)
			if c == "" then Fail("unfinished string") end
			if c == '"' then pos = pos + 1 break end
			if c == "\\" then
				local e = text:sub(pos + 1, pos + 1)
				if e == "u" then
					local cp = tonumber(text:sub(pos + 2, pos + 5), 16)
					if not cp then Fail("bad \\u escape") end
					pos = pos + 6
					if cp >= 0xD800 and cp <= 0xDBFF and text:sub(pos, pos + 1) == "\\u" then
						local low = tonumber(text:sub(pos + 2, pos + 5), 16)
						if low and low >= 0xDC00 and low <= 0xDFFF then
							cp = 0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00)
							pos = pos + 6
						end
					end
					out[#out + 1] = Utf8(cp)
				elseif ESCAPES[e] then
					out[#out + 1] = ESCAPES[e]
					pos = pos + 2
				else
					Fail("bad escape")
				end
			else
				local stop = text:find('["\\]', pos) or #text + 1
				out[#out + 1] = text:sub(pos, stop - 1)
				pos = stop
			end
		end
		return table.concat(out)
	end
	function Value()
		Space()
		local c = text:sub(pos, pos)
		if c == "{" then
			pos = pos + 1
			local obj = {}
			Space()
			if text:sub(pos, pos) == "}" then pos = pos + 1 return obj end
			while true do
				Space()
				if text:sub(pos, pos) ~= '"' then Fail("a key expected") end
				local key = String()
				Space()
				if text:sub(pos, pos) ~= ":" then Fail("':' expected") end
				pos = pos + 1
				obj[key] = Value()
				Space()
				local sep = text:sub(pos, pos)
				pos = pos + 1
				if sep == "}" then return obj end
				if sep ~= "," then Fail("',' or '}' expected") end
			end
		elseif c == "[" then
			pos = pos + 1
			local arr = {}
			Space()
			if text:sub(pos, pos) == "]" then pos = pos + 1 return arr end
			while true do
				arr[#arr + 1] = Value()
				Space()
				local sep = text:sub(pos, pos)
				pos = pos + 1
				if sep == "]" then return arr end
				if sep ~= "," then Fail("',' or ']' expected") end
			end
		elseif c == '"' then
			return String()
		elseif text:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif text:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif text:sub(pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		else
			local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
			if not num or num == "" then Fail("a value expected") end
			pos = pos + #num
			return tonumber(num)
		end
	end
	local v = Value()
	Space()
	if pos <= #text then Fail("text after the end") end
	return v
end

---------------------------------------------------------------------------
-- Checks and the Lua file
---------------------------------------------------------------------------

-- The bank as the addon takes it, or an error naming what is wrong.
function M.Check(bank)
	assert(type(bank) == "table" and type(bank.meta) == "table" and type(bank.answers) == "table", "answers.json: meta and answers")
	local topics, ids = {}, {}
	for _, t in ipairs(bank.meta.topics or {}) do
		assert(type(t.id) == "string" and type(t.title) == "string", "a topic's id and title")
		topics[t.id] = true
	end
	for i, a in ipairs(bank.answers) do
		local where = ("answer %d (%s)"):format(i, tostring(a.id))
		assert(type(a.id) == "string" and a.id:match("^[%w%-%.]+$"), where .. ": id")
		assert(not ids[a.id], where .. ": id used twice")
		ids[a.id] = true
		assert(topics[a.topic], where .. ": unknown topic")
		assert(type(a.in_game) == "string" and a.in_game ~= "" and #a.in_game <= M.IN_GAME_MAX, where .. ": in_game (1 to " .. M.IN_GAME_MAX .. " bytes)")
		-- (1.1.2's review: the Chat tab's box sends no line that starts with "/", ChatWindow.lua.)
		assert(a.in_game:sub(1, 1) ~= "/", where .. ": in_game starts with '/' (the Chat tab would not send it)")
		assert(type(a.answer) == "string" and a.answer ~= "" and #a.answer <= M.ANSWER_MAX + 40, where .. ": answer")
		for _, s in ipairs({ a.in_game, a.answer }) do
			assert(not s:find("[|\r\n]"), where .. ": no '|' or line break (the chat's escape)")
		end
		assert(type(a.questions) == "table" and #a.questions > 0, where .. ": questions")
	end
	return bank
end

local function Q(s) return ("%q"):format(s) end

-- Olympus/AnswerBank.lua for `bank`: the topics in order, each answer's id, topic, questions, the
-- in-game line (text) and the longer answer (long). Nothing else (sources and notes are for us).
function M.Render(bank)
	M.Check(bank)
	local out = {
		"-- Generated by scripts/answers.lua from docs/answers.json: edit that file, then run",
		"-- luajit scripts/answers.lua (tests/run.lua fails while this one differs from it).",
		"-- The answer bank (1.1.2): short answers to what players ask, by topic. Answers.lua shows them",
		"-- (the Answers button of the author, the High Council and the Stewards) and explains each page",
		"-- and count with them. English only: these are texts to send as they are.",
		"local ADDON, ns = ...",
		"",
		"ns.ANSWER_BANK = {",
		"\ttopics = {",
	}
	for _, t in ipairs(bank.meta.topics) do
		out[#out + 1] = ("\t\t{ id = %s, title = %s },"):format(Q(t.id), Q((t.title:gsub("^%d+%.%s*", ""):gsub("%s*%(%d+%.%d+%.%d+%)$", ""))))
	end
	out[#out + 1] = "\t},"
	out[#out + 1] = "\tanswers = {"
	for _, a in ipairs(bank.answers) do
		local qs = {}
		for _, q in ipairs(a.questions) do qs[#qs + 1] = Q(q) end
		out[#out + 1] = ("\t\t{ id = %s, topic = %s,"):format(Q(a.id), Q(a.topic))
		out[#out + 1] = ("\t\t\tq = { %s },"):format(table.concat(qs, ", "))
		out[#out + 1] = ("\t\t\ttext = %s,"):format(Q(a.in_game))
		out[#out + 1] = ("\t\t\tlong = %s },"):format(Q(a.answer))
	end
	out[#out + 1] = "\t},"
	out[#out + 1] = "}"
	return table.concat(out, "\n") .. "\n"
end

local function Read(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- The Lua file's text as docs/answers.json makes it (root: the repository's folder, with its "/").
function M.Expected(root)
	local json = assert(Read((root or "") .. M.SOURCE), "cannot read " .. M.SOURCE)
	return M.Render(M.Decode(json))
end

function M.Main(args)
	local check = args and args[1] == "--check"
	local want = M.Expected("")
	local have = Read(M.TARGET)
	if check then
		if have ~= want then
			io.stderr:write(M.TARGET .. " is not what " .. M.SOURCE .. " makes: run luajit scripts/answers.lua\n")
			os.exit(1)
		end
		print(M.TARGET .. " matches " .. M.SOURCE)
		return
	end
	if have == want then
		print(M.TARGET .. " is up to date")
		return
	end
	local f = assert(io.open(M.TARGET, "wb"))
	f:write(want)
	f:close()
	print("wrote " .. M.TARGET)
end

-- Run as a script (not loaded by the tests).
if arg and type(arg[0]) == "string" and arg[0]:match("answers%.lua$") then M.Main(arg) end

return M
