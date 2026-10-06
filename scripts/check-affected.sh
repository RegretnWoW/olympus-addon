#!/usr/bin/env bash
# Full static/aux checks; only complete mapped Arena modules may be omitted.
set -euo pipefail
cd "$(dirname "$0")/.."
for affected_filter in OLYMPUS_TEST_FILTER OLYMPUS_TEST_AUTHORITY_ONLY OLYMPUS_TEST_WATCH_ONLY OLYMPUS_TEST_ARENA_MODULES; do
	if [ -n "${!affected_filter:-}" ]; then
		printf 'Refusing inherited selector %s: affected checks must retain shared setup.\n' "$affected_filter" >&2
		exit 2
	fi
done
affected_paths=()
if [ "${1:-}" = "--base" ] && [ "$#" -eq 2 ]; then
	git rev-parse --verify "$2^{commit}" >/dev/null
	affected_tmp=$(mktemp -d)
	trap 'rm -rf "$affected_tmp"' EXIT
	# Do not hide Git failure behind process substitution and accidentally select a partial list.
	git diff --name-only -z "$2" -- > "$affected_tmp/tracked"
	git ls-files --others --exclude-standard -z > "$affected_tmp/untracked"
	while IFS= read -r -d '' affected_path; do affected_paths+=("$affected_path"); done < "$affected_tmp/tracked"
	while IFS= read -r -d '' affected_path; do affected_paths+=("$affected_path"); done < "$affected_tmp/untracked"
elif [ "${1:-}" = "--files" ] && [ "$#" -gt 1 ]; then
	shift
	affected_paths=("$@")
else
	printf 'Usage: bash scripts/check-affected.sh --base <verified-baseline-commit> | --files <path>...\n' >&2
	exit 2
fi
affected_plan=$(luajit scripts/check-affected.lua "${affected_paths[@]}")
affected_mode=FULL
affected_modules=""
while IFS=$'\t' read -r affected_key affected_value; do
	case "$affected_key" in
		MODE) affected_mode=$affected_value ;;
		REASON) printf 'Affected-check reason: %s\n' "$affected_value" ;;
		MODULE) affected_modules="${affected_modules}${affected_value}"$'\n' ;;
		*) printf 'Invalid selector output.\n' >&2; exit 2 ;;
	esac
done <<< "$affected_plan"
if [ "$affected_mode" = AFFECTED ]; then
	# Without the module-aware harness integration, running FULL is safer than pretending to focus.
	if ! rg -q 'OLYMPUS_TEST_ARENA_MODULES' tests/run.lua; then
		printf 'Module-aware harness unavailable; falling back FULL.\n'
	else
		[ -n "$affected_modules" ] || { printf 'Empty module selection.\n' >&2; exit 2; }
		export OLYMPUS_TEST_ARENA_MODULES="$affected_modules"
		printf 'Affected Arena modules selected; complete main harness, gamepad and auxiliary checks retained.\n'
	fi
elif [ "$affected_mode" != FULL ]; then
	printf 'Invalid selector mode.\n' >&2; exit 2
fi
bash scripts/check.sh
