#!/usr/bin/env bash
# Flag contract: every moodle-ci script `--help` rc 0 and `--bogus` usage rc within the timeout; every pluginskel *.py `--help` rc 0.
set -uo pipefail
H="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/cwd"
printf '#!/bin/sh\necho "fake docker $*" >&2\nexit 1\n' > "$T/bin/docker"; chmod +x "$T/bin/docker"
export PATH="$T/bin:$PATH"
TO="${CLI_TIMEOUT:-5}"
# mdb and mws document 64 (EX_USAGE) for their own refusals.
declare -A USAGE_RC=([mdb]=64 [mws]=64)

# contract <scripts-dir> <skel-dir>: prints FAIL lines and the checked count; rc 1 on any miss.
contract() {
    local s=$1 k=$2 f n rc want fail=0 c=0
    for f in "$s"/*; do
        [ -f "$f" ] || continue
        n="$(basename "$f")"
        if [ ! -x "$f" ]; then
            head -3 "$f" | grep -q '^# Sourced by' && continue
            echo "FAIL $n: not executable"; fail=1; continue
        fi
        (cd "$T/cwd" && timeout "$TO" "$f" --help </dev/null >/dev/null 2>&1); rc=$?
        [ $rc -eq 0 ] || { echo "FAIL $n --help: rc $rc"; fail=1; }
        want="${USAGE_RC[$n]:-2}"
        (cd "$T/cwd" && timeout "$TO" "$f" --bogus </dev/null >/dev/null 2>&1); rc=$?
        [ $rc -eq 124 ] && { echo "FAIL $n --bogus: hangs (> ${TO}s)"; fail=1; }
        [ $rc -ne 124 ] && [ $rc -ne "$want" ] && { echo "FAIL $n --bogus: rc $rc, want $want"; fail=1; }
        c=$((c + 1))
    done
    for f in "$k"/*.py; do
        [ -f "$f" ] || continue
        (cd "$T/cwd" && timeout "$TO" python3 "$f" --help </dev/null >/dev/null 2>&1); rc=$?
        [ $rc -eq 0 ] || { echo "FAIL $(basename "$f") --help: rc $rc"; fail=1; }
        c=$((c + 1))
    done
    [ $c -gt 0 ] || { echo "FAIL: nothing checked in $s $k"; return 1; }
    echo "checked $c"
    return $fail
}

# Self-test: a hang, a wrong usage rc, a broken --help and a non-executable non-library must each be red.
fx="$T/fx"; mkdir -p "$fx/s" "$fx/k"
printf '#!/bin/sh\n[ "$1" = --help ] && exit 0\nwhile :; do sleep 1; done\n' > "$fx/s/hang"
printf '#!/bin/sh\n[ "$1" = --help ] && exit 0\nexit 1\n' > "$fx/s/rc1"
printf '#!/bin/sh\n[ "$1" = --help ] && exit 0\nexit 2\n' > "$fx/s/good"
printf '#!/bin/sh\nexit 2\n' > "$fx/s/nohelp"
chmod +x "$fx/s/"*
printf '#!/bin/sh\nexit 0\n' > "$fx/s/noexec"
printf '# Sourced by mtest.\nlib() { :; }\n' > "$fx/s/lib"
printf 'import sys\nsys.exit(3)\n' > "$fx/k/bad.py"
out="$(TO=1 contract "$fx/s" "$fx/k")" && { echo "FAIL selftest: fixture passed"; exit 1; }
for want in "hang --bogus: hangs" "rc1 --bogus: rc 1, want 2" "nohelp --help: rc 2" "noexec: not executable" "bad.py --help: rc 3"; do
    grep -qF "$want" <<<"$out" || { echo "FAIL selftest: no '$want' in: $out"; exit 1; }
done
grep -qE 'FAIL (good|lib)' <<<"$out" && { echo "FAIL selftest: good/lib flagged: $out"; exit 1; }

out="$(contract "$H/moodle-ci/scripts" "$H/moodle-pluginskel")"; rc=$?
grep '^FAIL' <<<"$out"
[ $rc -eq 0 ] || { echo "FAILED"; exit 1; }
echo "PASS: ${out##*checked } CLIs keep the flag contract (selftest: 5 breaks red)"
