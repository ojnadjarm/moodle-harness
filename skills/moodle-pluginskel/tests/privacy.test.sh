#!/usr/bin/env bash
# Render skel plugins, add user tables, run privacy.py: provider shape, php -l, mprivacy static, codechecker, refusals,
# export/delete semantics on SQLite (fixtures/privacy-db.php) and the generated tests/privacy/provider_test.php.
# MOODLE_HARNESS_LIVE=1 also runs that provider_test on a live env (MOODLE_HARNESS_LIVE_ENV, default 5.2) via mfixture.
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)"; G="$S/generate.py"; DBT="$S/tests/fixtures/privacy-db.php"; PR="$S/privacy.py"; MP="$HOME/.claude/skills/moodle-ci/scripts/mprivacy"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

render() {
    mkdir -p "$T/$1"
    printf 'component: %s_t814\nname: T814\ncopyright: 2026 onwards, Example Author <author@example.com>\n' "$2" \
        > "$T/$1/recipe.yaml"
    python3 "$G" --target-dir "$T/$1" "$T/$1/recipe.yaml" >/dev/null
}
# add_tables <install.xml> <spec>...: spec "name:field,field:fk=ref,fk=ref"; creates the file when absent.
add_tables() {
    python3 - "$@" <<'PY'
import os, sys
path, specs = sys.argv[1], sys.argv[2:]
out = ""
for spec in specs:
    name, fields, keys = spec.split(":")
    out += f'    <TABLE NAME="{name}" COMMENT="{name}">\n      <FIELDS>\n'
    for n in fields.split(","):
        seq = "true" if n == "id" else "false"
        out += f'        <FIELD NAME="{n}" TYPE="int" LENGTH="10" NOTNULL="true" SEQUENCE="{seq}"/>\n'
    out += '      </FIELDS>\n      <KEYS>\n        <KEY NAME="primary" TYPE="primary" FIELDS="id"/>\n'
    for key in filter(None, keys.split(",")):
        f, ref = key.split("=")
        out += f'        <KEY NAME="{f}" TYPE="foreign" FIELDS="{f}" REFTABLE="{ref}" REFFIELDS="id"/>\n'
    out += "      </KEYS>\n    </TABLE>\n"
if os.path.exists(path):
    text = open(path).read().replace("  </TABLES>", out + "  </TABLES>")
else:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    text = f'<?xml version="1.0" encoding="UTF-8" ?>\n<XMLDB PATH="local/t814/db" VERSION="2026102000" COMMENT="t">\n  <TABLES>\n{out}  </TABLES>\n</XMLDB>\n'
open(path, "w").write(text)
PY
}
lint() { php -l "$1" >/dev/null 2>&1; }
codecheck() {
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker "$2" 2>&1)"; rc=$?; n="$(grep -cE '\| (ERROR|WARNING) \|' <<<"$out")"
        [ "$rc" -eq 0 ] && [ "$n" -eq 0 ] && ok "$1: codechecker 0 errors 0 warnings" \
            || bad "$1: codechecker rc=$rc, $n: $(grep -v '^[[:space:]]*$' <<<"$out" | head -12)"
    else
        echo "SKIP $1 codechecker: moodle-plugin-ci absent"
    fi
}
dbcheck() {
    out="$(php "$DBT" "$@" 2>&1)"; rc=$?; echo "$out"
    [ "$rc" -eq 0 ] && ! grep -q '^FAIL' <<<"$out" || bad "db $1: rc=$rc"
}
# ptest <label> <plugin> <metadata count>: the generated provider test lints and covers every provider call.
ptest() {
    local f="$2/tests/privacy/provider_test.php"
    lint "$f" && grep -q 'final class provider_test extends provider_testcase {' "$f" \
        && grep -q "assertCount($3, \$collection->get_collection())" "$f" || { bad "$1: provider_test: $(php -l "$f" 2>&1)"; return; }
    for t in get_metadata get_contexts_for_userid get_users_in_context export_user_data \
        delete_data_for_all_users_in_context delete_data_for_user delete_data_for_users; do
        grep -q "public function test_$t(): void {" "$f" || { bad "$1: provider_test has no test_$t"; return; }
    done
    ok "$1: provider_test.php: php -l, metadata count $3, 7 provider calls"
}
mstatic() {
    out="$("$MP" "$2" 2>&1)"
    grep -q '^PASS lang' <<<"$out" && grep -q '^PASS tables' <<<"$out" && ! grep -q '^FAIL' <<<"$out" \
        && ok "$1: mprivacy static PASS lang + tables" || bad "$1: mprivacy: $out"
}

