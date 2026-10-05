-- The CurseForge store page (1.1.5): docs/CURSEFORGE.md is the whole page, kept in step with the
-- README by the tests, and nearly twice what CurseForge's editor can save (scripts/curseforge-size.lua:
-- a body above about 100 KiB is refused). This script writes the page pasted there,
-- docs/CURSEFORGE-STORE.md, from it, the README, ROADMAP.md and the TOC's version:
--   - the same text, with the last versions' lines from ROADMAP.md (the TOC's version and the
--     ones before it, newest first) under "Recent versions", before the first "##" section;
--   - the longest sections (CUTS) cut to their opening, each with a link to the same section in
--     the README (an opening that leads into the part cut, "What goes where:", says that part is
--     there); every heading stays, so the page's own links still land (checked);
--   - the commands table cut to the most used (COMMANDS), with a link to the README's.
-- Nothing else is written by hand: a change goes in docs/CURSEFORGE.md (or ROADMAP.md), then here.
--   luajit scripts/curseforge-page.lua           write docs/CURSEFORGE-STORE.md
--   luajit scripts/curseforge-page.lua --check   compare only: exit 1 when the file is not what it would write
-- From the repository root. scripts/check.sh runs --check, then curseforge-size.lua --check on the
-- page (its budget); tests/run.lua loads both as modules.

local M = {}

M.SOURCE = "docs/CURSEFORGE.md"
M.TARGET = "docs/CURSEFORGE-STORE.md"
M.README = "README.md"
M.ROADMAP = "ROADMAP.md"
M.TOC = "Olympus/Olympus.toc"
M.REPO = "https://github.com/dnl-gentile/olympus-addon"
M.RECENT = 3 -- versions under "Recent versions": the TOC's and the two before it

-- Sections cut to their opening: the heading's text, and how many of its first parts stay (a part
-- is a paragraph, a list, a table or a quote; an opening line that runs into a list is a part).
M.CUTS = {
	{ title = "Channels", keep = 2 }, -- what each channel is, and its table
	{ title = "Net-off (1.1): the moderators hide a character or take a guild off the network", keep = 1 },
	{ title = "The Throne (the King and his Hands)", keep = 1 },
	{ title = "The King's Steward (1.0.0)", keep = 3 }, -- his opening, what he does, and what he never does
	{ title = "The Treasury (its keepers, the King, and the army when the King says so)", keep = 1 },
	{ title = "Privacy", keep = 1 },
	{ title = "Security and trust", keep = 2 },
	{ title = "What colluding characters can reach", keep = 1 },
}

-- The commands table's rows that stay, by their first command as the table writes it.
M.COMMANDS_TITLE = "Commands"
M.COMMANDS = {
	"/oly", "/oly realm", "/oly privacy", "/oly chat on\\|off", "/ol <text>", "/oly talk [olympus\\|captains\\|lords]",
	"/oly mute olympus", "/oly chatwindow tab", "/oly hop", "/oly lfg", "/oly week", "/oly craft [item or name]",
	"/oly loot", "/oly approved", "/oly helpme [text]", "/oly location on", "/oly borders on",
	"/oly nameplates on", "/oly chatmarks on", "/oly block <name>", "/oly filter add\\|remove <word>",
	"/oly alt add Name", "/oly sound", "/oly discord <code>", "/oly bug", "/oly status",
}

