#!/usr/bin/env bash
# Render a mod_ with generate.py, add child tables, run backup.py: files, backup_restore_test, php -l, structure,
# @covers gated on requires, codechecker, refusals. Then a local_ with course tables: backup_local_/restore_local_ plugin
# classes, their test, and its refusals.
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)"; G="$S/generate.py"; B="$S/backup.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

render() {
    mkdir -p "$T/$1"
    printf 'component: %s_t796\nname: T796\ncopyright: 2026 onwards, Example Author <author@example.com>\n' "$2" \
        > "$T/$1/recipe.yaml"
    python3 "$G" --target-dir "$T/$1" "$T/$1/recipe.yaml" >/dev/null
}
render full mod && render plain mod && render block block || { echo "FAIL generate.py render"; exit 1; }
P="$T/full/t796"
python3 - "$P/db/install.xml" <<'PY'
import sys
path = sys.argv[1]
f = '        <FIELD NAME="{}" TYPE="{}" {}NOTNULL="{}" {}SEQUENCE="{}"/>\n'
def table(name, fields, keys):
    out = f'    <TABLE NAME="{name}" COMMENT="{name}">\n      <FIELDS>\n'
    for n, t in fields:
        out += f.format(n, t, 'LENGTH="10" ' if t == "int" else "", "true" if t == "int" else "false",
                        'DEFAULT="0" ' if t == "int" and n != "id" else "", "true" if n == "id" else "false")
    out += '      </FIELDS>\n      <KEYS>\n        <KEY NAME="primary" TYPE="primary" FIELDS="id"/>\n'
    for field, ref in keys:
        out += f'        <KEY NAME="{field}" TYPE="foreign" FIELDS="{field}" REFTABLE="{ref}" REFFIELDS="id"/>\n'
    return out + "      </KEYS>\n    </TABLE>\n"
extra = table("t796_option", [("id", "int"), ("t796id", "int"), ("text", "text")], [("t796id", "t796")])
extra += table("t796_entry", [("id", "int"), ("t796id", "int"), ("userid", "int"), ("optionid", "int"),
                              ("message", "text"), ("messageformat", "int"), ("timecreated", "int")],
               [("t796id", "t796"), ("userid", "user"), ("optionid", "t796_option")])
extra += table("t796_log", [("id", "int"), ("entryid", "int")], [("entryid", "t796_entry")])
extra += table("t796_news", [("id", "int"), ("t796id", "int"), ("title", "text")], [("t796id", "t796")])
text = open(path).read().replace("  </TABLES>", extra + "  </TABLES>")
open(path, "w").write(text)
PY
M="$P/backup/moodle2"
FILES="backup_t796_activity_task.class.php backup_t796_stepslib.php restore_t796_activity_task.class.php restore_t796_stepslib.php"

lib0="$(md5sum < "$P/lib.php")"
out="$(python3 "$B" "$P" --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(grep -c '/backup/moodle2/' <<<"$out")" -eq 4 ] && ok "dry-run rc 0, lists 4 files" \
    || bad "dry-run rc=$rc: $out"
[ ! -e "$P/backup" ] && [ ! -e "$P/tests/backup" ] && [ "$lib0" = "$(md5sum < "$P/lib.php")" ] && ok "dry-run writes nothing" || bad "dry-run wrote files"

out="$(python3 "$B" "$P" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "run rc 0" || bad "run rc=$rc: $out"
for f in $FILES; do
    [ -s "$M/$f" ] || { bad "missing $f"; continue; }
    php -l "$M/$f" >/dev/null 2>&1 && ok "php -l $f" || bad "php -l $f: $(php -l "$M/$f" 2>&1)"
done
grep -A1 'case FEATURE_BACKUP_MOODLE2:' "$P/lib.php" | grep -q 'return true;' && php -l "$P/lib.php" >/dev/null 2>&1 \
    && ok "lib.php FEATURE_BACKUP_MOODLE2 true" || bad "lib.php flag: $(grep -A1 FEATURE_BACKUP "$P/lib.php")"
BT="$P/tests/backup/backup_restore_test.php"
[ -s "$BT" ] && php -l "$BT" >/dev/null 2>&1 && grep -q "^final class backup_restore_test extends \\\\advanced_testcase" "$BT" \
    && ok "tests/backup/backup_restore_test.php written, lint clean" || bad "backup_restore_test.php: $(php -l "$BT" 2>&1)"
