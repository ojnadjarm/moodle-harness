#!/usr/bin/env bash
# Drive upgrade.py on mktemp fixtures: new and hand-written upgrade.php, table/field/key/index add and drop, escaping, --base-file without git and its re-run guard (incl. XMLDB-editor layout), --add-field, XMLDB VERSION.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
U="$(cd "$(dirname "$0")/.." && pwd)/upgrade.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
commit() { git -C "$T/repo" add -A && git -C "$T/repo" -c user.name=t -c user.email=t@example.com commit -qm "$1"; }
version() { sed -n 's/^\$plugin->version = \([0-9]*\);/\1/p' "$P/version.php"; }
lint() { php -l "$P/db/upgrade.php" >/dev/null 2>&1 && ok "$1 php -l clean" || bad "$1 php -l: $(php -l "$P/db/upgrade.php" 2>&1)"; }

plugin() {
    P="$T/repo/$1"; mkdir -p "$P/db"
    cat > "$P/version.php" <<EOF
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
 * @package    $2
 * @copyright  2026 onwards, Example Author <author@example.com>
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

defined('MOODLE_INTERNAL') || die();

\$plugin->component = '$2';
\$plugin->version = 2026010100;
\$plugin->requires = 2024100700;
EOF
    cat > "$P/db/install.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" ?>
<XMLDB PATH="local/demo/db" VERSION="20260101" COMMENT="XMLDB file">
  <TABLES>
    <TABLE NAME="local_demo" COMMENT="Demo rows">
      <FIELDS>
        <FIELD NAME="id" TYPE="int" LENGTH="10" NOTNULL="true" SEQUENCE="true"/>
        <FIELD NAME="name" TYPE="char" LENGTH="255" NOTNULL="true" SEQUENCE="false"/>
      </FIELDS>
      <KEYS>
        <KEY NAME="primary" TYPE="primary" FIELDS="id"/>
      </KEYS>
    </TABLE>
  </TABLES>
</XMLDB>
EOF
}

git init -q "$T/repo"
plugin demo local_demo
commit init

python3 "$U" "$P" >"$T/out" 2>&1 && bad "no change accepted" \
    || { grep -q unchanged "$T/out" && ok "no change refused" || bad "no change message: $(cat "$T/out")"; }

sed -i 's|^\(        <FIELD NAME="name".*\)$|\1\n        <FIELD NAME="score" TYPE="number" LENGTH="10" DECIMALS="2" NOTNULL="false" DEFAULT="0" SEQUENCE="false"/>|' "$P/db/install.xml"
python3 "$U" --dry-run "$P" >"$T/out" 2>&1 && grep -qx '+ field local_demo.score' "$T/out" && [ ! -e "$P/db/upgrade.php" ] \
    && [ "$(version)" = 2026010100 ] && ok "dry-run prints diff, writes nothing" || bad "dry-run: $(cat "$T/out")"
python3 "$U" "$P" >"$T/out" 2>&1 || bad "add field rc: $(cat "$T/out")"
v1="$(version)"; today="$(date +%Y%m%d)00"
[ "$v1" -ge "$today" ] && [ "$v1" -gt 2026010100 ] && ok "version bumped to $v1" || bad "version after add field: $v1"
f="$P/db/upgrade.php"
grep -q "if (\$oldversion < $v1) {" "$f" && grep -q "if (!\$dbman->field_exists(\$table, \$field)) {" "$f" \
    && grep -q "new xmldb_field('score', XMLDB_TYPE_NUMBER, '10, 2', null, null, null, '0', 'name');" "$f" \
    && grep -q "upgrade_plugin_savepoint(true, $v1, 'local', 'demo');" "$f" && grep -q '\$dbman = \$DB->get_manager();' "$f" \
    && ok "add field step + savepoint in new upgrade.php" || bad "add field step: $(cat "$f")"
grep -q '@package    local_demo' "$f" && grep -q 'Example Author' "$f" && ok "new upgrade.php header" || bad "header"
lint "add field"
grep -q "<XMLDB PATH=\"local/demo/db\" VERSION=\"${v1:0:8}\"" "$P/db/install.xml" \
    && ok "8-digit XMLDB VERSION set to ${v1:0:8}" || bad "XMLDB VERSION: $(grep '<XMLDB' "$P/db/install.xml")"
