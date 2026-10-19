#!/usr/bin/env bash
# Fixture plugin list -> expected verdicts, run inside a bwrap sandbox with no network.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
fx=$here/fixtures
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sandbox=(bwrap --unshare-net --ro-bind / / --dev /dev --proc /proc --bind "$out" "$out")
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

check "selftest: sandbox has no network" '! "${sandbox[@]}" python3 -c "import socket; socket.create_connection((\"1.1.1.1\", 443), 3)" 2>/dev/null'
"${sandbox[@]}" python3 "$here/../audit.py" --plugins "$fx/plugins.json" --pluglist "$fx/pluglist.json" \
  --target 5.3 --now 2026-10-19 --label "Fixture site" --md "$out/a.md" --html "$out/a.html" --json "$out/a.json" > "$out/stdout"
python3 -c 'import json,sys; [print(r["component"]+"\t"+r["verdict"]) for r in json.load(open(sys.argv[1]))["rows"]]' "$out/a.json" > "$out/got.tsv"
check "verdicts match expected.tsv" 'diff "$fx/expected.tsv" "$out/got.tsv"'
check "summary line" 'grep -qx "7 add-ons · keep 4 · replace 1 · remove 2" "$out/stdout"'
check "update note for an older install" 'grep -q "update to 2.0 (2026090100)" "$out/a.md"'
check "stale plugin dated" 'grep -q "no release since 2023-05-01" "$out/a.md"'
check "status from the directory" 'grep -q "no 5.3 version (newest supports 4.2)" "$out/a.md"'
check "html escapes names" 'grep -q "Custom &lt;b&gt;tools&lt;/b&gt;" "$out/a.html" && ! grep -q "<b>tools" "$out/a.html"'
check "html has 7 rows" '[ "$(grep -o "<tr><td" "$out/a.html" | wc -l)" -eq 7 ]'
check "html is responsive" 'grep -q "width=device-width" "$out/a.html" && grep -q "@media (max-width:48rem)" "$out/a.html"'
exit $fail
