#!/usr/bin/env bash
# Runs every harness test file under nice -n 19, N at a time, one line each in file order; live Docker parts only with MOODLE_HARNESS_LIVE=1.
# Usage: tests/run.sh [-j N] [skills-dir]   (default: -j 4, -j 1 with MOODLE_HARNESS_LIVE=1; ~/.claude/skills)
# A test file with a "# harness: serial" line runs alone.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
par=4; [ "${MOODLE_HARNESS_LIVE:-}" = 1 ] && par=1
[ "${1:-}" = -j ] && { par=${2:-}; shift 2 || true; }
[[ $par =~ ^[1-9][0-9]*$ ]] || { echo "usage: tests/run.sh [-j N] [skills-dir]" >&2; exit 2; }
skills=${1:-$HOME/.claude/skills}
T=$(mktemp -d "${TMPDIR:-/tmp}/harness-run-XXXX"); trap 'rm -rf "$T"' EXIT
red=0
found=0
n=0
next=0
names=()
now() { echo "${EPOCHREALTIME/[.,]/}"; }
secs() { local t=$(( ($(now) - $1) / 100000 )); echo "$((t / 10)).$((t % 10))"; }
start=$(now)

job() {
  local i=$1 t0
  t0=$(now)
  shift
  nice -n 19 "$@" > "$T/$i.out" 2>&1 < /dev/null
  echo "$? $(secs "$t0")" > "$T/$i.tmp" && mv "$T/$i.tmp" "$T/$i.done"
}

flush() {
  local rc s
  while [ -f "$T/$next.done" ]; do
    read -r rc s < "$T/$next.done"
    printf '%-4s rc=%s %5ss %s\n' "$([ $rc = 0 ] && echo ok || echo FAIL)" "$rc" "$s" "${names[next]}"
    echo "$s ${names[next]}" >> "$T/times"
    [ $rc = 0 ] || { red=1; { grep -E 'FAIL' "$T/$next.out" || tail -5 "$T/$next.out"; } | sed 's/^/     /' | head -10; }
    next=$((next + 1))
  done
}

run() {
  local name=$1 f=$2 i=$n
  shift 2
  names[i]=$name
  n=$((n + 1))
  if grep -q '^# harness: serial' "$f"; then
    wait; flush; job "$i" bash "$f" "$@"; flush
  else
    while [ "$(jobs -rp | wc -l)" -ge "$par" ]; do wait -n; flush; done
    job "$i" bash "$f" "$@" &
  fi
}

for f in "$skills"/moodle-*/tests/*.test.sh "$skills"/set-moodle-harness/tests/*.test.sh; do
  [ -f "$f" ] && { found=$((found + 1)); run "${f#"$skills"/}" "$f"; }
done
[ $found -gt 0 ] || { echo "FAIL no skill test files under $skills"; red=1; }
run tests/no-machine-values.test.sh "$here/no-machine-values.test.sh" "$(dirname "$here")"
wait; flush

printf 'slowest: %s\n' "$(sort -rn "$T/times" | head -5 | awk '{printf "%s%s %ss", (NR > 1 ? ", " : ""), $2, $1}')"
printf 'total %ss, %s\n' "$(secs "$start")" "$([ $red = 0 ] && echo green || echo red)"
exit $red