commit field

cat > "$T/table.py" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("  </TABLES>", """    <TABLE NAME="local_demo_log" COMMENT="Log">
      <FIELDS>
        <FIELD NAME="id" TYPE="int" LENGTH="10" NOTNULL="true" SEQUENCE="true"/>
        <FIELD NAME="demoid" TYPE="int" LENGTH="10" NOTNULL="true" SEQUENCE="false"/>
        <FIELD NAME="note" TYPE="text" NOTNULL="false" SEQUENCE="false"/>
      </FIELDS>
      <KEYS>
        <KEY NAME="primary" TYPE="primary" FIELDS="id"/>
        <KEY NAME="demoid" TYPE="foreign" FIELDS="demoid" REFTABLE="local_demo" REFFIELDS="id"/>
      </KEYS>
    </TABLE>
  </TABLES>""")
open(p, "w").write(s)
EOF
python3 "$T/table.py" "$P/db/install.xml"
python3 "$U" "$P" >"$T/out" 2>&1 || bad "add table rc: $(cat "$T/out")"
v2="$(version)"
[ "$v2" -gt "$v1" ] && ok "second bump $v1 -> $v2" || bad "second bump: $v1 -> $v2"
grep -q "\$table->add_field('demoid', XMLDB_TYPE_INTEGER, '10', null, XMLDB_NOTNULL, null, null);" "$f" \
    && grep -q "\$table->add_key('demoid', XMLDB_KEY_FOREIGN, \['demoid'\], 'local_demo', \['id'\]);" "$f" \
    && grep -q 'if (!$dbman->table_exists($table)) {' "$f" && [ "$(grep -c '_savepoint(' "$f")" = 2 ] \
    && [ "$(grep -c 'get_manager' "$f")" = 1 ] && ok "add table step appended" || bad "add table step: $(cat "$f")"
lint "add table"
commit table

sed -i '0,/^      <\/KEYS>$/s||      </KEYS>\n      <INDEXES>\n        <INDEX NAME="name" UNIQUE="true" FIELDS="name"/>\n      </INDEXES>|' "$P/db/install.xml"
python3 "$U" "$P" >"$T/out" 2>&1 || bad "add index rc: $(cat "$T/out")"
grep -q "new xmldb_index('name', XMLDB_INDEX_UNIQUE, \['name'\]);" "$f" && grep -q 'if (!$dbman->index_exists($table, $index)) {' "$f" \
    && ok "add index step" || bad "add index step: $(cat "$T/out")"
lint "add index"
commit index

sed -i '/<FIELD NAME="score"/d' "$P/db/install.xml"
python3 "$U" "$P" >"$T/out" 2>&1 && grep -qx -- '- field local_demo.score' "$T/out" \
    && grep -q 'if ($dbman->field_exists($table, $field)) {' "$f" && ok "drop field step" || bad "drop field: $(cat "$T/out")"
lint "drop field"
python3 "$U" "$P" >"$T/out" 2>&1 && bad "dropped field generated twice" \
    || { grep -q 'already bumped' "$T/out" && ok "re-run refused while version.php bump is uncommitted" || bad "re-run message: $(cat "$T/out")"; }
python3 "$U" "$P" --base HEAD~3 --dry-run >"$T/out" 2>&1 && grep -qx '+ table local_demo_log' "$T/out" \
    && grep -qx '+ index local_demo.name' "$T/out" && ok "--base HEAD~3 diff" || bad "--base: $(cat "$T/out")"
python3 "$U" "$P" --base nosuchref >"$T/out" 2>&1 && bad "bad ref accepted" || ok "unknown ref refused"

plugin mymod mod_mymod; commit mod
sed -i 's|^\(        <FIELD NAME="name".*\)$|\1\n        <FIELD NAME="intro" TYPE="text" NOTNULL="false" SEQUENCE="false"/>|' "$P/db/install.xml"
python3 "$U" "$P" >"$T/out" 2>&1 && grep -q "upgrade_mod_savepoint(true, $(version), 'mymod');" "$P/db/upgrade.php" \
    && ok "mod savepoint variant" || bad "mod savepoint: $(cat "$T/out")"
