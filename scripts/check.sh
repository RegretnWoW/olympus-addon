#!/usr/bin/env bash
# Run the same addon checks locally and in CI. Requires Bash and LuaJIT.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v luajit >/dev/null 2>&1; then
	printf 'LuaJIT is required. Install luajit and rerun bash scripts/check.sh.\n' >&2
	exit 127
fi

printf 'Checking Lua syntax...\n'
lua_files=$(mktemp)
trap 'rm -f "$lua_files"' EXIT
find Olympus tests -type f -name '*.lua' -print0 > "$lua_files"
while IFS= read -r -d '' file; do
	# Compile to a listing without executing addon code or writing bytecode files.
	luajit -bl "$file" >/dev/null
done < "$lua_files"

printf 'Checking files listed in Olympus/Olympus.toc...\n'
luajit - <<'LUA'
local toc = assert(io.open("Olympus/Olympus.toc", "r"))
local failed = false
for line in toc:lines() do
	local entry = line:match("^%s*(.-)%s*$")
	if entry ~= "" and entry:sub(1, 1) ~= "#" then
		local path = "Olympus/" .. entry:gsub("\\", "/")
		local file = io.open(path, "rb")
		local contents = file and file:read("*a")
		if file then file:close() end
		if not contents then
			io.stderr:write("Cannot read TOC entry: " .. path .. "\n")
			failed = true
		end
	end
end
toc:close()
if failed then os.exit(1) end
LUA

printf 'Checking local/global name collisions...\n'
bash scripts/lint-globals.sh

printf 'Running offline tests...\n'
luajit tests/run.lua

printf 'All repository checks passed.\n'
