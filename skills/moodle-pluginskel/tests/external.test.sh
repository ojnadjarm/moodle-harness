#!/usr/bin/env bash
# Drive external.py on mktemp plugins: 4.5 vs 4.1 base class, services.php merge, php -l, codechecker, refusals.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
S="$(cd "$(dirname "$0")/.." && pwd)"
E="$S/external.py"; G="$S/generate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
version() { sed -n 's/^\$plugin->version = \([0-9]*\);/\1/p' "$1/version.php"; }

render() {
    mkdir -p "$T/$1"
    printf 'component: %s\nrequires: "%s"\ncopyright: 2026 onwards, Example Author <author@example.com>\ncapabilities:\n  - name: viewitems\n    title: View items\n' \
        "$2" "$1" > "$T/$1/recipe.yaml"
    python3 "$G" --target-dir "$T/$1" "$T/$1/recipe.yaml" >/dev/null 2>"$T/err" || bad "$1 skeleton: $(cat "$T/err")"
}

render 4.5 mod_demo; P45="$T/4.5/demo"
render 4.1 local_demo; P41="$T/4.1/demo"
mkdir -p "$P41/db"
{ sed -n '1,/^ \*\/$/p' "$P41/version.php" | sed 's/^ \* Plugin version and other metadata\.$/ * External functions and services./'
  cat <<'EOF'

defined('MOODLE_INTERNAL') || die();

$functions = [
    'local_demo_existing' => [
        'classname' => 'local_demo\external\existing',
        'type' => 'read',
    ]
];

$services = [
    'Demo service' => ['functions' => ['local_demo_existing'], 'enabled' => 1],
];
EOF
} > "$P41/db/services.php"
v0="$(version "$P45")"
python3 "$E" "$P45" get_items --params courseid:int,name:text --returns multiple --ajax --capability viewitems \
    >"$T/out" 2>&1 && ok "4.5 renders" || bad "4.5 rc: $(cat "$T/out")"
python3 "$E" "$P41" update_item --params contextid:int,flag:bool --capability local/demo:viewitems \
    >"$T/out" 2>&1 && ok "4.1 renders" || bad "4.1 rc: $(cat "$T/out")"

c45="$P45/classes/external/get_items.php"; c41="$P41/classes/external/update_item.php"
grep -q '^use core_external\\external_api;' "$c45" && ! grep -q externallib "$c45" \
    && ok "4.5 uses core_external" || bad "4.5 base class: $(grep -E '^use|externallib' "$c45")"
grep -q '^use external_api;' "$c41" && grep -q "require_once(\$CFG->libdir . '/externallib.php');" "$c41" \
    && ! grep -q core_external "$c41" "$P41/tests/external/update_item_test.php" \
    && ok "4.1 uses lib/externallib.php external_api" || bad "4.1 base class: $(grep -E '^use|externallib' "$c41")"
grep -q 'self::validate_parameters(self::execute_parameters()' "$c45" \
    && grep -q 'self::validate_context($context);' "$c45" \
    && grep -q "require_capability('mod/demo:viewitems', \$context);" "$c45" \
    && grep -q "context_course::instance(\$params\['courseid'\])" "$c45" \
    && grep -q 'public static function execute(int $courseid, string $name): array {' "$c45" \
    && grep -q 'execute_returns(): external_multiple_structure' "$c45" \
    && ok "4.5 class: validate_parameters, validate_context, require_capability" || bad "4.5 class body"
t45="$P45/tests/external/get_items_test.php"
grep -q 'get_items::execute($course->id, ' "$t45" && grep -q 'core_external\\external_api::clean_returnvalue(get_items::execute_returns()' "$t45" \
    && ok "4.5 test calls execute + clean_returnvalue" || bad "4.5 test body"
grep -q "'mod_demo_get_items' => \[" "$P45/db/services.php" && grep -q "'classname' => 'mod_demo\\\\external\\\\get_items'," "$P45/db/services.php" \
    && grep -q "'type' => 'read'," "$P45/db/services.php" && grep -q "'ajax' => true," "$P45/db/services.php" \
    && grep -q "'type' => 'write'," "$P41/db/services.php" && grep -q "'ajax' => false," "$P41/db/services.php" \
    && ok "services.php entry: name, classname, type, ajax" || bad "services.php: $(cat "$P45/db/services.php")"
