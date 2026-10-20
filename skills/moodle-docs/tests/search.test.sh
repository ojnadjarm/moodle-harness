#!/usr/bin/env bash
# search.py on a mktemp mirror fixture: snapshot, latest, unknown version, X.Y token match.
set -u
SEARCH="$(cd "$(dirname "$0")/.." && pwd)/search.py"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export MOODLE_DEVDOCS="$ROOT"
fail=0

page() { mkdir -p "$(dirname "$ROOT/$1")"; printf -- '---\ntitle: %s\n---\n%s\n' "$2" "$3" > "$ROOT/$1"; }
page docs/apis/hooks.md "Hooks Latest" "hook callbacks in the in-dev branch"
page versioned_docs/version-5.0/apis/hooks.md "Hooks Snapshot50" "hook callbacks in 5.0"
page versioned_docs/version-5.2/apis/hooks.md "Hooks Snapshot52" "hook callbacks in 5.2"
page general/upgrade.md "Upgrade notes" "Changes for 4.5 only"
page general/other.md "Other notes" "Version 4 and 5 were released"

check() {
    local name="$1" want="$2"; shift 2
    local out; out="$(python3 "$SEARCH" "$@" 2>&1)"
    if grep -q -- "$want" <<<"$out"; then echo "ok   $name"; else echo "FAIL $name: want '$want', got: $out"; fail=1; fi
}

check "snapshot"        "Hooks Snapshot50" --version 5.0 hook -n 1
check "latest default"  "Hooks Latest"     hook -n 1
check "newer -> docs/"  "Hooks Latest"     --version 5.3 hook -n 1
check "newer note"      "newer than the newest snapshot (5.2); searching docs/" --version 5.3 hook -n 1
check "unknown older"   "version-4.1 not found" --version 4.1 hook -n 1
check "X.Y token"       "Upgrade notes"    "4.5" -n 1
python3 "$SEARCH" --version 4.1 hook >/dev/null 2>&1 && { echo "FAIL unknown older exits 0"; fail=1; }
python3 "$SEARCH" "4.5" -n 5 | grep -q "Other notes" && { echo "FAIL X.Y split into digits"; fail=1; }

[ "$fail" = 0 ] && echo "PASS search.test.sh"
exit "$fail"
