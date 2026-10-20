#!/usr/bin/env bash
# Render a full recipe for 4.5, 5.2 and 5.3 into mktemp; check requires, file list and codechecker (not 5.2);
# recipe tables: per plugin type, mod merge, readers; sorted capability lang ids; block: get_content list; digit lengths;
# report_ nav callback + index.php; block: {}/null and non-ASCII requires refused.
set -uo pipefail
G="$(cd "$(dirname "$0")/.." && pwd)/generate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

expected="example/version.php
example/lang/en/tool_example.php
example/classes/privacy/provider.php
example/db/access.php
example/db/install.php
example/db/upgrade.php
example/settings.php
example/tests/example_test.php
example/cli/run.php"

for pair in 4.5:2024100700 5.2:2026042000 5.3:2026100500; do
    branch="${pair%%:*}"; want="${pair#*:}"; d="$T/$branch"; mkdir -p "$d"
    cat > "$d/recipe.yaml" <<EOF
component: tool_example
name: Example tool
requires: "$branch"
copyright: 2026 onwards, Example Author <author@example.com>
features: {settings: true, install: true, upgrade: true, privacy: true}
capabilities:
  - name: view
    title: View example
lang_strings:
  - id: taskname
    text: Scheduled task
phpunit_tests:
  - classname: example
cli_scripts:
  - filename: run
EOF
    python3 "$G" --target-dir "$d" "$d/recipe.yaml" >/dev/null 2>"$d/err" \
        && ok "$branch renders" || { bad "$branch renders: $(cat "$d/err")"; continue; }
    grep -q "^\$plugin->requires = $want;" "$d/example/version.php" \
        && ok "$branch requires $want" || bad "$branch requires: $(grep requires "$d/example/version.php")"
    got="$(cd "$d" && find example -type f | sort)"
    [ "$got" = "$(sort <<<"$expected")" ] && ok "$branch file list (9)" || bad "$branch file list: $got"
    [ "$branch" = 5.2 ] && continue
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker "$d/example" 2>&1)"; rc=$?
        if grep -q '| ERROR |' <<<"$out"; then bad "$branch codechecker: $(grep -c '| ERROR |' <<<"$out") errors"
        elif [ "$rc" -ne 0 ]; then bad "$branch codechecker rc=$rc: $(grep -v '^[[:space:]]*$' <<<"$out" | sed -n "/^In /{n;p;q}")"
        else ok "$branch codechecker 0 errors"; fi
    else
        echo "SKIP $branch codechecker: moodle-plugin-ci absent"
    fi
done

XSD="$(ls "$HOME"/moodle-envs/5.3/www/public/lib/xmldb/xmldb.xsd 2>/dev/null)"
lint() { if [ -n "$XSD" ]; then xmllint --noout --schema "$XSD" "$1" 2>&1; else xmllint --noout "$1" 2>&1; fi; }
tables_recipe() {
    printf 'component: %s\ncopyright: 2026 onwards, Example Author <author@example.com>\n' "$1"
    printf 'tables:\n  %s:\n    fields: [id, userid:int:10, name:char:255, timecreated:int:10%s]\n' "$2" "${3:-}"
    printf '    keys: [userid->user.id%s]\n    indexes: [timecreated, "unique:userid,name"]\n' "${4:-}"
}
for pair in local:local tool:admin/tool block:blocks mod:mod qtype:question/type format:course/format; do
    type="${pair%%:*}"; path="${pair#*:}/t877"; d="$T/tables-$type"; mkdir -p "$d"; x="$d/t877/db/install.xml"
    tables_recipe "${type}_t877" "$( [ "$type" = mod ] && echo t877 || echo "${type}_t877_item")" > "$d/recipe.yaml"
    python3 "$G" --target-dir "$d" "$d/recipe.yaml" >/dev/null 2>"$d/err" || { bad "tables: $type renders: $(cat "$d/err")"; continue; }
    out="$(lint "$x")" && ok "tables: $type install.xml valid${XSD:+ against xmldb.xsd}" || bad "tables: $type xmllint: $out"
    up="$(printf '../%.0s' $(seq $(( $(tr -cd / <<<"$path" | wc -c) + 2 ))))"
    grep -q "<XMLDB PATH=\"$path/db\" VERSION=\"[0-9]\{8\}\" COMMENT=\"XMLDB file for Moodle $path\"" "$x" \
        && grep -q "noNamespaceSchemaLocation=\"${up}lib/xmldb/xmldb.xsd\"" "$x" \
        && grep -q '<INDEX NAME="userid-name" UNIQUE="true" FIELDS="userid, name"/>' "$x" \
        && ok "tables: $type PATH, VERSION, COMMENT, xsd path, index" || bad "tables: $type header: $(sed -n 2,4p "$x")"