lint "mod"
commit modfield
sed -i 's|^\(        <FIELD NAME="intro".*\)$|\1\n        <FIELD NAME="grade" TYPE="int" LENGTH="10" NOTNULL="true" DEFAULT="0" SEQUENCE="false"/>|' "$P/db/install.xml"
commit modgrade
python3 "$U" "$P" --base HEAD~2 >"$T/out" 2>&1 && grep -qx '+ field local_demo.grade' "$T/out" \
    && grep -q "new xmldb_field('grade', XMLDB_TYPE_INTEGER" "$P/db/upgrade.php" && ok "--base before a committed bump writes the step" || bad "--base write: $(cat "$T/out")"

plugin foo block_foo
cat > "$P/db/upgrade.php" <<'EOF'
<?php
// This file is part of Moodle - https://moodle.org/

/**
 * Upgrade steps.
 *
 * @package    block_foo
 * @copyright  2026 onwards, Example Author <author@example.com>
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

/**
 * Executed on plugin upgrade.
 *
 * @param int $oldversion Version we are upgrading from.
 * @return bool
 */
function xmldb_block_foo_upgrade(int $oldversion): bool {
    global $DB;
    $dbman = $DB->get_manager();

    if ($oldversion < 2025060100) {
        // Foo savepoint reached.
        upgrade_block_savepoint(true, 2025060100, 'foo');
    }

    return true;
}

/**
 * Helper after the upgrade function.
 *
 * @return bool
 */
