#!/usr/bin/env bash
# mmobile on a throwaway local_hello: valid, missing method/init/class, comment/string-only method, missing string, wrong addon key,
# quotes, version.php block comment, delegate typo, missing delegate, non-array handler, unknown keys, module delegate, --refresh-delegates,
# {{{ in a template, CONTENT_OTHERDATA keys vs otherdata (literal, literal + more), javascript file paths (nested, core), bad flag, no app support.
set -uo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)/scripts/mmobile"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export MOODLE_ENVS="$T/envs" XDG_CACHE_HOME="$T/cache"
P="$T/local/hello"
mkdir -p "$P/db" "$P/classes/output" "$P/lang/en" "$P/templates" "$P/mobileapp"
echo "<?php \$plugin->component = 'local_hello';" > "$P/version.php"
touch "$P/mobileapp/styles.css" "$P/templates/mobile_view.mustache"
mobile() {
    cat > "$P/db/mobile.php" <<EOF
<?php
defined('MOODLE_INTERNAL') || die();
\$addons = ['$1' => [
    'handlers' => ['hello' => [
        'delegate' => 'CoreMainMenuDelegate',
        'method' => 'view_hello',
        'init' => 'hello_init',
        'displaydata' => ['title' => 'hello', 'icon' => 'earth'],
        'styles' => ['url' => \$CFG->wwwroot . '/local/hello/mobileapp/styles.css', 'version' => 1],
    ]],
    'lang' => [['hello', 'local_hello'], ['cancel', 'moodle']],
]];
EOF
}
cat > "$P/classes/output/mobile.php" <<'EOF'
<?php
namespace local_hello\output;
class mobile {
    public static function view_hello(array $args): array {
        global $OUTPUT;
        return ['templates' => [['id' => 'main', 'html' => $OUTPUT->render_from_template('local_hello/mobile_view', [])]]];
    }
    static public function hello_init(): array {
        return [];
    }
}
EOF
lang() { echo "<?php defined('MOODLE_INTERNAL') || die(); \$string['pluginname'] = 'Hello';$1" > "$P/lang/en/local_hello.php"; }
bad=0
check() { if eval "$1"; then echo "PASS $2"; else echo "FAIL $2"; bad=1; fi; }

mobile local_hello; lang " \$string['hello'] = 'Hello';"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && grep -q "^PASS local_hello: 1 handlers, 1 templates" <<<"$out"' "valid: rc 0"

sed -i 's/view_hello(/view_other(/' "$P/classes/output/mobile.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 1 ] && [ "$(grep -c ^FAIL <<<"$out")" = 1 ] && grep -q "^FAIL method .*view_hello()" <<<"$out"' "missing method: rc 1, one finding"
sed -i 's/view_other(/view_hello(/' "$P/classes/output/mobile.php"

lang ""
out="$("$M" "$P" 2>&1)"; rc=$?
check "[ \$rc = 1 ] && grep -q \"^FAIL lang .*'hello'\" <<<\"\$out\" && ! grep -q cancel <<<\"\$out\"" "missing string: rc 1, core string skipped"
lang " \$string['hello'] = 'Hello';"

mobile local_hullo
out="$("$M" "$P" 2>&1)"; rc=$?
check "[ \$rc = 1 ] && grep -q \"^FAIL addon .*'local_hullo'\" <<<\"\$out\"" "wrong addon key: rc 1"
mobile local_hello

echo '<?php $plugin->component = "local_hello";' > "$P/version.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && grep -q "^PASS local_hello:" <<<"$out"' "double-quoted component: rc 0"
echo '<?php $plugin->version = 1; // $plugin->component = local_hello;' > "$P/version.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 2 ] && grep -q "no component" <<<"$out"' "unreadable component: rc 2"
echo "<?php \$plugin->component = 'local_hello';" > "$P/version.php"

