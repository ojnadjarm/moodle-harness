#!/usr/bin/env bash
# Drive form.py on mktemp plugins: dynamic_form class, ModalForm AMD, lang, test, php -l, node --check, codechecker, refusals.
# MOODLE_HARNESS_LIVE=1 also installs the plugin on the 5.2 env (mfixture) and runs only the generated test.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
S="$(cd "$(dirname "$0")/.." && pwd)"
F="$S/form.py"; G="$S/generate.py"; CI="$S/../moodle-ci/scripts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
nothing() { [ ! -e "$1/classes/form/$2.php" ] && [ ! -e "$1/amd/src/$2.js" ] && [ ! -e "$1/tests/form/$2_test.php" ]; }

render() {
    mkdir -p "$T/$1"
    printf 'component: %s\nrequires: "%s"\ncopyright: 2026 onwards, Example Author <author@example.com>\ncapabilities:\n  - name: manage\n    title: Manage\n' \
        "$2" "${3:-$1}" > "$T/$1/recipe.yaml"
    python3 "$G" --target-dir "$T/$1" "$T/$1/recipe.yaml" >/dev/null 2>"$T/err" || bad "$1 skeleton: $(cat "$T/err")"
}
render 5.2 local_formdemo; P="$T/5.2/formdemo"
render 4.1 mod_formdemo; M="$T/4.1/formdemo"

python3 "$F" "$P" edit_entry --fields title:text,due:date_time_selector --cap manage >"$T/out" 2>&1 \
    && ok "system form renders" || bad "system rc: $(cat "$T/out")"
c="$P/classes/form/edit_entry.php"; j="$P/amd/src/edit_entry.js"; t="$P/tests/form/edit_entry_test.php"
grep -q 'class edit_entry extends \\core_form\\dynamic_form {' "$c" \
    && [ "$(grep -cE 'function (get_context_for_dynamic_submission|check_access_for_dynamic_submission|process_dynamic_submission|set_data_for_dynamic_submission|get_page_url_for_dynamic_submission)\(' "$c")" = 5 ] \
    && ok "class extends dynamic_form with the 5 methods" || bad "class: $(cat "$c")"
grep -A2 'function process_dynamic_submission' "$c" | grep -q 'return \$this->get_data();' \
    && grep -q "require_capability('local/formdemo:manage', \$this->get_context_for_dynamic_submission());" "$c" \
    && grep -q 'context_system::instance()' "$c" && ok "process returns data, access via require_capability, system context" \
    || bad "class body: $(cat "$c")"
grep -q "addElement('date_time_selector', 'due', get_string('form_edit_entry_due', 'local_formdemo'));" "$c" \
    && grep -q "setType('title', PARAM_TEXT);" "$c" && ok "fields: elements + setType" || bad "fields: $(cat "$c")"
grep -q "import ModalForm from 'core_form/modalform';" "$j" && grep -q "formClass: 'local_formdemo\\\\\\\\form\\\\\\\\edit_entry'," "$j" \
    && grep -q '@module     local_formdemo/edit_entry' "$j" && ok "AMD: ModalForm opener with formClass" || bad "AMD: $(cat "$j")"
node --check "$j" 2>"$T/err" && ok "node --check amd/src/edit_entry.js" || bad "node --check: $(cat "$T/err")"
grep -q 'edit_entry::mock_ajax_submit(\[' "$t" && grep -q '\$form->process_dynamic_submission();' "$t" \
    && grep -q "assertEquals('Example', \$result->title);" "$t" && grep -q 'make_timestamp(2026, 5, 4, 10, 30)' "$t" \
    && grep -q 'expectException(\\moodle_exception::class);' "$t" && ok "test: mock_ajax_submit + process_dynamic_submission + access denied" \
    || bad "test: $(cat "$t")"