grep -q "new \\\\backup_controller(" "$BT" && grep -q "new \\\\restore_controller(" "$BT" \
    && grep -q "\\\\backup::TARGET_NEW_COURSE" "$BT" && ok "test backs up and restores into a new course" || bad "test controllers"
for t in t796_option t796_entry t796_news; do
    grep -q "\$ids\['$t'\] = \$DB->insert_record('$t', \[" "$BT" \
        && grep -q "assertEquals(1, \$DB->count_records('$t', \['t796id' => \$newinstance->id\]));" "$BT" \
        && ok "test seeds and counts 1 $t row" || bad "test rows $t"
done
! grep -q "t796_log" "$BT" && ok "test skips the unlinked t796_log" || bad "t796_log seeded"
grep -q "'optionid' => \$ids\['t796_option'\]," "$BT" && grep -q "'userid' => \$user->id," "$BT" \
    && grep -q "assertEquals(\$user->id, \$DB->get_field('t796_entry', 'userid', \['t796id' => \$newinstance->id\]));" "$BT" \
    && ok "test seeds sibling FK + user, asserts the remapped userid" || bad "test FK/user seeds"
grep -q '@covers \\backup_t796_activity_structure_step' "$BT" && ! grep -q 'CoversClass' "$BT" \
    && ok "requires 2024100700: @covers docblock, no attributes" || bad "covers below 5.0: $(grep -n covers "$BT")"
grep -q "note: table t796_log has no foreign key to t796" <<<"$out" && ok "grandchild table reported" || bad "no t796_log note"

BS="$M/backup_t796_stepslib.php"; RS="$M/restore_t796_stepslib.php"; RT="$M/restore_t796_activity_task.class.php"
root="$(sed -n "/new backup_nested_element('t796'/,/]);/p" "$BS")"
grep -q "'name', 'intro', 'introformat', 'timemodified'," <<<"$root" && ! grep -qE "'(id|course)'," <<<"$root" \
    && ok "root element: all fields but id/course" || bad "root element: $root"
grep -q "\$entry->annotate_ids('user', 'userid');" "$BS" && ok "child userid annotated" || bad "userid not annotated"
sed -n '/if (\$userinfo) {/,/}/p' "$BS" | grep -q "\$entry->set_source_table('t796_entry', \['t796id' => backup::VAR_PARENTID\]" \
    && ok "user child gated by userinfo" || bad "t796_entry not gated"
sed -n '/if (\$userinfo) {/,/}/p' "$BS" | grep -q t796_option && bad "t796_option gated" || ok "plain child not gated"
grep -q "\$t796->annotate_files('mod_t796', 'intro', null);" "$BS" && ok "intro annotate_files" || bad "intro files"
grep -q "\$t796->add_child(\$entries);" "$BS" && grep -q "'/activity/t796/entries/entry'" "$RS" \
    && ok "backup and restore paths agree" || bad "paths differ"
grep -q "\$t796->add_child(\$newsitems);" "$BS" && grep -q "'/activity/t796/newsitems/news'" "$RS" \
    && ok "invariant name gets an underscore-free wrapper: news/newsitems" || bad "news: $(grep news "$BS")"
for fn in process_t796 process_t796_option process_t796_entry; do
    grep -q "protected function $fn(\$data)" "$RS" && ok "restore $fn" || bad "no $fn"
done
grep -q '$this->apply_activity_instance($newitemid);' "$RS" && grep -q "set_mapping('t796_entry', \$oldid" "$RS" \
    && ok "apply_activity_instance + set_mapping" || bad "restore mapping calls"
grep -q "\$data->userid = \$this->get_mappingid('user', \$data->userid);" "$RS" \
    && grep -q "\$data->optionid = \$this->get_mappingid('t796_option', \$data->optionid);" "$RS" \
    && ok "restore maps userid and sibling FK" || bad "restore FK maps"
grep -q "restore_decode_content('t796', \['intro'\], 't796')" "$RT" \
    && grep -q "restore_decode_content('t796_entry', \['message'\], 't796_entry')" "$RT" \
    && ok "decode contents" || bad "decode contents"