done
x="$T/tables-mod/t877/db/install.xml"
python3 -c 'import sys, xml.etree.ElementTree as E; t = E.parse(sys.argv[1]).findall("TABLES/TABLE"); \
    sys.exit(0 if [f.get("NAME") for f in t[0].find("FIELDS")] == ["id", "course", "name", "intro", "introformat", "timemodified", "userid", "timecreated"] \
    and len(t) == 1 and {k.get("NAME") for k in t[0].find("KEYS")} == {"primary", "course", "userid"} else 1)' "$x" \
    && ok "tables: mod instance table merges recipe fields and keys into the default one" || bad "tables: mod merge: $(cat "$x")"
python3 "$G" --list <(printf 'component: local_x\n') | grep -q install.xml \
    && bad "tables: install.xml without tables" || ok "tables: no tables key, no install.xml for local"

d="$T/readers"; mkdir -p "$d/v1" "$d/v2"
tables_recipe mod_t877 t877_entry ", t877id" ", t877id->t877.id" > "$d/v1/recipe.yaml"
tables_recipe mod_t877 t877_entry ", t877id, note:text" ", t877id->t877.id" > "$d/v2/recipe.yaml"
python3 "$G" --target-dir "$d/v1" "$d/v1/recipe.yaml" >/dev/null && python3 "$G" --target-dir "$d/v2" "$d/v2/recipe.yaml" >/dev/null \
    && python3 "$(dirname "$G")/upgrade.py" "$d/v2/t877" --base-file "$d/v1/t877/db/install.xml" --dry-run 2>&1 | grep -q '^+ field t877_entry.note$' \
    && python3 "$(dirname "$G")/backup.py" "$d/v2/t877" >/dev/null && grep -q "t877_entry" "$d/v2/t877/backup/moodle2/backup_t877_stepslib.php" \
    && python3 "$(dirname "$G")/privacy.py" "$d/v2/t877" >/dev/null && ! grep -q null_provider "$d/v2/t877/classes/privacy/provider.php" \
    && ok "tables: upgrade.py, backup.py and privacy.py read the generated install.xml" || bad "tables: readers"

python3 "$G" --list <(printf 'component: local_x\ntables:\n  local_x_a:\n    fields: [name:varchar]\n') >/dev/null 2>"$T/err" \
    && bad "tables: bad field type accepted" || { grep -q "bad field 'name:varchar'" "$T/err" && ok "tables: bad field type refused" || bad "tables: bad field message: $(cat "$T/err")"; }
python3 "$G" --list <(printf 'component: local_x\ntables:\n  local_x_a:\n    keys: [userid->user.id]\n') >/dev/null 2>"$T/err" \
    && bad "tables: key on unlisted field accepted" || ok "tables: key on unlisted field refused"
refuse() {
    python3 "$G" --list <(printf 'component: local_x\ntables:\n  %s:\n    fields: [%s]\n    keys: [%s]\n    indexes: [%s]\n' "$2" "$3" "$4" "$5") \
        >/dev/null 2>"$T/err"; rc=$?
    [ "$rc" -eq 1 ] && grep -q -- "$6" "$T/err" && ok "tables: $1 refused" || bad "tables: $1 rc=$rc: $(cat "$T/err")"
}
long="$(printf 'a%.0s' $(seq 64))"
refuse "non-numeric length" local_x_a "cnt:int:abc" "" "" "length must be 1..20"
refuse "char 5000" local_x_a "note:char:5000" "" "" "1..1333"
refuse "int 30" local_x_a "cnt:int:30" "" "" "1..20"
refuse "number 39" local_x_a "\"amt:number:39,2\"" "" "" "1..38"
refuse "decimals not below length" local_x_a "\"amt:number:5,5\"" "" "" "below the length"
refuse "length on text" local_x_a "note:text:10" "" "" "takes no length"
refuse "64-char field name" local_x_a "$long" "" "" "max 63"
refuse "54-char table name" "local_$(printf 'b%.0s' $(seq 48))" "name" "" "" "max 53"
refuse "index equal to an FK" local_x_a "userid" "userid->user.id" "userid" "collides with index"
refuse "second key on a field" local_x_a "userid" "userid->user.id, userid->user.id" "" "second key on 'userid'"
python3 "$G" --list <(printf 'component: local_x\ntables:\n  local_%s:\n    fields: [%s:char:1333, cnt:int:20, "amt:number:38,10"]\n    keys: [cnt->user.id]\n    indexes: ["cnt,amt"]\n' "$(printf 'c%.0s' $(seq 47))" "$(printf 'd%.0s' $(seq 63))") \
    >/dev/null 2>"$T/err" && ok "tables: limits 1333/20/38, 63-char field, 53-char table, index wider than an FK accepted" \
    || bad "tables: limits at the edge: $(cat "$T/err")"