lang="$P/lang/en/local_formdemo.php"
grep -q "^\$string\['form_edit_entry'\] = 'Edit entry';" "$lang" && grep -q "^\$string\['form_edit_entry_title'\] = 'Title';" "$lang" \
    && grep -q "^\$string\['form_edit_entry_due'\] = 'Due';" "$lang" && ok "lang: title + field labels" || bad "lang: $(cat "$lang")"

python3 "$F" "$M" pick --fields n:int,ok:checkbox,day:date_selector,notes:textarea --cap moodle/course:update --context course \
    >"$T/out" 2>&1 && ok "course form renders on 4.1 mod_ with a core cap" || bad "course rc: $(cat "$T/out")"
cm="$M/classes/form/pick.php"; tm="$M/tests/form/pick_test.php"
grep -q "context_course::instance(\$this->optional_param('courseid', 0, PARAM_INT))" "$cm" \
    && grep -q "addElement('hidden', 'courseid');" "$cm" && grep -q "'courseid' => \$course->id" "$tm" \
    && grep -q "require_capability('moodle/course:update'" "$cm" && grep -q "^\$string\['form_pick_notes'\]" "$M/lang/en/formdemo.php" \
    && ok "course context: hidden courseid, context_course, test passes courseid" || bad "course: $(cat "$cm")"

python3 "$F" "$M" rate --fields stars:int --cap moodle/course:update --context module --page view.php >"$T/out" 2>&1 \
    && ok "module form renders on mod_ with --page view.php" || bad "module rc: $(cat "$T/out")"
cr="$M/classes/form/rate.php"; tr="$M/tests/form/rate_test.php"; v="$M/view.php"
grep -q "context_module::instance(\$this->optional_param('cmid', 0, PARAM_INT))" "$cr" \
    && grep -q "addElement('hidden', 'cmid');" "$cr" && grep -q 'require_login($course, false, $cm);' "$cr" \
    && grep -q "get_course_and_cm_from_cmid(\$this->optional_param('cmid', 0, PARAM_INT), 'formdemo');" "$cr" \
    && grep -q "new moodle_url('/mod/formdemo/view.php'" "$cr" && ok "module context: cmid, context_module, require_login with cm" \
    || bad "module class: $(cat "$cr")"
grep -q "create_module('formdemo', \['course' => \$course->id\]);" "$tr" && grep -q "'cmid' => \$cm->cmid" "$tr" \
    && grep -q 'class mod_formdemo_generator extends testing_module_generator' "$M/tests/generator/lib.php" \
    && ok "module test: create_module + cmid, generator written" || bad "module test: $(cat "$tr")"
[ "$(grep -c "js_call_amd('mod_formdemo/rate', 'init', \['\[data-action=\"mod_formdemo-rate\"\]'\]);" "$v")" = 1 ] \
    && grep -q "'data-action' => 'mod_formdemo-rate'," "$v" && grep -q "'data-cmid' => \$PAGE->cm->id," "$v" \
    && grep -A1 "'data-cmid'" "$v" | tail -1 | grep -q '^\]);' && grep -A1 '^\]);' "$v" | grep -q 'echo $OUTPUT->footer();' \
    && grep -q 'next: mgrunt' "$T/out" && ok "--page: one js_call_amd + data-action button before the footer, mgrunt next" \
    || bad "--page view.php: $(cat "$v")"
