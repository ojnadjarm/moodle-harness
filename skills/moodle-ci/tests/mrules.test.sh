#!/usr/bin/env bash
# mrules on throwaway local_hello fixtures: one bad and one good case per rule, comment handling,
# requires gate, WARN-only rc 0, usage rc 2, --help, and a clean generate.py plugin rc 0.
set -uo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)"; M="$D/scripts/mrules"; G="$D/../moodle-pluginskel/generate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
P="$T/local/hello"
bad=0
fresh() { rm -rf "$P"; mkdir -p "$P/classes" "$P/tests" "$P/templates" "$P/lang/en"
    echo "<?php \$plugin->component = 'local_hello'; \$plugin->requires = ${1:-2024100700};" > "$P/version.php"; }
put() { mkdir -p "$(dirname "$P/$1")"; printf '%s\n' "$2" > "$P/$1"; }
expect() {  # name rc [grep]
    local out rc; out="$("$M" "$P" 2>&1)"; rc=$?
    if [ "$rc" = "$2" ] && { [ -z "${3:-}" ] || grep -q -- "$3" <<<"$out"; }; then echo "PASS $1"
    else echo "FAIL $1 (rc $rc, want $2): $out"; bad=1; fi
}

fresh; put classes/a.php '<?php
// Fixes DEF-1234 for the client.
$a = 1;'
expect "ticket id in a comment red" 1 'classes/a.php:2 ticket-id FAIL DEF-1234'
fresh; put UPGRADING.md '# local_hello
- Fixed MDL-84632.'
put upgrade.txt 'MDL-81125'; put db/upgrade.txt 'MDL-2'
expect "ticket id in UPGRADING.md and upgrade.txt green" 0
fresh; put readme.txt 'See MDL-20076'; put README.md 'MDL-1'
put CHANGES.md 'MDL-3'; put thirdpartylibs.xml '<libraries><!-- MDL-4 --></libraries>'
expect "ticket id in readme*, CHANGES* and thirdpartylibs.xml green" 0
fresh; put UPGRADING.md 'MDL-5'; put templates/a.mustache '{{! MDL-6 }}'; put amd/src/a.js '// MDL-7'
expect "ticket id in mustache red next to a skipped UPGRADING.md" 1 'templates/a.mustache:1 ticket-id FAIL MDL-6'
expect "ticket id in amd/src js red next to a skipped UPGRADING.md" 1 'amd/src/a.js:1 ticket-id FAIL MDL-7'
fresh; put classes/changes.php '<?php // Fixes MDL-8.'; put classes/readme_parser.php '<?php // Fixes MDL-9.'
put CHANGES '<!-- MDL-10 -->'; put readme_moodle.rst 'MDL-11'
expect "ticket id in classes/changes.php red" 1 'classes/changes.php:1 ticket-id FAIL MDL-8'
expect "ticket id in classes/readme_parser.php red" 1 'classes/readme_parser.php:1 ticket-id FAIL MDL-9'
expect "CHANGES and readme_moodle.rst still skipped next to them" 1 'mrules: 2 FAIL'
fresh; put classes/a.php '<?php
$enc = "UTF-8"; $iso = "ISO-8859-1";'
put lang/en/local_hello.php '<?php $string["x"] = "See ABC-12";'
put vendor/x/a.php '<?php // MDL-1'
expect "UTF-8/ISO-8859, lang/ and vendor/ green" 0
fresh; put classes/a.php '<?php
$a = 1; // phpcs:ignore moodle.Files.LineLength'
expect "phpcs:ignore red" 1 'classes/a.php:2 suppression FAIL phpcs:ignore'
fresh; put amd/src/a.js '/* eslint-disable no-console */'
put classes/a.php '<?php $a = "phpcs"; $b = "disable";'
expect "eslint-disable red" 1 'amd/src/a.js:1 suppression FAIL'
fresh; put classes/a.php '<?php
$ignore = true;'
expect "no suppression green" 0
fresh; put tests/a_test.php '<?php
final class a_test extends \advanced_testcase {
    public function test_x(): void { $m = new \ReflectionMethod($this, "x"); }
}'
expect "Reflection in tests red" 1 'tests/a_test.php:3 reflection FAIL'
fresh; put tests/a_test.php '<?php
// Never use \ReflectionMethod here.
final class a_test extends \advanced_testcase {
}'
put classes/a.php '<?php $r = new \ReflectionClass("x");'
expect "Reflection in a comment and outside tests/ green" 0
fresh; put tests/a_test.php '<?php
namespace local_hello;
final class b_test extends \advanced_testcase {
}'
expect "class/file mismatch red" 1 'tests/a_test.php:3 class-name FAIL class b_test in a_test.php'
fresh; put tests/sub/a_test.php '<?php
/** class b_test is a sibling. */
final class a_test extends \advanced_testcase {
    public function test_x(): void { $o = new class { }; }
}'
expect "class matches file green" 0
fresh; put tests/a_test.php '<?php
class a_testable extends \local_hello\api {
}
final class a_test extends \advanced_testcase {
}'
expect "helper class before the test class green" 0
fresh; put tests/a_test.php '<?php
class a_testable extends \local_hello\api {
}
final class b_test extends \advanced_testcase {
}'
expect "helper class, misnamed test class red" 1 'tests/a_test.php:4 class-name FAIL class b_test in a_test.php'
fresh; put yui/build/x/x-debug.js '/* eslint-disable */'
put sub/amd/build/a.min.js '/* eslint-disable */'
put sub/thirdpartylibs.xml '<libraries><library><location>fpdi</location></library></libraries>'
put sub/fpdi/README.md 'Uses ABC-1 autoloading.'
put pix/a.svg '<path d="M513-22"/>'
put README.md 'PSR-4 autoloading.'
expect "yui/build, nested amd/build, nested thirdpartylibs, svg, PSR-4 green" 0 'mrules: 0 FAIL, 0 WARN'
fresh 2024100700; put tests/a_test.php '<?php
use PHPUnit\Framework\Attributes\CoversClass;
#[CoversClass(\local_hello\api::class)]
final class a_test extends \advanced_testcase {
}'
expect "#[CoversClass] with requires 4.5 red" 1 'tests/a_test.php:3 covers-attribute FAIL #\[CoversClass\]'
fresh 2025041400.00; put tests/a_test.php '<?php
#[\PHPUnit\Framework\Attributes\CoversNothing]
final class a_test extends \advanced_testcase {
}'
expect "#[CoversNothing] with requires 5.0 green" 0
fresh; put classes/a.php '<?php
echo $OUTPUT->confirm("Sure?", $yes, $no);'
expect "confirm page WARN rc 0" 0 'classes/a.php:2 confirm-page WARN'
fresh; put classes/a.php '<?php
// echo $OUTPUT->confirm("Sure?", $yes, $no);
$c = $form->confirm;'
expect "confirm in a comment green" 0 'mrules: 0 FAIL, 0 WARN'
fresh; put templates/a.mustache '{{!
    Example: <span class="badge-success">x</span>
}}
<span class="badge badge-danger">{{n}}</span>
<button class="btn btn-danger">x</button>'
expect "banned classes WARN rc 0" 0 'templates/a.mustache:4 banned-class WARN badge-danger'
expect "btn-danger WARN line 5" 0 'templates/a.mustache:5 banned-class WARN btn-danger'
fresh; put templates/a.mustache '<div class="badge bg-secondary" data-alert-id="1" role="alert">x</div>'
put classes/output/a.php '<?php $c = "alert-danger";'
expect "neutral template, banned class outside templates/ green" 0 'mrules: 0 FAIL, 0 WARN'

out="$("$M" --help)"; rc=$?
[ "$rc" = 0 ] && grep -qi usage <<<"$out" && echo "PASS --help" || { echo "FAIL --help rc $rc"; bad=1; }
"$M" --bogus >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && echo "PASS unknown flag rc 2" || { echo "FAIL unknown flag rc $rc"; bad=1; }
"$M" "$T/none" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && echo "PASS missing dir rc 2" || { echo "FAIL missing dir rc $rc"; bad=1; }

if python3 -c 'import yaml' 2>/dev/null; then
    g="$T/gen"; mkdir -p "$g"
    cat > "$g/recipe.yaml" <<'EOF'
component: tool_example
name: Example tool
requires: "4.5"
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
    python3 "$G" --target-dir "$g" "$g/recipe.yaml" >/dev/null 2>&1
    out="$("$M" "$g/example" 2>&1)"; rc=$?
    [ "$rc" = 0 ] && echo "PASS generated plugin rc 0" || { echo "FAIL generated plugin rc $rc: $out"; bad=1; }
else
    echo "SKIP generated plugin: no python yaml"
fi
exit $bad