cp "$P/classes/output/mobile.php" "$T/mobile.php.bak"
sed -i 's/public static function view_hello(/\/\/ public static function view_hello(\n    public static function view_other(/' "$P/classes/output/mobile.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 1 ] && grep -q "^FAIL method .*view_hello()" <<<"$out"' "method only in a comment: rc 1"
cp "$T/mobile.php.bak" "$P/classes/output/mobile.php"

sed -i "s/'title' => 'hello'/'title' => get_string('hello', 'local_hello'), 'x' => (string) new lang_string('hello', 'local_hello')/" "$P/db/mobile.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && grep -q "^PASS local_hello:" <<<"$out"' "get_string/lang_string in displaydata: rc 0"
mobile local_hello

sed -i 's/hello_init(/other_init(/' "$P/classes/output/mobile.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 1 ] && [ "$(grep -c ^FAIL <<<"$out")" = 1 ] && grep -q "^FAIL init .*hello_init()" <<<"$out"' "missing init: rc 1, one finding"
cp "$T/mobile.php.bak" "$P/classes/output/mobile.php"

rm "$P/classes/output/mobile.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 1 ] && grep -q "^FAIL method .*view_hello()" <<<"$out"' "missing classes/output/mobile.php: rc 1"
cp "$T/mobile.php.bak" "$P/classes/output/mobile.php"

sed -i "s/'CoreMainMenuDelegate'/'CoreMainMenuDelegat'/" "$P/db/mobile.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 1 ] && grep -q "^FAIL delegate .*CoreMainMenuDelegat.*nearest: CoreMainMenuDelegate)" <<<"$out"' "delegate typo: rc 1, nearest name"
sed -i "s/'CoreMainMenuDelegat'/''/" "$P/db/mobile.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && ! grep -q WARN <<<"$out"' "empty delegate (JS-registered): rc 0"
mobile local_hello

sed -i "/'delegate' => /d" "$P/db/mobile.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check "[ \$rc = 0 ] && grep -q \"^WARN delegate .*handler 'hello': no delegate key\" <<<\"\$out\"" "missing delegate key: WARN naming the handler, rc 0"
mobile local_hello

sed -i "s/'handlers' => \['hello' => \[/'handlers' => ['h' => 'oops', 'hello' => [/" "$P/db/mobile.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check "[ \$rc = 1 ] && grep -q \"^FAIL handler .*handler 'h': not an array\" <<<\"\$out\" && ! grep -q '^PASS' <<<\"\$out\"" "non-array handler 'oops': FAIL naming the handler, rc 1"
mobile local_hello

sed -i "s/'init' => 'hello_init',/&\n        'restrict' => [], 'colour' => 'red',/" "$P/db/mobile.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && [ "$(grep -c "^WARN key" <<<"$out")" = 2 ] && grep -q "WARN .*'"'restrict'"'.*init response" <<<"$out" && grep -q "WARN .*'"'colour'"'" <<<"$out"' "unknown handler keys: WARN, rc 0"
mobile local_hello

sed -i "s/'CoreMainMenuDelegate'/'CoreCourseModuleDelegate'/; s/'displaydata' => \['title' => 'hello', /'displaydata' => [/" "$P/db/mobile.php"
out="$("$M" "$P" 2>&1)"; rc=$?
out2="$(sed -i "s/'init' => 'hello_init',/&\n        'moodlecomponent' => 'mod_hello',/" "$P/db/mobile.php"; "$M" "$P" 2>&1)"; rc2=$?
check '[ $rc = 1 ] && grep -q "^FAIL delegate .*needs a mod_ component, got .local_hello." <<<"$out" && [ $rc2 = 0 ] && ! grep -q WARN <<<"$out2"' "CoreCourseModuleDelegate: mod_ component required"
mobile local_hello

sed -i 's/public static function view_hello(/public static function view_other(/; s/static public function hello_init(/static public function other_init(/' "$P/classes/output/mobile.php"
sed -i 's/^}$/    const X = "public static function view_hello(";\n    const Y = <<<EOT\n    static public function hello_init() {\n    EOT;\n}/' "$P/classes/output/mobile.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 1 ] && grep -q "^FAIL method .*view_hello()" <<<"$out" && grep -q "^FAIL init .*hello_init()" <<<"$out"' "method only in a string/heredoc: rc 1"
cp "$T/mobile.php.bak" "$P/classes/output/mobile.php"

