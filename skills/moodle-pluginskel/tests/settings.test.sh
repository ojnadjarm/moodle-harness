#!/usr/bin/env bash
# Drive settings.py on mktemp plugins: 5 setting types, block_ has_config, externalpage, merge, idempotence, final class and abstract class blocks, configint :010 decimal, brace error file, refusals, php -l, codechecker.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
S="$(cd "$(dirname "$0")/.." && pwd)"
X="$S/settings.py"; G="$S/generate.py"; A="$S/access.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

render() {
    mkdir -p "$T/$1"
    printf 'component: %s\nrequires: "4.5"\ncopyright: 2026 onwards, Example Author <author@example.com>\n%s' "$2" "${3:-}" \
        > "$T/$1/recipe.yaml"
    python3 "$G" --target-dir "$T/$1" "$T/$1/recipe.yaml" >/dev/null 2>"$T/err" || bad "$1 skeleton: $(cat "$T/err")"
}

# Stub admin tree: includes settings.php, every get_string must exist in the lang file; prints the tree as JSON.
cat > "$T/stub.php" <<'PHP'
<?php
define('MOODLE_INTERNAL', 1);
define('PARAM_TEXT', 'text');
define('PARAM_INT', 'int');
$string = [];
include $argv[2];
function get_string($id, $component) {
    global $string;
    if (!isset($string[$id])) {
        fwrite(STDERR, "missing string $id\n");
        exit(3);
    }
    return $string[$id];
}
class admin_setting {
    public $args;
    public function __construct(...$args) {
        $this->args = $args;
    }
}
class admin_setting_heading extends admin_setting {
}
class admin_setting_configtext extends admin_setting {
}
class admin_setting_configcheckbox extends admin_setting {
}
class admin_setting_configselect extends admin_setting {
}
class admin_setting_configduration extends admin_setting {
}
class admin_settingpage {
    public $name;
    public $items = [];
    public function __construct($name, $title) {
        $this->name = $name;
    }
    public function add($s) {
        $this->items[] = array_merge([substr(get_class($s), 14)], array_slice($s->args, 0, 1), array_slice($s->args, 3));
    }
}
class admin_externalpage {
    public $args;
    public function __construct(...$args) {
        $this->args = $args;
    }
}
class moodle_url {
    public $url;
    public function __construct($url) {
        $this->url = $url;
    }
}
class admin_root {
    public $fulltree = true;
    public $tree = [];
    public function add($parent, $node) {
        $this->tree[] = $node instanceof admin_externalpage
            ? [$parent, 'page', $node->args[0], $node->args[2]->url, $node->args[3]] : [$parent, 'settingpage', $node->name];
    }
}
$ADMIN = new admin_root();
$hassiteconfig = ($argv[3] ?? '1') === '1';
$settings = new admin_settingpage('preset', 'Preset');
include $argv[1];
echo json_encode(['tree' => $ADMIN->tree, 'settings' => $settings ? $settings->items : null]);
PHP
tree() { php "$T/stub.php" "$1/settings.php" "$2" "${3:-1}" 2>&1; }
# check <label> <plugin> <lang> <python expression over j> [hassiteconfig 1|0]
check() {
    local out; out="$(tree "$2" "$3" "${5:-1}")"
    python3 -c "import json, sys; j = json.loads(sys.argv[1]); sys.exit(0 if ($4) else 1)" "$out" 2>/dev/null \
        && ok "$1" || bad "$1: $out"
}

python3 "$X" --help | grep -q configselect && python3 "$X" --help | grep -q configint && ok "--help names configselect, configint" \
    || bad "--help"

render loc local_demo; P="$T/loc/demo"; lang="$P/lang/en/local_demo.php"
python3 "$A" "$P" view --type read --context system >/dev/null 2>&1 || bad "access.py view"
[ ! -e "$P/settings.php" ] && python3 "$X" "$P" --setting apikey:configtext:abc --setting mode:configselect:b --choices a,b \
    --setting enabled:configcheckbox:1 --setting ttl:configduration --page tickets.php --cap local/demo:view >"$T/out" 2>&1 \
    && [ -f "$P/settings.php" ] && ok "local_: creates settings.php" || bad "create: $(cat "$T/out")"