grep -q "restore_decode_rule('T796VIEWBYID', '/mod/t796/view.php?id=\$1', 'course_module')" "$RT" \
    && grep -q 'T796INDEX\*\$2@\$' "$M/backup_t796_activity_task.class.php" \
    && ok "encode + decode rules for view.php/index.php" || bad "link rules"

render edge mod || { echo "FAIL generate.py render edge"; exit 1; }
E="$T/edge/t796"
python3 - "$E/db/install.xml" <<'PY'
import sys
path = sys.argv[1]
def table(name, fields, keys):
    out = f'    <TABLE NAME="{name}" COMMENT="{name}">\n      <FIELDS>\n'
    for n in fields:
        seq = "true" if n == "id" else "false"
        out += f'        <FIELD NAME="{n}" TYPE="int" LENGTH="10" NOTNULL="true" SEQUENCE="{seq}"/>\n'
    out += '      </FIELDS>\n      <KEYS>\n        <KEY NAME="primary" TYPE="primary" FIELDS="id"/>\n'
    for field, ref in keys:
        out += f'        <KEY NAME="{field}" TYPE="foreign" FIELDS="{field}" REFTABLE="{ref}" REFFIELDS="id"/>\n'
    return out + "      </KEYS>\n    </TABLE>\n"
extra = table("t796_a", ["id", "t796id", "gid", "bid", "parent"],
              [("t796id", "t796"), ("gid", "t796_g"), ("bid", "t796_b"), ("parent", "t796_a")])
extra += table("t796_b", ["id", "t796id", "userid"], [("t796id", "t796"), ("userid", "user")])
extra += table("t796_g", ["id", "aid"], [("aid", "t796_a")])
extra += table("t796_this", ["id", "t796id"], [("t796id", "t796")])
extra += table("t796_9x", ["id", "t796id"], [("t796id", "t796")])
extra += table("t796_entry", ["id", "t796id"], [("t796id", "t796")])
extra += table("t796_entries", ["id", "t796id"], [("t796id", "t796")])
extra += table("t796_canvas", ["id", "t796id"], [("t796id", "t796")])
extra += table("t796_series", ["id", "t796id"], [("t796id", "t796")])
text = open(path).read().replace("  </TABLES>", extra + "  </TABLES>")
root = ('        <FIELD NAME="scaleid" TYPE="int" LENGTH="10" NOTNULL="true" DEFAULT="0" SEQUENCE="false"/>\n'
        '        <FIELD NAME="groupingid" TYPE="int" LENGTH="10" NOTNULL="true" DEFAULT="0" SEQUENCE="false"/>\n')
rootkeys = ('        <KEY NAME="scaleid" TYPE="foreign" FIELDS="scaleid" REFTABLE="scale" REFFIELDS="id"/>\n'
            '        <KEY NAME="groupingid" TYPE="foreign" FIELDS="groupingid" REFTABLE="groupings" REFFIELDS="id"/>\n')
head, sep, rest = text.partition('<TABLE NAME="t796" ')
rest = rest.replace("      </FIELDS>", root + "      </FIELDS>", 1).replace("      </KEYS>", rootkeys + "      </KEYS>", 1)
open(path, "w").write(head + sep + rest)
PY
sed -i 's/^\$plugin->requires = .*/$plugin->requires = 2026042000;/' "$E/version.php"
out="$(python3 "$B" "$E" 2>&1)"; rc=$?
EM="$E/backup/moodle2"; EB="$EM/backup_t796_stepslib.php"; ER="$EM/restore_t796_stepslib.php"
lint=0; for f in $FILES; do php -l "$EM/$f" >/dev/null 2>&1 || lint=1; done
[ "$rc" -eq 0 ] && [ "$lint" -eq 0 ] && ok "edge mod: rc 0, 4 files lint clean" || bad "edge rc=$rc lint=$lint: $out"
ET="$E/tests/backup/backup_restore_test.php"
php -l "$ET" >/dev/null 2>&1 && grep -q '^use PHPUnit\\Framework\\Attributes\\CoversClass;' "$ET" \
    && grep -q '^#\[CoversClass(\\restore_t796_activity_structure_step::class)\]' "$ET" && ! grep -q '@covers' "$ET" \
    && ok "requires 2026042000: CoversClass attributes, no @covers" || bad "covers 5.x: $(grep -n -i covers "$ET")"
