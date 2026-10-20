#!/usr/bin/env bash
# Drive task.py on mktemp plugins: scheduled + adhoc, db/tasks.php create and merge, lang, version, php -l, codechecker, refusals.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
S="$(cd "$(dirname "$0")/.." && pwd)"
K="$S/task.py"; G="$S/generate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
version() { sed -n 's/^\$plugin->version = \([0-9]*\);/\1/p' "$1/version.php"; }

render() {
    mkdir -p "$T/$1"
    printf 'component: %s\nrequires: "%s"\ncopyright: 2026 onwards, Example Author <author@example.com>\n' "$2" "$1" > "$T/$1/recipe.yaml"
    python3 "$G" --target-dir "$T/$1" "$T/$1/recipe.yaml" >/dev/null 2>"$T/err" || bad "$1 skeleton: $(cat "$T/err")"
}

render 4.5 mod_demo; P45="$T/4.5/demo"
render 4.1 local_demo; P41="$T/4.1/demo"
v0="$(version "$P45")"
python3 "$K" "$P45" send_reminders --scheduled "*/15 R * * 1-5" >"$T/out" 2>&1 && ok "scheduled renders" || bad "scheduled rc: $(cat "$T/out")"
v1="$(version "$P45")"; [ "$v1" -gt "$v0" ] && ok "version bumped $v0 -> $v1" || bad "version not bumped: $v1"
vA="$(version "$P45")"
python3 "$K" "$P45" process_item --adhoc >"$T/out" 2>&1 && ok "adhoc renders" || bad "adhoc rc: $(cat "$T/out")"
[ "$(version "$P45")" = "$vA" ] && ok "adhoc leaves version.php alone" || bad "adhoc bumped version"
[ ! -e "$P41/db/tasks.php" ] && python3 "$K" "$P41" do_work --adhoc >/dev/null 2>&1 && [ ! -e "$P41/db/tasks.php" ] \
    && ok "adhoc writes no db/tasks.php" || bad "adhoc wrote db/tasks.php"

cs="$P45/classes/task/send_reminders.php"; ca="$P45/classes/task/process_item.php"
grep -q 'class send_reminders extends \\core\\task\\scheduled_task {' "$cs" \
    && grep -q "return get_string('task_send_reminders', 'mod_demo');" "$cs" \
    && ok "scheduled class: scheduled_task + get_name via get_string" || bad "scheduled class: $(cat "$cs")"
grep -q 'class process_item extends \\core\\task\\adhoc_task {' "$ca" && grep -q '\$this->get_custom_data();' "$ca" \
    && grep -q 'set_custom_data(' "$ca" && ok "adhoc class: adhoc_task + custom data" || bad "adhoc class: $(cat "$ca")"
tp="$P45/db/tasks.php"
php -r "define('MOODLE_INTERNAL', 1); include '$tp'; \$t = \$tasks[0];
    exit(count(\$tasks) == 1 && \$t['classname'] == 'mod_demo\\task\\send_reminders' && \$t['minute'] == '*/15'
        && \$t['hour'] == 'R' && \$t['dayofweek'] == '1-5' && \$t['month'] == '*' ? 0 : 1);" \
    && ok "db/tasks.php entry: classname + schedule" || bad "db/tasks.php: $(cat "$tp")"
lang="$P45/lang/en/demo.php"
grep -q "^\$string\['task_send_reminders'\] = 'Send reminders';" "$lang" && grep -q "^\$string\['task_process_item'\]" "$lang" \
    && ok "lang strings added" || bad "lang: $(cat "$lang")"
ids="$(sed -n "s/^\$string\['\([^']*\)'\].*/\1/p" "$lang")"
ids="$(grep -v '^pluginname$' <<<"$ids")"
[ "$ids" = "$(LC_ALL=C sort <<<"$ids")" ] && ok "lang strings inserted in order" || bad "lang order: $ids"
grep -q 'manager::get_scheduled_task(send_reminders::class)' "$P45/tests/task/send_reminders_test.php" \
    && grep -q '\$task->execute();' "$P45/tests/task/send_reminders_test.php" \
    && ok "scheduled test: execute" || bad "scheduled test body"
