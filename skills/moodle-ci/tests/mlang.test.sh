#!/usr/bin/env bash
# mlang on a throwaway mod_x fixture: missing PHP/mustache/JS/db ids red, unused warns rc 0, implicit and dynamic
# ids not unused, comments ignored, namespaced exceptions and string(s)_for_js used, lang/es parity warns,
# usage rc 2; db/mobile.php lang pairs and app plugin.<comp>.<id> keys used; --sync <xx> inserts missing ids sorted
# above the next id's comments, keeps translations and the file header (GPL // or docblock), skips commented ids,
# creates lang/<xx> for a valid code only; non-literal strings_for_js / get_strings dynamic; core 5.2 (read-only):
# blocks/html 0 FAIL, mod/assign rc 1 on its one real gap.
set -uo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)/scripts/mlang"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
P="$T/mod/x"
mkdir -p "$P/lang/en" "$P/db" "$P/templates" "$P/amd/src" "$P/classes"
echo "<?php \$plugin->component = 'mod_x';" > "$P/version.php"
cat > "$P/lang/en/x.php" <<'EOF'
<?php
$string['pluginname'] = 'X';
$string['modulename'] = 'X';
$string['modulename_help'] = 'Help';
$string['modulenameplural'] = 'Xs';
$string['pluginadministration'] = 'X admin';
$string['x:view'] = 'View';
$string['messageprovider:note'] = 'Note';
$string['cachedef_store'] = 'Store';
$string['privacy:metadata'] = 'None';
$string['phpid'] = 'A';
$string['shortid'] = 'B';
$string['field'] = 'Field';
$string['field_help'] = 'Field help';
$string['tplid'] = 'C';
$string['jsid'] = 'D';
$string['jsobj'] = 'E';
$string['status_open'] = 'Open';
$string['errid'] = 'Err';
$string['orphan'] = 'Unused';
$string['nsid'] = 'Ns';
$string['forjs'] = 'F';
$string['forjsa'] = 'Fa';
$string['forjsb'] = 'Fb';
EOF
cat > "$P/db/access.php" <<'EOF'
<?php
$capabilities = ['mod/x:view' => ['captype' => 'read']];
EOF
cat > "$P/db/messages.php" <<'EOF'
<?php
$messageproviders = ['note' => ['defaults' => ['popup' => 1]]];
EOF
cat > "$P/db/caches.php" <<'EOF'
<?php
$definitions = ['store' => ['mode' => 1]];
EOF
cat > "$P/lib.php" <<'EOF'
<?php
echo get_string('phpid', 'mod_x'), get_string('shortid', 'x'), get_string('blocksettings', 'block');
$s = new lang_string('phpid', 'x');
$mform->addHelpButton('f', 'field', 'x');
$st = get_string('status_' . $state, 'x');
throw new \moodle_exception('errid', 'x');
// get_string('incomment', 'x');
EOF
cat > "$P/classes/form.php" <<'EOF'
<?php
throw new \core\exception\moodle_exception('nsid', 'mod_x', '', ['a' => 1]);
$PAGE->requires->string_for_js('forjs', 'mod_x');
$PAGE->requires->strings_for_js([
    'forjsa', 'forjsb',
], 'x');
$PAGE->requires->strings_for_js(array('help'), 'moodle');
EOF
echo "{{#str}} tplid, mod_x {{/str}}" > "$P/templates/view.mustache"
cat > "$P/amd/src/view.js" <<'EOF'
import {getString, getStrings} from 'core/str';
getString('jsid', 'mod_x');
getStrings([{key: 'jsobj', component: 'mod_x'}]);
/* getString('jscomment', 'mod_x'); */
EOF
bad=0
check() { if eval "$1"; then echo "PASS $2"; else echo "FAIL $2"; bad=1; fi; }

out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && ! grep -q "^FAIL" <<<"$out"' "all ids defined: rc 0, no FAIL"
check 'grep -q "^WARN lang/en/x.php:20 unused orphan$" <<<"$out" && [ $(grep -c "^WARN" <<<"$out") = 1 ]' \
    "only orphan unused (implicit, help, dynamic prefix silenced)"