check "local_: 4 types inside hassiteconfig + fulltree, values and choices" "$P" "$lang" \
    "j['settings'] == [['configtext', 'local_demo/apikey', 'abc', 'text'], \
     ['configselect', 'local_demo/mode', 'b', {'a': 'A', 'b': 'B'}], ['configcheckbox', 'local_demo/enabled', 1], \
     ['configduration', 'local_demo/ttl', 3600]]"
check "local_: settingpage + externalpage under localplugins with cap" "$P" "$lang" \
    "j['tree'] == [['localplugins', 'settingpage', 'local_demo'], \
     ['localplugins', 'page', 'local_demo_tickets', '/local/demo/tickets.php', 'local/demo:view']]"
grep -q "^\$string\['ttl_desc'\] = 'Ttl description.';" "$lang" && grep -q "^\$string\['tickets'\] = 'Tickets';" "$lang" \
    && ok "name, desc and page lang strings" || bad "lang: $(cat "$lang")"
check "externalpage outside if (\$hassiteconfig): cap holders get the link" "$P" "$lang" \
    "j['tree'] == [['localplugins', 'page', 'local_demo_tickets', '/local/demo/tickets.php', 'local/demo:view']]" 0

before="$(md5sum "$P/settings.php" "$lang")"
python3 "$X" "$P" --setting apikey:configtext >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'exists' "$T/out" && [ "$before" = "$(md5sum "$P/settings.php" "$lang")" ] \
    && ok "second setting run: rc 1 exists, nothing written" || bad "setting rerun rc=$rc: $(cat "$T/out")"
python3 "$X" "$P" --page tickets.php --cap local/demo:view >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'admin_externalpage local_demo_tickets exists' "$T/out" \
    && [ "$before" = "$(md5sum "$P/settings.php" "$lang")" ] && ok "second page run: rc 1 exists" || bad "page rerun rc=$rc: $(cat "$T/out")"
python3 "$X" "$P" --setting fresh:configtext --page tickets.php --cap local/demo:view >/dev/null 2>&1
[ "$before" = "$(md5sum "$P/settings.php" "$lang")" ] && ok "mixed run with one existing item writes nothing" || bad "partial write"

python3 "$X" "$P" --setting later:configcheckbox >"$T/out" 2>&1 && \
    check "merge into the existing fulltree block" "$P" "$lang" \
        "len(j['settings']) == 5 and j['settings'][-1] == ['configcheckbox', 'local_demo/later', 0] and len(j['tree']) == 2" \
    || bad "merge: $(cat "$T/out")"
ids="$(sed -n "s/^\$string\['\([^']*\)'\].*/\1/p" "$lang")"
[ "$ids" = "$(LC_ALL=C sort <<<"$ids")" ] && ok "lang ids sorted" || bad "lang order: $ids"

render gen local_gen 'features:
  settings: true
'
Q="$T/gen/gen"; ql="$Q/lang/en/local_gen.php"; printf "\$string['report'] = 'Report';\n" >> "$ql"
python3 "$X" "$Q" --setting limit:configduration:60 --page admin/report.php >"$T/out" 2>&1 \
    && check "generated local settings.php: fulltree added in hassiteconfig, one settingpage" "$Q" "$ql" \
        "j['settings'] == [['configduration', 'local_gen/limit', 60]] and j['tree'] == [['localplugins', 'settingpage', \
        'local_gen'], ['localplugins', 'page', 'local_gen_report', '/local/gen/admin/report.php', 'moodle/site:config']]" \
    || bad "generated local: $(cat "$T/out")"
