#!/usr/bin/env bash
# Fixture tests for wire-hooks.py: fresh file, re-run, fleet SessionStart present, other keys preserved.
set -uo pipefail
script="$(cd "$(dirname "$0")/.." && pwd)/wire-hooks.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
count() { python3 -c 'import json,sys;h=json.load(open(sys.argv[1]))["hooks"];print(sum(x.get("command","").endswith(sys.argv[3]) for g in h.get(sys.argv[2],[]) for x in g["hooks"]))' "$@"; }

f=$tmp/fresh.json
python3 "$script" "$f" >/dev/null
check "fresh: SessionStart + Stop added" '[ "$(count "$f" SessionStart /moodle-session-start.sh)" = 1 ] && [ "$(count "$f" Stop /moodle-stop-reminder.sh)" = 1 ]'

cp "$f" "$tmp/before.json"
out=$(python3 "$script" "$f")
check "re-run: no changes, bytes identical" 'grep -q "no changes" <<< "$out" && cmp -s "$f" "$tmp/before.json"'

f=$tmp/fleet.json
echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"$HOME/agents/adapters/claude/hooks/session-start.sh"}]}]}}' > "$f"
python3 "$script" "$f" >/dev/null
check "fleet: no moodle SessionStart, fleet kept, Stop added" '[ "$(count "$f" SessionStart /moodle-session-start.sh)" = 0 ] && [ "$(count "$f" SessionStart /session-start.sh)" = 1 ] && [ "$(count "$f" Stop /moodle-stop-reminder.sh)" = 1 ]'

f=$tmp/other.json
echo '{"model":"x","permissions":{"allow":["Bash(ls)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"$HOME/.claude/hooks/moodle-stop-reminder.sh"}]}],"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/x/guard.py"}]}]}}' > "$f"
python3 "$script" "$f" >/dev/null
check "other keys and hooks kept, Stop not doubled" 'python3 -c "import json,sys;d=json.load(open(sys.argv[1]));assert d[\"model\"]==\"x\" and d[\"permissions\"][\"allow\"]==[\"Bash(ls)\"] and d[\"hooks\"][\"PreToolUse\"][0][\"hooks\"][0][\"command\"]==\"/x/guard.py\"" "$f" && [ "$(count "$f" Stop /moodle-stop-reminder.sh)" = 1 ] && [ "$(count "$f" SessionStart /moodle-session-start.sh)" = 1 ]'

exit $fail