check 'grep -q "1 dynamic" <<<"$out"' "dynamic id counted"
check '! grep -q "incomment\|jscomment" <<<"$out"' "comments ignored"
check '! grep -q "unused \(nsid\|forjs\)" <<<"$out"' "core\\exception\\moodle_exception and string(s)_for_js ids used"

mkdir -p "$P/lang/es"
sed "/'tplid'/d" "$P/lang/en/x.php" > "$P/lang/es/x.php"
echo "\$string['esonly'] = 'Solo';" >> "$P/lang/es/x.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && grep -q "^WARN lang/en/x.php:15 missing in es tplid$" <<<"$out"' "lang/es lacks an en id: WARN, rc 0"
check 'grep -q "^WARN lang/es/x.php:24 only in es esonly$" <<<"$out" && grep -q "2 lang parity" <<<"$out"' \
    "lang/es-only id: WARN"
rm -r "$P/lang/es"

A="$T/app/x"; mkdir -p "$T/app"; cp -r "$P" "$A"
printf "\$string['apponly'] = 'App';\n\$string['appkey'] = 'Key';\n" >> "$A/lang/en/x.php"
cat > "$A/db/mobile.php" <<'EOF2'
<?php
$addons = ['mod_x' => [
    'handlers' => ['view' => ['method' => 'mobile_view']],
    'lang' => [
        ['pluginname', 'x'], ['apponly', 'mod_x'],
        ['nomob', 'mod_x'], ['nocore', 'core'],
    ],
]];
EOF2
echo "<ion-label>{{ 'plugin.mod_x.appkey' | translate }}</ion-label>" > "$A/templates/mobile_view.mustache"
out="$("$M" "$A" 2>&1)"; rc=$?
check '! grep -q "unused \(apponly\|appkey\)" <<<"$out"' "db/mobile.php lang pair and app plugin.<comp>.<id> key: used"
check '[ $rc = 1 ] && grep -q "^FAIL db/mobile.php:6 nomob$" <<<"$out" && ! grep -q nocore <<<"$out"' \
    "db/mobile.php lang pair missing from lang/en: FAIL file:line, other components ignored"

S="$T/sync/x"; mkdir -p "$T/sync"; cp -r "$P" "$S"
printf "\$string['multi'] = 'a;\nb';\n" >> "$S/lang/en/x.php"
mkdir -p "$S/lang/es"
{ echo "<?php"; grep "^\$string" "$S/lang/en/x.php" | grep -v "'tplid'\|'jsid'\|'multi'\|^b" | LC_ALL=C sort \
    | sed "s/= '/= 'ES /"; } > "$S/lang/es/x.php"
cp "$S/lang/es/x.php" "$T/es.before"
out="$("$M" --sync es "$S" 2>&1)"; rc=$?
check '[ $rc = 0 ] && [ "$out" = "synced 3 ids to lang/es" ]' "--sync es: rc 0, synced 3 ids"
check 'grep "^\\\$string" "$S/lang/es/x.php" | LC_ALL=C sort -c && grep -qx "\\\$string\[.jsid.\] = .D.;" "$S/lang/es/x.php" \
    && grep -x -A1 "\\\$string\[.multi.\] = .a;" "$S/lang/es/x.php" | tail -1 | grep -qx "b.;"' "--sync: English text at its sorted place, multi-line kept"
check 'diff <(grep -v "^\\\$string\[.\(tplid\|jsid\|multi\).\]\|^b.;$" "$S/lang/es/x.php") "$T/es.before"' \
    "--sync: existing translations untouched"
check '[ "$("$M" --sync es "$S" 2>&1)" = "synced 0 ids to lang/es" ] && ! "$M" "$S" 2>&1 | grep -q "missing in es"' \
    "--sync again: 0 ids, parity clean"
C="$T/syncc/x"; mkdir -p "$C/lang/en" "$C/lang/de"; cp "$P/version.php" "$C/"
printf "<?php\n\$string['aaa'] = 'A';\n// \$string['old'] = 'Old';\n\$string['bbb'] = 'B';\n\$string['ccc'] = 'C';\n\$string['ddd'] = 'D';\n" \
    > "$C/lang/en/x.php"