printf "<?php\n/*\n\$plugin->component = 'local_wrong';\n*/\n\$plugin->component = 'local_hello';\n" > "$P/version.php"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && grep -q "^PASS local_hello:" <<<"$out"' "version.php block comment skipped: rc 0"
echo "<?php \$plugin->component = 'local_hello';" > "$P/version.php"

if [ -f "$HOME/.moodle-devdocs/general/app/development/plugins-development-guide/api-reference.md" ]; then
    mkdir -p "$T/s/scripts" "$T/s/reference"; cp "$M" "$T/s/scripts/"
    out="$("$T/s/scripts/mmobile" --refresh-delegates 2>&1)"; rc=$?
    check '[ $rc = 0 ] && cmp -s "$T/s/reference/mobile-delegates.json" "$(dirname "$M")/../reference/mobile-delegates.json"' "--refresh-delegates rebuilds the shipped JSON"
fi

ret() { cp "$T/mobile.php.bak" "$P/classes/output/mobile.php"; sed -i "s|)\]\]\];$|)]], $1];|" "$P/classes/output/mobile.php"; }
tpl() { printf '%s\n' "$1" > "$P/templates/mobile_view.mustache"; }
tpl '<p>{{{html}}}</p>'
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && grep -q "^WARN template .*local_hello/mobile_view: {{{" <<<"$out"' "{{{ in a rendered template: WARN, rc 0"
tpl $'{{!\n    {{{html}}} is not used here.\n}}\n<p>{{html}}</p>'
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && ! grep -q WARN <<<"$out"' "{{{ only in a {{! }} comment: no WARN"

tpl $'{{=<% %>=}}\n<ion-item *ngFor="let row of CONTENT_OTHERDATA.rows">{{ CONTENT_OTHERDATA.title }}</ion-item>'
out="$("$M" "$P" 2>&1)"; rc=$?
check "[ \$rc = 1 ] && [ \"\$(grep -c '^FAIL otherdata' <<<\"\$out\")\" = 2 ] && grep -q \"^FAIL otherdata .*handler 'hello': local_hello/mobile_view reads CONTENT_OTHERDATA.rows, not in view_hello()\" <<<\"\$out\"" "CONTENT_OTHERDATA.k with no otherdata: FAIL per key, rc 1"
ret "'otherdata' => ['rows' => json_encode([])]"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 1 ] && grep -q "^FAIL otherdata .*CONTENT_OTHERDATA.title" <<<"$out" && ! grep -q "CONTENT_OTHERDATA.rows" <<<"$out"' "otherdata missing one key: FAIL names only it"
ret "'otherdata' => array('rows' => '[]', \"title\" => 'x')"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && grep -q "^PASS local_hello:" <<<"$out"' "otherdata array() has every key: rc 0"
ret "'otherdata' => \$args"
out="$("$M" "$P" 2>&1)"; rc=$?
check "[ \$rc = 0 ] && grep -q \"^NOTE otherdata .*handler 'hello': view_hello() 'otherdata' is not a lone literal\" <<<\"\$out\" && ! grep -q '^FAIL' <<<\"\$out\"" "non-literal otherdata: NOTE, not checked, rc 0"
ret "'otherdata' => ['rows' => '[]'] + \$extra"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && grep -q "^NOTE otherdata .*not a lone literal" <<<"$out" && ! grep -q "^FAIL" <<<"$out"' '[...] + $extra otherdata: NOTE, not checked, rc 0'
cp "$T/mobile.php.bak" "$P/classes/output/mobile.php"; : > "$P/templates/mobile_view.mustache"