grep -q "'parent' => 0," "$ET" && grep -q "'gid' => 0," "$ET" && grep -q "'bid' => \$ids\['t796_b'\]," "$ET" \
    && grep -q "'scaleid' => 0," "$ET" && ok "test seeds self/skipped FKs 0, earlier sibling by id" || bad "edge seeds"
! grep -q "get_mappingid('t796_g'" "$ER" && grep -q "note: t796_a.gid references t796_g, which is not backed up" <<<"$out" \
    && ok "FK to a skipped table: not mapped, noted" || bad "gid: $(grep gid "$ER") / $out"
ba="$(grep -n 'add_child($as);' "$EB" | cut -d: -f1)"; bb="$(grep -n 'add_child($bs);' "$EB" | cut -d: -f1)"
[ -n "$ba" ] && [ -n "$bb" ] && [ "$bb" -lt "$ba" ] && ok "referenced sibling t796_b backed up before t796_a" \
    || bad "sibling order a=$ba b=$bb"
grep -q "note: t796_a.parent references t796_a itself" <<<"$out" && ok "self reference noted" || bad "no self note: $out"
grep -q "note: t796_a.bid references t796_b, which is restored only with user data" <<<"$out" \
    && ok "ungated -> gated reference noted" || bad "no userinfo note: $out"
grep -q "note: t796.scaleid references scale" <<<"$out" && grep -q "note: t796.groupingid references groupings" <<<"$out" \
    && ok "root FKs other than user noted" || bad "root FK notes: $out"
! grep -qE '\$this = |\$9x|\$entries = new backup_nested_element\(.entries., \[.id.\]' "$EB" \
    && grep -q "new backup_nested_element('t796_this', \['id'\]" "$EB" \
    && grep -q "new backup_nested_element('t796_9x', \['id'\]" "$EB" \
    && ok "invalid or clashing element names use the table name" || bad "names: $(grep -E 'backup_nested_element' "$EB")"
grep -q "\$canvas = new backup_nested_element('canvas', \['id'\]" "$EB" && grep -q "\$t796->add_child(\$canvases);" "$EB" \
    && grep -q "\$series = new backup_nested_element('series', \['id'\]" "$EB" && grep -q "\$t796->add_child(\$seriesitems);" "$EB" \
    && grep -q "'/activity/t796/canvases/canvas'" "$ER" && grep -q "'/activity/t796/seriesitems/series'" "$ER" \
    && ! grep -qE '\$(canvas|canvases|series|seriesitems)_' "$EB" \
    && ok "singular -s names keep their name, no underscore: canvas/canvases, series/seriesitems" || bad "names: $(grep -E 'canvas|series' "$EB")"

out="$(python3 "$B" "$T/plain/t796" 2>&1)"; rc=$?
lint=0; for f in $FILES; do php -l "$T/plain/t796/backup/moodle2/$f" >/dev/null 2>&1 || lint=1; done
[ "$rc" -eq 0 ] && [ "$lint" -eq 0 ] && ! grep -q userinfo "$T/plain/t796/backup/moodle2/backup_t796_stepslib.php" \
    && ok "plain T763 mod: 4 files lint clean, no userinfo" || bad "plain mod rc=$rc lint=$lint: $out"

if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
    out="$(nice -n 19 "$MPC" codechecker "$P" 2>&1)"; rc=$?; n="$(grep -cE '\| (ERROR|WARNING) \|' <<<"$out")"
    [ "$rc" -eq 0 ] && [ "$n" -eq 0 ] && ok "codechecker 0 errors 0 warnings" \
        || bad "codechecker rc=$rc, $n errors/warnings: $(grep -v '^[[:space:]]*$' <<<"$out" | head -12)"
else
    echo "SKIP codechecker: moodle-plugin-ci absent"
fi

