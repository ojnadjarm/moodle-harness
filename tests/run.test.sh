#!/usr/bin/env bash
# run.sh on a fixture skills dir of sleep/false tests: order, rc, FAIL excerpt, slowest, -j timing, the "# harness: serial" marker.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/run-test-XXXX"); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "ok   $3"; else echo "FAIL $3: got [$1] want [$2]"; fails=$((fails + 1)); fi; }
now() { echo "${EPOCHREALTIME/[.,]/}"; }

mkdir -p "$T/repo/tests" "$T/shared"
cp "$here/run.sh" "$T/repo/tests/run.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/repo/tests/no-machine-values.test.sh"
R="$T/repo/tests/run.sh"
export RUN_TEST_SHARED="$T/shared"
mk() { mkdir -p "$T/$1/moodle-x/tests"; printf '#!/usr/bin/env bash\n%s\n' "$3" > "$T/$1/moodle-x/tests/$2.test.sh"; }
busy='touch "$RUN_TEST_SHARED/busy.$$"; sleep 0.5; rm "$RUN_TEST_SHARED/busy.$$"'
alone='sleep 0.2; ! ls "$RUN_TEST_SHARED"/busy.* >/dev/null 2>&1 || { echo "FAIL not alone"; exit 1; }'

for i in 1 2 3 4; do mk four "s$i" 'sleep 1'; done
t0=$(now); out=$(bash "$R" -j 4 "$T/four"); rc=$?; ms=$(( ($(now) - t0) / 1000 ))
check "$rc $(tail -1 <<<"$out" | grep -o 'green')" "0 green" "-j 4: green, rc 0"
check "$([ "$ms" -lt 2500 ] && echo fast || echo "${ms}ms")" fast "-j 4: 4 x 1 s in < 2.5 s"

mk order a 'sleep 0.6'; mk order b 'sleep 0.1'; mk order c 'echo noise; echo "FAIL boom"; exit 3'; mk order d 'sleep 0.3'
out=$(bash "$R" -j 4 "$T/order"); rc=$?
check "$(grep -oE '(moodle-x/tests/[a-d]|tests/no-machine-values)\.test\.sh$' <<<"$out" | tr '\n' ' ')" \
    "moodle-x/tests/a.test.sh moodle-x/tests/b.test.sh moodle-x/tests/c.test.sh moodle-x/tests/d.test.sh tests/no-machine-values.test.sh " "file order kept"
check "$rc" 1 "a failing file: rc 1"
check "$(grep -A1 'c\.test\.sh$' <<<"$out" | sed -n '1s/ .*//p;2p')" "$(printf 'FAIL\n     FAIL boom')" "FAIL line and excerpt follow the file"
check "$(grep -c 'rc=3 .*c\.test\.sh$' <<<"$out")" 1 "rc of the file shown"
check "$(tail -2 <<<"$out" | head -1 | grep -o 'test\.sh' | wc -l)" 5 "slowest: 5 files"
check "$(tail -2 <<<"$out" | head -1 | cut -d' ' -f2)" moodle-x/tests/a.test.sh "slowest: a first"
check "$(tail -1 <<<"$out" | grep -oE '^total [0-9.]+s, red$' | wc -l)" 1 "last line: total Xs, red"

mk serial p1 "$busy"; mk serial p2 "$busy"; mk serial q "# harness: serial
$alone"; mk serial r "$busy"
out=$(bash "$R" -j 4 "$T/serial"); rc=$?
check "$rc" 0 "harness: serial marker: the file runs alone"
sed -i '/harness: serial/d' "$T/serial/moodle-x/tests/q.test.sh"
out=$(bash "$R" -j 4 "$T/serial"); rc=$?
check "$rc $(grep -c 'FAIL not alone' <<<"$out")" "1 1" "control: without the marker it overlaps"

mk one a 'sleep 0.5'; mk one b 'sleep 0.5'
t0=$(now); out=$(bash "$R" -j 1 "$T/one"); rc=$?; ms=$(( ($(now) - t0) / 1000 ))
check "$rc $([ "$ms" -ge 1000 ] && echo serial || echo "${ms}ms")" "0 serial" "-j 1: one file at a time"

out=$(bash "$R" -j 0 "$T/one" 2>&1); check "$? $(grep -c usage <<<"$out")" "2 1" "-j 0: usage, rc 2"
mkdir -p "$T/empty"; out=$(bash "$R" "$T/empty"); check "$? $(grep -c 'FAIL no skill test files' <<<"$out")" "1 1" "no test files: rc 1"

echo "$fails failed"
[ "$fails" = 0 ]