ret "'javascript' => file_get_contents(\$CFG->dirroot . '/local/hello/mobileapp/init.js')"
out="$("$M" "$P" 2>&1)"; rc=$?
touch "$P/mobileapp/init.js"; out2="$("$M" "$P" 2>&1)"; rc2=$?
check '[ $rc = 1 ] && grep -q "^FAIL javascript .*/local/hello/mobileapp/init.js. not found" <<<"$out" && [ $rc2 = 0 ]' "javascript dirroot path: FAIL when missing, rc 0 when present"
ret "'javascript' => file_get_contents(__DIR__ . '/../../mobileapp/nope.js')"
out="$("$M" "$P" 2>&1)"; rc=$?
ret "'javascript' => file_get_contents(__DIR__ . '/../../mobileapp/init.js')"
out2="$("$M" "$P" 2>&1)"; rc2=$?
check '[ $rc = 1 ] && grep -q "^FAIL javascript .*nope.js. not found" <<<"$out" && [ $rc2 = 0 ]' "javascript __DIR__ path: FAIL when missing, rc 0 when present"
ret "'javascript' => file_get_contents(\$CFG->dirroot . '/local/hello/js/hello/init.js')"
out="$("$M" "$P" 2>&1)"; rc=$?
mkdir -p "$P/js/hello"; touch "$P/js/hello/init.js"; out2="$("$M" "$P" 2>&1)"; rc2=$?
check '[ $rc = 1 ] && grep -q "^FAIL javascript .*js/hello/init.js. not found" <<<"$out" && [ $rc2 = 0 ]' "javascript dirroot path with /<name>/ twice: resolves from the first"
ret "'javascript' => file_get_contents(\$CFG->dirroot . '/lib/core.js')"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && grep -q "^NOTE javascript .*/lib/core.js. is outside the plugin and no core tree" <<<"$out"' "javascript core path, no requires: NOTE, rc 0"
ret "'javascript' => file_get_contents(\$CFG->dirroot . '/lib/hello/core.js')"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 0 ] && grep -q "^NOTE javascript .*/lib/hello/core.js. is outside the plugin" <<<"$out" && ! grep -q "^FAIL" <<<"$out"' "javascript core path with /<name>/ under another dir: outside the plugin"
mkdir -p "$MOODLE_ENVS/x/www/lib/classes"; printf '<?php\n$branch = %s;\n' "'502'" > "$MOODLE_ENVS/x/www/version.php"
echo "<?php \$plugin->component = 'local_hello'; \$plugin->requires = 2026042000;" > "$P/version.php"
ret "'javascript' => file_get_contents(\$CFG->dirroot . '/lib/core.js')"
out="$("$M" "$P" 2>&1)"; rc=$?
touch "$MOODLE_ENVS/x/www/lib/core.js"; out2="$("$M" "$P" 2>&1)"; rc2=$?
check '[ $rc = 1 ] && grep -q "^FAIL javascript .*/lib/core.js. not found in core $MOODLE_ENVS/x/www" <<<"$out" && [ $rc2 = 0 ] && ! grep -q javascript <<<"$out2"' "javascript core path with an msrc core tree: FAIL when missing, rc 0 when present"
echo "<?php \$plugin->component = 'local_hello';" > "$P/version.php"
cp "$T/mobile.php.bak" "$P/classes/output/mobile.php"

out="$(cd "$T"; timeout 5 "$M" --bogus 2>&1)"; rc=$?
check '[ $rc = 2 ] && grep -q "unknown option --bogus" <<<"$out"' "bad flag: rc 2, no hang"

rm "$P/mobileapp/styles.css" "$P/templates/mobile_view.mustache"
out="$("$M" "$P" 2>&1)"; rc=$?
check '[ $rc = 1 ] && grep -q "^FAIL styles" <<<"$out" && grep -q "^FAIL template .*mobile_view" <<<"$out"' "missing styles file and template: rc 1"

rm "$P/db/mobile.php"
out="$("$M" "$P/classes" 2>&1)"; rc=$?
check '[ $rc = 0 ] && grep -q "no app support" <<<"$out"' "no db/mobile.php: no app support, rc 0"

exit $bad
