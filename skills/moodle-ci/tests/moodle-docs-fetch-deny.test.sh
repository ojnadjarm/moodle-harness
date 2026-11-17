#!/usr/bin/env bash
# moodle-docs-fetch-deny.sh: moodledev.io denied with the mirror pointer, #not-in-mirror and other hosts pass, bad input fails open.
set -uo pipefail
H="$(cd "$(dirname "$0")/../../.." && pwd)/hooks/moodle-docs-fetch-deny.sh"
bad=0
check() { if eval "$1"; then echo "PASS $2"; else echo "FAIL $2"; bad=1; fi; }
hook() { printf '%s' "$1" | "$H"; }
req() { printf '{"tool_name":"WebFetch","tool_input":{"url":"%s","prompt":"x"}}' "$1"; }

out="$(hook "$(req https://moodledev.io/docs/5.0/apis/core/dml)")"; rc=$?
check '[ $rc = 0 ] && python3 -c "import json,sys;h=json.loads(sys.argv[1])[\"hookSpecificOutput\"];assert h[\"permissionDecision\"]==\"deny\" and \"/moodle-docs\" in h[\"permissionDecisionReason\"] and \"#not-in-mirror\" in h[\"permissionDecisionReason\"]" "$out"' "moodledev.io: deny JSON naming /moodle-docs and the pass"
out="$(hook "$(req http://www.moodledev.io)")"
check 'grep -q "\"deny\"" <<<"$out"' "subdomain, no path: deny"
out="$(hook "$(req https://moodledev.io/docs/5.0/apis/x#not-in-mirror)")"; rc=$?
check '[ $rc = 0 ] && [ -z "$out" ]' "#not-in-mirror: passes"
for u in https://docs.moodle.org/dev/Events_API https://moodledev.io.example.com/x https://example.com/?u=moodledev.io; do
    out="$(hook "$(req "$u")")"; rc=$?
    check '[ $rc = 0 ] && [ -z "$out" ]' "other host passes: $u"
done
out="$(hook 'not json')"; rc=$?
check '[ $rc = 0 ] && [ -z "$out" ]' "bad input: fails open"
exit "$bad"