render mod mod && render plain mod || { echo "FAIL generate.py render"; exit 1; }
P="$T/mod/t814"; PV="$P/classes/privacy/provider.php"; L="$P/lang/en/t814.php"
add_tables "$P/db/install.xml" "t814_entry:id,t814id,userid,timecreated:t814id=t814,userid=user"
out="$("$MP" "$P" 2>&1)"
grep -q '^FAIL tables     t814_entry has user fields' <<<"$out" && ok "before: mprivacy FAILs the null provider" \
    || bad "before: mprivacy did not fail"

sum0="$(cat "$PV" "$L" | md5sum)"
out="$(python3 "$PR" "$P" --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q 'classes/privacy/provider.php' <<<"$out" && grep -q 'tests/privacy/provider_test.php' <<<"$out" \
    && [ "$sum0" = "$(cat "$PV" "$L" | md5sum)" ] && [ ! -e "$P/tests" ] \
    && ok "dry-run rc 0, lists provider + provider_test, writes nothing" || bad "dry-run rc=$rc: $out"

out="$(python3 "$PR" "$P" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "mod: run rc 0" || bad "mod: run rc=$rc: $out"
lint "$PV" && lint "$L" && ok "mod: php -l provider + lang" || bad "mod: php -l: $(php -l "$PV" 2>&1)"
for i in 'metadata\\provider,' 'request\\core_userlist_provider,' 'request\\plugin\\provider {'; do
    grep -q "core_privacy\\\\local\\\\$i" "$PV" || bad "mod: interface $i missing"
done
! grep -q null_provider "$PV" && ok "mod: metadata + plugin + userlist interfaces" || bad "mod: still null_provider"
for f in get_metadata get_contexts_for_userid get_users_in_context export_user_data \
    delete_data_for_all_users_in_context delete_data_for_user delete_data_for_users; do
    grep -q "public static function $f(" "$PV" || bad "mod: no $f"
done
grep -q "'JOIN {t814_entry} t ON t.t814id = j0.id'," "$PV" && grep -q 'CONTEXT_MODULE' "$PV" \
    && grep -q 'instanceof \\context_module' "$PV" && ok "mod: joins via course_modules, CONTEXT_MODULE" \
    || bad "mod: joins/context: $(grep -n "JOIN\|CONTEXT_" "$PV")"
grep -q "\$string\['privacy:metadata:t814_entry'\]" "$L" && grep -q "\$string\['privacy:metadata:t814_entry:userid'\]" "$L" \
    && ! grep -q "\$string\['privacy:metadata'\]" "$L" && ok "mod: table + field strings, null string dropped" \
    || bad "mod: lang: $(grep privacy "$L")"
ptest mod "$P" 1
grep -q "'t814_entry' => \[" "$P/tests/privacy/provider_test.php" && grep -q 'class mod_t814_generator extends testing_module_generator' \
    "$P/tests/generator/lib.php" && ok "mod: provider_test seeds t814_entry, module generator written" \
    || bad "mod: seed/generator: $(ls "$P/tests" 2>&1)"
mstatic mod "$P"
codecheck mod "$P"

before="$(cat "$PV" "$L" | md5sum)"
out="$(python3 "$PR" "$P" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'not a null provider: refusing' <<<"$out" && [ "$before" = "$(cat "$PV" "$L" | md5sum)" ] \
    && ok "real provider refused (rc $rc), files unchanged" || bad "rerun rc=$rc: $out"

