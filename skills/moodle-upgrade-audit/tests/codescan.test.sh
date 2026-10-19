#!/usr/bin/env bash
# Fixture UPGRADING.md + fixture plugin (3 planted calls, look-alike decoys) -> exact hits, in a bwrap sandbox with no network.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
fx=$here/fixtures/codescan
cs=$here/../codescan.py
real=${UPGRADING:-$HOME/moodle-envs/5.3/www/UPGRADING.md}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sandbox=(bwrap --unshare-net --ro-bind / / --dev /dev --proc /proc --bind "$out" "$out")
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

check "selftest: sandbox has no network" '! "${sandbox[@]}" python3 -c "import socket; socket.create_connection((\"1.1.1.1\", 443), 3)" 2>/dev/null'
check "selftest: plugin tree is read-only in the sandbox" '! "${sandbox[@]}" touch "$fx/local_fx/x" 2>/dev/null'
"${sandbox[@]}" python3 "$cs" --upgrading "$fx/UPGRADING.md" --symbols > "$out/sym"
check "symbols per version (4.5 out of range, removed beats an earlier deprecation)" 'diff <(printf "5.2\tremoved 2\tdeprecated 0\n5.3\tremoved 0\tdeprecated 1\n") "$out/sym"'
"${sandbox[@]}" python3 "$cs" "$fx/local_fx" --upgrading "$fx/UPGRADING.md" --json "$out/fx.json" > "$out/fx.txt"
check "exactly 3 hits" '[ "$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))[\"hits\"]))" "$out/fx.json")" -eq 3 ]'
check "hits by severity, file:line" 'diff <(printf "removed\tlib.php:8\tcalendar_add_event_metadata\t5.2\nremoved\tlib.php:9\tcore_message\\\\api::get_messages\t5.2\ndeprecated\tlib.php:10\tuser_create_user\t5.3\n") <(python3 -c "import json,sys; [print(h[\"severity\"],h[\"file\"]+\":\"+str(h[\"line\"]),h[\"name\"],h[\"version\"],sep=\"\t\") for h in json.load(open(sys.argv[1]))[\"hits\"]]" "$out/fx.json")'
check "summary with hours" 'grep -qx "local_fx: 3 hits · removed 2 · deprecated 1 · estimate 1.25 h" "$out/fx.txt"'
check "reference cited" 'grep -q "MDL-87426" "$out/fx.txt"'
if [ -f "$real" ]; then
  "${sandbox[@]}" python3 "$cs" --upgrading "$real" --symbols > "$out/real"
  check "real UPGRADING.md: 5.0-5.3 each have removed and deprecated symbols" '[ "$(awk -F"\t" "\$2!=\"removed 0\" && \$3!=\"deprecated 0\"" "$out/real" | cut -f1 | tr "\n" " ")" = "5.0 5.1 5.2 5.3 " ]'
  "${sandbox[@]}" python3 "$cs" "$fx/local_fx" --upgrading "$real" > "$out/realfx.txt"
  check "real UPGRADING.md: fixture plugin gives exactly 3 hits" 'tail -1 "$out/realfx.txt" | grep -q "^local_fx: 3 hits · removed 2 · deprecated 1"'
else
  echo "skip real UPGRADING.md checks ($real missing)"
fi
exit $fail