[ "$(grep -c "^\$string\['report'\]" "$ql")" = 1 ] && [ "$(grep -c 'new admin_settingpage' "$Q/settings.php")" = 1 ] \
    && ok "existing page string reused, no second settingpage" || bad "dup: $(cat "$Q/settings.php")"

render mod mod_demo 'features:
  settings: true
'
M="$T/mod/demo"; ml="$M/lang/en/demo.php"
python3 "$X" "$M" --setting style:configselect --choices plain,fancy --page report.php --cap mod/demo:view >"$T/out" 2>&1 \
    && check "mod_: merge into fulltree after heading, page under modsettings" "$M" "$ml" \
        "j['settings'][0][0] == 'heading' and j['settings'][1] == ['configselect', 'mod_demo/style', 'plain', \
        {'plain': 'Plain', 'fancy': 'Fancy'}] and j['tree'] == [['modsettings', 'page', 'mod_demo_report', \
        '/mod/demo/report.php', 'mod/demo:view']]" \
    || bad "mod: $(cat "$T/out")"

render tool tool_demo; W="$T/tool/demo"
python3 "$X" "$W" --page index.php >"$T/out" 2>&1 \
    && check "tool_: page only, no settingpage, /admin/tool url under tools" "$W" "$W/lang/en/tool_demo.php" \
        "j['tree'] == [['tools', 'page', 'tool_demo_index', '/admin/tool/demo/index.php', 'moodle/site:config']]" \
    || bad "tool: $(cat "$T/out")"

render mod2 mod_two; N="$T/mod2/two"; nl="$N/lang/en/two.php"
[ ! -e "$N/settings.php" ] && python3 "$X" "$N" --page report.php --cap moodle/course:view >"$T/out" 2>&1 \
    && grep -q '^warning: core includes mod_ settings.php only for site admins' "$T/out" \
    && check "mod_ page only: \$settings = null, no empty settingpage, cap warning" "$N" "$nl" \
        "j['settings'] is None and j['tree'] == [['modsettings', 'page', 'mod_two_report', '/mod/two/report.php', \
        'moodle/course:view']]" \
    || bad "mod page only: $(cat "$T/out")"
python3 "$X" "$N" --setting colour:configtext >"$T/out" 2>&1 \
    && check "mod_ setting after page only: \$settings = null removed" "$N" "$nl" \
        "j['settings'] == [['configtext', 'mod_two/colour', '', 'text']] and len(j['tree']) == 1" \
    || bad "mod null removal: $(cat "$T/out")"

render rep report_demo; R="$T/rep/demo"
python3 "$X" "$R" --page index.php >"$T/out" 2>&1 && ! grep -q warning "$T/out" \
    && check "report_ page only: \$settings = null" "$R" "$R/lang/en/report_demo.php" \
        "j['settings'] is None and j['tree'] == [['reports', 'page', 'report_demo_index', '/report/demo/index.php', \
        'moodle/site:config']]" \
    || bad "report page only: $(cat "$T/out")"

render two local_two; L="$T/two/two"
printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\n\$settings = new admin_settingpage('local_two', 'Two');\n\$ADMIN->add('localplugins', \$settings);\n" \
    > "$L/settings.php"
before="$(md5sum "$L/settings.php" "$L/lang/en/local_two.php")"
python3 "$X" "$L" --setting apikey:configtext >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'admin_settingpage outside if (\$hassiteconfig)' "$T/out" \
    && [ "$before" = "$(md5sum "$L/settings.php" "$L/lang/en/local_two.php")" ] \
    && ok "top-level settingpage without hassiteconfig refused rc 1" || bad "local_two rc=$rc: $(cat "$T/out")"

render three local_three; L3="$T/three/three"
printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\nif (\$hassiteconfig) {\n    \$ADMIN->add('localplugins', new admin_category('x', 'X'));\n}\n\$settings = new \\\\admin_settingpage('local_three', 'Three');\n" \
    > "$L3/settings.php"