printf "<?php\n// \$string['aaa'] = 'DE A';\n// Note about ddd.\n\$string['ddd'] = 'DE D';\n" > "$C/lang/de/x.php"
out="$("$M" --sync de "$C" 2>&1)"; rc=$?
check '[ $rc = 0 ] && [ "$out" = "synced 3 ids to lang/de" ] && ! grep -q "^.string\[.old.\]" "$C/lang/de/x.php" \
    && grep -qx ".string\[.aaa.\] = .A.;" "$C/lang/de/x.php"' "--sync: commented en id not synced, commented de id missing"
check 'grep -x -B1 -A1 "// Note about ddd." "$C/lang/de/x.php" | paste -sd" " | grep -qx ".string\[.ccc.\] = .C.; // Note about ddd. .string\[.ddd.\] = .DE D.;"' \
    "--sync: comment stays above its statement"
printf "<?php\n\$string['aaa'] = 'DE A';\n/*\n * Block about ddd.\n */\n\$string['ddd'] = 'DE D';\n" > "$C/lang/de/x.php"
out="$("$M" --sync de "$C" 2>&1)"; rc=$?
check '[ $rc = 0 ] && grep -x -B1 "/\*" "$C/lang/de/x.php" | head -1 | grep -qx ".string\[.ccc.\] = .C.;" \
    && grep -x -A1 "/\*" "$C/lang/de/x.php" | tail -1 | grep -qx " \* Block about ddd."' "--sync: ids go above the next id's /* */ block"
printf "<?php\n/**\n * Strings.\n *\n * @package local_x\n */\n\$string['ccc'] = 'DE C';\n" > "$C/lang/de/x.php"
"$M" --sync de "$C" >/dev/null 2>&1
check 'sed -n "7p" "$C/lang/de/x.php" | grep -qx ".string\[.aaa.\] = .A.;" && sed -n "6p" "$C/lang/de/x.php" | grep -qx " \*/"' \
    "--sync: an id sorted first goes below the file docblock"
G="// This file is part of Moodle - https://moodle.org/\n//\n// You should have received a copy of the GNU General Public License\n// along with Moodle.  If not, see <https://www.gnu.org/licenses/>.\n"
printf "<?php\n$G// Section.\n\$string['ccc'] = 'DE C';\n" > "$C/lang/de/x.php"; head -5 "$C/lang/de/x.php" > "$T/gpl.h"
"$M" --sync de "$C" >/dev/null 2>&1
check 'head -5 "$C/lang/de/x.php" | diff -q - "$T/gpl.h" >/dev/null && sed -n "6p" "$C/lang/de/x.php" | grep -qx ".string\[.aaa.\] = .A.;" \
    && grep -x -A1 "// Section." "$C/lang/de/x.php" | tail -1 | grep -qx ".string\[.ccc.\] = .DE C.;"' \
    "--sync: a GPL // header with no blank line stays at lines 2-5, section comment with its id"
printf "<?php\n/**\n * Strings.\n *\n * @package local_x\n */\n// Section.\n\$string['ccc'] = 'DE C';\n" > "$C/lang/de/x.php"
"$M" --sync de "$C" >/dev/null 2>&1
check 'sed -n "6p" "$C/lang/de/x.php" | grep -qx " \*/" && sed -n "7,10p" "$C/lang/de/x.php" | paste -sd" " \
    | grep -qx ".string\[.aaa.\] = .A.; .string\[.bbb.\] = .B.; // Section. .string\[.ccc.\] = .DE C.;"' \
    "--sync: docblock + section comment: the section comment stays with its id"
printf "<?php\n// GPL header.\n\ndefined('MOODLE_INTERNAL') || die();\n\n" | cat - <(tail -n +2 "$C/lang/en/x.php") > "$T/en.x"
cp "$T/en.x" "$C/lang/en/x.php"
out="$("$M" --sync pt_br "$C" 2>&1)"; rc=$?
check '[ $rc = 0 ] && [ "$out" = "synced 4 ids to lang/pt_br" ] && head -5 "$C/lang/pt_br/x.php" | diff - <(head -5 "$T/en.x") \
    && [ $(grep -c "^.string" "$C/lang/pt_br/x.php") = 4 ]' "--sync pt_br without lang/pt_br: creates it with the en header, rc 0"
