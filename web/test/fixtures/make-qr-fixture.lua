-- Writes web/test/fixtures/qr-matrices.txt: the QR codes the addon's encoder
-- (Olympus/libs/QREncode/qrencode.lua) makes for the link URLs of vectors.json, which
-- web/test/qr.test.mjs reads with the page's jsQR. From the repository root:
--
--   luajit web/test/fixtures/make-qr-fixture.lua [path/to/qrencode.lua]
--
-- Byte mode, EC level M up to version 15, else L (what Link.lua asks for). Each block is
-- "# <name>", "url <the URL>", then the rows: 1 dark, 0 light (no quiet zone).

local path = arg[1] or "Olympus/libs/QREncode/qrencode.lua"
local here = (arg[0]:match("^(.*)[/\\]") or ".") .. "/"

local ns = {}
local lib = assert(loadfile(path))("Olympus", ns)
local qrcode = (ns.QREncode and ns.QREncode.qrcode) or (lib and lib.qrcode)
assert(qrcode, "no qrcode function in " .. path)

local f = assert(io.open(here .. "vectors.json", "rb"))
local json = f:read("*a")
f:close()

-- The "bundles" array: each bundle's name and URL, in order (only bundles have both there).
local section = assert(json:match('"bundles": %[(.-)\n %]'), "no bundles section")
local names, urls = {}, {}
for name in section:gmatch('\n   "name": "([^"]*)"') do names[#names + 1] = name end
for url in section:gmatch('"url": "([^"]*)"') do urls[#urls + 1] = url end
assert(#names == #urls, "names and URLs do not pair up")

local out = {}
for i, url in ipairs(urls) do
	local name = names[i]
	local ok, m = qrcode(url, 2) -- M
	local size = ok and #m or 0
	local version = (size - 17) / 4
	if not ok or version > 15 then ok, m = qrcode(url, 1) end -- L
	assert(ok, m)
	out[#out + 1] = "# " .. name .. " (version " .. ((#m - 17) / 4) .. ")"
	out[#out + 1] = "url " .. url
	for y = 1, #m do
		local row = {}
		for x = 1, #m do row[x] = m[x][y] > 0 and "1" or "0" end
		out[#out + 1] = table.concat(row)
	end
end
assert(#out > 0, "no URLs found in vectors.json")

local w = assert(io.open(here .. "qr-matrices.txt", "wb"))
w:write(table.concat(out, "\n"), "\n")
w:close()
print(here .. "qr-matrices.txt")