sed -i "s|^echo \$OUTPUT->footer();|\$PAGE->requires->js_call_amd('mod_formdemo/memo', 'init', ['[data-action=\"mod_formdemo-memo\"]']);\n&|" "$v"
python3 "$F" "$M" memo --fields body:textarea --cap moodle/course:update --context module --page view.php >"$T/out" 2>&1 \
    && [ "$(grep -c "js_call_amd('mod_formdemo/memo'" "$v")" = 1 ] && ! grep -q "'mod_formdemo-memo'," "$v" \
    && grep -q 'already has the mod_formdemo/memo opener' "$T/out" && ok "--page idempotent: a wired opener is not added twice" \
    || bad "idempotent: $(cat "$T/out")"
python3 "$F" "$P" other --fields a:text --cap manage --context module >"$T/out" 2>&1 && bad "--context module on local_ accepted" \
    || { grep -q 'needs a mod_ plugin' "$T/out" && nothing "$P" other && ok "--context module refused for non-mod_, nothing written" \
        || bad "module local_: $(cat "$T/out")"; }
python3 "$F" "$M" other --fields a:text --cap moodle/course:update --page nosuch.php >"$T/out" 2>&1 && bad "missing --page accepted" \
    || { grep -q 'not a .php file' "$T/out" && nothing "$M" other && ok "missing --page refused, nothing written" \
        || bad "missing page: $(cat "$T/out")"; }

lintfail=0; n=0
for f in "$c" "$t" "$lang" "$cm" "$tm" "$M/lang/en/formdemo.php" "$cr" "$tr" "$v" "$M/tests/generator/lib.php"; do
    n=$((n + 1)); php -l "$f" >/dev/null 2>&1 || { lintfail=1; bad "php -l $f: $(php -l "$f" 2>&1)"; }
done
[ "$lintfail" = 0 ] && ok "php -l clean ($n files)"
for p in "$P" "$M"; do
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker --max-warnings 0 "$p" 2>&1)"; rc=$?
        if grep -q '| ERROR \|| WARNING ' <<<"$out" || [ "$rc" -ne 0 ]; then bad "${p#"$T"/} codechecker rc=$rc: $(grep -E 'ERROR|WARNING' <<<"$out" | head -5)"
        else ok "codechecker 0 errors 0 warnings ${p#"$T"/}"; fi
    else
        echo "SKIP codechecker: moodle-plugin-ci absent"
    fi
done

render 4.0 local_old; O="$T/4.0/old"
sed -i 's/^\$plugin->requires = [0-9]*;/$plugin->requires = 2020110900;/' "$O/version.php"
python3 "$F" "$O" f --fields a:text --cap manage >"$T/out" 2>&1 && bad "requires 3.10 accepted" \
    || { grep -q 'needs Moodle 3.11' "$T/out" && nothing "$O" f && ok "requires 3.10 refused, nothing written" || bad "3.10: $(cat "$T/out")"; }
sed -i 's/^\$plugin->requires = [0-9]*;/$plugin->requires = 2021051700;/' "$O/version.php"
python3 "$F" "$O" f --fields a:text --cap manage >"$T/out" 2>&1 && ok "requires 3.11 accepted" || bad "3.11: $(cat "$T/out")"
sed -i 's/^\$plugin->requires = [0-9]*;/$plugin->requires = 2022041900.00;/' "$O/version.php"
python3 "$F" "$O" g --fields a:text --cap manage >"$T/out" 2>&1 && ok "decimal requires 2022041900.00 accepted" \
    || bad "decimal: $(cat "$T/out")"
sed -i -e "s/^\\\$plugin->component = 'local_old';/\\\$plugin->component = \"local_old\";/" -e 's/^\$plugin->requires = .*;/$plugin->requires = 2020110900;/' "$O/version.php"
python3 "$F" "$O" h --fields a:text --cap manage >"$T/out" 2>&1 && bad "quoted 3.10 requires accepted" \
    || { grep -q 'needs Moodle 3.11' "$T/out" && ok "double-quoted component and requires read" || bad "quoted: $(cat "$T/out")"; }
before="$(md5sum "$c" "$lang")"
python3 "$F" "$P" edit_entry --fields title:text --cap manage >"$T/out" 2>&1 && bad "existing form accepted" \
    || { grep -q 'edit_entry.php already exists' "$T/out" && [ "$before" = "$(md5sum "$c" "$lang")" ] \
        && ok "existing form refused, nothing written" || bad "existing: $(cat "$T/out")"; }
