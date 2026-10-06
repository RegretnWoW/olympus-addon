#!/usr/bin/env bash
# Run the same addon checks locally and in CI. Requires Bash and LuaJIT; the Python checks
# (the High Council's signing script) run wherever python3 is installed, as on CI.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v luajit >/dev/null 2>&1; then
	printf 'LuaJIT is required. Install luajit and rerun bash scripts/check.sh.\n' >&2
	exit 127
fi

printf 'Checking Lua syntax...\n'
check_tmp=$(mktemp -d)
trap 'rm -rf "$check_tmp"' EXIT
lua_files="$check_tmp/lua-files"
lua_dirs="Olympus tests"
[ -d Olympus_Arena ] && lua_dirs="Olympus Olympus_Arena tests" # (1.2: the Blood Arena's companion)
find $lua_dirs -type f -name '*.lua' -print0 > "$lua_files"
while IFS= read -r -d '' file; do
	# Compile to a listing without executing addon code or writing bytecode files.
	luajit -bl "$file" >/dev/null
done < "$lua_files"

printf 'Checking Python syntax...\n'
if command -v python3 >/dev/null 2>&1; then
	py_files="$check_tmp/py-files"
	find scripts tests -type f -name '*.py' -print0 > "$py_files"
	while IFS= read -r -d '' file; do
		# Compiled only, never run; the bytecode goes to the temporary folder, not the repository.
		PYTHONPYCACHEPREFIX="$check_tmp/pycache" python3 -m py_compile "$file"
	done < "$py_files"
else
	printf 'python3 not found: Python checks skipped.\n'
fi

printf 'Checking files listed in Olympus/Olympus.toc...\n'
luajit - <<'LUA'
local failed = false
-- (1.2: the Blood Arena's companion, Olympus_Arena/Olympus_Arena.toc, when the folder is there.)
for _, pair in ipairs({ { "Olympus", "Olympus/Olympus.toc" }, { "Olympus_Arena", "Olympus_Arena/Olympus_Arena.toc" } }) do
	local toc = io.open(pair[2], "r")
	if not toc and pair[1] == "Olympus" then
		io.stderr:write("Cannot read " .. pair[2] .. "\n")
		os.exit(1)
	end
	if toc then
		for line in toc:lines() do
			local entry = line:match("^%s*(.-)%s*$")
			if entry ~= "" and entry:sub(1, 1) ~= "#" then
				local path = pair[1] .. "/" .. entry:gsub("\\", "/")
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
	end
end
if failed then os.exit(1) end
LUA

# 1.1.2: the answer bank the addon loads is the one docs/answers.json makes (the script changes nothing).
if [ -f scripts/answers.lua ]; then
	printf 'Checking the answer bank against docs/answers.json...\n'
	luajit scripts/answers.lua --check
fi

# 1.1.5: the CurseForge store page is what scripts/curseforge-page.lua makes of docs/CURSEFORGE.md,
# and its body fits CurseForge's editor (scripts/curseforge-size.lua's budget). Both change nothing.
if [ -f scripts/curseforge-page.lua ]; then
	printf 'Checking the CurseForge store page...\n'
	luajit scripts/curseforge-page.lua --check
	luajit scripts/curseforge-size.lua --check docs/CURSEFORGE-STORE.md
fi

printf 'Checking local/global name collisions...\n'
bash scripts/lint-globals.sh

# 1.1.5: the gamepad gate's static audit. Every place the addon reaches into the game's own UI is
# registered in Olympus/GamepadRegistry.lua, tagged in the code and behind the gate; it compiles
# the addon's files to read them and runs none of them.
if [ -f scripts/gamepad-audit.lua ]; then
	printf 'Checking the gamepad gate...\n'
	luajit scripts/gamepad-audit.lua
fi

printf 'Running offline tests...\n'
luajit tests/run.lua

printf 'Running the signing round trip...\n'
bash tests/sign-roundtrip.sh

# Max's border textures (Olympus/media/borders): the offline tests check the .tga files
# themselves; with Pillow installed, also that they are what scripts/make-borders.py builds
# from his PNGs in media/borders/src (the script changes nothing with --check).
if [ -f scripts/make-borders.py ]; then
	printf 'Checking the border textures against their PNG sources...\n'
	if command -v python3 >/dev/null 2>&1 && python3 -c 'import PIL' >/dev/null 2>&1; then
		PYTHONDONTWRITEBYTECODE=1 python3 scripts/make-borders.py --check
	else
		printf 'python3 with Pillow not found: the border textures check skipped.\n'
	fi
fi

# Bone Throw's textures (Olympus_Arena/media/farkle, 1.2): what scripts/make-farkle-art.py builds
# from the PNGs in media/farkle/src (the script changes nothing with --check).
if [ -f scripts/make-farkle-art.py ]; then
	printf "Checking Bone Throw's textures against their PNG sources...\n"
	if command -v python3 >/dev/null 2>&1 && python3 -c 'import PIL' >/dev/null 2>&1; then
		PYTHONDONTWRITEBYTECODE=1 python3 scripts/make-farkle-art.py --check
	else
		printf 'python3 with Pillow not found: the Bone Throw textures check skipped.\n'
	fi
fi

# Olympus Link's vectors, sample, draw and inbox, shared with the page's and the Worker's tests:
# checked again with Python's "cryptography" wherever it is installed (the script changes nothing).
if [ -f tests/fixtures/make-link-vectors.py ]; then
	printf "Checking Olympus Link's shared vectors...\n"
	if command -v python3 >/dev/null 2>&1 && python3 -c 'import cryptography' >/dev/null 2>&1; then
		PYTHONDONTWRITEBYTECODE=1 python3 tests/fixtures/make-link-vectors.py --check
	else
		printf 'python3 with "cryptography" not found: the shared vectors check skipped.\n'
	fi
fi

printf 'All repository checks passed.\n'