before="$(md5sum "$L3/settings.php" "$L3/lang/en/local_three.php")"
python3 "$X" "$L3" --setting apikey:configtext >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'settings.php:7: admin_settingpage outside .*duplicate admin page name' "$T/out" \
    && [ "$before" = "$(md5sum "$L3/settings.php" "$L3/lang/en/local_three.php")" ] \
    && ok "Duplicate: \\\\admin_settingpage after the hassiteconfig block refused rc 1 with file:line" \
    || bad "local_three rc=$rc: $(cat "$T/out")"

render four local_four; L4="$T/four/four"
printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\n// \$settings = new admin_settingpage('local_four', 'Old');\n\$x = 'new admin_settingpage(';\n" \
    > "$L4/settings.php"
python3 "$X" "$L4" --setting apikey:configtext >"$T/out" 2>&1 \
    && check "duplicate check skips comments and strings: one settingpage" "$L4" "$L4/lang/en/local_four.php" \
        "j['tree'] == [['localplugins', 'settingpage', 'local_four']]" \
    || bad "local_four: $(cat "$T/out")"

render mod3 mod_three; M3="$T/mod3/three"
printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\n\$settings = new admin_settingpage('modsettingthree', 'Three');\n" > "$M3/settings.php"
before="$(md5sum "$M3/settings.php" "$M3/lang/en/three.php")"
python3 "$X" "$M3" --setting colour:configtext >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'settings.php:4: admin_settingpage in a mod_ settings.php.*duplicate' "$T/out" \
    && [ "$before" = "$(md5sum "$M3/settings.php" "$M3/lang/en/three.php")" ] \
    && ok "Duplicate: mod_ settingpage next to core's \$settings refused rc 1 with file:line" \
    || bad "mod_three rc=$rc: $(cat "$T/out")"

for t in block auth; do
    render "$t" "${t}_cap"; C="$T/$t/cap"
    python3 "$X" "$C" --page index.php --cap moodle/site:viewreports >"$T/out" 2>&1 \
        && grep -q "^warning: .*lib/classes/plugininfo/$t.php load_settings() returns when !\$hassiteconfig: 5.2 line [0-9]*, 5.3 line [0-9]*" "$T/out" \
        && grep -q '^note: no fulltree block' "$T/out" \
        && ok "${t}_ --cap warning names plugininfo/$t.php, page-only note" || bad "${t}_ cap: $(cat "$T/out")"
done

render blk block_demo; B="$T/blk/demo"; bc="$B/block_demo.php"; bl="$B/lang/en/block_demo.php"
! grep -q has_config "$bc" && python3 "$X" "$B" --setting maxmarks:configint:10 >"$T/out" 2>&1 \
    && check "block_ configint: configtext with PARAM_INT, int default" "$B" "$bl" \
        "j['settings'] == [['configtext', 'block_demo/maxmarks', 10, 'int']]" \
    || bad "block configint: $(cat "$T/out")"
grep -Pzq '\n    public function has_config\(\) \{\n        return true;\n    \}\n\}\n$' "$bc" && grep -q "^$bc$" "$T/out" \
    && ok "block_ without has_config: has_config() returning true added" || bad "block has_config add: $(cat "$bc")"
before="$(md5sum "$bc")"
python3 "$X" "$B" --setting limit:configint >"$T/out" 2>&1 && [ "$before" = "$(md5sum "$bc")" ] && ! grep -q "^$bc$" "$T/out" \
    && [ "$(grep -c 'function has_config' "$bc")" = 1 ] && grep -q "'block_demo/limit',$" "$B/settings.php" \
    && grep -A3 "'block_demo/limit',$" "$B/settings.php" | grep -q '^        0,$' \
    && ok "block_ second run: has_config untouched (idempotent), configint default 0" || bad "block rerun: $(cat "$T/out")"

