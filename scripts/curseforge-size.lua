-- The CurseForge page's size (1.1.2): CurseForge's editor saves the project description with
-- PUT /_api/projects/description/<id>, a JSON body {"description": <the page as HTML>,
-- "descriptionType": 1}, and the server refuses a body above about 100 KiB (413, "request entity
-- too large": measured 2026-09-30, 102,382 bytes passed and 102,421 were refused). This script
-- renders a page to HTML the way the editor does (Markdown with GitHub's tables, headings with
-- ids like <h1 id="olympus">, the characters & < > " ' as entities), wraps it as that body and
-- prints its size in bytes. The page pasted there is docs/CURSEFORGE-STORE.md (1.1.5: what
-- scripts/curseforge-page.lua makes of docs/CURSEFORGE.md, the whole page, nearly twice the limit).
--   luajit scripts/curseforge-size.lua                 the size of docs/CURSEFORGE-STORE.md's body
--   luajit scripts/curseforge-size.lua --check [FILE]  the same (or FILE's); exit 1 above the budget
--   luajit scripts/curseforge-size.lua FILE            the size of FILE's body (docs/CURSEFORGE.md...)
--   luajit scripts/curseforge-size.lua --html FILE     print the HTML it measured (FILE: any page)
-- From the repository root. scripts/check.sh runs --check; tests/run.lua loads it as a module
-- (M.Render, M.Body, M.Slug), checks its HTML and the store page's body against M.BUDGET.
-- Calibrated on 2026-09-30: the 1.1.2 page (165,850 bytes of Markdown), whose body CurseForge's
-- editor sent as 172,342 bytes, measures 172,229 here (0.07% under).

local M = {}

M.SOURCE = "docs/CURSEFORGE-STORE.md"
M.LIMIT = 102400 -- where CurseForge's server starts refusing (about 100 KiB)
M.BUDGET = 92000 -- ours: room to spare under the limit, for the estimate's error and a later edit

---------------------------------------------------------------------------
-- Inline Markdown: escapes, code spans, links, images, autolinks, raw tags, emphasis.
---------------------------------------------------------------------------

local ENTITY = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }
local function Escape(s) return (s:gsub("[&<>\"']", ENTITY)) end
M.Escape = Escape

local PUNCT = "[!\"#$%%&'()*+,%-./:;<=>?@%[\\%]^_`{|}~]"
local function IsPunct(c) return c ~= "" and c:find("^" .. PUNCT) ~= nil end
local function IsSpace(c) return c == "" or c:find("^%s") ~= nil end

local Inline

-- A link's or image's "(destination "title")" at pos (the "("): the destination and the end.
local function Destination(s, pos)
	if s:sub(pos, pos) ~= "(" then return nil end
	local depth, i = 0, pos
	while i <= #s do
		local c = s:sub(i, i)
		if c == "\\" then
			i = i + 1
		elseif c == "(" then
			depth = depth + 1
		elseif c == ")" then
			depth = depth - 1
			if depth == 0 then
				local inner = s:sub(pos + 1, i - 1):match("^%s*(.-)%s*$")
				local dest = inner:match("^<(.-)>") or inner:match("^(%S*)")
				return dest, i
			end
		end
		i = i + 1
	end
	return nil
end

-- The "]" closing the bracket at pos, code spans skipped.
local function CloseBracket(s, pos)
	local depth, i = 0, pos
	while i <= #s do
		local c = s:sub(i, i)
		if c == "\\" then
			i = i + 1
		elseif c == "`" then
			local run = s:match("^`+", i)
			local close = s:find(run, i + #run, true)
			if close then i = close + #run - 1 end
		elseif c == "[" then
			depth = depth + 1
		elseif c == "]" then
			depth = depth - 1
			if depth == 0 then return i end
		end
		i = i + 1
	end
	return nil
end

local function Delimiter(s, i, run)
	local before, after = s:sub(i - 1, i - 1), s:sub(i + #run, i + #run)
	local left = not IsSpace(after) and (not IsPunct(after) or IsSpace(before) or IsPunct(before))
	local right = not IsSpace(before) and (not IsPunct(before) or IsSpace(after) or IsPunct(after))
	local char = run:sub(1, 1)
	local open, close = left, right
	if char == "_" then
		open = left and (not right or IsPunct(before))
		close = right and (not left or IsPunct(after))
	end
	return { char = char, n = #run, open = open, close = close }
end

-- CommonMark's "process emphasis", on a list of nodes (strings, or delimiter runs).
local function Emphasis(nodes)
	local i = 1
	while i <= #nodes do
		local closer = nodes[i]
		if type(closer) == "table" and closer.close and closer.n > 0 then
			local found
			for j = i - 1, 1, -1 do
				local opener = nodes[j]
				if type(opener) == "table" and opener.char == closer.char and opener.open and opener.n > 0 then
					-- (the rule of 3: a run that both opens and closes pairs only in sums not of 3)
					if not ((opener.close or closer.open) and (opener.n + closer.n) % 3 == 0 and not (opener.n % 3 == 0 and closer.n % 3 == 0)) then
						found = j
						break
					end
				end
			end
			if found then
				local opener = nodes[found]
				local use = (opener.n >= 2 and closer.n >= 2) and 2 or 1
				local tag = use == 2 and "strong" or "em"
				opener.n, closer.n = opener.n - use, closer.n - use
				-- Runs between them can no longer pair across this one.
				for k = found + 1, i - 1 do
					if type(nodes[k]) == "table" then nodes[k].open, nodes[k].close = false, false end
				end
				opener.after = "<" .. tag .. ">" .. (opener.after or "")
				closer.before = (closer.before or "") .. "</" .. tag .. ">"
				if closer.n > 0 then i = i - 1 end
			end
		end
		i = i + 1
	end
	local out = {}
	for _, n in ipairs(nodes) do
		if type(n) == "table" then
			-- (a closer's tags come before what is left of its run; an opener's after)
			out[#out + 1] = (n.before or "") .. n.char:rep(n.n) .. (n.after or "")
		else
			out[#out + 1] = n
		end
	end
	return table.concat(out)
end

local RAW_TAG = "^</?[%a][%w%-]*%s*[^<>]->"

Inline = function(s)
	local nodes, text = {}, {}
	local function Flush()
		if #text > 0 then nodes[#nodes + 1] = Escape(table.concat(text)); text = {} end
	end
	local function Put(html) Flush(); nodes[#nodes + 1] = html end
	local i = 1
	while i <= #s do
		local c = s:sub(i, i)
		if c == "\\" and IsPunct(s:sub(i + 1, i + 1)) then
			text[#text + 1] = s:sub(i + 1, i + 1)
			i = i + 2
		elseif c == "\\" and s:sub(i + 1, i + 1) == "\n" then
			Put("<br>\n")
			i = i + 2
		elseif c == "`" then
			local run = s:match("^`+", i)
			local close = s:find("%f[`]" .. run .. "%f[^`]", i + #run)
			if close then
				local code = s:sub(i + #run, close - 1):gsub("\n", " ")
				if code:find("^ .* $") and code:find("[^ ]") then code = code:sub(2, -2) end
				Put("<code>" .. Escape(code) .. "</code>")
				i = close + #run
			else
				text[#text + 1] = run
				i = i + #run
			end
		elseif (c == "!" and s:sub(i + 1, i + 1) == "[") or c == "[" then
			local image = c == "!"
			local open = image and i + 1 or i
			local close = CloseBracket(s, open)
			local dest, stop
			if close then dest, stop = Destination(s, close + 1) end
			if dest then
				local label = s:sub(open + 1, close - 1)
				if image then
					Put(('<img src="%s" alt="%s">'):format(Escape(dest), Escape((label:gsub("[*_`]", "")))))
				else
					Put(('<a href="%s">%s</a>'):format(Escape(dest), Inline(label)))
				end
				i = stop + 1
			else
				text[#text + 1] = c
				i = i + 1
			end
		elseif c == "<" then
			local auto = s:match("^<(%a[%w+.%-]*:[^%s<>]*)>", i)
			local tag = not auto and s:match(RAW_TAG, i)
			if auto then
				Put(('<a href="%s">%s</a>'):format(Escape(auto), Escape(auto)))
				i = i + #auto + 2
			elseif tag then
				Put(tag)
				i = i + #tag
			else
				text[#text + 1] = c
				i = i + 1
			end
		elseif (c == "h" or c == "w") and (s:find("^https?://", i) or s:find("^www%.", i)) and (i == 1 or s:sub(i - 1, i - 1):find("[%s(*_~]")) then
			-- GitHub's autolinks: a bare URL, less its closing punctuation.
			local url = s:match("^[^%s<]+", i)
			url = url:gsub("[?!.,:*_~'\"]+$", "")
			while url:sub(-1) == ")" and select(2, url:gsub("%(", "")) < select(2, url:gsub("%)", "")) do url = url:sub(1, -2) end
			local href = url:sub(1, 4) == "www." and "http://" .. url or url
			Put(('<a href="%s">%s</a>'):format(Escape(href), Escape(url)))
			i = i + #url
		elseif c == "*" or c == "_" then
			local run = s:match("^%" .. c .. "+", i)
			Flush()
			nodes[#nodes + 1] = Delimiter(s, i, run)
			i = i + #run
		elseif c == "\n" then
			-- A soft break; two spaces or more before it make a hard one.
			local hard = #text > 0 and text[#text]:find("  $")
			if #text > 0 then text[#text] = text[#text]:gsub(" +$", "") end
			Put(hard and "<br>\n" or "\n")
			i = i + 1
		else
			local plain = s:match("^[^\\`!%[<hw*_\n]+", i) or c
			text[#text + 1] = plain
			i = i + #plain
		end
	end
	Flush()
	return Emphasis(nodes)
end
M.Inline = Inline

---------------------------------------------------------------------------
-- Headings' ids, as the editor makes them (marked's slugger: GitHub's anchors for these titles).
---------------------------------------------------------------------------

function M.Slug(title)
	local s = title:lower():gsub("^%s+", ""):gsub("%s+$", "")
	s = s:gsub("<[!/%a][^>]->", "")
	s = s:gsub("[\\'!\"#$%%&()*+,./:;<=>?@%[%]^`{|}~]", "")
	s = s:gsub("%s", "-")
	return s
end

-- A heading's text as the slugger sees it: the Markdown's marks and links gone.
local function Plain(s)
	s = s:gsub("!?%[(.-)%]%b()", "%1"):gsub("[*_`]", "")
	return s
end
M.Plain = Plain

---------------------------------------------------------------------------
-- Blocks: headings, paragraphs, lists, block quotes, tables, code, rules, raw HTML.
---------------------------------------------------------------------------

local function Blank(l) return l:find("^%s*$") ~= nil end
local function Indent(l)
	local n = 0
	for i = 1, #l do
		local c = l:sub(i, i)
		if c == " " then n = n + 1 elseif c == "\t" then n = n + 4 - n % 4 else break end
	end
	return n
end
local function Dedent(l, n)
	local i, col = 1, 0
	while col < n and i <= #l do
		local c = l:sub(i, i)
		if c == " " then col = col + 1 elseif c == "\t" then col = col + 4 - col % 4 else break end
		i = i + 1
	end
	return l:sub(i)
end

local function Fence(l) return l:match("^ ? ? ?(```+)") or l:match("^ ? ? ?(~~~+)") end
local function Heading(l) return l:match("^ ? ? ?(#+)%s+(.-)%s*#*%s*$") end
local function Rule(l)
	local t = l:gsub("%s", "")
	return #t >= 3 and (t:find("^%-+$") or t:find("^%*+$") or t:find("^_+$")) and Indent(l) < 4
end
local function Quote(l) return l:match("^ ? ? ?>") ~= nil end
local function Bullet(l)
	local ind, mark, sp, rest = l:match("^( *)([-*+])( +)(.*)$")
	if not ind then
		ind, mark, sp = l:match("^( *)([-*+])()$")
		if ind then sp, rest = "", "" end
	end
	if ind and #ind < 4 then return #ind, mark, #ind + 1 + (#sp > 4 and 1 or math.max(#sp, 1)), rest end
	local num, delim
	ind, num, delim, sp, rest = l:match("^( *)(%d+)([.)])( +)(.*)$")
	if ind and #ind < 4 and #num <= 9 then
		return #ind, delim, #ind + #num + 1 + (#sp > 4 and 1 or #sp), rest, tonumber(num)
	end
	return nil
end
local function HtmlBlock(l)
	return l:match("^ ? ? ?<[/!]?%a") ~= nil
end
local function Row(l)
	local s = l:match("^%s*(.-)%s*$")
	s = s:gsub("^|", "")
	if s:sub(-1) == "|" and s:sub(-2, -2) ~= "\\" then s = s:sub(1, -2) end
	local cells, cur, i = {}, {}, 1
	while i <= #s do
		local c = s:sub(i, i)
		if c == "\\" and s:sub(i + 1, i + 1) == "|" then
			cur[#cur + 1] = "|"
			i = i + 2
		elseif c == "`" then
			-- A code span keeps its "|" only escaped; plain ones still split the cell (GitHub's rule).
			cur[#cur + 1] = c
			i = i + 1
		elseif c == "|" then
			cells[#cells + 1] = table.concat(cur):match("^%s*(.-)%s*$")
			cur = {}
			i = i + 1
		else
			cur[#cur + 1] = c
			i = i + 1
		end
	end
	cells[#cells + 1] = table.concat(cur):match("^%s*(.-)%s*$")
	return cells
end
local function DelimiterRow(l)
	if not l:find("|", 1, true) and not l:find("^%s*:?%-+:?%s*$") then return nil end
	local cells = Row(l)
	for _, c in ipairs(cells) do if not c:find("^:?%-+:?$") then return nil end end
	return cells
end

local Blocks

local function Paragraph(lines, tight)
	local body = table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
	body = body:gsub("\n[ \t]+", "\n")
	local html = Inline(body)
	if tight then return html end
	return "<p>" .. html .. "</p>\n"
end

-- Can this line start a block that ends a paragraph?
local function Interrupts(l)
	if Fence(l) or Heading(l) or Rule(l) or Quote(l) then return true end
	local _, _, _, rest, num = Bullet(l)
	if rest and rest ~= "" and (not num or num == 1) then return true end
	return false
end

local function List(lines, i, slugs)
	local _, mark, _, _, first = Bullet(lines[i])
	local ordered = first ~= nil
	local items, loose = {}, false
	local blankBefore = false
	while i <= #lines do
		-- (A line that reaches here is not indented to the last item's content: a sibling, or the end.)
		local ind, m, content, rest, num = Bullet(lines[i])
		if not ind or m ~= mark or (num ~= nil) ~= ordered then break end
		if blankBefore and #items > 0 then loose = true end
		local item = { rest }
		i = i + 1
		local blanks = 0
		while i <= #lines do
			local l = lines[i]
			if Blank(l) then
				blanks = blanks + 1
				item[#item + 1] = ""
				i = i + 1
			elseif Indent(l) >= content then
				if blanks > 0 then item.blankInside = true end
				blanks = 0
				item[#item + 1] = Dedent(l, content)
				i = i + 1
			elseif blanks == 0 and not Bullet(l) and not Interrupts(l) and not Blank(item[#item]) then
				-- A lazy continuation of the item's paragraph.
				item[#item + 1] = l
				i = i + 1
			else
				break
			end
		end
		while #item > 1 and Blank(item[#item]) do item[#item] = nil end
		blankBefore = blanks > 0
		items[#items + 1] = item
		if blanks > 0 then
			local nextInd, nextMark = Bullet(lines[i] or "")
			if not nextInd or nextMark ~= mark then break end
		end
	end
	for _, item in ipairs(items) do if item.blankInside then loose = true end end
	local out = {}
	local tag = ordered and "ol" or "ul"
	out[#out + 1] = (ordered and first ~= 1) and ('<ol start="%d">\n'):format(first) or ("<" .. tag .. ">\n")
	for _, item in ipairs(items) do
		out[#out + 1] = "<li>" .. Blocks(item, slugs, not loose):gsub("\n$", "") .. "</li>\n"
	end
	out[#out + 1] = "</" .. tag .. ">\n"
	return table.concat(out), i
end

Blocks = function(lines, slugs, tight)
	local out = {}
	local i = 1
	while i <= #lines do
		local l = lines[i]
		if Blank(l) then
			i = i + 1
		elseif Fence(l) then
			local fence = Fence(l)
			local info = l:match("^%s*[`~]+%s*(%S*)")
			local code = {}
			i = i + 1
			while i <= #lines and not (lines[i]:match("^ ? ? ?" .. fence:sub(1, 1):rep(#fence)) and lines[i]:find("^%s*[`~]+%s*$")) do
				code[#code + 1] = lines[i]
				i = i + 1
			end
			i = i + 1
			local body = #code > 0 and Escape(table.concat(code, "\n")) .. "\n" or ""
			local class = info ~= "" and (' class="language-%s"'):format(Escape(info)) or ""
			out[#out + 1] = ("<pre><code%s>%s</code></pre>\n"):format(class, body)
		elseif Heading(l) and #Heading(l) <= 6 then
			local hashes, title = Heading(l)
			local level = #hashes
			local id = M.Slug(Plain(title))
			if slugs[id] then
				slugs[id] = slugs[id] + 1
				id = id .. "-" .. slugs[id]
			else
				slugs[id] = 0
			end
			out[#out + 1] = ('<h%d id="%s">%s</h%d>\n'):format(level, id, Inline(title), level)
			i = i + 1
		elseif Rule(l) then
			out[#out + 1] = "<hr>\n"
			i = i + 1
		elseif Quote(l) then
			local inner = {}
			while i <= #lines and not Blank(lines[i]) do
				local q = lines[i]
				if Quote(q) then
					inner[#inner + 1] = (q:gsub("^ ? ? ?> ?", "", 1))
				elseif Interrupts(q) then
					break
				else
					inner[#inner + 1] = q -- (lazy)
				end
				i = i + 1
			end
			out[#out + 1] = "<blockquote>\n" .. Blocks(inner, slugs) .. "</blockquote>\n"
		elseif Bullet(l) and select(4, Bullet(l)) then
			local html
			html, i = List(lines, i, slugs)
			out[#out + 1] = html
		elseif l:find("|", 1, true) and lines[i + 1] and DelimiterRow(lines[i + 1]) and #Row(l) == #DelimiterRow(lines[i + 1]) then
			local head = Row(l)
			local t = { "<table>\n<thead>\n<tr>\n" }
			for _, c in ipairs(head) do t[#t + 1] = "<th>" .. Inline(c) .. "</th>\n" end
			t[#t + 1] = "</tr>\n</thead>\n"
			i = i + 2
			local body = false
			while i <= #lines and not Blank(lines[i]) and not Interrupts(lines[i]) do
				if not body then t[#t + 1] = "<tbody>"; body = true end
				local cells = Row(lines[i])
				t[#t + 1] = "<tr>\n"
				for k = 1, #head do t[#t + 1] = "<td>" .. Inline(cells[k] or "") .. "</td>\n" end
				t[#t + 1] = "</tr>\n"
				i = i + 1
			end
			if body then t[#t + 1] = "</tbody>" end
			t[#t + 1] = "</table>\n"
			out[#out + 1] = table.concat(t)
		elseif HtmlBlock(l) then
			local raw = {}
			while i <= #lines and not Blank(lines[i]) do
				raw[#raw + 1] = lines[i]
				i = i + 1
			end
			out[#out + 1] = table.concat(raw, "\n") .. "\n"
		else
			local para = { l }
			i = i + 1
			while i <= #lines and not Blank(lines[i]) and not Interrupts(lines[i]) and not HtmlBlock(lines[i])
				and not (lines[i]:find("|", 1, true) and lines[i + 1] and DelimiterRow(lines[i + 1])) do
				para[#para + 1] = lines[i]
				i = i + 1
			end
			out[#out + 1] = Paragraph(para, tight)
			if tight then out[#out + 1] = "\n" end
		end
	end
	return table.concat(out)
end

-- The page as HTML.
function M.Render(markdown)
	local lines = {}
	for l in (markdown:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
	return Blocks(lines, {})
end

---------------------------------------------------------------------------
-- The request's body, as the editor's JSON.stringify writes it (UTF-8 kept as is).
---------------------------------------------------------------------------

local JSON_ESCAPE = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }
function M.Json(s)
	return '"' .. s:gsub('[%c"\\]', function(c) return JSON_ESCAPE[c] or ("\\u%04x"):format(c:byte()) end) .. '"'
end

function M.Body(markdown)
	return '{"description":' .. M.Json(M.Render(markdown)) .. ',"descriptionType":1}'
end

local function Read(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end
M.Read = Read

function M.Main(args)
	if args[1] == "--html" then
		io.write(M.Render(assert(Read(args[2] or M.SOURCE), "cannot read " .. tostring(args[2] or M.SOURCE))))
		return
	end
	local path = (args[1] ~= "--check" and args[1]) or args[2] or M.SOURCE
	local markdown = assert(Read(path), "cannot read " .. path)
	local size = #M.Body(markdown)
	print(("%s: %d bytes of Markdown, a body of %d bytes (budget %d, CurseForge refuses above about %d)")
		:format(path, #markdown, size, M.BUDGET, M.LIMIT))
	if args[1] == "--check" and size > M.BUDGET then
		io.stderr:write(("%s: %d bytes over the budget: cut more of it in scripts/curseforge-page.lua (CUTS, COMMANDS), linking to the README\n")
			:format(path, size - M.BUDGET))
		os.exit(1)
	end
end

-- Run as a script (not loaded by the tests).
if arg and type(arg[0]) == "string" and arg[0]:match("curseforge%-size%.lua$") then M.Main(arg) end

return M
