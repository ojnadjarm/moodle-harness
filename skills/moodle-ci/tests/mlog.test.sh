#!/usr/bin/env bash
# mlog in a mktemp state dir: log path per component, 7-day and 50-run pruning, component reader.
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/mlog"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tmp" "$T/home" "$T/p1" "$T/p2" "$T/p3"
export TMPDIR="$T/tmp" XDG_STATE_HOME="$T/state"
. "$S"
L="$T/state/moodle-harness/logs"
bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got '$1')"; bad=1; fi; }

f="$(mlog_new mtest-phpunit local_x)"
check "$([[ "$f" =~ ^$L/local_x/mtest-phpunit-[0-9]{8}-[0-9]{6}-.{4}\.log$ ]] && [ -f "$f" ] && echo ok)" ok "path is <home>/<component>/<tool>-<stamp>.log"
check "$(dirname "$(env -u XDG_STATE_HOME HOME="$T/home" bash -c ". '$S'; mlog_new mci local_x")")" \
    "$T/home/.local/state/moodle-harness/logs/local_x" "default home is ~/.local/state"
mlog_new mtest >/dev/null 2>&1; check $? 2 "missing component: rc 2"

d="$L/local_y"; mkdir -p "$d"
for i in $(seq 60); do
    touch -d "-$i minutes" "$d/mtest-phpunit-old$i.log" "$d/mtest-phpunit-old$i.log.clean"
done
touch -d '-8 days' "$d/mtest-phpunit-ancient.log.init" "$d/notes.txt"
mkdir -p "$L/local_z"; touch -d '-1 hour' "$L/local_z/mtest-keep.log"
new="$(mlog_new mtest-phpunit local_y)"
check "$(ls "$d"/*.log | wc -l)" 50 "prune keeps 50 logs"
check "$([ -f "$new" ] && [ -f "$d/mtest-phpunit-old49.log" ] && [ ! -e "$d/mtest-phpunit-old50.log" ] && echo ok)" ok "newest kept, oldest dropped"
check "$(ls "$d"/*.clean | wc -l)" 49 "side files go with their log"
check "$([ -e "$d/mtest-phpunit-ancient.log.init" ] && echo kept || echo gone)" gone "files older than 7 days pruned"
check "$([ -f "$L/local_z/mtest-keep.log" ] && echo kept)" kept "other component untouched"
check "$([ -e "$d/notes.txt" ] && echo kept)" kept "orphan sweep keeps files that are not <log>.<ext>"

d="$L/local_w"; mkdir -p "$d"
touch -d '-8 days' "$d/mci-a.log"; touch -d '-6 days' "$d/mci-b.log"
mlog_new mci local_w >/dev/null
check "$(ls "$d" | grep -c '^mci-[ab]\.log$') $([ -e "$d/mci-b.log" ] && echo b)" "1 b" "under 50: only the > 7 day log goes"

d="$L/local_v"; mkdir -p "$d"
for i in $(seq 55); do touch -d "-$i seconds" "$d/mtest-fresh$i.log"; done
mlog_new mtest local_v >/dev/null
check "$(ls "$d"/*.log | wc -l)" 56 "a log changed < 10 min ago survives prune"
d="$L/local_t"; mkdir -p "$d"
for i in $(seq 55); do touch -d "-$i hours" "$d/mtest-g$i.log"; done
touch -d '-1 minute' "$d/mtest-g55.log.clean"; touch -d '-9 days' "$d/mtest-g54.log.clean"
touch -d '-8 days' "$d/mci-aged.log"; touch -d '-1 day' "$d/mci-aged.log.clean"
mlog_new mtest local_t >/dev/null
check "$(ls "$d" | grep -c '^mtest-g54\.log') $(ls "$d" | grep -c '^mtest-g55\.log') $(ls "$d" | grep -c '^mci-aged')" "0 2 0" \
    "a log and its side files are pruned or kept together"

d="$L/local_u"; mkdir -p "$d"
for i in $(seq 55); do touch -d "-$i hours" "$d/mtest-old$i.log"; done
(flock -n 9 && mlog_new mtest local_u >/dev/null) 9>"$d/.prune.lock"
check "$(ls "$d"/*.log | wc -l)" 56 "no prune while another holds .prune.lock"

echo "<?php \$plugin->component = 'local_one';" > "$T/p1/version.php"
printf '<?php\n$plugin->component  =  "local_two";\n' > "$T/p2/version.php"
check "$(mlog_component "$T/p1") $(mlog_component "$T/p2") [$(mlog_component "$T/p3")]" "local_one local_two []" \
    "component from single, double quotes; none -> empty"
check "$(find "$T/tmp" -mindepth 1 | wc -l)" 0 "nothing written to TMPDIR"
exit $bad