function block_foo_helper(): bool {
    return true;
}
EOF
python3 "$T/table.py" "$P/db/install.xml"; commit foo
f="$P/db/upgrade.php"; cp "$f" "$T/foo.orig"
sed -i 's|^\(        <FIELD NAME="name".*\)$|\1\n        <FIELD NAME="label" TYPE="char" LENGTH="20" NOTNULL="true" DEFAULT="it'"'"'s \\ ok" SEQUENCE="false"/>|' "$P/db/install.xml"
sed -i '0,/^        <KEY NAME="primary".*$/s||&\n        <KEY NAME="name" TYPE="unique" FIELDS="name"/>|' "$P/db/install.xml"
python3 "$U" "$P" >"$T/out" 2>&1 || bad "hand-written rc: $(cat "$T/out")"
v="$(version)"; step="$(grep -n "if (\$oldversion < $v) {" "$f" | cut -d: -f1)"; helper="$(grep -n 'function block_foo_helper' "$f" | cut -d: -f1)"
[ -n "$step" ] && [ "$step" -lt "$helper" ] && [ "$(sed -n "$((step - 1))p" "$f")" = "" ] \
    && tail -n 8 "$f" | diff -q - <(tail -n 8 "$T/foo.orig") >/dev/null && [ "$(grep -c 'get_manager' "$f")" = 1 ] \
    && grep -q 'if ($oldversion < 2025060100) {' "$f" && ok "step lands in xmldb_block_foo_upgrade(), not the helper after it" \
    || bad "hand-written placement: $(cat "$f")"
grep -qF "'it\\'s \\\\ ok', 'name');" "$f" && grep -q "new xmldb_key('name', XMLDB_KEY_UNIQUE, \['name'\]);" "$f" \
    && grep -q "upgrade_block_savepoint(true, $v, 'foo');" "$f" && ok "escaped DEFAULT, add key, block savepoint" || bad "escape/key: $(cat "$f")"
lint "hand-written"
commit foostep

sed -i '/<KEY NAME="name" TYPE="unique"/d' "$P/db/install.xml"
python3 - "$P/db/install.xml" <<'EOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(re.sub(r'    <TABLE NAME="local_demo_log".*?</TABLE>\n', "", s, flags=re.S))
EOF
python3 "$U" "$P" >"$T/out" 2>&1 && grep -qx -- '- key local_demo.name' "$T/out" && grep -qx -- '- table local_demo_log' "$T/out" \
    && grep -q '    $dbman->drop_table($table);' "$f" && grep -q '$dbman->drop_key($table, $key);' "$f" \
    && ok "drop table and drop key steps" || bad "drop table/key: $(cat "$T/out")"
lint "drop table/key"
commit foodrop

cp "$P/version.php" "$T/version.before"
sed -i 's|^\(        <FIELD NAME="name".*\)$|\1\n        <FIELD NAME="bad'"'"'name" TYPE="int" LENGTH="10" NOTNULL="false" SEQUENCE="false"/>|' "$P/db/install.xml"
python3 "$U" "$P" >"$T/out" 2>&1 && bad "bad name accepted" \
    || { grep -q "bad'name" "$T/out" && cmp -s "$P/version.php" "$T/version.before" && ok "invalid name refused, nothing written" || bad "bad name: $(cat "$T/out")"; }

R="$T/nogit"; mkdir -p "$R"; P0="$P"; P="$R/fresh"; mkdir -p "$P/db"
cp "$P0/version.php" "$P/version.php"; sed -i "s/^\\\$plugin->component = .*/\\\$plugin->component = 'local_fresh';/" "$P/version.php"
sed "/bad'name/d" "$P0/db/install.xml" > "$T/old-install.xml"
sed 's|VERSION="[0-9]*"|VERSION="2026010100"|; s|^\(        <FIELD NAME="name".*\)$|\1\n        <FIELD NAME="extra" TYPE="int" LENGTH="10" NOTNULL="false" SEQUENCE="false"/>|' \
    "$T/old-install.xml" > "$P/db/install.xml"
GIT_CEILING_DIRECTORIES="$R" python3 "$U" "$P" >"$T/out" 2>&1; rc=$?
[ "$rc" = 2 ] && grep -q -- '--base-file' "$T/out" && grep -q -- '--base' "$T/out" && grep -q 'not in a git repo' "$T/out" \
    && [ ! -e "$P/db/upgrade.php" ] && ok "no git repo: rc 2 naming --base-file and --base" || bad "no repo rc=$rc: $(cat "$T/out")"
GIT_CEILING_DIRECTORIES="$R" python3 "$U" "$P" --base-file "$T/old-install.xml" >"$T/out" 2>&1 || bad "base-file rc: $(cat "$T/out")"
v="$(version)"; f="$P/db/upgrade.php"
grep -qx '+ field local_demo.extra' "$T/out" && [ "$(grep -c '^[+-] ' "$T/out")" = 1 ] \
    && grep -q "new xmldb_field('extra', XMLDB_TYPE_INTEGER" "$f" && grep -q "upgrade_plugin_savepoint(true, $v, 'local', 'fresh');" "$f" \
    && ok "--base-file diff writes the step without git" || bad "--base-file: $(cat "$T/out")"
grep -q "VERSION=\"$v\"" "$P/db/install.xml" && [ "$v" -gt 2026010100 ] \
    && ok "10-digit XMLDB VERSION set to $v" || bad "XMLDB VERSION: $(grep '<XMLDB' "$P/db/install.xml") vs $v"
lint "base-file"
GIT_CEILING_DIRECTORIES="$R" python3 "$U" "$P" --base-file "$T/none.xml" >"$T/out" 2>&1 && bad "missing base file accepted" \
    || { grep -q 'is not a file' "$T/out" && ok "missing --base-file refused" || bad "missing base file: $(cat "$T/out")"; }
python3 "$U" "$P" --base HEAD --base-file "$T/old-install.xml" >/dev/null 2>&1 && bad "--base with --base-file accepted" \
    || ok "--base and --base-file are exclusive"

cp "$P/version.php" "$T/version.before"
GIT_CEILING_DIRECTORIES="$R" python3 "$U" "$P" --base-file "$T/old-install.xml" >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'already has a guarded step for + field local_demo.extra' "$T/out" && cmp -s "$P/version.php" "$T/version.before" \
    && [ "$(grep -c "new xmldb_field('extra'" "$f")" = 1 ] && ok "--base-file re-run refused rc 1, no duplicate step" || bad "re-run rc=$rc: $(cat "$T/out")"

plugin ed local_ed; mv "$P" "$R/ed"; P="$R/ed"; f="$P/db/upgrade.php"; cp "$P/db/install.xml" "$T/ed-old.xml"
sed -i 's|^\(        <FIELD NAME="name".*\)$|\1\n        <FIELD NAME="extra" TYPE="int" LENGTH="10" NOTNULL="false" SEQUENCE="false"/>|
    s|^\(        <KEY NAME="primary".*\)$|\1\n        <KEY NAME="nameuq" TYPE="unique" FIELDS="name"/>|
    s|^      </KEYS>$|&\n      <INDEXES>\n        <INDEX NAME="extra" UNIQUE="false" FIELDS="extra"/>\n      </INDEXES>|' "$P/db/install.xml"
cat > "$f" <<'EOF2'
<?php
function xmldb_local_ed_upgrade($oldversion) {
    global $DB;
    $dbman = $DB->get_manager();

    if ($oldversion < 2026010200) {

        // Define field extra to be added to local_demo.
        $table = new xmldb_table('local_demo');
        $field = new xmldb_field('extra', XMLDB_TYPE_INTEGER, '10', null, null, null, null, 'name');

        // Conditionally launch add field extra.
        if (!$dbman->field_exists($table, $field)) {
            $dbman->add_field($table, $field);
        }

        // Define key nameuq (unique) to be added to local_demo.
        $table = new xmldb_table('local_demo');
        $key = new xmldb_key('nameuq', XMLDB_KEY_UNIQUE, ['name']);

        // Launch add key nameuq.
        $dbman->add_key($table, $key);

        // Define index extra (not unique) to be added to local_demo.
        $table = new xmldb_table('local_demo');
        $index = new xmldb_index('extra', XMLDB_INDEX_NOTUNIQUE, ['extra']);

        // Conditionally launch add index extra.
        if (!$dbman->index_exists($table, $index)) {
            $dbman->add_index($table, $index);
        }

        // Ed savepoint reached.
        upgrade_plugin_savepoint(true, 2026010200, 'local', 'ed');
    }

    return true;
}
EOF2
cp "$f" "$T/ed.before"; cp "$P/version.php" "$T/version.before"
GIT_CEILING_DIRECTORIES="$R" python3 "$U" "$P" --base-file "$T/ed-old.xml" >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'already has a guarded step for + field local_demo.extra, + key local_demo.nameuq, + index local_demo.extra' "$T/out" \
    && cmp -s "$f" "$T/ed.before" && cmp -s "$P/version.php" "$T/version.before" \
    && ok "--base-file re-run refused on XMLDB-editor-style steps (comment lines, key)" || bad "editor re-run rc=$rc: $(cat "$T/out")"
plugin key local_key; mv "$P" "$R/key"; P="$R/key"; f="$P/db/upgrade.php"; cp "$P/db/install.xml" "$T/key-old.xml"
sed -i 's|^\(        <KEY NAME="primary".*\)$|\1\n        <KEY NAME="nameuq" TYPE="unique" FIELDS="name"/>|' "$P/db/install.xml"
GIT_CEILING_DIRECTORIES="$R" python3 "$U" "$P" --base-file "$T/key-old.xml" >"$T/out" 2>&1 || bad "key-only rc: $(cat "$T/out")"
cp "$f" "$T/key.before"; cp "$P/version.php" "$T/version.before"
GIT_CEILING_DIRECTORIES="$R" python3 "$U" "$P" --base-file "$T/key-old.xml" >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'already has a guarded step for + key local_demo.nameuq' "$T/out" && cmp -s "$f" "$T/key.before" \
    && cmp -s "$P/version.php" "$T/version.before" && [ "$(grep -c 'add_key' "$f")" = 1 ] \
    && ok "key-only --base-file re-run refused rc 1, no duplicate add_key" || bad "key-only re-run rc=$rc: $(cat "$T/out")"
P="$R/fresh"

XSDPATH="$HOME/moodle-envs/5.3/www/public/lib/xmldb/xmldb.xsd"; XSD=""
[ -f "$XSDPATH" ] && XSD="$XSDPATH" || echo "SKIP xsd (no $XSDPATH)"
xlint() { if [ -n "$XSD" ]; then xmllint --noout --schema "$XSD" "$1" 2>&1; else xmllint --noout "$1" 2>&1; fi; }
addf() { GIT_CEILING_DIRECTORIES="$R" python3 "$U" "$P" "$@" >"$T/out" 2>&1; }
plugin addf local_addf; mv "$P" "$R/addf"; P="$R/addf"; f="$P/db/upgrade.php"; x="$P/db/install.xml"
addf --add-field local_demo.priority:int:2 --dry-run && grep -qx '+ field local_demo.priority' "$T/out" \
    && ! grep -q priority "$x" && [ ! -e "$f" ] && ok "--add-field --dry-run writes nothing" || bad "add-field dry-run: $(cat "$T/out")"
addf --add-field local_demo.priority:int:2 --add-field local_demo.title:char || bad "add-field rc: $(cat "$T/out")"
v="$(version)"
grep -A1 '<FIELD NAME="name"' "$x" | grep -q '<FIELD NAME="priority" TYPE="int" LENGTH="2" NOTNULL="true" DEFAULT="0" SEQUENCE="false"/>' \
    && grep -A1 '<FIELD NAME="priority"' "$x" | grep -q '<FIELD NAME="title" TYPE="char" LENGTH="255" NOTNULL="true" SEQUENCE="false"/>' \
    && ok "--add-field x2 inserts FIELDs after the last field" || bad "add-field install.xml: $(cat "$x")"
out="$(xlint "$x")" && ok "--add-field install.xml valid${XSD:+ against xmldb.xsd}" || bad "add-field xmllint: $out"
grep -q "new xmldb_field('priority', XMLDB_TYPE_INTEGER, '2', null, XMLDB_NOTNULL, null, '0', 'name');" "$f" \
    && grep -q "new xmldb_field('title', XMLDB_TYPE_CHAR, '255', null, XMLDB_NOTNULL, null, null, 'priority');" "$f" \
    && grep -q "upgrade_plugin_savepoint(true, $v, 'local', 'addf');" "$f" && grep -q "VERSION=\"${v:0:8}\"" "$x" \
    && ok "--add-field writes the step, bump and VERSION" || bad "add-field step: $(cat "$T/out") $(cat "$f")"
lint "add-field"
cp "$x" "$T/x.before"; cp "$P/version.php" "$T/version.before"
for spec in local_demo.priority:int local_nope.foo:int local_demo.foo:bogus local_demo.foo:int:x local_demo.foo:int:2:9 nodot; do
    addf --add-field "$spec" && bad "add-field '$spec' accepted" \
        || { cmp -s "$x" "$T/x.before" && cmp -s "$P/version.php" "$T/version.before" && grep -qF -- "${spec#*.}" "$T/out" \
            && ok "--add-field '$spec' refused, nothing written" || bad "add-field '$spec': $(cat "$T/out")"; }
done
sed -i 's|\(<FIELD NAME="id"[^/]*\)/>|\1 NEXT="name"/>|; s|\(<FIELD NAME="name"[^/]*\)/>|\1 PREVIOUS="id"/>|' "$T/x.before"
sed '/priority\|title/d' "$T/x.before" > "$x"
addf --add-field local_demo.rank:number:10,2 || bad "chain rc: $(cat "$T/out")"
grep -q '<FIELD NAME="name" .*PREVIOUS="id" NEXT="rank"/>' "$x" \
    && grep -q '<FIELD NAME="rank" TYPE="number" LENGTH="10" NOTNULL="true" DEFAULT="0" SEQUENCE="false" DECIMALS="2" PREVIOUS="name"/>' "$x" \
    && out="$(xlint "$x")" && ok "--add-field keeps the PREVIOUS/NEXT chain valid" || bad "chain: $out $(cat "$x")"
sed -i 's| VERSION="[0-9]*"||' "$x"
addf --add-field local_demo.flag:int:1 && grep -q 'warning: .*no numeric VERSION' "$T/out" && grep -q '<FIELD NAME="flag"' "$x" \
    && ok "missing XMLDB VERSION warns on stderr" || bad "VERSION warning: $(cat "$T/out")"

if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
    out="$(nice -n 19 "$MPC" codechecker "$T/repo/demo" 2>&1)"; rc=$?; n="$(grep -cE '\| (ERROR|WARNING) \|' <<<"$out")"
    [ "$rc" -eq 0 ] && [ "$n" -eq 0 ] && ok "codechecker 0 errors 0 warnings on generated upgrade.php" \
        || bad "codechecker rc=$rc, $n errors/warnings: $(grep -v '^[[:space:]]*$' <<<"$out" | head -8)"
else
    echo "SKIP codechecker: moodle-plugin-ci absent"
fi

[ "$fails" -eq 0 ] && echo "PASS upgrade.test.sh" || { echo "FAIL upgrade.test.sh ($fails)"; exit 1; }
