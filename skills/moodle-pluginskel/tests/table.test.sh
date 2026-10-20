#!/usr/bin/env bash
# Drive table.py on mktemp plugins: plain + dynamic tables, 4.1 table_sql vs 4.5 sql_table, page, lang, test, php -l, codechecker, refusals, --datecols, --context course, --page/--param.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
S="$(cd "$(dirname "$0")/.." && pwd)"
K="$S/table.py"; G="$S/generate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

render() {
    mkdir -p "$T/$1"
    printf 'component: %s\nrequires: "%s"\ncopyright: 2026 onwards, Example Author <author@example.com>\n%s' "$2" "$3" "${4:-}" > "$T/$1/recipe.yaml"
    python3 "$G" --target-dir "$T/$1" "$T/$1/recipe.yaml" >/dev/null 2>"$T/err" || bad "$1 skeleton: $(cat "$T/err")"
}

render l45 local_demo 4.5; P45="$T/l45/demo"
render l41 local_demo 4.1; P41="$T/l41/demo"
render t45 tool_demo 4.5; PT="$T/t45/demo"
render old local_demo 2021051700; POLD="$T/old/demo"
CRS='tables:
  local_crs_mark:
    fields: [courseid, userid, name:char:255, grade, note:text, timemodified]
    keys: [courseid->course.id, userid->user.id]
    indexes: ["unique:courseid,userid"]
  local_crs_log:
    fields: [userid, name:char:255]
'
render c45 local_crs 4.5 "$CRS"; PC45="$T/c45/crs"
render c41 local_crs 4.1 "$CRS"; PC41="$T/c41/crs"

python3 "$K" "$P45" questions --table question --cols id,name,timemodified --dynamic >"$T/out" 2>&1 \
    && ok "dynamic 4.5 renders" || bad "dynamic 4.5 rc: $(cat "$T/out")"
python3 "$K" "$P41" questions --table question --cols name,duedate --capability moodle/site:viewreports >"$T/out" 2>&1 \
    && ok "plain 4.1 renders" || bad "plain 4.1 rc: $(cat "$T/out")"
python3 "$K" "$PT" question_bank_entries_overview --table question_bank_entries --cols id,questioncategoryid,idnumber,ownerid --dynamic --capability moodle/question:viewall >"$T/out" 2>&1 \
    && ok "dynamic admin/tool long names render" || bad "tool rc: $(cat "$T/out")"

c45="$P45/classes/table/questions.php"; c41="$P41/classes/table/questions.php"
grep -q 'class questions extends \\core_table\\sql_table implements \\core_table\\dynamic {' "$c45" \
    && ! grep -q 'tablelib.php' "$c45" && ok "4.5 class: sql_table + dynamic, no tablelib" || bad "4.5 class: $(cat "$c45")"
grep -q 'class questions extends \\table_sql {' "$c41" && grep -q "require_once(\$CFG->libdir . '/tablelib.php');" "$c41" \
    && ! grep -q 'has_capability' "$c41" && ok "4.1 plain class: table_sql + tablelib, no dynamic" || bad "4.1 class: $(cat "$c41")"
grep -q "define_columns(\['id', 'name', 'timemodified'\]);" "$c45" && grep -q "get_string('questions_name', 'local_demo')," "$c45" \
    && grep -q "set_sql('id, name, timemodified', '{question}', '1=1');" "$c45" \
    && ok "columns, headers, set_sql" || bad "columns/sql: $(cat "$c45")"
grep -q "set_sql('id, name, duedate', '{question}', '1=1');" "$c41" && ok "id added to fields when not a column" || bad "fields: $(grep set_sql "$c41")"
grep -q 'public function col_timemodified($row): string {' "$c45" && grep -q 'public function col_duedate($row): string {' "$c41" \
    && ! grep -q 'col_name' "$c45" && grep -q 'return s($row->$column);' "$c45" \
    && ok "col_* for time fields only, other columns escaped" || bad "col_ methods"
grep -q "return has_capability('moodle/site:config', \$this->get_context());" "$c45" && grep -q 'function guess_base_url(): void' "$c45" \
    && grep -q 'function get_context(): \\context' "$c45" && ok "dynamic: has_capability, guess_base_url, get_context" || bad "dynamic methods"
grep -q 'class questions_filterset extends \\core_table\\local\\filter\\filterset' "$P45/classes/table/questions_filterset.php" \
    && [ ! -e "$P41/classes/table/questions_filterset.php" ] && ok "filterset only for dynamic" || bad "filterset"