render blf block_off; BF="$T/blf/off"; bf="$BF/block_off.php"
perl -0pi -e 's/\n\}\n\z/\n\n    \/**\n     * No settings.\n     *\n     * \@return bool\n     *\/\n    public function has_config(): bool {\n        return false;\n    }\n}\n/' "$bf"
grep -q 'return false;' "$bf" && python3 "$X" "$BF" --page index.php >"$T/out" 2>&1 \
    && grep -q 'public function has_config(): bool {' "$bf" && ! grep -q 'return false;' "$bf" \
    && [ "$(grep -c 'function has_config' "$bf")" = 1 ] && grep -A1 'function has_config' "$bf" | grep -q '^        return true;$' \
    && ok "block_ with has_config false: patched to return true (page only)" || bad "block has_config false: $(cat "$T/out") $(cat "$bf")"

render bln block_none; BN="$T/bln/none"
sed -i 's/^class block_none extends/class block_other extends/' "$BN/block_none.php"
before="$(md5sum "$BN/block_none.php" "$BN/lang/en/block_none.php")"
python3 "$X" "$BN" --setting n:configint >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'class block_none not found' "$T/out" && [ ! -e "$BN/settings.php" ] \
    && [ "$before" = "$(md5sum "$BN/block_none.php" "$BN/lang/en/block_none.php")" ] \
    && ok "block_ class not found: refused rc 1, nothing written" || bad "block no class rc=$rc: $(cat "$T/out")"

for m in final abstract; do
    render "bm$m" "block_$m"; BM="$T/bm$m/$m"
    sed -i "s/^class block_$m extends/$m class block_$m extends/" "$BM/block_$m.php"
    grep -q "^$m class block_$m extends" "$BM/block_$m.php" && python3 "$X" "$BM" --setting n:configint >"$T/out" 2>&1 \
        && grep -q 'function has_config' "$BM/block_$m.php" && php -l "$BM/block_$m.php" >/dev/null 2>&1 \
        && ok "block_ $m class: has_config() added" || bad "block $m class: $(cat "$T/out")"
done

render boct block_oct; BO="$T/boct/oct"
python3 "$X" "$BO" --setting ten:configint:010 --setting eight:configint:08 --setting neg:configint:-007 >"$T/out" 2>&1 \
    && check "configint :010 -> 10, :08 -> 8, :-007 -> -7 (decimal, no octal)" "$BO" "$BO/lang/en/block_oct.php" \
        "[s[2] for s in j['settings']] == [10, 8, -7]" \
    || bad "configint leading zeros: $(cat "$T/out")"

render bbr block_brace; BB="$T/bbr/brace"
perl -0pi -e 's/\n\}\n\z/\n/' "$BB/block_brace.php"
python3 "$X" "$BB" --setting n:configint >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'block_brace.php: unbalanced braces' "$T/out" && ! grep -q 'settings.php' "$T/out" \
    && [ ! -e "$BB/settings.php" ] && ok "unbalanced braces in block_brace.php: the error names it" \
    || bad "brace error file rc=$rc: $(cat "$T/out")"

render qt qtype_cap; QT="$T/qt/cap"
python3 "$X" "$QT" --page index.php --cap moodle/question:config >"$T/out" 2>&1 && ! grep -q '^warning: ' "$T/out" \
    && ok "qtype_ --cap: no admin-only warning (core also loads for moodle/question:config)" || bad "qtype cap: $(cat "$T/out")"

render five local_five; L5="$T/five/five"
printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\n\$settings = new Admin_SettingPage('local_five', 'Five');\n\$ADMIN->add('localplugins', \$settings);\n" \
    > "$L5/settings.php"
before="$(md5sum "$L5/settings.php" "$L5/lang/en/local_five.php")"
python3 "$X" "$L5" --setting apikey:configtext >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'settings.php:4: admin_settingpage outside .*duplicate admin page name' "$T/out" \
    && [ "$before" = "$(md5sum "$L5/settings.php" "$L5/lang/en/local_five.php")" ] \
    && ok "Duplicate: mixed-case Admin_SettingPage refused rc 1" || bad "local_five rc=$rc: $(cat "$T/out")"