python3 "$F" "$P" other --fields a:text --cap nosuchcap >"$T/out" 2>&1 && bad "undefined cap accepted" \
    || { grep -q "local/formdemo:nosuchcap' is not defined" "$T/out" && nothing "$P" other && ok "undefined own capability refused" \
        || bad "cap: $(cat "$T/out")"; }
for spec in "a:color" "Bad:text" "courseid:int" "a:text,a:int" ","; do
    python3 "$F" "$P" other --fields "$spec" --cap manage >"$T/out" 2>&1 && bad "fields '$spec' accepted" \
        || { grep -q 'error:' "$T/out" && nothing "$P" other && ok "fields '$spec' refused" || bad "fields '$spec': $(cat "$T/out")"; }
done
python3 "$F" "$P" Other --fields a:text --cap manage >"$T/out" 2>&1 && bad "bad name accepted" || ok "bad form name refused"
python3 "$F" "$M" other --fields a:text --cap moodle/course:update --context module --page index.php >"$T/out" 2>&1 \
    && bad "--context module on cm-less index.php accepted" \
    || { grep -q 'index.php: --context module needs a page with a course module' "$T/out" && nothing "$M" other \
        && ok "--context module refused on cm-less index.php, nothing written" || bad "cm-less page: $(cat "$T/out")"; }
printf '<?php\n// require_login($course, false, $cm);\necho $OUTPUT->footer();\n' >"$M/commented.php"
python3 "$F" "$M" other --fields a:text --cap moodle/course:update --context module --page commented.php >"$T/out" 2>&1 \
    && bad "--context module on a commented-out require_login accepted" \
    || { grep -q 'commented.php: --context module needs' "$T/out" && nothing "$M" other \
        && ok "--context module refused on a commented-out require_login" || bad "commented page: $(cat "$T/out")"; }
printf '<?php\nrequire_course_login($course, true, $cm);\necho $OUTPUT->footer();\n' >"$M/courselogin.php"
python3 "$F" "$M" viacl --fields a:text --cap moodle/course:update --context module --page courselogin.php >"$T/out" 2>&1 \
    && grep -q "js_call_amd('mod_formdemo/viacl'" "$M/courselogin.php" \
    && ok "--context module accepted on a require_course_login(..., \$cm) page" || bad "require_course_login: $(cat "$T/out")"

if [ "${MOODLE_HARNESS_LIVE:-}" = 1 ]; then
    render live local_t882form 5.2; L="$T/live/t882form"
    python3 "$F" "$L" edit_entry --fields title:text,due:date_time_selector,n:int,ok:checkbox --cap manage --context course >/dev/null \
        || bad "live render"
    W="$(realpath "$HOME/moodle-envs/5.2/www")"; [ -d "$W/public" ] && W="$W/public"
    t0=$(date +%s)
    out="$("$CI/mfixture" with 5.2 "$L" -- "$CI/mtest" phpunit "$W/local/t882form/tests/form/edit_entry_test.php" 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && ok "live 5.2: edit_entry_test.php green, $(($(date +%s) - t0)) s" \
        || { bad "live 5.2 rc $rc"; tail -15 <<<"$out"; }
    render live mod_t977form 5.2; LM="$T/live/t977form"
    python3 "$F" "$LM" rate --fields stars:int,note:text --cap moodle/course:update --context module --page view.php \
        >/dev/null || bad "live module render"
    t0=$(date +%s)
    out="$("$CI/mfixture" with 5.2 "$LM" -- "$CI/mtest" phpunit "$W/mod/t977form/tests/form/rate_test.php" 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && ok "live 5.2: module rate_test.php green, $(($(date +%s) - t0)) s" \
        || { bad "live 5.2 module rc $rc"; tail -15 <<<"$out"; }
else
    echo "SKIP live: set MOODLE_HARNESS_LIVE=1 to run the generated test on 5.2"
fi

[ "$fails" -eq 0 ] && echo "PASS form.test.sh" || { echo "FAIL form.test.sh ($fails)"; exit 1; }