Q="$T/plain/t814"; before="$(cat "$Q/classes/privacy/provider.php" "$Q/lang/en/t814.php" | md5sum)"
out="$(python3 "$PR" "$Q" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q 'null provider kept' <<<"$out" \
    && [ "$before" = "$(cat "$Q/classes/privacy/provider.php" "$Q/lang/en/t814.php" | md5sum)" ] \
    && ok "no user tables: null provider kept, files unchanged" || bad "plain rc=$rc: $out"

render deep mod || { echo "FAIL generate.py render deep"; exit 1; }
D="$T/deep/t814"; DV="$D/classes/privacy/provider.php"
python3 - "$D/db/install.xml" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read().replace('<FIELD NAME="timemodified"',
    '<FIELD NAME="usermodified" TYPE="int" LENGTH="10" NOTNULL="true" DEFAULT="0" SEQUENCE="false"/>\n'
    '        <FIELD NAME="currententryid" TYPE="int" LENGTH="10" NOTNULL="true" DEFAULT="0" SEQUENCE="false"/>\n'
    '        <FIELD NAME="timemodified"', 1)
t = t.replace('REFTABLE="course" REFFIELDS="id"/>', 'REFTABLE="course" REFFIELDS="id"/>\n'
    '        <KEY NAME="currententryid" TYPE="foreign" FIELDS="currententryid" REFTABLE="t814_entry" REFFIELDS="id"/>', 1)
open(p, "w").write(t)
PY
add_tables "$D/db/install.xml" "t814_entry:id,t814id,userid,usermodified:t814id=t814,userid=user" \
    "t814_log:id,entryid,graderid:entryid=t814_entry,graderid=user" "t814_orphan:id,userid:" \
    "t814_note:id,entryid:entryid=t814_entry" "t814_a:id,entryid,bid,userid,code,slot:entryid=t814_entry,bid=t814_b,userid=user" \
    "t814_b:id,aid:aid=t814_a"
python3 - "$D/db/install.xml" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
head, tail = t.split('<TABLE NAME="t814_a"', 1)
tail = tail.replace('</KEYS>', '  <KEY NAME="code" TYPE="unique" FIELDS="code"/>\n      </KEYS>\n      <INDEXES>\n'
    '        <INDEX NAME="slot" UNIQUE="true" FIELDS="entryid, slot"/>\n      </INDEXES>', 1)
open(p, "w").write(head + '<TABLE NAME="t814_a"' + tail)
head, tail = open(p).read().split('<TABLE NAME="t814_entry"', 1)
tail = tail.replace('</KEYS>', '</KEYS>\n      <INDEXES>\n        <INDEX NAME="once" UNIQUE="true" FIELDS="t814id, userid"/>\n'
    '      </INDEXES>', 1)
open(p, "w").write(head + '<TABLE NAME="t814_entry"' + tail)
PY
O="$T/deep1"; cp -r "$D" "$O"
add_tables "$O/db/install.xml" "t814_one:id,t814id,userid:t814id=t814,userid=user"
python3 - "$O/db/install.xml" <<'PY'
import sys
p = sys.argv[1]
head, tail = open(p).read().split('<TABLE NAME="t814_one"', 1)
open(p, "w").write(head + '<TABLE NAME="t814_one"' + tail.replace('TYPE="foreign" FIELDS="t814id"', 'TYPE="foreign-unique" FIELDS="t814id"', 1))
PY
out="$(python3 "$PR" "$D" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && lint "$DV" && ok "deep mod: rc 0, php -l" || bad "deep rc=$rc: $out"
grep -q "'JOIN {t814_entry} j1 ON j1.t814id = j0.id'," "$DV" && grep -q "'JOIN {t814_log} t ON t.entryid = j1.id'," "$DV" \
    && ok "grandchild joined through its parent" || bad "grandchild joins: $(grep JOIN "$DV")"