v1="$(version "$P45")"; [ "$v1" -gt "$v0" ] && ok "version bumped $v0 -> $v1" || bad "version not bumped: $v1"

python3 "$E" "$P41" get_more --returns single >"$T/out" 2>&1 || bad "merge rc: $(cat "$T/out")"
grep -q "'local_demo_existing' => \[" "$P41/db/services.php" && grep -q "'local_demo_update_item' => \[" "$P41/db/services.php" \
    && grep -q "'local_demo_get_more' => \[" "$P41/db/services.php" && grep -q "'Demo service' =>" "$P41/db/services.php" \
    && [ "$(grep -c '^\$functions = ' "$P41/db/services.php")" = 1 ] \
    && ok "merge keeps existing entries and \$services" || bad "merge: $(cat "$P41/db/services.php")"
mkdir -p "$T/arr/db"; cp "$P45/version.php" "$T/arr/"
printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\$functions = array(\n    'mod_demo_old' => array('classname' => 'x', 'type' => 'read')\n);\n" > "$T/arr/db/services.php"
python3 "$E" "$T/arr" get_new >/dev/null 2>"$T/err" && php -l "$T/arr/db/services.php" >/dev/null 2>&1 \
    && php -r "define('MOODLE_INTERNAL', 1); include '$T/arr/db/services.php'; exit(count(\$functions) == 2 ? 0 : 1);" \
    && ok "merge into array() keeps old entry" || bad "array() merge: $(cat "$T/err" "$T/arr/db/services.php")"

for empty in '[]' 'array()'; do
    mkdir -p "$T/empty/db"; cp "$P45/version.php" "$T/empty/"
    printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\$functions = %s;\n\n\$services = [\n    'Svc' => ['functions' => [], 'enabled' => 1],\n];\n" "$empty" > "$T/empty/db/services.php"
    python3 "$E" "$T/empty" get_a >/dev/null 2>"$T/err" \
        && php -r "define('MOODLE_INTERNAL', 1); include '$T/empty/db/services.php'; exit(isset(\$functions['mod_demo_get_a']) && array_keys(\$services) == ['Svc'] ? 0 : 1);" \
        && ok "merge into one-line \$functions = $empty" || bad "one-line $empty merge: $(cat "$T/err" "$T/empty/db/services.php")"
    rm -rf "$T/empty"
done
mkdir -p "$T/nophp/bin"; ln -s "$(command -v python3)" "$T/nophp/bin/python3"
PATH="$T/nophp/bin" python3 "$E" "$P45" get_nophp >"$T/out" 2>&1
grep -q 'php not on PATH' "$T/out" && ok "missing php warns" || bad "missing php silent: $(cat "$T/out")"
rm -f "$P45/classes/external/get_nophp.php" "$P45/tests/external/get_nophp_test.php"
sed -i "/'mod_demo_get_nophp' => \[/,/^    \],/d" "$P45/db/services.php"

mobileok() { php -r "define('MOODLE_INTERNAL', 1); define('MOODLE_OFFICIAL_MOBILE_SERVICE', 'moodle_mobile_app'); include '$1'; exit(\$functions['$2']['services'] == [$3] ? 0 : 1);"; }
python3 "$E" "$P45" get_app --mobile >"$T/out" 2>&1 && mobileok "$P45/db/services.php" mod_demo_get_app "'moodle_mobile_app'" \
    && ! php -r "define('MOODLE_INTERNAL', 1); define('MOODLE_OFFICIAL_MOBILE_SERVICE', 'm'); include '$P45/db/services.php'; exit(isset(\$functions['mod_demo_get_items']['services']) ? 0 : 1);" \
    && ok "--mobile adds MOODLE_OFFICIAL_MOBILE_SERVICE to the new entry only" || bad "--mobile: $(cat "$T/out" "$P45/db/services.php")"
A="$T/auto"; mkdir -p "$A/db"; cp "$P45/version.php" "$A/"; printf "<?php\n\$addons = [];\n" > "$A/db/mobile.php"
python3 "$E" "$A" get_auto >"$T/out" 2>&1 && mobileok "$A/db/services.php" mod_demo_get_auto "'moodle_mobile_app'" \
    && ok "db/mobile.php adds MOODLE_OFFICIAL_MOBILE_SERVICE without --mobile" || bad "mobile.php auto: $(cat "$T/out" "$A/db/services.php")"