local function Read(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end
M.Read = Read

local function Lines(text)
	local out = {}
	for l in (text:gsub("\r\n", "\n"):gsub("\n$", "") .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = l end
	return out
end

local function Fence(l) return l:match("^ ? ? ?```") or l:match("^ ? ? ?~~~") end
local function HeadingOf(l) return l:match("^(#+)%s+(.-)%s*#*%s*$") end

-- The page in sections: { heading = the line (nil before the first), title, level, body = { lines } }.
-- A "#" line inside a fence is no heading.
local function Sections(lines)
	local out, cur, fenced = {}, { body = {} }, false
	for _, l in ipairs(lines) do
		local hashes, title = HeadingOf(l)
		if not fenced and hashes and #hashes <= 6 then
			out[#out + 1] = cur
			cur = { heading = l, title = title, level = #hashes, body = {} }
		else
			if Fence(l) then fenced = not fenced end
			cur.body[#cur.body + 1] = l
		end
	end
	out[#out + 1] = cur
	if not out[1].heading and #out[1].body == 0 then table.remove(out, 1) end
	return out
end
M.Sections = Sections

-- Each heading's id, as the editor and GitHub make them (a repeated one gets -1, -2...): the ids
-- in order, and the first id of each title.
local function Anchors(sections, size)
	local list, byTitle, seen = {}, {}, {}
	for _, s in ipairs(sections) do
		if s.heading then
			local id = size.Slug(size.Plain(s.title))
			if seen[id] then
				seen[id] = seen[id] + 1
				id = id .. "-" .. seen[id]
			else
				seen[id] = 0
			end
			list[#list + 1] = id
			if not byTitle[s.title] then byTitle[s.title] = id end
		end
	end
	return list, byTitle
end
M.Anchors = Anchors

local function Blank(l) return l:find("^%s*$") ~= nil end
local function Starts(l)
	if l:find("^ ? ? ?[-*+] ") or l:find("^ ? ? ?%d+[.)] ") then return "list" end
	if l:find("^%s*|") then return "table" end
	if l:find("^ ? ? ?>") then return "quote" end
	if Fence(l) then return "fence" end
	return "text"
end

-- A section's body in parts: each ends at a blank line (a fence at its closing line), and an
-- opening paragraph also where a list, a table or a quote starts under it with no blank line.
-- Each part: { gap = a blank line before it, lines }.
local function Parts(body)
	local out, cur, gap, fenced = {}, nil, false, false
	for _, l in ipairs(body) do
		if fenced then
			cur[#cur + 1] = l
			if Fence(l) then fenced = false; cur = nil end
		elseif Blank(l) then
			cur, gap = nil, true
		else
			local kind = Starts(l)
			if not cur or (cur.kind == "text" and kind ~= "text") then
				cur = { kind = kind, gap = gap }
				out[#out + 1] = cur
				gap = false
			end
			cur[#cur + 1] = l
			if kind == "fence" and #cur == 1 then fenced = true end
		end
	end
	return out
end
M.Parts = Parts

-- The line that links a cut to the same section of the README: its words, then the link.
local function MoreLine(words, title, anchors)
	local id = anchors[title]
	if not id then error(("%s has no heading %q for the store page's link"):format(M.README, title), 0) end
	return ("*%s [%s](%s#%s).*"):format(words, title, M.REPO, id)
end

-- An opening that leads into the part the cut takes away: it ends on a colon ("What goes
-- where:") or its last sentence names "the following". Its link then says that part is in the
-- README, so the page never reads as broken off mid-sentence.
local LEADS_TO = { list = "The list is", table = "The table is", quote = "The quote is" }
local function Leads(part)
	local text = table.concat(part, " "):gsub("%s+$", "")
	if text:find(":$") then return true end
	local last = text:match(".*[.!?]%s+(%u.*)$") or text
	return last:find("the following", 1, true) ~= nil
end

local function Cut(section, keep, readme)
	local parts = Parts(section.body)
	if #parts <= keep then error(("%s: %q has %d parts, nothing to cut at %d"):format(M.SOURCE, section.title, #parts, keep), 0) end
	local body = {}
	if section.body[1] and Blank(section.body[1]) then body[1] = "" end
	for i = 1, keep do
		if i > 1 and parts[i].gap then body[#body + 1] = "" end
		for _, l in ipairs(parts[i]) do body[#body + 1] = l end
	end
	body[#body + 1] = ""
	local words = "Continued in the README:"
	if Leads(parts[keep]) then
		words = (LEADS_TO[parts[keep + 1].kind] or "What follows is") .. " in the README, with the rest of this section:"
	end
	body[#body + 1] = MoreLine(words, section.title, readme)
	body[#body + 1] = ""
	section.body = body
end

local function Commands(section, readme)
	local keep, found, body = {}, {}, {}
	for _, c in ipairs(M.COMMANDS) do keep[c] = true end
	for _, l in ipairs(section.body) do
		local first = l:match("^|%s*`([^`]*)`")
		if not first then
			body[#body + 1] = l
		elseif keep[first] then
			if found[first] then error(("%s: two command rows start with %s"):format(M.SOURCE, first), 0) end
			found[first] = true
			body[#body + 1] = l
		end
	end
	for _, c in ipairs(M.COMMANDS) do
		if not found[c] then error(("%s: no command row starts with %s"):format(M.SOURCE, c), 0) end
	end
	local last = 0
	for i, l in ipairs(body) do if l:find("^|") then last = i end end
	table.insert(body, last + 1, "")
	table.insert(body, last + 2, MoreLine("Every command in the README:", section.title, readme))
	section.body = body
end

-- ROADMAP.md's "## Done" lines for the TOC's version and the ones before it, newest first.
function M.Recent(roadmap, version, n)
	local items, done = {}, false
	for _, l in ipairs(Lines(roadmap)) do
		if l:find("^## ") then
			done = l == "## Done"
		elseif done then
			local v, text = l:match("^%- v(%d+%.%d+%.%d+) (.*)$")
			if v then
				items[#items + 1] = { version = v, lines = { text } }
			elseif l:find("^%- ") then
				items[#items + 1] = { lines = {} } -- (a line that names no version ends the one before)
			elseif l:find("^  %S") and items[#items] then
				local t = items[#items].lines
				t[#t + 1] = (l:gsub("^%s+", ""))
			end
		end
	end
	local at
	for i, item in ipairs(items) do if item.version == version then at = i end end
	if not at then error(("%s has no Done line for v%s, the TOC's version"):format(M.ROADMAP, version), 0) end
	local out = {}
	for i = at, 1, -1 do
		if items[i].version then out[#out + 1] = items[i] end
		if #out == n then break end
	end
	if #out < n then error(("%s: %d versions up to v%s, not %d"):format(M.ROADMAP, #out, version, n), 0) end
	return out
end

local function RecentSection(recent)
	local body = { "" }
	for _, item in ipairs(recent) do
		for i, l in ipairs(item.lines) do
			-- (an issue's number, as ROADMAP.md writes it, links to it: "#56" alone means nothing here)
			l = l:gsub("%(#(%d+)%)", "([#%1](" .. M.REPO .. "/issues/%1))")
			body[#body + 1] = i == 1 and ("- **%s**: %s"):format(item.version, l) or ("  " .. l)
		end
	end
	body[#body + 1] = ""
	body[#body + 1] = ("Every version's notes are in the [GitHub releases](%s/releases). This page is the short one for CurseForge: the [README](%s#olympus) has every section in full."):format(M.REPO, M.REPO)
	body[#body + 1] = ""
	return { heading = "## Recent versions", title = "Recent versions", level = 2, body = body }
end

-- The store page from the full page, the README, ROADMAP.md and the TOC's version (texts).
function M.Build(full, readme, roadmap, version, size)
	local _, readmeIds = Anchors(Sections(Lines(readme)), size)
	local sections = Sections(Lines(full))
	local byTitle = {}
	for _, s in ipairs(sections) do
		if s.title then
			if byTitle[s.title] then byTitle[s.title] = false else byTitle[s.title] = s end
		end
	end
	local function Find(title)
		local s = byTitle[title]
		if s == nil then error(("%s has no heading %q"):format(M.SOURCE, title), 0) end
		if s == false then error(("%s has two headings %q"):format(M.SOURCE, title), 0) end
		return s
	end
	for _, cut in ipairs(M.CUTS) do Cut(Find(cut.title), cut.keep, readmeIds) end
	Commands(Find(M.COMMANDS_TITLE), readmeIds)
	local at
	for i, s in ipairs(sections) do
		if s.level == 2 then at = i break end
	end
	if not at then error(M.SOURCE .. " has no ## section", 0) end
	table.insert(sections, at, RecentSection(M.Recent(roadmap, version, M.RECENT)))
	local out = {}
	for _, s in ipairs(sections) do
		if s.heading then out[#out + 1] = s.heading end
		for _, l in ipairs(s.body) do out[#out + 1] = l end
	end
	while #out > 0 and Blank(out[#out]) do out[#out] = nil end
	local page = table.concat(out, "\n") .. "\n"
	-- Every link to a heading of the page lands on one.
	local ids = {}
	for _, id in ipairs(Anchors(Sections(Lines(page)), size)) do ids[id] = true end
	for id in page:gmatch("%]%(#([^)%s]+)%)") do
		if not ids[id] then error(("the store page links to #%s, a heading it does not have"):format(id), 0) end
	end
	return page
end

function M.Version(toc)
	return toc:match("## Version:%s*(%S+)")
end

function M.Expected(root)
	root = root or ""
	local size = dofile(root .. "scripts/curseforge-size.lua")
	local function Need(path) return assert(Read(root .. path), "cannot read " .. path) end
	local version = M.Version(Need(M.TOC))
	if not version then error(M.TOC .. " has no ## Version", 0) end
	return M.Build(Need(M.SOURCE), Need(M.README), Need(M.ROADMAP), version, size)
end

function M.Main(args)
	local check = args and args[1] == "--check"
	local ok, want = pcall(M.Expected, "")
	if not ok then
		io.stderr:write(tostring(want) .. "\n")
		os.exit(1)
	end
	local have = Read(M.TARGET)
	if check then
		if have ~= want then
			io.stderr:write(M.TARGET .. " is not what " .. M.SOURCE .. " makes: run luajit scripts/curseforge-page.lua\n")
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
if arg and type(arg[0]) == "string" and arg[0]:match("curseforge%-page%.lua$") then M.Main(arg) end

return M
