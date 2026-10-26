#!/usr/bin/env bash
# moodle-stop-reminder.sh against mktemp git fixtures: block once per diff, only the changed component's log silences it.
set -uo pipefail
H="$HOME/.claude/hooks/moodle-stop-reminder.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/plugin/classes" "$T/plain" "$T/tmp" "$T/state" "$T/q\"uote/classes" "$T/core/lib" "$T/core/local/a/classes" "$T/core/local/b" "$T/del/classes" "$T/perf/lib"
L="$T/state/moodle-harness/logs"
gitinit() { git -C "$1" init -q && git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm init; }
printf '<?php\n$plugin->component = "local_x";\n' > "$T/plugin/version.php"
printf "<?php\n\$plugin->component = 'local_q';\n" > "$T/q\"uote/version.php"
echo '<?php' > "$T/core/lib/moodlelib.php"
printf "<?php\n\$plugin->component = 'local_a';\n" > "$T/core/local/a/version.php"
printf "<?php\n\$plugin->component = 'local_b';\n" > "$T/core/local/b/version.php"
printf "<?php\n\$plugin->component = 'local_d';\n" > "$T/del/version.php"
echo '<?php' > "$T/del/classes/one.php"; echo '<?php' > "$T/del/classes/two.php"
echo '<?php' > "$T/perf/lib/moodlelib.php"
for i in $(seq 1 30); do mkdir -p "$T/perf/local/p$i/classes"; printf "<?php\n\$plugin->component = 'local_p$i';\n" > "$T/perf/local/p$i/version.php"; done
for d in plugin 'q"uote' core del perf; do gitinit "$T/$d"; done

bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got '$1')"; bad=1; fi; }
run() { printf '%s' "${2:-{\"stop_hook_active\":false\}}" | CLAUDE_PROJECT_DIR="$1" TMPDIR="$T/tmp" XDG_STATE_HOME="$T/state" "$H"; echo "rc=$?"; }
newlog() { mkdir -p "$L/$1" && touch -d '+2 seconds' "$L/$1/$2"; }
blocked() { run "$@" | head -1 | jq -r .decision 2>/dev/null; }

check "$(run "$T/plugin")" "rc=0" "clean tree: silent"
check "$(run "$T/plain")" "rc=0" "non-Moodle dir: silent"
echo '<?php // x' > "$T/plugin/classes/a.php"
check "$(run "$T/plugin" '{"stop_hook_active":true}')" "rc=0" "stop_hook_active: silent"
t0=$(date +%s%N)
j="$(run "$T/plugin" | head -1)"
check "$(jq -r .decision <<<"$j" 2>/dev/null)" "block" "PHP changed, no CI log: decision block"
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
check "$([ "$ms" -lt 500 ] && echo fast)" "fast" "runtime ${ms} ms < 500"
check "$(jq -r '.reason | contains("mci auto: the checks the change class needs") and (contains("PHPUnit") | not) | tostring' <<<"$j" 2>/dev/null)" "true" "reason names mci auto"
check "$(run "$T/plugin")" "rc=0" "same diff hash: silent"
echo '<?php // y' >> "$T/plugin/version.php"
check "$(blocked "$T/plugin")" "block" "new diff hash: blocks again"
echo '<?php // z' >> "$T/plugin/version.php"
newlog local_other mtest-phpunit-20261020-000000-abcd.log
newlog local_other mci-20261020-000000-abcd.log
check "$(blocked "$T/plugin")" "block" "other plugin's newer log does not silence"
echo '<?php // w' >> "$T/plugin/version.php"
newlog local_x mtest-phpunit-20261020-000000-abcd.log
check "$(run "$T/plugin")" "rc=0" "own mtest log newer than PHP: silent"
echo '<?php // v' >> "$T/plugin/version.php"
rm -rf "$L/local_x"; newlog local_x mci-20261020-000000-abcd.log
check "$(run "$T/plugin")" "rc=0" "own mci log newer than PHP: silent"
echo '<?php // x' > "$T/q\"uote/classes/a.php"
j="$(run "$T/q\"uote" | head -1)"
check "$(jq -r '.decision + " " + (.reason | contains("q\"uote") | tostring)' <<<"$j" 2>/dev/null)" "block true" "quote in path: valid JSON with the path"
echo '<?php // y' >> "$T/core/lib/moodlelib.php"
newlog local_any mtest-phpunit-20261020-000000-abcd.log
check "$(run "$T/core")" "rc=0" "core root: any plugin's log counts"
echo '<?php' > "$T/core/lib/moodlelib.php"
echo '<?php // a' > "$T/core/local/a/classes/x.php"
newlog local_b mtest-phpunit-20261020-000001-abcd.log
j="$(run "$T/core" | head -1)"
check "$(jq -r '.decision + " " + (.reason | contains("(local_a)") | tostring)' <<<"$j" 2>/dev/null)" "block true" "core root: B's run does not silence an A-only change"
rm -rf "$L/local_b"
echo '<?php // a2' >> "$T/core/local/a/classes/x.php"
newlog local_a mtest-phpunit-20261020-000001-abcd.log
check "$(run "$T/core")" "rc=0" "core root: plugin A's run silences an A-only change"
echo '<?php // b' >> "$T/core/local/b/version.php"
newlog local_a mci-20261020-000001-abcd.log
j="$(run "$T/core" | head -1)"
check "$(jq -r '.decision + " " + (.reason | contains("local_b") and (contains("local_a") | not) | tostring)' <<<"$j" 2>/dev/null)" "block true" "core root: A's run does not silence a B change"
mkdir -p "$T/del/lang/en" "$T/del/templates"; echo "<?php \$string['a'] = 'A';" > "$T/del/lang/en/local_d.php"; echo '<?php' > "$T/del/templates/t.php"
check "$(run "$T/del")" "rc=0" "lang/** and templates/** PHP only: silent (T1399)"
rm "$T/del/classes/one.php"
check "$(blocked "$T/del")" "block" "deletion-only diff: blocks"
rm "$T/del/classes/two.php"; newlog local_d mtest-phpunit-20261020-000000-abcd.log
check "$(run "$T/del")" "rc=0" "deletion-only diff, own log newer: silent"
for i in $(seq 1 30); do for k in $(seq 1 20); do echo '<?php' > "$T/perf/local/p$i/classes/c$k.php"; done; done
for k in $(seq 1 100); do echo '<?php' > "$T/perf/lib/l$k.php"; done
t0=$(date +%s%N)
check "$(blocked "$T/perf")" "block" "core root, 700 changed files: decision block"
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
check "$([ "$ms" -lt 500 ] && echo fast)" "fast" "core root runtime ${ms} ms < 500"
mkdir -p "$T/fake/hooks"; cp "$H" "$(dirname "$H")/moodle-detect.sh" "$T/fake/hooks/"
echo '<?php // u' >> "$T/plugin/version.php"
j="$(H="$T/fake/hooks/moodle-stop-reminder.sh" run "$T/plugin" | head -1)"
check "$(jq -r '.decision + " " + (.reason | contains("'"$T"'/fake/skills/moodle-ci/scripts/mlog is missing") | tostring)' <<<"$j" 2>/dev/null)" "block true" "missing mlog: blocks and names the file"
check "$(H="$T/fake/hooks/moodle-stop-reminder.sh" run "$T/plugin")" "rc=0" "missing mlog: fires once"
check "$(find "$T/tmp" -mindepth 1 | wc -l)" "0" "nothing written to TMPDIR"
exit $bad