v2="$(version "$P45")"
python3 "$E" "$P45" get_items --mobile >"$T/out" 2>&1 && mobileok "$P45/db/services.php" mod_demo_get_items "'moodle_mobile_app'" \
    && [ "$(version "$P45")" -gt "$v2" ] && [ ! -e "$P45/classes/external/get_items_test.php" ] \
    && ok "--mobile on an existing function adds the services key, bumps version" || bad "--mobile existing: $(cat "$T/out" "$P45/db/services.php")"
before="$(md5sum "$P45/db/services.php" "$P45/version.php")"
python3 "$E" "$P45" get_items --mobile >"$T/out" 2>&1 && grep -q 'already in MOODLE_OFFICIAL_MOBILE_SERVICE' "$T/out" \
    && [ "$before" = "$(md5sum "$P45/db/services.php" "$P45/version.php")" ] && [ "$(grep -c MOODLE_OFFICIAL_MOBILE_SERVICE "$P45/db/services.php")" = 2 ] \
    && ok "--mobile rerun is a no-op" || bad "--mobile rerun: $(cat "$T/out")"
for svc in "array('other_svc')" "[]" "['other_svc',]"; do
    M="$T/svc"; mkdir -p "$M/db"; cp "$P41/version.php" "$M/"
    printf "<?php\n\$functions = array(\n    'local_demo_old' => array(\n        'classname' => 'x',\n        'services' => %s,\n    ),\n    'local_demo_two' => array('classname' => 'y'),\n);\n" "$svc" > "$M/db/services.php"
    want="'other_svc', 'moodle_mobile_app'"; [ "$svc" = "[]" ] && want="'moodle_mobile_app'"
    python3 "$E" "$M" old --mobile >"$T/out" 2>&1 && python3 "$E" "$M" two --mobile >>"$T/out" 2>&1 \
        && mobileok "$M/db/services.php" local_demo_old "$want" && mobileok "$M/db/services.php" local_demo_two "'moodle_mobile_app'" \
        && grep -qF "'services' => array(MOODLE_OFFICIAL_MOBILE_SERVICE)," "$M/db/services.php" \
        && ok "--mobile merges into existing services $svc and array() entries" || bad "services $svc merge: $(cat "$T/out" "$M/db/services.php")"
    rm -rf "$M"
done