lg="$(grep -n "'t814_log' => \[" "$DV" | cut -d: -f1)"; en="$(grep -n "'t814_entry' => \[" "$DV" | cut -d: -f1)"
[ -n "$lg" ] && [ -n "$en" ] && [ "$lg" -lt "$en" ] && ok "grandchild deleted before its parent" || bad "order log=$lg entry=$en"
grep -A2 "'fields' => \['graderid'\]" "$DV" | grep -q "'owners' => \['t.graderid', 'j1.userid'\]," \
    && grep -A2 "'fields' => \['userid', 'usermodified'\]" "$DV" | grep -q "'owners' => \['t.userid'\]," \
    && grep -A6 "'t814' => \[" "$DV" | grep -q "'owners' => \[\]," \
    && grep -q "'JOIN {t814} t ON t.id = cm.instance'," "$DV" \
    && ok "owners: FK-to-user field + parent owner; usermodified and instance only set to 0" \
    || bad "owners: $(grep -n "fields\|owners\|modifiers" "$DV")"
grep -q 'note: table t814_orphan has no foreign-key path to t814' <<<"$out" \
    && grep -q "add_database_table('t814_orphan'" "$DV" && ! grep -q "'t814_orphan' => \[" "$DV" \
    && ok "unreachable user table: metadata only, noted" || bad "orphan: $out"
ptest "deep mod" "$D" 5
F="$D/tests/privacy/provider_test.php"
grep -A3 "'t814_a' => \[" "$F" | grep -q "'unique' => \['code', 'slot'\]," \
    && grep -q 'is_int($row->$field) ? $userid : (string) $userid' "$F" \
    && ok "unique key + unique index: seed values distinct per user" \
    || bad "unique: $(sed -n '/const ROWS/,/];/p' "$F")"
grep -q 'note: foreign-key cycle at t814_b.aid' <<<"$out" \
    && grep -A1 "'t814_b' => \[" "$F" | grep -q "'refs' => \[\]," \
    && grep -A1 "'t814_a' => \[" "$F" | grep -q "'bid' => 't814_b'" \
    && ok "cycle t814_a -> t814_b -> t814_a: back edge seeded as a value, noted" \
    || bad "cycle: $out $(sed -n '/const ROWS/,/];/p' "$F")"
grep -A1 "'t814_log' => \[" "$F" | grep -q "'refs' => \['entryid' => 't814_entry', 'graderid' => 'user'\]," \
    && grep -A2 "'t814' => \[" "$F" | grep -q "'values' => \[\]," \
    && ! grep -q "'t814_orphan' => \[\|'t814_note' => \[" "$F" \
    && ok "deep mod: seeds follow foreign keys to the instance, unreachable tables not seeded" \
    || bad "deep mod seed rows: $(sed -n '/const ROWS/,/];/p' "$F")"
grep -q 'note: foreign-key cycle at t814.currententryid' <<<"$out" && ! grep -q 'note: foreign-key cycle at t814_entry' <<<"$out" \
    && grep -A1 "'t814_entry' => \[" "$F" | grep -q "'refs' => \['t814id' => 't814', 'userid' => 'user', 'usermodified' => 'user'\]," \
    && grep -A3 "'t814_entry' => \[" "$F" | grep -q "'unique' => \[\]," \
    && ok "cycle through the instance: cut at the instance, the entry keeps its link to it" \
    || bad "instance cycle: $out $(sed -n '/const ROWS/,/];/p' "$F")"
grep -q 'note: t814_note.entryid references user table t814_entry' <<<"$out" && ! grep -q 'note: t814_log' <<<"$out" \
    && ok "dependent non-user table noted, cascaded user table not" \
    || bad "no dependent note: $out"
dbcheck mod "$D" mod_t814
dbcheck test "$D" mod_t814
out="$(python3 "$PR" "$O" --dry-run 2>&1)"
grep -q 'note: unique key t814_one(t814id) holds only the instance' <<<"$out" && ! grep -q 'note: unique key t814_a' <<<"$out" \
    && ok "unique key on the instance alone: noted" || bad "instance unique key: $out"
out="$("$MP" "$D" 2>&1)"
grep -q '^PASS lang' <<<"$out" && grep -q '^PASS tables' <<<"$out" && ! grep -q '^FAIL' <<<"$out" \
    && [ "$(grep -c '^WARN .* t814_orphan has user fields, not in ' <<<"$out")" -eq 4 ] \
    && ok "deep mod: mprivacy static PASS lang + tables, WARNs only the noted hand-work t814_orphan" \
    || bad "deep mod: mprivacy: $out"
codecheck "deep mod" "$D"

render inst mod || { echo "FAIL generate.py render inst"; exit 1; }
I="$T/inst/t814"
python3 - "$I/db/install.xml" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read().replace('<FIELD NAME="timemodified"',
    '<FIELD NAME="usermodified" TYPE="int" LENGTH="10" NOTNULL="true" DEFAULT="0" SEQUENCE="false"/>\n'
    '        <FIELD NAME="timemodified"', 1)
open(p, "w").write(t)
PY
out="$(python3 "$PR" "$I" 2>&1)"; rc=$?
IT="$I/tests/privacy/provider_test.php"
[ "$rc" -eq 0 ] && grep -q 'note: only t814 holds user fields: user2 owns no row' <<<"$out" \
    && [ "$(grep -c 'assertGreaterThan(0, $kept);' "$IT")" -eq 2 ] \
    && [ "$(grep -c 'assertSame($kept, $this->owned($this->user2->id));' "$IT")" -eq 2 ] \
    && ok "instance-only user field: noted, kept checks assert user2 owns rows" || bad "instance-only rc=$rc: $out"

render sys local || { echo "FAIL generate.py render local"; exit 1; }
Y="$T/sys/t814"; YV="$Y/classes/privacy/provider.php"
add_tables "$Y/db/install.xml" "local_t814_item:id,usermodified,ownerid,timemodified:ownerid=user"
out="$(python3 "$PR" "$Y" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && lint "$YV" && lint "$Y/lang/en/local_t814.php" && ok "local_: rc 0, php -l" || bad "local_ rc=$rc: $out"
grep -q 'instanceof \\context_system' "$YV" && grep -q 'add_system_context()' "$YV" && ! grep -q course_modules "$YV" \
    && grep -q "'fields' => \['usermodified', 'ownerid'\]," "$YV" && ok "local_: CONTEXT_SYSTEM, both user fields" \
    || bad "local_: $(grep -n "context\|fields" "$YV" | head)"
dbcheck sys "$Y" local_t814
ptest local_ "$Y" 1
grep -q 'context_system::instance()' "$Y/tests/privacy/provider_test.php" && [ ! -e "$Y/tests/generator" ] \
    && ok "local_: provider_test in the system context, no generator" || bad "local_: provider_test context/generator"
mstatic local_ "$Y"
codecheck local_ "$Y"
! grep -q 'context_course\|context_where' "$YV" "$Y/tests/privacy/provider_test.php" \
    && ok "local_ without courseid: no course context code" || bad "local_: course code in a system-only provider"

render crs local || { echo "FAIL generate.py render crs"; exit 1; }
C="$T/crs/t814"; CV="$C/classes/privacy/provider.php"; CT="$C/tests/privacy/provider_test.php"
add_tables "$C/db/install.xml" "local_t814_item:id,courseid,ownerid,usermodified:courseid=course,ownerid=user" \
    "local_t814_pref:id,userid:userid=user"
out="$(python3 "$PR" "$C" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && lint "$CV" && lint "$CT" && ok "courseid: rc 0, php -l" || bad "courseid rc=$rc: $out"
grep -q 'note: local_t814_item rows with courseid 0 or a deleted course match no context' <<<"$out" \
    && ! grep -q 'note: local_t814_pref rows' <<<"$out" && ok "courseid: courseid 0 rows noted" || bad "courseid note: $out"
grep -q 'instanceof \\context_course' "$CV" && grep -q 'CONTEXT_COURSE' "$CV" && grep -q 'add_system_context()' "$CV" \
    && grep -A1 "'local_t814_item' => \[" "$CV" | grep -q "'course' => 'courseid'," \
    && grep -A1 "'local_t814_pref' => \[" "$CV" | grep -q "'course' => null," \
    && ok "courseid: course table in context_course, the other in the system context" \
    || bad "courseid: $(grep -n "context\|'course'" "$CV" | head)"
dbcheck course "$C" local_t814
ptest courseid "$C" 2
[ "$(grep -c 'create_course()' "$CT")" -eq 2 ] && grep -q "private const COURSES = \['local_t814_item' => 'courseid'\];" "$CT" \
    && grep -q 'assertContains((int) $this->othercontext->id, $this->contextids($this->user3->id));' "$CT" \
    && ok "courseid: provider_test seeds 2 courses, deleting one context keeps the other's rows" \
    || bad "courseid provider_test: $(grep -n 'course' "$CT")"
dbcheck test "$C" local_t814
cp -r "$C" "$T/crsbad"; sed -i 's/\["t.{$course} = :courseid", \[.courseid. => $context->instanceid\]\]/["1 = 1", []]/' \
    "$T/crsbad/classes/privacy/provider.php"
out="$(php "$DBT" test "$T/crsbad" local_t814 2>&1)"
grep -q '^FAIL db test: provider_test test_delete_data_for_all_users_in_context' <<<"$out" \
    && ok "courseid: provider_test fails a provider that deletes in every course" || bad "courseid mutant not caught: $out"
grep -q 'public function test_system_context(): void {' "$CT" && ! grep -q test_system_context "$Y/tests/privacy/provider_test.php" \
    && ok "courseid: provider_test exports and deletes the courseless rows in the system context" \
    || bad "courseid: no test_system_context"
cp -r "$C" "$T/sysbad"; sed -i "s/return \$context instanceof \\\\context_system ? \['1 = 1', \[\]\] : null;/return null;/" \
    "$T/sysbad/classes/privacy/provider.php"
out="$(php "$DBT" test "$T/sysbad" local_t814 2>&1)"
! grep -q "context_system ? \['1 = 1'" "$T/sysbad/classes/privacy/provider.php" \
    && grep -q '^FAIL db test: provider_test test_system_context' <<<"$out" \
    && ok "courseid: provider_test fails a provider with no system context branch" || bad "system mutant not caught: $out"
mstatic courseid "$C"
codecheck courseid "$C"

if [ "${MOODLE_HARNESS_LIVE:-}" = 1 ]; then
    ENV="${MOODLE_HARNESS_LIVE_ENV:-5.2}"; CI="$HOME/.claude/skills/moodle-ci/scripts"
    W="$(realpath "$HOME/moodle-envs/$ENV/www")"; [ -d "$W/public" ] && W="$W/public"
    out="$(nice -n 19 "$CI/mfixture" with "$ENV" "$D" -- nice -n 19 "$CI/mtest" phpunit "$W/mod/t814" --filter provider_test 2>&1)"
    rc=$?
    [ "$rc" -eq 0 ] && grep -qE '^OK( \(7 tests|, but)' <<<"$out" && grep -qE '(7 tests|Tests: 7,)' <<<"$out" \
        && grep -q 'mfixture: removed mod_t814' <<<"$out" \
        && ok "live $ENV: deep mod provider_test 7 tests pass, fixture removed" \
        || bad "live $ENV: rc=$rc: $(tail -15 <<<"$out")"
else
    echo "SKIP live provider_test: set MOODLE_HARNESS_LIVE=1 to run it on a live env"
fi

[ "$fails" -eq 0 ] && echo "all privacy cases pass" || echo "$fails FAILURES"
exit $((fails > 0))