pg="$P45/questions.php"
grep -q "^require(__DIR__ . '/../../config.php');" "$pg" && grep -q '^require_login();' "$pg" \
    && grep -q "^require_capability('moodle/site:config', \$context);" "$pg" && grep -q "set_url(\$url);" "$pg" \
    && grep -q "new moodle_url('/local/demo/questions.php')" "$pg" && grep -q 'set_filterset(new \\local_demo\\table\\questions_filterset());' "$pg" \
    && grep -q 'echo $OUTPUT->header();' "$pg" && grep -q '$table->out(30, false);' "$pg" && ok "page: login, capability, PAGE, filterset, out" || bad "page: $(cat "$pg")"
grep -q "^require(__DIR__ . '/../../../config.php');" "$PT/question_bank_entries_overview.php" && grep -q "'/admin/tool/demo/question_bank_entries_overview.php'" "$PT/question_bank_entries_overview.php" \
    && ok "admin/tool page: config depth + URL" || bad "tool page: $(cat "$PT/question_bank_entries_overview.php")"
grep -q "require_capability('moodle/site:viewreports'" "$P41/questions.php" && ! grep -q set_filterset "$P41/questions.php" \
    && ok "plain page: --capability, no filterset" || bad "plain page"

lang="$P45/lang/en/local_demo.php"
grep -q "^\$string\['questions'\] = 'Questions';" "$lang" && grep -q "^\$string\['questions_timemodified'\] = 'Time modified';" "$lang" \
    && grep -q "^\$string\['questions_id'\]" "$lang" && ok "lang strings added" || bad "lang: $(cat "$lang")"
ids="$(sed -n "s/^\$string\['\([^']*\)'\].*/\1/p" "$lang" | grep -v '^pluginname$')"
[ "$ids" = "$(LC_ALL=C sort <<<"$ids")" ] && ok "lang strings in order" || bad "lang order: $ids"

t45="$P45/tests/table/questions_test.php"; t41="$P41/tests/table/questions_test.php"
grep -q 'final class questions_test extends \\advanced_testcase' "$t45" && grep -q 'query_db(5, false);' "$t45" \
    && grep -q "assertSame(userdate(86400), \$row\['timemodified'\]);" "$t45" && grep -q 'function test_has_capability' "$t45" \
    && grep -q 'dynamic\\get::execute(' "$t45" && grep -q '^            hiddencolumns: \[\],$' "$t45" && grep -q "^            uniqueid: 'local_demo-questions'," "$t45" && ! grep -q 'test_has_capability' "$t41" \
    && ok "PHPUnit test: query, format_row, capability + dynamic get" || bad "test: $(cat "$t45")"

python3 "$K" "$PC45" marks --table local_crs_mark --cols id,userid,grade,timemodified --context course >"$T/out" 2>&1 \
    && ok "--context course plain renders" || bad "course plain rc: $(cat "$T/out")"
python3 "$K" "$PC45" dmarks --table local_crs_mark --cols id,name --context course --dynamic --capability moodle/course:viewhiddencourses >"$T/out" 2>&1 \
    && ok "--context course dynamic renders" || bad "course dynamic rc: $(cat "$T/out")"
python3 "$K" "$PC41" dmarks --table local_crs_mark --cols id,name --context course --dynamic >"$T/out" 2>&1 \
    && ok "--context course dynamic 4.1 renders" || bad "course dynamic 4.1 rc: $(cat "$T/out")"
cp="$PC45/marks.php"; cc="$PC45/classes/table/marks.php"; ct="$PC45/tests/table/marks_test.php"
grep -q "^\$courseid = required_param('courseid', PARAM_INT);" "$cp" && grep -q '^\$course = get_course(\$courseid);' "$cp" \
    && grep -q '^require_login(\$course);' "$cp" && grep -q '^\$context = context_course::instance(\$course->id);' "$cp" \
    && grep -q "^require_capability('moodle/site:config', \$context);" "$cp" && grep -q "new moodle_url('/local/crs/marks.php', \['courseid' => \$course->id\]);" "$cp" \
    && grep -q "new \\\\local_crs\\\\table\\\\marks('local_crs-marks', \$course->id);" "$cp" && ! grep -q 'context_system\|require_login();\|set_context' "$cp" \
    && ok "course page: courseid param, require_login(\$course), course-context capability" || bad "course page: $(cat "$cp")"
