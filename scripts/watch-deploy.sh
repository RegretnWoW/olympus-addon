#!/usr/bin/env bash
# Keeps the WoW PC on the latest push of a branch: checks GitHub every 20 s and runs
# scripts/deploy.sh (from that commit) whenever the branch moves. Then /reload in game.
# Your working copy is not touched: each push is unpacked into a temp folder.
#   WOW_HOST=user@192.168.0.10 scripts/watch-deploy.sh [branch]
# Deploys to every WoW folder (_classic_era_, _anniversary_...) that already has Olympus,
# or only to WOW_FLAVOR if set. Same optional WOW_DIR as deploy.sh; WATCH_INTERVAL in
# seconds. Ctrl+C stops it.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
: "${WOW_HOST:?set WOW_HOST=user@ip}"
export WOW_DIR="${WOW_DIR:-C:/Program Files (x86)/World of Warcraft}"
BRANCH="${1:-main}"
INTERVAL="${WATCH_INTERVAL:-20}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
last=""

# The WoW folders that have Olympus installed (WOW_FLAVOR alone if set; empty = deploy.sh's default).
flavors() {
	if [ -n "${WOW_FLAVOR:-}" ]; then echo "$WOW_FLAVOR"; return; fi
	ssh "$WOW_HOST" "powershell -NoProfile -Command \"Get-ChildItem -Directory -Path '$WOW_DIR/*/Interface/AddOns/Olympus' -ErrorAction SilentlyContinue | ForEach-Object { \$_.Parent.Parent.Parent.Name }\"" | tr -d '\r'
}

deploy() {
	local list f ok=0
	list=$(flavors)
	[ -n "$list" ] || list="-"
	for f in $list; do
		if [ "$f" = "-" ]; then
			"$WORK/tree/scripts/deploy.sh" >/dev/null || ok=1
		else
			WOW_FLAVOR="$f" "$WORK/tree/scripts/deploy.sh" >/dev/null || ok=1
		fi
	done
	[ "$list" = "-" ] && list="default folder"
	DEPLOYED="$list"
	return $ok
}

echo "watching origin/$BRANCH -> $WOW_HOST (every ${INTERVAL}s, Ctrl+C to stop)"
while true; do
	if git fetch -q origin "$BRANCH" 2>/dev/null; then
		sha=$(git rev-parse FETCH_HEAD)
		if [ "$sha" != "$last" ]; then
			rm -rf "$WORK/tree" && mkdir -p "$WORK/tree"
			# (1.2: the Blood Arena's companion folder too, on a branch that has it.)
			paths="Olympus scripts"
			git cat-file -e "$sha:Olympus_Arena" 2>/dev/null && paths="Olympus Olympus_Arena scripts"
			git archive "$sha" $paths | tar -xf - -C "$WORK/tree"
			if deploy; then
				last=$sha
				echo "$(date +%H:%M:%S) deployed $(git log -1 --format='%h %s' "$sha") to ${DEPLOYED//$'\n'/ }  -> /reload in game"
				osascript -e "display notification \"/reload in game\" with title \"Olympus ${sha:0:7} deployed\"" 2>/dev/null || true
			else
				echo "$(date +%H:%M:%S) deploy of ${sha:0:7} failed, trying again in ${INTERVAL}s"
			fi
		fi
	fi
	sleep "$INTERVAL"
done