ta45="$P45/tests/task/process_item_test.php"; ta41="$P41/tests/task/do_work_test.php"
grep -q 'queue_adhoc_task(process_item::instance(42));' "$ta45" && grep -q '\$this->run_all_adhoc_tasks();' "$ta45" \
    && grep -q '\\phpunit_util::run_all_adhoc_tasks();' "$ta41" \
    && ok "adhoc test: queue + run_all_adhoc_tasks (4.1 via phpunit_util)" || bad "adhoc test body"

python3 "$K" "$P45" cleanup --scheduled "0 3 * * *" >"$T/out" 2>&1 || bad "merge rc: $(cat "$T/out")"
php -r "define('MOODLE_INTERNAL', 1); include '$tp';
    exit(count(\$tasks) == 2 && \$tasks[0]['classname'] == 'mod_demo\\task\\send_reminders'
        && \$tasks[1]['classname'] == 'mod_demo\\task\\cleanup' ? 0 : 1);" \
    && [ "$(grep -c '^\$tasks = ' "$tp")" = 1 ] && ok "merge keeps the existing entry" || bad "merge: $(cat "$tp")"
mkdir -p "$T/arr/db" "$T/arr/lang/en"; cp "$P41/version.php" "$T/arr/"; cp "$P41/lang/en/local_demo.php" "$T/arr/lang/en/"
printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\$tasks = array(\n    array('classname' => '\\\\local_demo\\\\task\\\\old', 'minute' => '*')\n);\n" > "$T/arr/db/tasks.php"
python3 "$K" "$T/arr" fresh --scheduled "5 * * * *" >/dev/null 2>"$T/err" \
    && php -r "define('MOODLE_INTERNAL', 1); include '$T/arr/db/tasks.php'; exit(count(\$tasks) == 2 ? 0 : 1);" \
    && ok "merge into array() keeps old entry" || bad "array() merge: $(cat "$T/err" "$T/arr/db/tasks.php")"