grep -q 'public function __construct(string $uniqueid, int $courseid) {' "$cc" \
    && grep -q "set_sql('id, userid, grade, timemodified', '{local_crs_mark}', 'courseid = :courseid', \[" "$cc" \
    && grep -q "^            'courseid' => \$courseid,$" "$cc" && grep -q "moodle_url('/local/crs/marks.php', \['courseid' => \$courseid\])" "$cc" \
    && ok "course class: SQL and base URL filter on courseid" || bad "course class: $(cat "$cc")"
grep -q 'create_course();' "$ct" && [ "$(grep -c 'create_course();' "$ct")" = 2 ] \
    && grep -q 'foreach (\[\$course->id, \$course->id, \$other->id\] as \$i => \$courseid) {' "$ct" \
    && grep -q "^                'name' => 'x' . \$i,$" "$ct" && grep -q "^                'userid' => \$i,$" "$ct" && grep -q "^                'note' => 'x' . \$i,$" "$ct" \
    && ! grep -q "'id' => \$i" "$ct" && grep -q "new marks('local_crs-marks', \$course->id);" "$ct" && grep -q 'assertCount(2, \$table->rawdata);' "$ct" \
    && grep -q "new marks('local_crs-marks', SITEID);" "$ct" && ! grep -q 'count_records' "$ct" \
    && ok "course test: seeds 2 courses, counts one course's 2 rows" || bad "course test: $(cat "$ct")"
dc="$PC45/classes/table/dmarks.php"; dt="$PC45/tests/table/dmarks_test.php"; dp="$PC45/dmarks.php"
grep -q 'protected int $courseid = 0;' "$dc" && grep -q 'public function set_filterset(\\core_table\\local\\filter\\filterset $filterset): void {' "$dc" \
    && grep -q "courseid = (int) \$filterset->get_filter('courseid')->current();" "$dc" && grep -q 'return \\context_course::instance($this->courseid);' "$dc" \
    && grep -q "moodle_url('/local/crs/dmarks.php', \['courseid' => \$this->courseid\])" "$dc" && ! grep -q 'context_system' "$dc" \
    && grep -q "return \['courseid' => \\\\core_table\\\\local\\\\filter\\\\integer_filter::class\];" "$PC45/classes/table/dmarks_filterset.php" \
    && grep -q "integer_filter('courseid', null, \[(int) \$course->id\])" "$dp" && grep -q "^\$table = new \\\\local_crs\\\\table\\\\dmarks('local_crs-dmarks');" "$dp" \
    && ok "course dynamic: filterset courseid, get_context course, page filter" || bad "course dynamic: $(cat "$dc" "$dp")"
grep -q 'set_filterset(self::filterset($course->id));' "$dt" && grep -q 'private static function filterset(int $courseid): dmarks_filterset {' "$dt" \
    && grep -q '^            filters: $filters,$' "$dt" && grep -q 'assertCount(2, $table->rawdata);' "$dt" \
    && grep -q 'set_filterset(self::filterset($this->getDataGenerator()->create_course()->id));' "$dt" \
    && grep -q '^            $filters,$' "$PC41/tests/table/dmarks_test.php" \
    && ok "course dynamic test: filterset helper, ws filters (named + positional)" || bad "course dynamic test: $(cat "$dt")"
grep -q 'set_filterset(new \\local_demo\\table\\questions_filterset());' "$pg" && ! grep -q 'get_required_filters' "$P45/classes/table/questions_filterset.php" \
    && grep -q '^            filters: \[\],$' "$t45" && ok "system context unchanged" || bad "system context changed"
for a in "logs --table local_crs_log --cols id,name" "nope --table local_crs_none --cols id"; do
    # shellcheck disable=SC2086
    python3 "$K" "$PC45" $a --context course >"$T/out" 2>&1; rc=$?
    n1="${a%% *}"
    [ "$rc" = 1 ] && grep -q "needs a courseid field in table" "$T/out" && [ ! -e "$PC45/classes/table/$n1.php" ] \
        && ok "--context course without courseid refused rc 1: ${a#* --table }" || bad "no courseid rc=$rc: $(cat "$T/out")"
done
python3 "$K" "$P45" crs --table question --cols id --context course >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "needs a courseid field" "$T/out" && ok "--context course without install.xml refused rc 1" || bad "no install.xml rc=$rc: $(cat "$T/out")"
python3 "$K" "$PC45" visits --table local_crs_mark --cols id,name --context course --dynamic --page index --param id >"$T/out" 2>&1 \
    && ok "--page index --param id renders" || bad "--page index --param id rc: $(cat "$T/out")"
