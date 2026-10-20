#!/usr/bin/env bash
# Render testdata.py into a mktemp git plugin: files, php -l, exclude line, seeded rows on a stub $DB, codechecker, refusal.
set -uo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)/testdata.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

P="$T/repo/local/demo"; mkdir -p "$P"; git init -q "$T/repo"
cat > "$P/version.php" <<'PHP'
<?php
// This file is part of Moodle - https://moodle.org/
//
// Moodle is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Moodle is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Moodle.  If not, see <https://www.gnu.org/licenses/>.

/**
 * Version details.
 *
 * @package    local_demo
 * @copyright  2026 onwards, Example Author <author@example.com>
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

defined('MOODLE_INTERNAL') || die();

$plugin->component = 'local_demo';
$plugin->version = 2026010100;
$plugin->requires = 2024100700;
PHP

# table <name> <field:type[:reftable]>...: one install.xml TABLE block; $UKEY a unique key, $UINDEX a unique index.
table() {
    local name="$1" spec f t r keys="" indexes=""; shift
    printf '    <TABLE NAME="%s" COMMENT="%s">\n      <FIELDS>\n' "$name" "$name"
    printf '        <FIELD NAME="id" TYPE="int" LENGTH="10" NOTNULL="true" SEQUENCE="true"/>\n'
    for spec in "$@"; do
        IFS=: read -r f t r <<<"$spec"
        printf '        <FIELD NAME="%s" TYPE="%s" NOTNULL="false" SEQUENCE="false"/>\n' "$f" "$t"
        [ -n "$r" ] && keys+="        <KEY NAME=\"$f\" TYPE=\"foreign\" FIELDS=\"$f\" REFTABLE=\"$r\" REFFIELDS=\"id\"/>\n"
    done
    [ -n "${UKEY:-}" ] && keys+="        <KEY NAME=\"uk\" TYPE=\"unique\" FIELDS=\"$UKEY\"/>\n"
    [ -n "${UINDEX:-}" ] && indexes="      <INDEXES>\n        <INDEX NAME=\"ux\" UNIQUE=\"true\" FIELDS=\"$UINDEX\"/>\n      </INDEXES>\n"
    printf '      </FIELDS>\n      <KEYS>\n        <KEY NAME="primary" TYPE="primary" FIELDS="id"/>\n%b      </KEYS>\n%b    </TABLE>\n' \
        "$keys" "$indexes"
}
# installxml <plugin dir> <table output>: wrap TABLE blocks into db/install.xml.
installxml() {
    mkdir -p "$1/db"
    printf '<?xml version="1.0" encoding="UTF-8" ?>\n<XMLDB PATH="x/db" VERSION="2026102000" COMMENT="t">\n  <TABLES>\n%s\n  </TABLES>\n</XMLDB>\n' "$2" > "$1/db/install.xml"
}
installxml "$P" "$(table local_demo_item name:char courseid:int userid:int:user timecreated:int
    table local_demo_entry itemid:int:local_demo_item note:text usermodified:int timemodified:int
    table local_demo_flag itemid:int:local_demo_item weight:int)"

# stubrun <setup.php> <reset.php> <rows.php> <prefix> <seeded php> <fields php>: seed twice and reset on an in-memory $DB.
stubrun() {
    {
        cat <<'STUB'
<?php
define('MOODLE_INTERNAL', true);
define('IGNORE_MULTIPLE', 1);
class fake_db {
    public array $t = ['local_demo_item' => [999 => ['id' => 999, 'name' => 'keep me']]];
    public int $inserts = 0;
    private int $next = 1;
    public function sql_compare_text($f) {
        return $f;
    }
    public function sql_like($f, $p) {
        return "$f LIKE $p";
    }
    public function record_exists($table, $conditions) {
        return (bool) array_filter($this->t[$table] ?? [], fn($r) => array_intersect_key($r, $conditions) == $conditions);
    }
    public function sql_like_escape($s) {
        return $s;
    }
    private function find($table, $select, $params) {
        preg_match('/^(\w+) (=|LIKE) :marker$/', $select, $m);
        return array_filter($this->t[$table] ?? [], fn($r) => $m[2] === '=' ? ($r[$m[1]] ?? null) === $params['marker']
            : str_starts_with((string) ($r[$m[1]] ?? ''), rtrim($params['marker'], '%')));
    }
    public function get_field_select($table, $field, $select, $params, $strictness) {
        $rows = $this->find($table, $select, $params);
        return $rows ? reset($rows)[$field] : false;
    }
    public function insert_record($table, $row) {
        $this->inserts++;
        $id = $this->next++;
        $this->t[$table][$id] = ['id' => $id] + (array) $row;
        return $id;
    }
    public function count_records_select($table, $select, $params) {
        return count($this->find($table, $select, $params));
    }
    public function delete_records_select($table, $select, $params) {
        $this->t[$table] = array_diff_key($this->t[$table] ?? [], $this->find($table, $select, $params));
    }
}
STUB
        sed -n "/^function $4_rows(/,/^}/p" "$1"
        sed -n "/^function $4_reset(/,/^}/p" "$2"
        cat <<STUB
\$DB = new fake_db();
\$spec = require('$3');
\$student = (object) ['id' => 42];
\$course = (object) ['id' => 7];
\$instance = (object) ['instance' => 77];
foreach ([1, 2] as \$run) {
    \$seeded = $5;
    \$fields = $6;
    foreach (array_keys(\$spec) as \$table) {
        $4_rows(\$spec, \$table, 3, \$fields, \$seeded);
    }
    echo "run\$run inserts=" . \$DB->inserts . "\n";
}
echo 'seeded=' . json_encode(\$seeded) . "\n";
echo 'rows=' . json_encode(\$DB->t) . "\n";
echo 'deleted=' . json_encode($4_reset(\$course, \$spec)) . "\n";
echo 'left=' . json_encode(\$DB->t) . "\n";
STUB
    } > "$T/stub.php"
    php "$T/stub.php" 2>&1
}

out="$(python3 "$D" "$P" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "first run rc 0" || bad "first run rc=$rc: $out"
F="$P/.research/testdata"
grep -q 'table local_demo_flag has no char or text column' <<<"$out" && ok "unmarkable table noted" || bad "no note: $out"
for f in setup.php reset.php rows.php testing-instructions.md; do
    [ -s "$F/$f" ] && ok "wrote $f" || bad "missing $f"
done
php -l "$F/rows.php" >/dev/null 2>&1 && ok "php -l rows.php" || bad "php -l rows.php: $(php -l "$F/rows.php" 2>&1)"
for f in setup.php reset.php; do
    php -l "$F/$f" >/dev/null 2>&1 && ok "php -l $f" || bad "php -l $f: $(php -l "$F/$f" 2>&1)"
    grep -q "define('CLI_SCRIPT', true);" "$F/$f" && grep -q "lib/setup.php" "$F/$f" \
        && ok "$f: CLI_SCRIPT + config.php lookup" || bad "$f: CLI header"
    grep -q '@copyright  2026 onwards, Example Author' "$F/$f" && ok "$f: copyright from version.php" || bad "$f: copyright"
done
for fn in user course enrol module; do
    grep -q "^function local_demo_testdata_$fn(" "$F/setup.php" && ok "helper $fn" || bad "helper $fn missing"
done
for api in user_create_user create_course enrol_user create_module moodle_url; do
    grep -q "$api(" "$F/setup.php" && ok "uses $api" || bad "no $api"
done
grep -q '^## Steps' "$F/testing-instructions.md" && grep -q '/course/edit.php' "$F/testing-instructions.md" \
    && grep -q 'php .research/testdata/setup.php' "$F/testing-instructions.md" && ok "instructions shape" || bad "instructions shape"
grep -qx '/local/demo/.research/testdata/' "$T/repo/.git/info/exclude" && ok "git exclude line" || bad "exclude: $(cat "$T/repo/.git/info/exclude")"
[ -z "$(git -C "$T/repo" status --porcelain --untracked-files=all -- local/demo/.research)" ] && ok "fixture untracked-invisible" || bad "git status shows fixture"

grep -q "^    local_demo_testdata_rows(\$spec, \$table, 5, \$fields, \$seeded);" "$F/setup.php" && ok "--rows default 5" || bad "default rows"
grep -q "'refs' => \['itemid' => 'local_demo_item', 'usermodified' => 'user'\]" "$F/rows.php" && ok "rows.php: FK walk from privacy" \
    || bad "rows.php refs: $(cat "$F/rows.php")"
grep -q 'cli_writeln("Rows {$table}: " . count($ids));' "$F/setup.php" && ok "setup.php prints row counts" || bad "no row counts"

# Seed twice and reset on a stub $DB.
got="$(stubrun "$F/setup.php" "$F/reset.php" "$F/rows.php" local_demo_testdata '[]' \
    "$(sed -n 's/^\$fields = \(.*\);$/\1/p' "$F/setup.php")")"
grep -q '^run1 inserts=6$' <<<"$got" && ok "3 rows per markable table" || bad "stub seed: $got"
grep -q '^run2 inserts=6$' <<<"$got" && ok "rerun inserts nothing (idempotent)" || bad "stub rerun: $got"
python3 - "$got" <<'PY2' && ok "userid, courseid, FK and time* values" || bad "stub values: $got"
import json, sys, time
lines = dict(line.split("=", 1) for line in sys.argv[1].splitlines() if "=" in line and not line.startswith("run"))
rows, seeded = json.loads(lines["rows"]), json.loads(lines["seeded"])
items = [r for r in rows["local_demo_item"].values() if r["id"] != 999]
entries = list(rows["local_demo_entry"].values())
assert [r["name"] for r in items] == ["testdata-1", "testdata-2", "testdata-3"]
assert all(r["userid"] == 42 and r["courseid"] == 7 and abs(r["timecreated"] - time.time()) < 60 for r in items)
assert [e["itemid"] for e in entries] == seeded["local_demo_item"] and all(e["usermodified"] == 42 for e in entries)
assert seeded["local_demo_flag"] == [] and "local_demo_flag" not in rows
PY2
grep -q '^deleted={"local_demo_item":3,"local_demo_entry":3}$' <<<"$got" \
    && grep -q '^left={"local_demo_item":{"999":{"id":999,"name":"keep me"}},"local_demo_entry":\[\]}$' <<<"$got" \
    && ok "reset deletes only marked rows" || bad "stub reset: $got"

# Config lookup: 4.x root and 5.1+ public/ layouts, theme config.php skipped.
for layout in "m4" "m5/public"; do
    R="$T/$layout"; mkdir -p "$R/lib" "$R/theme/demo/td"
    printf '<?php\necho "ROOT=" . __DIR__;\n' > "$R/config.php"; touch "$R/lib/setup.php"
    printf '<?php\necho "THEME";\n' > "$R/theme/demo/config.php"
    sed -n '/^define(.CLI_SCRIPT/,/^})());/p' "$F/setup.php" | sed '1i <?php' > "$R/theme/demo/td/probe.php"
    got="$(php "$R/theme/demo/td/probe.php" 2>&1)"
    [ "$got" = "ROOT=$R" ] && ok "config lookup $layout" || bad "config lookup $layout: $got"
done
mkdir -p "$T/lone"; sed -n '/^define(.CLI_SCRIPT/,/^})());/p' "$F/setup.php" | sed '1i <?php' > "$T/lone/probe.php"
php "$T/lone/probe.php" >/dev/null 2>&1 && bad "no Moodle above: rc 0" || ok "no Moodle above: rc 1"

before="$(md5sum "$F"/* | md5sum)"
out="$(python3 "$D" "$P" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'refusing to overwrite' <<<"$out" && ok "second run refuses (rc $rc)" || bad "second run rc=$rc: $out"
[ "$before" = "$(md5sum "$F"/* | md5sum)" ] && ok "files unchanged after refusal" || bad "files changed"
[ "$(grep -c testdata "$T/repo/.git/info/exclude")" -eq 1 ] && ok "exclude line once" || bad "exclude duplicated"

python3 "$D" "$T/repo/local" >/dev/null 2>&1 && bad "no version.php accepted" || ok "no version.php refused"

python3 "$D" "$P" --dir r3 --rows 3 >/dev/null 2>&1 && grep -q "_rows(\$spec, \$table, 3," "$P/r3/setup.php" \
    && ok "--rows 3 rendered" || bad "--rows 3"
out="$(python3 "$D" "$P" --dir r0 --rows 0 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q -- '--rows needs at least 1' <<<"$out" && [ ! -e "$P/r0" ] && ok "--rows 0 refused" || bad "--rows 0: rc=$rc $out"
rm -rf "$P/r3"

# mod_: rows hang off the created activity instance.
M="$T/repo/mod/quest"; mkdir -p "$M"
sed "s/local_demo/mod_quest/" "$P/version.php" > "$M/version.php"
installxml "$M" "$(table quest course:int name:char intro:text timemodified:int
    table quest_answer questid:int:quest userid:int:user answer:char timecreated:int timelimit:int
    UINDEX=questid,userid table quest_grade questid:int:quest userid:int:user feedback:text
    UKEY=courseid table quest_setting courseid:int label:char
    UKEY=code table quest_code code:int label:char)"
python3 "$D" "$M" >/dev/null 2>&1; G="$M/.research/testdata"
grep -q "^\$instance = mod_quest_testdata_module(\$course, 'quest', 'mod_quest test instance');" "$G/setup.php" \
    && php -l "$G/setup.php" >/dev/null && ok "mod_: instance created, php -l" || bad "mod_ instance line"
got="$(stubrun "$G/setup.php" "$G/reset.php" "$G/rows.php" mod_quest_testdata \
    "$(sed -n 's/^\$seeded = \(.*\);$/\1/p' "$G/setup.php")" "$(sed -n 's/^\$fields = \(.*\);$/\1/p' "$G/setup.php")")"
grep -q '"quest":\[77\],"quest_answer":\[1,2,3\]' <<<"$got" \
    && grep -q '"answer":"testdata-1","timecreated":[0-9]*,"timelimit":0,"questid":77,"userid":42' <<<"$got" \
    && ok "mod_: answers point to the instance, timelimit not a timestamp" || bad "mod_ stub: $got"
grep -q "'keys' => \[\['questid', 'userid'\]\]" "$G/rows.php" && grep -q "'keys' => \[\['courseid'\]\]" "$G/rows.php" \
    && ok "rows.php: unique keys and indexes" || bad "rows.php keys: $(cat "$G/rows.php")"
grep -q '^run1 inserts=8$' <<<"$got" && grep -q '^run2 inserts=8$' <<<"$got" \
    && ok "unique on fixed fields: 1 row, rerun idempotent" || bad "unique stub: $got"
python3 - "$got" <<'PY3' && ok "no unique key repeats" || bad "unique values: $got"
import json, sys
lines = dict(line.split("=", 1) for line in sys.argv[1].splitlines() if "=" in line and not line.startswith("run"))
rows, seeded = json.loads(lines["rows"]), json.loads(lines["seeded"])
assert len(seeded["quest_grade"]) == 1 and len(seeded["quest_setting"]) == 1 and len(seeded["quest_code"]) == 3
assert [r["code"] for r in rows["quest_code"].values()] == [1, 2, 3]
assert [(r["questid"], r["userid"]) for r in rows["quest_grade"].values()] == [(77, 42)]
assert [r["courseid"] for r in rows["quest_setting"].values()] == [7]
PY3
grep -q 'sql_like($DB->sql_compare_text($marker), ' "$G/reset.php" && ok "reset.php: LIKE on sql_compare_text" || bad "reset like"

# Codechecker scans visible dirs only, so render a second copy under testdata/.
python3 "$D" "$P" --dir testdata >/dev/null 2>&1
if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
    out="$(nice -n 19 "$MPC" codechecker "$P" 2>&1)"; rc=$?; n="$(grep -cE '\| (ERROR|WARNING) \|' <<<"$out")"
    [ "$rc" -eq 0 ] && [ "$n" -eq 0 ] && ok "codechecker 0 errors 0 warnings" \
        || bad "codechecker rc=$rc, $n errors/warnings: $(grep -v '^[[:space:]]*$' <<<"$out" | head -12)"
else
    echo "SKIP codechecker: moodle-plugin-ci absent"
fi

[ "$fails" -eq 0 ] && echo "all testdata cases pass" || echo "$fails FAILURES"
exit $((fails > 0))
