#!/usr/bin/env bash
# Guard selftest on a fixture HOME: real env paths are refused, the throwaway path is allowed.
set -u
S="$(cd "$(dirname "$0")/.." && pwd)/rehearse.sh"
FX="$(mktemp -d)"; trap 'rm -rf "$FX"' EXIT
mkdir -p "$FX/moodle-envs/"{4.5,vass,vass-services,5.3,shared,4.5-rehearsal}
fail=0
refused() { HOME="$FX" REHEARSAL_DIR="${1:-$FX/moodle-envs/4.5-rehearsal}" REHEARSAL_PROJECT="${2:-moodle45r}" "$S" nocmd 2>&1 | grep -q '^refused'; }
for d in 4.5 vass vass/moodle vass-services 5.3 shared; do
    refused "$FX/moodle-envs/$d" || { echo "FAIL: $d not refused"; fail=1; }
done
for p in moodle45 moodle53 vass-services moodle-shared; do
    refused "" "$p" || { echo "FAIL: project $p not refused"; fail=1; }
done
refused && { echo "FAIL: throwaway path refused"; fail=1; }
[ "$fail" = 0 ] && echo "guard.test: ok"
exit "$fail"