for v in page settings2; do
    render "six$v" local_six; L6="$T/six$v/six"
    if [ "$v" = page ]; then body="    \$page = new admin_settingpage('local_six', 'Six');\n    \$ADMIN->add('localplugins', \$page);\n"
    else body="    \$settings = new admin_settingpage('local_six', 'Six');\n    \$ADMIN->add('localplugins', \$settings);\n    \$settings = new admin_settingpage('local_six2', 'Six 2');\n"; fi
    printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\nif (\$hassiteconfig) {\n$body}\n" > "$L6/settings.php"
    before="$(md5sum "$L6/settings.php" "$L6/lang/en/local_six.php")"
    python3 "$X" "$L6" --setting apikey:configtext >"$T/out" 2>&1; rc=$?
    [ "$rc" = 1 ] && grep -q 'settings.php:4: if (\$hassiteconfig) needs exactly one \$settings = new admin_settingpage' "$T/out" \
        && [ "$before" = "$(md5sum "$L6/settings.php" "$L6/lang/en/local_six.php")" ] \
        && ok "hassiteconfig page not one \$settings ($v) refused rc 1" || bad "local_six $v rc=$rc: $(cat "$T/out")"
done

printf "\$string['taken'] = 'Taken';\n" >> "$lang"; before="$(md5sum "$P/settings.php")"
python3 "$X" "$P" --setting taken:configtext >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "string 'taken' exists" "$T/out" && [ "$before" = "$(md5sum "$P/settings.php")" ] \
    && ok "existing lang string refused rc 1" || bad "lang refusal rc=$rc: $(cat "$T/out")"
sed -i "/'taken'/d" "$lang"
for spec in "" "--setting x:configfoo" "--setting Bad:configtext" "--setting x:configcheckbox:2" "--setting x:configduration:1h" \
        "--setting x:configselect" "--setting x:configint:1.5" "--setting x:configselect:z --choices a,b" "--setting x:configtext --choices a" \
        "--setting x:configselect --setting y:configselect --choices a" "--page ../x.php" "--page x.php --cap bad" \
        "--page x.php --cap local/demo:missing"; do
    before="$(md5sum "$P/settings.php" "$lang")"
    # shellcheck disable=SC2086
    python3 "$X" "$P" $spec >"$T/out" 2>&1; rc=$?
    [ "$rc" = 1 ] && grep -q '^error: ' "$T/out" && [ "$before" = "$(md5sum "$P/settings.php" "$lang")" ] \
        && ok "refused: ${spec:-(nothing)}" || bad "${spec:-(nothing)} rc=$rc: $(cat "$T/out")"
done

lintfail=0; n=0
for f in "$P/settings.php" "$lang" "$Q/settings.php" "$M/settings.php" "$ml" "$W/settings.php" "$N/settings.php" "$R/settings.php" \
        "$B/settings.php" "$bc" "$bl" "$bf"; do
    n=$((n + 1)); php -l "$f" >/dev/null 2>&1 || { lintfail=1; bad "php -l $f: $(php -l "$f" 2>&1)"; }
done
[ "$lintfail" = 0 ] && ok "php -l clean ($n files)"
for p in "$P" "$Q" "$M" "$W" "$B" "$BF"; do
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker --max-warnings 0 "$p" 2>&1)"; rc=$?
        if grep -q '| \(ERROR\|WARNING\) |' <<<"$out"; then bad "$p codechecker: $(grep '| \(ERROR\|WARNING\) |' <<<"$out")"
        elif [ "$rc" -ne 0 ]; then bad "$p codechecker rc=$rc"
        else ok "codechecker 0/0 ${p#"$T"/}"; fi
    else
        echo "SKIP codechecker: moodle-plugin-ci absent"
    fi
done

[ "$fails" -eq 0 ] && echo "PASS settings.test.sh" || { echo "FAIL settings.test.sh ($fails)"; exit 1; }