d="$T/capsort"; mkdir -p "$d"
printf 'component: local_t877\ncopyright: x\ncapabilities:\n  - {name: view, title: V}\n  - {name: manage, title: M}\n  - {name: approve, title: A}\n' > "$d/recipe.yaml"
python3 "$G" --target-dir "$d" "$d/recipe.yaml" >/dev/null \
    && [ "$(grep -o "^\$string\['t877:[a-z]*'\]" "$d/t877/lang/en/local_t877.php" | tr '\n' ' ')" = "\$string['t877:approve'] \$string['t877:manage'] \$string['t877:view'] " ] \
    && ok "capability lang ids sorted" || bad "capability sort: $(grep "t877:" "$d/t877/lang/en/local_t877.php")"

d="$T/blocklist"; mkdir -p "$d"; b="$d/t976/block_t976.php"
block_recipe() {
    printf 'component: %s\ncopyright: 2026 onwards, Example Author <author@example.com>\n' "$1"
    printf 'tables:\n  block_t976_mark:\n    fields: [userid:int:10, title:char:255, timecreated:int:10]\n    keys: [userid->user.id]\n%b' "$2"
}
block_recipe block_t976 'block: {table: block_t976_mark, link: marks.php}\n' > "$d/recipe.yaml"
python3 "$G" --target-dir "$d" "$d/recipe.yaml" >/dev/null 2>"$T/err" \
    && grep -q "get_records('block_t976_mark', \['userid' => \$USER->id\], 'id DESC', 'id, title', 0, 5)" "$b" \
    && grep -q 'format_string($row->title, true' "$b" \
    && grep -q "new moodle_url('/blocks/t976/marks.php')" "$b" \
    && grep -q "^\$string\['viewall'\]" "$d/t976/lang/en/block_t976.php" && php -l "$b" >/dev/null \
    && ok "block: get_content lists the user's 5 latest rows and links marks.php" || bad "block get_content: $(cat "$T/err"; sed -n '/get_content/,/^    }/p' "$b")"
if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
    out="$(nice -n 19 "$MPC" codechecker "$d/t976" 2>&1)" && ! grep -q '| ERROR \|| WARNING' <<<"$out" \
        && ok "block: get_content codechecker 0/0" || bad "block codechecker: $(grep -A1 '| ERROR \|| WARNING' <<<"$out" | head -6)"
fi
d="$T/blockplain"; mkdir -p "$d"; block_recipe block_t976 '' > "$d/recipe.yaml"
python3 "$G" --target-dir "$d" "$d/recipe.yaml" >/dev/null \
    && [ "$(sed -n '/function get_content/,/^    }/p' "$d/t976/block_t976.php" | grep -c 'DB\|moodle_url')" -eq 0 ] \
    && ! grep -q viewall "$d/t976/lang/en/block_t976.php" \
    && ok "block: no block: key keeps the empty get_content" || bad "block plain: $(sed -n '/get_content/,/^    }/p' "$d/t976/block_t976.php")"
refuse_block() {
    python3 "$G" --list <(block_recipe "$2" "$3") >/dev/null 2>"$T/err"; rc=$?
    [ "$rc" -eq 1 ] && grep -q -- "$4" "$T/err" && ok "block: $1 refused" || bad "block: $1 rc=$rc: $(cat "$T/err")"
}
refuse_block "unknown table" block_t976 'block: {table: block_t976_nope, link: marks.php}\n' "not in the recipe tables"
refuse_block "link outside the plugin" block_t976 'block: {table: block_t976_mark, link: ../x.php}\n' "bad link"
refuse_block "block: on local_" local_t976 'block: {table: block_t976_mark, link: marks.php}\n' "needs a block_ component"
refuse "Unicode-digit length ²" local_x_a "cnt:int:²" "" "" "length must be 1..20"
refuse "Unicode-digit decimals" local_x_a "\"amt:number:10,²\"" "" "" "below the length"
grep -q Traceback "$T/err" && bad "length ²: traceback" || ok "length ²: no traceback"
python3 "$G" --target-dir "$T/lead0" <(printf 'component: local_t976\ncopyright: x\ntables:\n  local_t976_a:\n    fields: [cnt:int:010, "amt:number:010,02"]\n') >/dev/null 2>"$T/err" \
    && grep -q 'NAME="cnt" TYPE="int" LENGTH="10"' "$T/lead0/t976/db/install.xml" \
    && grep -q 'NAME="amt" TYPE="number" LENGTH="10" .*DECIMALS="2"' "$T/lead0/t976/db/install.xml" \
    && ok "length 010 normalised to 10, decimals 02 to 2" || bad "length 010: $(cat "$T/err"; grep -h 'cnt\|amt' "$T/lead0/t976/db/install.xml")"