tasksfixture() {
    rm -rf "$T/$1"; mkdir -p "$T/$1/db" "$T/$1/lang/en"
    cp "$P41/version.php" "$T/$1/"; cp "$P41/lang/en/local_demo.php" "$T/$1/lang/en/"
    printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n%s\n" "$2" > "$T/$1/db/tasks.php"
}
old="'classname' => 'local_demo\\\\\\\\task\\\\\\\\old', 'minute' => '*'"
for c in "spaced|\$tasks = array (\n    array($old)\n);" "indented|if (true) {\n    \$tasks = [\n        [$old],\n    ];\n}" \
    "nospace|\$tasks=[[$old]];"; do
    tasksfixture "${c%%|*}" "$(printf "${c#*|}")"
    python3 "$K" "$T/${c%%|*}" fresh --scheduled "5 * * * *" >/dev/null 2>"$T/err" && php -l "$T/${c%%|*}/db/tasks.php" >/dev/null \
        && php -r "define('MOODLE_INTERNAL', 1); include '$T/${c%%|*}/db/tasks.php';
            exit(count(\$tasks) == 2 && \$tasks[0]['classname'] == 'local_demo\\task\\old'
                && \$tasks[1]['classname'] == 'local_demo\\task\\fresh' ? 0 : 1);" \
        && [ "$(grep -c '\$tasks *=' "$T/${c%%|*}/db/tasks.php")" = 1 ] \
        && ok "merge into ${c%%|*} \$tasks keeps old entry" || bad "${c%%|*} merge: $(cat "$T/err" "$T/${c%%|*}/db/tasks.php")"
done
tasksfixture var "\$tasks = \$othertasks;"
before="$(md5sum "$T/var/db/tasks.php" "$T/var/version.php")"
python3 "$K" "$T/var" fresh --scheduled "5 * * * *" >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'not as a \[ or array( literal' "$T/out" && [ ! -e "$T/var/classes/task/fresh.php" ] \
    && [ "$before" = "$(md5sum "$T/var/db/tasks.php" "$T/var/version.php")" ] \
    && ok "\$tasks set without a literal refused rc 1, nothing written" || bad "var refusal rc=$rc: $(cat "$T/out")"

before="$(md5sum "$T/arr/db/tasks.php" "$T/arr/version.php")"
python3 "$K" "$T/arr" old --scheduled "0 0 * * *" >"$T/out" 2>&1 && bad "registered task accepted" \
    || { grep -q 'already exists in' "$T/out" && [ "$before" = "$(md5sum "$T/arr/db/tasks.php" "$T/arr/version.php")" ] \
        && ok "task already in db/tasks.php refused, nothing written" || bad "tasks.php refusal: $(cat "$T/out")"; }

lintfail=0; n=0
for f in "$P45"/classes/task/*.php "$P45"/tests/task/*.php "$tp" "$lang" "$P41"/classes/task/*.php "$P41"/tests/task/*.php; do
    n=$((n + 1)); php -l "$f" >/dev/null 2>&1 || { lintfail=1; bad "php -l $f: $(php -l "$f" 2>&1)"; }
done
[ "$lintfail" = 0 ] && ok "php -l clean ($n files)"
for p in "$P45" "$P41"; do
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker "$p" 2>&1)"; rc=$?
        if grep -q '| ERROR |' <<<"$out"; then bad "$p codechecker: $(grep -c '| ERROR |' <<<"$out") errors"
        elif [ "$rc" -ne 0 ]; then bad "$p codechecker rc=$rc"
        else ok "codechecker 0 errors ${p#"$T"/}"; fi
    else
        echo "SKIP codechecker: moodle-plugin-ci absent"
    fi
done

before="$(md5sum "$tp" "$P45/version.php" "$cs" "$lang")"
python3 "$K" "$P45" send_reminders --scheduled "0 0 * * *" >"$T/out" 2>&1 && bad "existing class accepted" \
    || { grep -q 'send_reminders.php already exists' "$T/out" && [ "$before" = "$(md5sum "$tp" "$P45/version.php" "$cs" "$lang")" ] \
        && ok "existing class refused, nothing written" || bad "class refusal: $(cat "$T/out")"; }
python3 "$K" "$P45" process_item --adhoc >"$T/out" 2>&1 && bad "existing adhoc class accepted" \
    || { grep -q 'already exists' "$T/out" && ok "existing adhoc class refused" || bad "adhoc refusal: $(cat "$T/out")"; }
for cron in "0 0 * *" "0 0 * R *" "0 0 R * *" "99 0 * * *" "0 0 * 13 *" "x 0 * * *"; do
    python3 "$K" "$P45" bad_cron --scheduled "$cron" >"$T/out" 2>&1 && bad "cron '$cron' accepted" \
        || { grep -q 'bad ' "$T/out" && [ ! -e "$P45/classes/task/bad_cron.php" ] && ok "cron '$cron' refused" || bad "cron refusal: $(cat "$T/out")"; }
done
python3 "$K" "$P45" x >"$T/out" 2>&1 && bad "no kind accepted" || ok "--scheduled or --adhoc required"

mkdir -p "$T/pg"
printf 'component: local_purge\nrequires: "4.5"\ncopyright: 2026 onwards, Example Author <author@example.com>\ntables:\n  local_purge_log:\n    fields: [userid, name:char:255, timecreated]\n' > "$T/pg/recipe.yaml"
python3 "$G" --target-dir "$T/pg" "$T/pg/recipe.yaml" >/dev/null 2>"$T/err" || bad "purge skeleton: $(cat "$T/err")"
PP="$T/pg/purge"; cp_="$PP/classes/task/purge_old.php"; tp_="$PP/tests/task/purge_old_test.php"
python3 "$K" "$PP" purge_old --scheduled "0 3 * * *" --purge local_purge_log.timecreated --setting retention >"$T/out" 2>&1 \
    && grep -q "\$retention = (int) get_config('local_purge', 'retention');" "$cp_" && grep -q 'if (\$retention <= 0) {' "$cp_" \
    && grep -qF "\$DB->delete_records_select('local_purge_log', 'timecreated < ?', [time() - \$retention]);" "$cp_" \
    && ok "--purge --setting: delete_records_select with time() - get_config" || bad "purge class: $(cat "$T/out" "$cp_")"
grep -qF "set_config('retention', DAYSECS, 'local_purge');" "$tp_" \
    && grep -qF "\$DB->insert_record('local_purge_log', ['timecreated' => 1, 'name' => 'x']);" "$tp_" \
    && grep -qF "\$keep = \$DB->insert_record('local_purge_log', ['timecreated' => time(), 'name' => 'x']);" "$tp_" \
    && grep -qF "\$this->assertEquals(1, \$DB->count_records('local_purge_log'));" "$tp_" && ! grep -q 'expectOutputRegex' "$tp_" \
    && ok "purge test seeds an old and a new row, asserts 1 left" || bad "purge test: $(cat "$tp_")"
python3 "$K" "$PP" purge_month --scheduled "0 4 * * *" --purge local_purge_log.timecreated >"$T/out" 2>&1 \
    && grep -q '\$retention = 30 \* DAYSECS;' "$PP/classes/task/purge_month.php" && ! grep -q 'get_config\|set_config' \
        "$PP/classes/task/purge_month.php" "$PP/tests/task/purge_month_test.php" \
    && ok "--purge without --setting: 30 days" || bad "purge default: $(cat "$T/out" "$PP/classes/task/purge_month.php")"
lintfail=0
for f in "$PP"/classes/task/*.php "$PP"/tests/task/*.php "$PP/db/tasks.php"; do php -l "$f" >/dev/null 2>&1 || lintfail=1; done
[ "$lintfail" = 0 ] && ok "purge php -l clean" || bad "purge php -l"
if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
    out="$(nice -n 19 "$MPC" codechecker "$PP" 2>&1)"; rc=$?
    ! grep -q '| ERROR |' <<<"$out" && [ "$rc" = 0 ] && ok "purge codechecker 0 errors" || bad "purge codechecker rc=$rc"
fi
before="$(md5sum "$PP/version.php" "$PP/db/tasks.php" "$PP/lang/en/local_purge.php")"
for c in "nosuch.timecreated|table nosuch not found" "local_purge_log.nosuch|no int field nosuch" \
    "local_purge_log.name|no int field name" "local_purge_log|bad --purge"; do
    python3 "$K" "$PP" purge_bad --scheduled "0 3 * * *" --purge "${c%%|*}" >"$T/out" 2>&1; rc=$?
    [ "$rc" = 1 ] && grep -q "${c#*|}" "$T/out" && [ ! -e "$PP/classes/task/purge_bad.php" ] \
        && [ "$before" = "$(md5sum "$PP/version.php" "$PP/db/tasks.php" "$PP/lang/en/local_purge.php")" ] \
        && ok "--purge ${c%%|*} refused rc 1, nothing written" || bad "--purge ${c%%|*} rc=$rc: $(cat "$T/out")"
done
python3 "$K" "$P41" purge_x --scheduled "0 3 * * *" --purge t.timecreated >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'needs .*db/install.xml' "$T/out" && ok "--purge without install.xml refused rc 1" || bad "no install.xml rc=$rc: $(cat "$T/out")"
python3 "$K" "$PP" purge_bad --adhoc --purge local_purge_log.timecreated >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'needs --scheduled' "$T/out" && ok "--purge with --adhoc refused rc 1" || bad "adhoc purge rc=$rc: $(cat "$T/out")"
python3 "$K" "$PP" purge_bad --scheduled "0 3 * * *" --setting retention >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'needs --purge' "$T/out" && ok "--setting without --purge refused rc 1" || bad "setting alone rc=$rc: $(cat "$T/out")"

[ "$fails" -eq 0 ] && echo "PASS task.test.sh" || { echo "FAIL task.test.sh ($fails)"; exit 1; }