ip="$PC45/index.php"; vc="$PC45/classes/table/visits.php"
grep -q "^\$courseid = required_param('id', PARAM_INT);" "$ip" && grep -q "new moodle_url('/local/crs/index.php', \['id' => \$course->id\]);" "$ip" \
    && grep -q "integer_filter('courseid', null, \[(int) \$course->id\])" "$ip" && [ ! -e "$PC45/visits.php" ] \
    && grep -q "moodle_url('/local/crs/index.php', \['id' => \$this->courseid\])" "$vc" && ! grep -q "\['courseid' => \$this->courseid\]" "$vc" \
    && ok "--param id: required_param, page URL, AJAX base URL use id" || bad "--param id: $(cat "$ip" "$vc")"

lintfail=0; n=0
for f in "$P45"/classes/table/*.php "$P45"/*.php "$P45"/tests/table/*.php "$lang" "$P41"/classes/table/*.php "$P41"/*.php "$PT"/classes/table/*.php "$PT"/*.php \
    "$PC45"/classes/table/*.php "$PC45"/*.php "$PC45"/tests/table/*.php "$PC41"/classes/table/*.php "$PC41"/*.php "$PC41"/tests/table/*.php; do
    n=$((n + 1)); php -l "$f" >/dev/null 2>&1 || { lintfail=1; bad "php -l $f: $(php -l "$f" 2>&1)"; }
done
[ "$lintfail" = 0 ] && ok "php -l clean ($n files)"
for p in "$P45" "$P41" "$PT" "$PC45" "$PC41"; do
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker "$p" 2>&1)"; rc=$?
        if grep -q '| \(ERROR\|WARNING\) |' <<<"$out"; then bad "$p codechecker: $(grep '| \(ERROR\|WARNING\) |' <<<"$out")"
        elif [ "$rc" -ne 0 ]; then bad "$p codechecker rc=$rc"
        else ok "codechecker 0/0 ${p#"$T"/}"; fi
    else
        echo "SKIP codechecker: moodle-plugin-ci absent"
    fi
done

python3 "$K" "$POLD" list --table user --cols id,username --dynamic >"$T/out" 2>&1 && bad "--dynamic on < 4.0 accepted" \
    || { grep -q 'needs $plugin->requires >= 2022041900' "$T/out" && [ ! -e "$POLD/classes/table/list.php" ] \
        && ok "--dynamic refused below 4.0, nothing written" || bad "old refusal: $(cat "$T/out")"; }
python3 "$K" "$POLD" users --table user --cols id,username >/dev/null 2>&1 && ok "plain table accepted below 4.0" || bad "plain < 4.0 refused"
before="$(md5sum "$c45" "$lang")"
python3 "$K" "$P45" questions --table question --cols id >"$T/out" 2>&1 && bad "existing class accepted" \
    || { grep -q 'questions.php already exists' "$T/out" && [ "$before" = "$(md5sum "$c45" "$lang")" ] \
        && ok "existing table refused, nothing written" || bad "class refusal: $(cat "$T/out")"; }
rm "$c45" "$P45/questions.php" "$t45" "$P45/classes/table/questions_filterset.php"
python3 "$K" "$P45" questions --table question --cols id >"$T/out" 2>&1 && bad "existing string accepted" \
    || { grep -q "string 'questions' already exists" "$T/out" && [ ! -e "$c45" ] && ok "existing lang string refused" || bad "string refusal: $(cat "$T/out")"; }
for a in "Bad --table x --cols id" "x --table Bad --cols id" "x --table t --cols id,Bad" "x --table t --cols id,id" \
         "x --table t --cols id --capability a/b" "x --table t --cols id,fullname"; do
    # shellcheck disable=SC2086
    python3 "$K" "$P45" $a >"$T/out" 2>&1 && bad "'$a' accepted" \
        || { grep -q 'bad ' "$T/out" && ok "refused: $a" || bad "refusal '$a': $(cat "$T/out")"; }
done
python3 "$K" "$P41" dyn --table t --cols id --dynamic >"$T/out" 2>&1 \
    && [ "$(grep -A12 'get::execute(' "$P41/tests/table/dyn_test.php" | tail -2 | tr -d ' \n')" = "[],null" ] \
    && php -l "$P41/tests/table/dyn_test.php" >/dev/null && ok "4.1 dynamic test: complete positional args" || bad "4.1 dyn: $(cat "$T/out")"
python3 "$K" "$P45" short --table t --cols id --dynamic --capability view >"$T/out" 2>&1 \
    && grep -q "has_capability('local/demo:view'" "$P45/classes/table/short.php" && grep -q "require_capability('local/demo:view'" "$P45/short.php" \
    && ok "--capability view expands to local/demo:view" || bad "short cap: $(cat "$T/out")"
python3 "$K" "$P45" times --table t --cols id,timezone,timelimit,update,timecreated,timeusermodified,time,timestart,timeclose,startdate >"$T/out" 2>&1 \
    && [ "$(grep -o 'function col_[a-z]*' "$P45/classes/table/times.php" | tr '\n' ' ')" = "function col_timecreated function col_timeusermodified function col_time function col_timestart function col_timeclose function col_startdate " ] \
    && grep -q "'timezone' => '<b>x</b>'" "$P45/tests/table/times_test.php" && grep -q "'update' => '<b>x</b>'" "$P45/tests/table/times_test.php" \
    && ok "timezone/timelimit/update stay text, time*/*date columns are dates" || bad "timecols: $(cat "$T/out") $(grep -o 'function col_[a-z]*' "$P45/classes/table/times.php")"