before="$(cat "$M"/* | md5sum)"
out="$(python3 "$B" "$P" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'already exists: refusing' <<<"$out" && [ "$before" = "$(cat "$M"/* | md5sum)" ] \
    && ok "existing backup/ refused (rc $rc), files unchanged" || bad "rerun rc=$rc: $out"
mv "$P/backup" "$T/backup.keep"
out="$(python3 "$B" "$P" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'backup_restore_test.php already exists: refusing' <<<"$out" && [ ! -e "$P/backup" ] \
    && ok "existing tests/backup/backup_restore_test.php refused (rc $rc)" || bad "test rerun rc=$rc: $out"
out="$(python3 "$B" "$T/block/t796" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && grep -q "core never loads block_ plugin-level backup classes (no add_plugin_structure('block'))" <<<"$out" \
    && [ ! -e "$T/block/t796/backup" ] && ok "block_ refused (rc 1), names why" || bad "block_ rc=$rc: $out"
rm "$T/plain/t796/db/install.xml"; rm -r "$T/plain/t796/backup" "$T/plain/t796/tests/backup"
out="$(python3 "$B" "$T/plain/t796" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'has no db/install.xml' <<<"$out" && ok "missing install.xml refused" || bad "no install.xml rc=$rc: $out"

L="$T/local/t1027"; mkdir -p "$T/local"
cat > "$T/local/recipe.yaml" <<'EOF'
component: local_t1027
name: T1027
copyright: 2026 onwards, Example Author <author@example.com>
tables:
  local_t1027_note:
    fields: [courseid, visitid, body:text, timecreated]
    keys: [courseid->course.id, visitid->local_t1027_visit.id]
  local_t1027_visit:
    fields: [courseid, userid, timecreated]
    keys: [courseid->course.id, userid->user.id]
  local_t1027_flag:
    fields: [courseid, done]
  local_t1027_cfg:
    fields: [name:char:255]
EOF
python3 "$G" --target-dir "$T/local" "$T/local/recipe.yaml" >/dev/null || { echo "FAIL generate.py render local"; exit 1; }
LM="$L/backup/moodle2"; LB="$LM/backup_local_t1027_plugin.class.php"; LR="$LM/restore_local_t1027_plugin.class.php"
LT="$L/tests/backup/backup_restore_test.php"
out="$(python3 "$B" "$L" --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q 'backup_local_t1027_plugin.class.php' <<<"$out" && [ ! -e "$L/backup" ] && [ ! -e "$L/tests/backup" ] \
    && ok "local_ dry-run lists files, writes nothing" || bad "local dry-run rc=$rc: $out"
out="$(python3 "$B" "$L" 2>&1)"; rc=$?
lint=0; for f in "$LB" "$LR" "$LT"; do [ -s "$f" ] && php -l "$f" >/dev/null 2>&1 || lint=1; done
[ "$rc" -eq 0 ] && [ "$lint" -eq 0 ] && [ "$(ls "$LM" | wc -l)" -eq 2 ] \
    && ok "local_: rc 0, backup_local_/restore_local_ plugin classes + test, lint clean" || bad "local rc=$rc lint=$lint: $out"
grep -q '^class backup_local_t1027_plugin extends backup_local_plugin {' "$LB" \
    && grep -q 'protected function define_course_plugin_structure() {' "$LB" \
    && grep -q "\$flag->set_source_table('local_t1027_flag', \['courseid' => backup::VAR_COURSEID\], 'id ASC');" "$LB" \
    && sed -n '/if (\$userinfo) {/,/}/p' "$LB" | grep -q "\$visit->set_source_table('local_t1027_visit', \['courseid' => backup::VAR_COURSEID\]" \
    && grep -q "\$visit->annotate_ids('user', 'userid');" "$LB" && grep -q "get_setting_value('users')" "$LB" \
    && ok "backup_local_ plugin: course source by VAR_COURSEID, user table gated by users, userid annotated" \
    || bad "backup plugin: $(cat "$LB")"
grep -q '^class restore_local_t1027_plugin extends restore_local_plugin {' "$LR" \
    && grep -q "public function process_local_t1027_visit(\$data) {" "$LR" \
    && grep -q "\$data->courseid = \$this->task->get_courseid();" "$LR" \
    && grep -q "\$data->userid = \$this->get_mappingid('user', \$data->userid);" "$LR" \
    && grep -q "\$data->visitid = \$this->get_mappingid('local_t1027_visit', \$data->visitid);" "$LR" \
    && grep -q "new restore_path_element('local_t1027_visit', \$this->get_pathfor('/visits/visit'))" "$LR" \
    && grep -q "\$wrapper->add_child(\$visits);" "$LB" \
    && ok "restore_local_ plugin: course + user + sibling mapping, paths match backup" || bad "restore plugin: $(cat "$LR")"
v="$(grep -n 'add_child($visits);' "$LB" | cut -d: -f1)"; n="$(grep -n 'add_child($notes);' "$LB" | cut -d: -f1)"
[ -n "$v" ] && [ -n "$n" ] && [ "$v" -lt "$n" ] && ok "referenced visit table backed up before note" || bad "order v=$v n=$n"
grep -q "assertEquals(1, \$DB->count_records('local_t1027_note', \['courseid' => \$newcourseid\]));" "$LT" \
    && grep -q "assertEquals(1, \$DB->count_records('local_t1027_flag', \['courseid' => \$newcourseid\]));" "$LT" \
    && grep -q "'visitid' => \$ids\['local_t1027_visit'\]," "$LT" && grep -q "'courseid' => \$course->id," "$LT" \
    && grep -q "assertEquals(\$user->id, \$DB->get_field('local_t1027_visit', 'userid', \['courseid' => \$newcourseid\]));" "$LT" \
    && grep -q '@covers \\backup_local_t1027_plugin' "$LT" && ! grep -q CoversClass "$LT" \
    && ok "test seeds course rows, counts restored rows per table, asserts userid, @covers below 5.0" \
    || bad "local test: $(grep -nE 'assert|covers|=>' "$LT")"
grep -q "note: table local_t1027_cfg has no course field: not backed up" <<<"$out" && ! grep -q local_t1027_cfg "$LB" \
    && ok "table without a course field skipped and noted" || bad "cfg: $out"
if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
    cout="$(nice -n 19 "$MPC" codechecker "$L" 2>&1)"; rc=$?; n="$(grep -cE '\| (ERROR|WARNING) \|' <<<"$cout")"
    [ "$rc" -eq 0 ] && [ "$n" -eq 0 ] && ok "local_ codechecker 0 errors 0 warnings" \
        || bad "local codechecker rc=$rc, $n: $(grep -v '^[[:space:]]*$' <<<"$cout" | head -12)"
fi
out="$(python3 "$B" "$L" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'already exists: refusing' <<<"$out" && ok "local_ rerun refused" || bad "local rerun rc=$rc"

rm -r "$L/backup" "$L/tests/backup"
sed -i 's/^\$plugin->requires = .*/$plugin->requires = 2026042000;/' "$L/version.php"
out="$(python3 "$B" "$L" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && php -l "$LT" >/dev/null 2>&1 && grep -q '^#\[CoversClass(\\restore_local_t1027_plugin::class)\]' "$LT" \
    && ! grep -q '@covers' "$LT" && ok "local_ requires 2026042000: CoversClass attributes" || bad "local 5.x covers: $out"

mkdir -p "$T/nocourse"
printf 'component: local_t1027b\nname: T1027b\ntables:\n  local_t1027b_cfg:\n    fields: [name:char:255, userid]\n' \
    > "$T/nocourse/recipe.yaml"
python3 "$G" --target-dir "$T/nocourse" "$T/nocourse/recipe.yaml" >/dev/null
out="$(python3 "$B" "$T/nocourse/t1027b" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && grep -q 'has no table with a courseid field or a foreign key to course' <<<"$out" \
    && [ ! -e "$T/nocourse/t1027b/backup" ] && [ ! -e "$T/nocourse/t1027b/tests/backup" ] \
    && ok "local_ without a courseid table: rc 1, names why, writes nothing" || bad "nocourse rc=$rc: $out"
render tool tool || { echo "FAIL generate.py render tool"; exit 1; }
out="$(python3 "$B" "$T/tool/t796" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && grep -q 'tool_t796 is not a mod_ or local_ plugin' <<<"$out" && ok "tool_ refused (rc 1)" || bad "tool rc=$rc: $out"

[ "$fails" -eq 0 ] && echo "all backup cases pass" || echo "$fails FAILURES"
exit $((fails > 0))