lintfail=0
for f in "$P45"/classes/external/*.php "$P45"/tests/external/*.php "$P45/db/services.php" \
         "$P41"/classes/external/*.php "$P41"/tests/external/*.php "$P41/db/services.php"; do
    php -l "$f" >/dev/null 2>&1 || { lintfail=1; bad "php -l $f: $(php -l "$f" 2>&1)"; }
done
[ "$lintfail" = 0 ] && ok "php -l clean (10 files)"
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

before="$(md5sum "$P45/db/services.php" "$P45/version.php" "$c45")"
python3 "$E" "$P45" get_items >"$T/out" 2>&1 && bad "existing function accepted" \
    || { grep -q 'mod_demo_get_items already exists' "$T/out" && [ "$before" = "$(md5sum "$P45/db/services.php" "$P45/version.php" "$c45")" ] \
        && ok "existing function refused, nothing written" || bad "refusal: $(cat "$T/out")"; }
rm "$P45/tests/external/get_items_test.php"
sed -i "/'mod_demo_get_items' => \[/,/^    \],/d" "$P45/db/services.php"
python3 "$E" "$P45" get_items >"$T/out" 2>&1 && bad "existing class file accepted" \
    || { grep -q 'already exists' "$T/out" && ok "existing class file refused" || bad "class refusal: $(cat "$T/out")"; }
python3 "$E" "$P45" get_x --params 'a:nope' >"$T/out" 2>&1 && bad "bad param type accepted" \
    || { grep -q "bad param 'a:nope'" "$T/out" && ok "bad param type refused" || bad "param refusal: $(cat "$T/out")"; }
for p in context params; do
    python3 "$E" "$P45" get_x --params "$p:int" >"$T/out" 2>&1 && bad "param '$p' accepted" \
        || { grep -q "param '$p' is reserved" "$T/out" && ok "param '$p' refused" || bad "$p refusal: $(cat "$T/out")"; }
done

i=0
for start in '$functions = array (' '    $functions = [' '$functions=['; do
    i=$((i + 1)); M="$T/merge$i"; mkdir -p "$M/db"; cp "$P41/version.php" "$M/"
    close="]"; [ "${start%(}" != "$start" ] && close=")"
    printf "<?php\n%s\n    'local_demo_old' => ['classname' => 'local_demo\\\\external\\\\old', 'type' => 'read'],\n%s;\n" \
        "$start" "$close" > "$M/db/services.php"
    python3 "$E" "$M" get_new >"$T/out" 2>&1 || bad "'$start' rc: $(cat "$T/out")"
    grep -q "'local_demo_old' =>" "$M/db/services.php" && grep -q "'local_demo_get_new' =>" "$M/db/services.php" \
        && [ "$(grep -c 'functions *=' "$M/db/services.php")" = 1 ] && php -l "$M/db/services.php" >/dev/null 2>&1 \
        && ok "'$start' merge keeps the old entry, one assignment, php -l" || bad "'$start' merge: $(cat "$M/db/services.php")"
done
M="$T/merge4"; mkdir -p "$M/db"; cp "$P41/version.php" "$M/"
printf "<?php\n\$functions = array_merge([], [\n    'local_demo_old' => ['classname' => 'local_demo\\\\external\\\\old'],\n]);\n" > "$M/db/services.php"
before="$(md5sum "$M/db/services.php" "$M/version.php")"
python3 "$E" "$M" get_new >"$T/out" 2>&1 && bad "unparseable \$functions accepted" \
    || { grep -q "$M/db/services.php: \$functions is set" "$T/out" && [ "$before" = "$(md5sum "$M/db/services.php" "$M/version.php")" ] \
        && [ ! -e "$M/classes" ] && php -l "$M/db/services.php" >/dev/null 2>&1 \
        && ok "unparseable \$functions refused naming the file, nothing written" || bad "unparseable refusal: $(cat "$T/out")"; }

for c in "/* last */" "// last" "# last"; do
    i=$((i + 1)); M="$T/merge$i"; mkdir -p "$M/db"; cp "$P41/version.php" "$M/"
    printf "<?php\n\$functions = [\n    'local_demo_old' => ['classname' => 'local_demo\\\\external\\\\old'], %s\n];\n" "$c" > "$M/db/services.php"
    python3 "$E" "$M" get_new >"$T/out" 2>&1 && php -l "$M/db/services.php" >/dev/null 2>&1 \
        && php -r "include '$M/db/services.php'; exit(count(\$functions) == 2 ? 0 : 1);" \
        && grep -qF "$c" "$M/db/services.php" && ok "merge after trailing '$c': entry before the bracket, php -l" \
        || bad "trailing '$c' merge: $(cat "$T/out" "$M/db/services.php")"
done
M="$T/merge$((i + 1))"; mkdir -p "$M/db"; cp "$P41/version.php" "$M/"
printf "<?php\n\$functions = [\n    'local_demo_old' => ['classname' => 'x'] /* no comma, ] here */\n];\n" > "$M/db/services.php"
python3 "$E" "$M" get_new >"$T/out" 2>&1 && php -r "include '$M/db/services.php'; exit(count(\$functions) == 2 ? 0 : 1);" \
    && grep -qF "['classname' => 'x'], /* no comma" "$M/db/services.php" \
    && ok "comma goes before a trailing /* */ holding ]" || bad "comma placement: $(cat "$T/out" "$M/db/services.php")"

N="$T/note/note"; mkdir -p "$T/note"
printf 'component: local_note\nrequires: "4.5"\ncopyright: 2026 onwards, Example Author <author@example.com>\ntables:\n  local_note_item:\n    fields: [userid, name:char:255, "score:number:10,2", body:text, timemodified]\n  local_note_tag:\n    fields: [name:char:255]\n' \
    > "$T/note/recipe.yaml"
python3 "$G" --target-dir "$T/note" "$T/note/recipe.yaml" >/dev/null 2>"$T/err" || bad "note skeleton: $(cat "$T/err")"
before="$(find "$N" -type f -exec md5sum {} + | sort)"
for bad in "--table local_note_tag --cols name|has no userid field" "--table local_note_x --cols name|not in .*install.xml" \
           "--table local_note_item --cols name,nope|has no field nope" "--table local_note_item|--table and --cols go together" \
           "--table local_note_item --cols name --returns single|use --returns multiple"; do
    python3 "$E" "$N" get_notes ${bad%%|*} >"$T/out" 2>&1 && bad "accepted: ${bad%%|*}" \
        || { grep -q -- "${bad#*|}" "$T/out" && ok "refused: ${bad%%|*}" || bad "refusal ${bad%%|*}: $(cat "$T/out")"; }