for xx in Fr fra_ es_ abcd e1 en; do
    "$M" --sync "$xx" "$S" >/dev/null 2>&1; rc=$?
    check '[ $rc = 2 ] && [ ! -e "$S/lang/$xx" -o "$xx" = en ]' "--sync $xx: invalid code or en, rc 2, no dir"
done
out="$("$M" --sync 2>&1)"; rc=$?
check '[ $rc = 2 ]' "--sync with no lang code: rc 2"
printf "\$PAGE->requires->strings_for_js(\$ids, 'mod_x');\n\$x = get_strings(\$keys, 'x');\n\$PAGE->requires->strings_for_js(\$ids, 'moodle');\n" \
    >> "$S/lib.php"
out="$("$M" "$S" 2>&1)"; rc=$?
check '[ $rc = 0 ] && grep -q "3 dynamic" <<<"$out"' "non-literal strings_for_js / get_strings: dynamic, other components not"

cat >> "$P/lib.php" <<'EOF'
echo get_string('nophp', 'mod_x');
EOF
echo "{{#str}}notpl, x{{/str}}" >> "$P/templates/view.mustache"
echo "getString('nojs', 'mod_x');" >> "$P/amd/src/view.js"
printf "\$PAGE->requires->string_for_js('nojsone', 'x');\n\$PAGE->requires->strings_for_js(['nojsa'], 'mod_x');\n" >> "$P/classes/form.php"
echo "throw new \\core\\exception\\coding_exception('nonsid', 'x');" >> "$P/classes/form.php"
printf "<?php\n\$capabilities = [\n    'mod/x:view' => [],\n    'mod/x:edit' => [],\n];\n" > "$P/db/access.php"
printf "<?php\n\$definitions = [\n    'store' => [],\n    'other' => ['mode' => 1],\n];\n" > "$P/db/caches.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 1 ]' "missing ids: rc 1"
check 'grep -q "^FAIL lib.php:8 nophp$" <<<"$out"' "missing PHP id file:line"
check 'grep -q "^FAIL templates/view.mustache:2 notpl$" <<<"$out"' "missing mustache id file:line"
check 'grep -q "^FAIL amd/src/view.js:5 nojs$" <<<"$out"' "missing JS id file:line"
check 'grep -q "^FAIL db/access.php:4 x:edit$" <<<"$out" && grep -q "^FAIL db/caches.php:4 cachedef_other$" <<<"$out"' \
    "missing capability and cache definition strings"
check 'grep -q "^FAIL classes/form.php:8 nojsone$" <<<"$out" && grep -q "^FAIL classes/form.php:9 nojsa$" <<<"$out"' \
    "missing string_for_js / strings_for_js ids FAIL"
check 'grep -q "^FAIL classes/form.php:10 nonsid$" <<<"$out"' "missing core\\exception id FAIL"
check '! grep -q "cachedef_mode\|blocksettings" <<<"$out"' "nested keys and other components ignored"

out="$("$M" "$T" 2>&1)"; rc=$?
check '[ $rc = 2 ] && grep -q "no plugin version.php" <<<"$out"' "no plugin: rc 2"

core="$HOME/moodle-envs/5.2/www/public"
if [ -d "$core/blocks/html" ] && [ -d "$core/mod/assign" ]; then
    out="$("$M" "$core/blocks/html" 2>&1)"; rc=$?
    check '[ $rc = 0 ] && ! grep -q "^FAIL" <<<"$out"' "core 5.2 blocks/html: 0 FAIL"
    out="$("$M" "$core/mod/assign" 2>&1)"; rc=$?
    check '[ $rc = 1 ] && [ $(grep -c "^FAIL" <<<"$out") = 1 ] && grep -q "^FAIL locallib.php:[0-9]* invalidfileandsubmissionid$" <<<"$out" \
        && grep -q "^mlang: mod_assign [0-9]* defined, .* 1 missing," <<<"$out"' \
        "core 5.2 mod/assign: rc 1, summary, its one real missing id"
    check '! grep -q "unused invalidmarkerallocation:notenoughmarkers$" <<<"$out"' \
        "core 5.2 mod/assign: core\\exception\\moodle_exception id used"
else
    echo "SKIP core 5.2 blocks/html or mod/assign not on disk"
fi
exit $bad