python3 "$K" "$P45" dates --table t --cols id,opened,timemodified --datecols opened >"$T/out" 2>&1 \
    && [ "$(grep -o 'function col_[a-z]*' "$P45/classes/table/dates.php" | tr '\n' ' ')" = "function col_opened " ] \
    && grep -q "'opened' => 86400" "$P45/tests/table/dates_test.php" && grep -q "'timemodified' => '<b>x</b>'" "$P45/tests/table/dates_test.php" \
    && ok "--datecols overrides the time* guess" || bad "datecols: $(cat "$T/out")"
python3 "$K" "$P45" nodates --table t --cols id,timecreated --datecols '' >"$T/out" 2>&1 \
    && ! grep -q 'function col_' "$P45/classes/table/nodates.php" && ok "--datecols '' gives no date columns" || bad "empty datecols: $(cat "$T/out")"
python3 "$K" "$P45" baddates --table t --cols id,name --datecols name,timedue >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "bad --datecols 'name,timedue': timedue not in --cols" "$T/out" && [ ! -e "$P45/classes/table/baddates.php" ] \
    && ok "--datecols outside --cols refused rc 1, nothing written" || bad "datecols refusal rc=$rc: $(cat "$T/out")"
python3 "$K" "$P45" own --table t --cols id --capability local/demo:missing >"$T/out" 2>&1 \
    && grep -q 'warning: local/demo:missing is not defined' "$T/out" && ok "undefined plugin capability warns" || bad "cap warning: $(cat "$T/out")"

printf '<?php\nrequire(__DIR__ . "/../../config.php");\necho $OUTPUT->header();\necho $OUTPUT->footer();\n' >"$PC41/index.php"
before="$(md5sum "$PC41/index.php")"
python3 "$K" "$PC41" rep --table local_crs_mark --cols id,name --context course --page index --param id >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'index.php already exists: merge this table block' "$T/out" \
    && grep -q "^\$table = new \\\\local_crs\\\\table\\\\rep('local_crs-rep', \$course->id);" "$T/out" \
    && [ ! -e "$PC41/classes/table/rep.php" ] && [ "$before" = "$(md5sum "$PC41/index.php")" ] \
    && ok "existing index.php refused rc 1 with the table block, nothing written" || bad "index refusal rc=$rc: $(cat "$T/out")"
sed -n '/^\$table = new/p' "$T/out" >>"$PC41/index.php"; before="$(md5sum "$PC41/index.php")"
python3 "$K" "$PC41" rep --table local_crs_mark --cols id,name --context course --page index --param id >"$T/out" 2>&1 \
    && [ -e "$PC41/classes/table/rep.php" ] && [ "$before" = "$(md5sum "$PC41/index.php")" ] \
    && grep -q "\['id' => \$courseid\]" "$PC41/classes/table/rep.php" \
    && ok "index.php with the table block merged in: accepted, page kept" || bad "merged index rc: $(cat "$T/out")"
python3 "$K" "$P45" sysp --table t --cols id --param id >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q -- '--param needs --context course' "$T/out" && [ ! -e "$P45/classes/table/sysp.php" ] \
    && ok "--param without --context course refused rc 1" || bad "--param system rc=$rc: $(cat "$T/out")"
python3 "$K" "$PC45" badp --table local_crs_mark --cols id --context course --param Id >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "bad --param 'Id'" "$T/out" && ok "bad --param refused rc 1" || bad "bad --param rc=$rc: $(cat "$T/out")"

[ "$fails" -eq 0 ] && echo "PASS table.test.sh" || { echo "FAIL table.test.sh ($fails)"; exit 1; }