refuse_block "block: {}" block_t976 'block: {}\n' "needs a block_ component"
refuse_block "block: null" block_t976 'block: null\n' "needs a block_ component"

d="$T/report"; mkdir -p "$d"; r="$d/t1019"
printf 'component: report_t1019\nname: T1019 report\ncopyright: 2026 onwards, Example Author <author@example.com>\n' > "$d/recipe.yaml"
python3 "$G" --target-dir "$d" "$d/recipe.yaml" >/dev/null 2>"$T/err" \
    && [ "$(cd "$d" && find t1019 -type f | sort | tr '\n' ' ')" = "t1019/classes/privacy/provider.php t1019/index.php t1019/lang/en/report_t1019.php t1019/lib.php t1019/version.php " ] \
    && ok "report: lib.php and index.php written" || bad "report files: $(cat "$T/err"; cd "$d" && find t1019 -type f)"
grep -q '^function report_t1019_extend_navigation_course(\$navigation, \$course, \$context) {$' "$r/lib.php" \
    && grep -q "has_capability('moodle/site:viewreports', \$context)" "$r/lib.php" \
    && grep -q "new moodle_url('/report/t1019/index.php', \['id' => \$course->id\])" "$r/lib.php" \
    && ok "report: extend_navigation_course is cap-checked and links index.php?id=" || bad "report lib.php: $(cat "$r/lib.php")"
grep -q 'require_login(\$course);' "$r/index.php" && grep -q 'context_course::instance(\$course->id)' "$r/index.php" \
    && grep -q "require_capability('moodle/site:viewreports', \$context)" "$r/index.php" \
    && grep -q "\$OUTPUT->heading(get_string('pluginname', 'report_t1019'))" "$r/index.php" \
    && php -l "$r/lib.php" >/dev/null && php -l "$r/index.php" >/dev/null \
    && ok "report: index.php logs in to the course, checks its context, prints the heading; php -l clean" \
    || bad "report index.php: $(cat "$r/index.php")"
if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
    out="$(nice -n 19 "$MPC" codechecker --max-warnings 0 "$r" 2>&1)" && ! grep -q '| ERROR \|| WARNING' <<<"$out" \
        && ok "report: codechecker 0/0" || bad "report codechecker: $(grep -A1 '| ERROR \|| WARNING' <<<"$out" | head -6)"
fi
d="$T/reportcap"; mkdir -p "$d"
printf 'component: report_t1019\ncopyright: x\ncapabilities:\n  - {name: view, title: View, contextlevel: CONTEXT_COURSE}\n' > "$d/recipe.yaml"
python3 "$G" --target-dir "$d" "$d/recipe.yaml" >/dev/null \
    && grep -q "has_capability('report/t1019:view'" "$d/t1019/lib.php" && grep -q "require_capability('report/t1019:view'" "$d/t1019/index.php" \
    && ok "report: a recipe view capability guards the nav link and the page" || bad "report view cap: $(grep -h capability "$d/t1019/"*.php)"

python3 "$G" --list <(printf "component: tool_x\nrequires: '²'\n") >/dev/null 2>"$T/err"; rc=$?
[ "$rc" -eq 1 ] && grep -q "unknown 'requires'" "$T/err" && ok "requires '²' refused" || bad "requires ²: rc=$rc $(cat "$T/err")"
python3 "$G" --target-dir "$T/rawreq" <(printf 'component: tool_t1019\ncopyright: x\nrequires: 2024100700\n') >/dev/null \
    && grep -q '^\$plugin->requires = 2024100700;' "$T/rawreq/t1019/version.php" && ok "requires raw ASCII version accepted" \
    || bad "requires raw version"

python3 "$G" --list <(printf 'component: tool_x\nrequires: "9.9"\n')>/dev/null 2>"$T/err" \
    && bad "unknown branch accepted" || { grep -q "5.3" "$T/err" && ok "unknown branch refused, lists 5.3" || bad "unknown branch message: $(cat "$T/err")"; }

[ "$fails" -eq 0 ] && echo "PASS generate.test.sh" || echo "FAIL generate.test.sh ($fails)"
exit $((fails > 0))