done
[ "$before" = "$(find "$N" -type f -exec md5sum {} + | sort)" ] && ok "--table refusals wrote nothing" || bad "--table refusals wrote files"
for cols in ',' ' , '; do
    python3 "$E" "$N" get_notes --table local_note_item --cols "$cols" >"$T/out" 2>&1 && bad "--cols '$cols' accepted" \
        || { grep -q -- '--cols has no column names' "$T/out" && [ "$before" = "$(find "$N" -type f -exec md5sum {} + | sort)" ] \
            && ok "--cols '$cols' refused, nothing written" || bad "--cols '$cols': $(cat "$T/out")"; }
done
python3 "$E" "$N" get_dups --table local_note_item --cols name,name,score >"$T/out" 2>&1 \
    && grep -q 'note: duplicate --cols dropped: name' "$T/out" \
    && grep -qF "'id, name, score');" "$N/classes/external/get_dups.php" \
    && [ "$(grep -c "'name' => new external_value" "$N/classes/external/get_dups.php")" = 1 ] \
    && [ "$(grep -c "\['name'\]" "$N/tests/external/get_dups_test.php")" = 1 ] \
    && ok "--cols name,name deduped with a note" || bad "--cols dedupe: $(cat "$T/out")"
python3 "$E" "$N" get_notes --table local_note_item --cols name,score,body >"$T/out" 2>&1 \
    && ok "--table renders" || bad "--table rc: $(cat "$T/out")"
cn="$N/classes/external/get_notes.php"; tn="$N/tests/external/get_notes_test.php"
grep -q 'global $DB, $USER;' "$cn" \
    && grep -qF "\$records = \$DB->get_records('local_note_item', ['userid' => \$USER->id], 'id', 'id, name, score, body');" "$cn" \
    && grep -qF 'return array_values($records);' "$cn" && grep -q 'execute_returns(): external_multiple_structure' "$cn" \
    && grep -qF "'id' => new external_value(PARAM_INT, 'Id')," "$cn" && grep -qF "'name' => new external_value(PARAM_TEXT, 'Name')," "$cn" \
    && grep -qF "'score' => new external_value(PARAM_FLOAT, 'Score')," "$cn" && grep -qF "'body' => new external_value(PARAM_RAW, 'Body')," "$cn" \
    && ! grep -q "'timemodified' =>" "$cn" && ok "--table class: get_records for \$USER->id, typed returns from install.xml" \
    || bad "--table class: $(cat "$cn")"
[ "$(grep -c "insert_record('local_note_item'" "$tn")" = 2 ] && grep -qF "'userid' => \$USER->id," "$tn" \
    && grep -qF "'userid' => \$other->id," "$tn" && grep -qF "'timemodified' => 2," "$tn" \
    && grep -qF '$this->assertCount(1, $result);' "$tn" && grep -qF "\$this->assertEquals(\$ownid, \$result[0]['id']);" "$tn" \
    && grep -qF "\$this->assertEquals('a', \$result[0]['name']);" "$tn" && grep -qF "\$this->assertEquals(1, \$result[0]['score']);" "$tn" \
    && ! grep -q 'assertIsArray' "$tn" && ok "--table test seeds own + other row, asserts count and values" || bad "--table test: $(cat "$tn")"
t41="$P41/tests/external/update_item_test.php"; grep -q 'assertIsArray' "$t41" && ! grep -q 'insert_record\|global $DB' "$t41" \
    && ok "no --table: test unchanged" || bad "no --table test changed"
for f in "$cn" "$tn" "$N/db/services.php"; do php -l "$f" >/dev/null 2>&1 || bad "php -l $f: $(php -l "$f" 2>&1)"; done
if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
    out="$(nice -n 19 "$MPC" codechecker "$N" 2>&1)"; rc=$?
    grep -q '| ERROR \|| WARNING ' <<<"$out" || [ "$rc" -ne 0 ] && bad "note codechecker rc=$rc: $out" || ok "codechecker 0/0 --table plugin"
fi

[ "$fails" -eq 0 ] && echo "PASS external.test.sh" || { echo "FAIL external.test.sh ($fails)"; exit 1; }
