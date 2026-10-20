#!/usr/bin/env bash
# Drive mobile.py on mktemp plugins: main menu, course module, block and no-displaydata delegates, --table user rows,
# decimal version, templates/mobileapp, --capability checked in the delegate's context (system, course, module + require_login,
# block), contextlevel warning, tests/output/mobile_test.php with an enrolled student; mmobile 0 FAIL/0 WARN,
# codechecker 0/0, refusals (delegate vs plugin type, table checks).
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
S="$(cd "$(dirname "$0")/.." && pwd)"
K="$S/mobile.py"; G="$S/generate.py"; MM="$S/../moodle-ci/scripts/mmobile"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
version() { sed -n 's/^\$plugin->version = \([0-9.]*\);/\1/p' "$1/version.php"; }
# notes_xml <plugin> <fields>: db/install.xml with one table local_demo_note of those fields.
notes_xml() {
    mkdir -p "$1/db"
    { printf '<?xml version="1.0" encoding="UTF-8" ?>\n<XMLDB PATH="local/rows/db" VERSION="2026102000" COMMENT="t">\n'
      printf '  <TABLES>\n    <TABLE NAME="local_demo_note" COMMENT="n">\n      <FIELDS>\n'
      for f in $2; do printf '        <FIELD NAME="%s" TYPE="char" LENGTH="255" NOTNULL="false" SEQUENCE="false"/>\n' "$f"; done
      printf '      </FIELDS>\n    </TABLE>\n  </TABLES>\n</XMLDB>\n'; } > "$1/db/install.xml"
}

render() {
    mkdir -p "$T/$1"
    printf 'component: %s\nrequires: "4.5"\ncopyright: 2026 onwards, Example Author <author@example.com>\n' "$2" > "$T/$1/recipe.yaml"
    python3 "$G" --target-dir "$T/$1" "$T/$1/recipe.yaml" >/dev/null 2>"$T/err" || bad "$1 skeleton: $(cat "$T/err")"
}
mobile() {
    php -r "define('MOODLE_INTERNAL', 1); \$CFG = (object) ['wwwroot' => 'https://w.invalid']; include '$1/db/mobile.php';
        \$h = reset(\$addons)['handlers']; \$h = \$h[key(\$h)]; $2"
}
mmobile() {
    local out; out="$("$MM" "$1" 2>&1)"; local rc=$?
    if [ "$rc" -eq 0 ] && ! grep -q '^FAIL\|^WARN' <<<"$out" && grep -q '^PASS' <<<"$out"; then ok "mmobile 0 FAIL 0 WARN: $2"
    else bad "mmobile $2 rc=$rc: $out"; fi
}

render local local_demo; PL="$T/local/demo"
render mod mod_demo; PM="$T/mod/demo"
render block block_demo; PB="$T/block/demo"
render links local_links; PK="$T/links/links"

v0="$(version "$PL")"
python3 "$K" "$PL" --delegate CoreMainMenuDelegate >"$T/out" 2>&1 && ok "main menu renders" || bad "main menu rc: $(cat "$T/out")"
[ "$(version "$PL")" -gt "$v0" ] && ok "version bumped $v0 -> $(version "$PL")" || bad "version not bumped"
mobile "$PL" "exit(array_keys(\$addons) == ['local_demo'] && \$h['delegate'] == 'CoreMainMenuDelegate'
    && \$h['method'] == 'mobile_demo_view' && \$h['displaydata'] == ['title' => 'mobile_demo', 'icon' => 'earth']
    && in_array(['mobile_demo', 'local_demo'], reset(\$addons)['lang']) ? 0 : 1);" \
    && ok "db/mobile.php: addon = component, delegate, method, displaydata, lang" || bad "db/mobile.php: $(cat "$PL/db/mobile.php")"
c="$PL/classes/output/mobile.php"
grep -q '^namespace local_demo\\output;' "$c" && grep -q 'public static function mobile_demo_view(array \$args): array {' "$c" \
    && grep -q "render_from_template('local_demo/mobileapp/demo', \[\])" "$c" \
    && grep -q "'javascript' => ''," "$c" && grep -q "'otherdata' => \[\]," "$c" \
    && ok "output class: static method returns templates, javascript, otherdata" || bad "output class: $(cat "$c")"
m="$PL/templates/mobileapp/demo.mustache"
grep -q '@template local_demo/mobileapp/demo' "$m" && [ ! -e "$PL/templates/mobile_demo.mustache" ] && grep -q '^{{=<% %>=}}$' "$m" \
    && grep -q "{{ 'plugin.local_demo.mobile_demo' | translate }}" "$m" \
    && ok "mustache: templates/mobileapp/demo, @template, delimiter switch, app strings" || bad "mustache: $(cat "$m")"
tf="$PL/tests/output/mobile_test.php"
grep -q '^namespace local_demo\\output;' "$tf" && grep -q '^final class mobile_test extends \\advanced_testcase {' "$tf" \
    && grep -q '@covers     \\local_demo\\output\\mobile' "$tf" && grep -q '\$result = mobile::mobile_demo_view(\[\]);' "$tf" \
    && grep -q "assertEquals('main', \$result\['templates'\]\[0\]\['id'\]);" "$tf" \
    && grep -q "assertStringContainsString('plugin.local_demo.mobile_demo', " "$tf" \
    && grep -q "assertSame(\[\], \$result\['otherdata'\]);" "$tf" \
    && ok "tests/output/mobile_test.php: template id main, page string, empty otherdata" || bad "mobile_test.php: $(cat "$tf")"
grep -q "no --capability and 0 capabilities" "$T/out" && ! grep -q 'require_capability' "$c" \
    && ! grep -q 'requires_capability' "$tf" && ok "no db/access.php: no require_capability, warning" || bad "no cap: $(cat "$T/out")"
grep -q "^\$string\['mobile_demo'\] = 'Demo';" "$PL/lang/en/local_demo.php" && ok "lang string added" || bad "lang"
mmobile "$PL" "CoreMainMenuDelegate"

python3 "$K" "$PM" --delegate CoreCourseModuleDelegate --handler course_view >"$T/out" 2>&1 \
    && mobile "$PM" "exit(\$h['method'] == 'mobile_course_view_view' && \$h['displaydata'] == ['class' => ''] ? 0 : 1);" \
    && ok "course module, --handler course_view" || bad "course module: $(cat "$T/out" "$PM/db/mobile.php")"
[ -f "$PM/templates/mobileapp/course_view.mustache" ] && grep -q "^\$string\['mobile_course_view'\]" "$PM/lang/en/demo.php" \
    && ok "mod: template + lang in lang/en/demo.php" || bad "mod template or lang"
mmobile "$PM" "CoreCourseModuleDelegate"
render modicon mod_pic; PI="$T/modicon/pic"; mkdir -p "$PI/pix"; echo '<svg/>' > "$PI/pix/monologo.svg"
python3 "$K" "$PI" --delegate CoreCourseModuleDelegate >/dev/null 2>&1 \
    && mobile "$PI" "exit(\$h['displaydata']['icon'] == 'https://w.invalid/mod/pic/pix/monologo.svg' ? 0 : 1);" \
    && ok "mod icon from pix/monologo.svg" || bad "mod icon: $(cat "$PI/db/mobile.php")"

python3 "$K" "$PB" --delegate CoreBlockDelegate >"$T/out" 2>&1 \
    && mobile "$PB" "exit(\$h['displaydata'] == ['title' => 'mobile_demo', 'class' => 'block_demo'] ? 0 : 1);" \
    && ok "block: displaydata title + class" || bad "block: $(cat "$T/out" "$PB/db/mobile.php")"
mmobile "$PB" "CoreBlockDelegate"
python3 "$K" "$PK" --delegate CoreContentLinksDelegate >"$T/out" 2>&1 \
    && mobile "$PK" "exit(!array_key_exists('displaydata', \$h) ? 0 : 1);" \
    && ok "delegate without displaydata omits it" || bad "links: $(cat "$T/out" "$PK/db/mobile.php")"
mmobile "$PK" "CoreContentLinksDelegate"

render ref local_ref; PR="$T/ref/ref"
snap() { find "$PR" -type f -exec md5sum {} + | sort; }
before="$(snap)"
python3 "$K" "$PR" --delegate CoreMainMenuDelegat >"$T/out" 2>&1 && bad "unknown delegate accepted" \
    || { grep -q "not an app delegate.*nearest: CoreMainMenuDelegate" "$T/out" && [ "$before" = "$(snap)" ] \
        && ok "unknown delegate refused with nearest, nothing written" || bad "unknown delegate: $(cat "$T/out")"; }
python3 "$K" "$PR" --delegate CoreCourseModuleDelegate >"$T/out" 2>&1 && bad "mod-only delegate accepted for local_" \
    || { grep -q "needs a mod_ plugin" "$T/out" && [ "$before" = "$(snap)" ] \
        && ok "mod-only delegate refused for local_, nothing written" || bad "mod-only: $(cat "$T/out")"; }
python3 "$K" "$PR" --delegate CoreMainMenuDelegate --handler Bad-Name >"$T/out" 2>&1 && bad "bad handler accepted" \
    || { grep -q "bad handler name" "$T/out" && [ "$before" = "$(snap)" ] && ok "bad handler name refused" || bad "handler: $(cat "$T/out")"; }
before="$(find "$PL" -type f -exec md5sum {} + | sort)"
python3 "$K" "$PL" --delegate CoreMainMenuDelegate --handler other >"$T/out" 2>&1 && bad "second run accepted" \
    || { grep -q "mobile.php already exists" "$T/out" && [ "$before" = "$(find "$PL" -type f -exec md5sum {} + | sort)" ] \
        && ok "existing db/mobile.php refused, nothing written" || bad "existing: $(cat "$T/out")"; }
python3 "$K" "$PR" >"$T/out" 2>&1 && bad "no --delegate accepted" || ok "--delegate required"
for d in CoreBlockDelegate AddonModQuizAccessRuleDelegate CoreQuestionDelegate; do
    b="$(snap)"; python3 "$K" "$PR" --delegate "$d" >"$T/out" 2>&1 && bad "$d accepted for local_" \
        || { grep -q "local_ref can take: .*CoreMainMenuDelegate" "$T/out" && ! grep -q "can take: .*$d" "$T/out" \
            && [ "$b" = "$(snap)" ] && ok "$d refused for local_, allowed delegates named" || bad "$d: $(cat "$T/out")"; }
done
python3 "$K" "$PM" --delegate CoreBlockDelegate --handler blk >"$T/out" 2>&1 && bad "CoreBlockDelegate accepted for mod_" \
    || { grep -q "needs a block_ plugin, got mod_demo; mod_demo can take: .*CoreCourseModuleDelegate" "$T/out" \
        && ok "CoreBlockDelegate refused for mod_" || bad "block on mod: $(cat "$T/out")"; }

render rows local_rows; PT="$T/rows/rows"
sed -i 's/^\$plugin->version = [0-9]*;/$plugin->version = 2026102000.01;/' "$PT/version.php"
notes_xml "$PT" "id userid title"
before="$(find "$PT" -type f -exec md5sum {} + | sort)"
python3 "$K" "$PT" --delegate CoreMainMenuDelegate --table local_demo_note --cols title,nope >"$T/out" 2>&1 \
    && bad "unknown --cols accepted" || { grep -q "has no field nope" "$T/out" && ok "unknown column refused" || bad "cols: $(cat "$T/out")"; }
python3 "$K" "$PT" --delegate CoreMainMenuDelegate --table local_demo_note >"$T/out" 2>&1 \
    && bad "--table without --cols accepted" || { grep -q "go together" "$T/out" && ok "--table needs --cols" || bad "pair: $(cat "$T/out")"; }
python3 "$K" "$PT" --delegate CoreMainMenuDelegate --table local_demo_nope --cols title >"$T/out" 2>&1 \
    && bad "unknown table accepted" || { grep -q "not in .*install.xml (tables: local_demo_note)" "$T/out" && ok "unknown table refused" || bad "table: $(cat "$T/out")"; }
notes_xml "$PT" "id owner title"
python3 "$K" "$PT" --delegate CoreMainMenuDelegate --table local_demo_note --cols title >"$T/out" 2>&1 \
    && bad "table without userid accepted" || { grep -q "has no userid field" "$T/out" && ok "table without userid refused" || bad "userid: $(cat "$T/out")"; }
notes_xml "$PT" "id userid title"
[ "$before" = "$(find "$PT" -type f -exec md5sum {} + | sort)" ] && ok "table refusals wrote nothing" || bad "table refusals wrote files"
python3 "$K" "$PT" --delegate CoreMainMenuDelegate --table local_demo_note --cols title,userid >"$T/out" 2>&1 \
    && ok "--table renders on decimal version" || bad "--table rc: $(cat "$T/out")"
grep -q "2026102000.01 -> " "$T/out" && [ "$(version "$PT")" -gt 2026102000 ] && ok "decimal version bumped to $(version "$PT")" \
    || bad "decimal version: $(cat "$T/out")"
c="$PT/classes/output/mobile.php"
grep -q 'global \$DB, \$OUTPUT, \$USER;' "$c" \
    && grep -q "get_records('local_demo_note', \['userid' => \$USER->id\], 'id')" "$c" \
    && grep -q "'title' => format_string(\$record->title, true, \['context' => \$context\])," "$c" \
    && grep -q "render_from_template('local_rows/mobileapp/rows', \[\])" "$c" \
    && grep -q "'otherdata' => \['rows' => json_encode(\$rows)\]," "$c" \
    && ok "output class: current user's rows through format_string, in otherdata" || bad "table class: $(cat "$c")"
m="$PT/templates/mobileapp/rows.mustache"
grep -q '^    <ion-item \*ngFor="let row of CONTENT_OTHERDATA.rows">$' "$m" \
    && grep -q '<p><core-format-text \[text\]="row.title"></core-format-text></p>' "$m" \
    && grep -q '<p><core-format-text \[text\]="row.userid"></core-format-text></p>' "$m" \
    && ! grep -qF '{{{' "$m" && ! grep -q '{{#rows}}' "$m" \
    && ok "mustache: *ngFor over CONTENT_OTHERDATA.rows, no triple mustache" || bad "table mustache: $(cat "$m")"
php -r "define('MOODLE_INTERNAL', 1);
    class context_user { public static function instance(\$id) { return new self(); } }
    function format_string(\$s, \$strip = true, \$o = []) { return htmlspecialchars(\$s); }
    \$USER = (object) ['id' => 2];
    \$DB = new class { public function get_records(\$t, \$c, \$s) { return [1 => (object) ['title' => '{{ 1+1 }}', 'userid' => 2]]; } };
    \$OUTPUT = new class { public function render_from_template(\$n, \$ctx) {
        return file_get_contents('$m') . json_encode(\$ctx); } };
    require '$c';
    \$r = \\local_rows\\output\\mobile::mobile_rows_view([]);
    \$rows = \$r['otherdata']['rows'];
    exit(strpos(\$r['templates'][0]['html'], '1+1') === false && is_string(\$rows)
        && json_decode(\$rows, true) == [['title' => '{{ 1+1 }}', 'userid' => '2']] ? 0 : 1);" >"$T/out" 2>&1 \
    && ok "row {{ 1+1 }} travels in otherdata JSON, never in the template html" || bad "injection row: $(cat "$T/out")"
mmobile "$PT" "--table"
tf="$PT/tests/output/mobile_test.php"
grep -q 'global \$DB, \$USER;' "$tf" && grep -q "'userid' => \$USER->id," "$tf" && grep -q "'userid' => \$other->id," "$tf" \
    && grep -q "\$rows = json_decode(\$result\['otherdata'\]\['rows'\], true);" "$tf" \
    && grep -q 'assertCount(1, \$rows);' "$tf" && grep -q "assertEquals('a', \$rows\[0\]\['title'\]);" "$tf" \
    && grep -q "assertEquals(\$USER->id, \$rows\[0\]\['userid'\]);" "$tf" \
    && ok "mobile_test.php: own row in otherdata rows, other user's row absent" || bad "table test: $(cat "$tf")"

render cap local_cap; PC="$T/cap/cap"
python3 "$S/access.py" "$PC" view --type read --context system --archetypes user=allow >/dev/null 2>&1
python3 "$K" "$PC" --delegate CoreMainMenuDelegate >"$T/out" 2>&1 && ok "single access.py cap renders" || bad "cap rc: $(cat "$T/out")"
c="$PC/classes/output/mobile.php"; tf="$PC/tests/output/mobile_test.php"
grep -q "^        require_capability('local/cap:view', \\\\context_system::instance());$" "$c" \
    && ok "default capability: the only db/access.php cap, system context" || bad "default cap: $(cat "$c")"
grep -q 'public function test_mobile_cap_view_requires_capability(): void {' "$tf" \
    && grep -q 'public function test_mobile_cap_view_with_capability(): void {' "$tf" \
    && grep -q 'roleid = \$CFG->defaultuserroleid;' "$tf" && grep -q 'contextid = \\context_system::instance()->id;' "$tf" \
    && grep -q "assign_capability('local/cap:view', CAP_ALLOW, \$roleid, \$contextid, true);" "$tf" \
    && grep -q "assign_capability('local/cap:view', CAP_PROHIBIT, \$roleid, \$contextid, true);" "$tf" \
    && grep -q 'expectException(\\required_capability_exception::class);' "$tf" \
    && ok "mobile_test.php: authenticated user granted opens, prohibited gets required_capability_exception" \
    || bad "cap test: $(cat "$tf")"
! grep -q warning "$T/out" && ok "system capability on a system page: no contextlevel warning" || bad "sys warn: $(cat "$T/out")"
php -r "define('MOODLE_INTERNAL', 1);
    class context_system { public static function instance() { return new self(); } }
    function require_capability(\$cap, \$ctx) { if (\$cap !== 'local/cap:view') { exit(2); } throw new Exception('denied'); }
    \$OUTPUT = new class { public function render_from_template(\$n, \$ctx) { exit(3); } };
    require '$c';
    try { \\local_cap\\output\\mobile::mobile_cap_view([]); } catch (Exception \$e) { exit(0); } exit(4);" >"$T/out" 2>&1 \
    && ok "denied capability stops the page before render" || bad "cap order rc $?: $(cat "$T/out")"
mmobile "$PC" "--capability default"
python3 "$S/access.py" "$PC" manage --type write --context system --archetypes manager=allow >/dev/null 2>&1
rm -r "$PC/db/mobile.php" "$PC/classes/output" "$PC/templates" "$PC/tests/output"
python3 "$K" "$PC" --delegate CoreMainMenuDelegate --handler two >"$T/out" 2>&1 && grep -q "no --capability and 2 capabilities" "$T/out" \
    && ! grep -q 'require_capability' "$c" && ok "2 caps, no --capability: none chosen, warning" || bad "2 caps: $(cat "$T/out" "$c")"
rm -r "$PC/db/mobile.php" "$PC/classes/output" "$PC/templates" "$PC/tests/output"
python3 "$K" "$PC" --delegate CoreMainMenuDelegate --handler three --capability manage >"$T/out" 2>&1 \
    && grep -q "require_capability('local/cap:manage', " "$c" && ! grep -q warning "$T/out" \
    && ok "--capability manage -> local/cap:manage" || bad "short cap: $(cat "$T/out" "$c")"
rm -r "$PC/db/mobile.php" "$PC/classes/output" "$PC/templates" "$PC/tests/output"
python3 "$K" "$PC" --delegate CoreMainMenuDelegate --handler four --capability local/cap:nope >"$T/out" 2>&1 \
    && grep -q "warning: local/cap:nope is not defined in db/access.php" "$T/out" && ok "undefined own capability warned" \
    || bad "undefined cap: $(cat "$T/out")"
rm "$PC/db/mobile.php" "$PC/classes/output/mobile.php" "$PC/templates/mobileapp/four.mustache"
python3 "$K" "$PC" --delegate CoreMainMenuDelegate --handler four >"$T/out" 2>&1 && bad "existing mobile_test.php accepted" \
    || { grep -q "tests/output/mobile_test.php already exists" "$T/out" && ok "existing tests/output/mobile_test.php refused" \
        || bad "existing test: $(cat "$T/out")"; }

render capm mod_capm; PN="$T/capm/capm"
python3 "$K" "$PN" --delegate CoreCourseModuleDelegate --capability view >"$T/out" 2>&1 && ok "mod --capability view renders" \
    || bad "mod cap rc: $(cat "$T/out")"
c="$PN/classes/output/mobile.php"; tf="$PN/tests/output/mobile_test.php"
grep -q "^        \[\$course, \$cm\] = get_course_and_cm_from_cmid(\$args\['cmid'\], 'capm');$" "$c" \
    && grep -q "^        require_login(\$course, false, \$cm, true, true);$" "$c" \
    && grep -q "^        require_capability('mod/capm:view', \\\\context_module::instance(\$cm->id));$" "$c" \
    && [ "$(grep -n require_login "$c" | cut -d: -f1)" -lt "$(grep -n require_capability "$c" | cut -d: -f1)" ] \
    && ok "mod: get_course_and_cm_from_cmid + require_login(course, cm), then module context" || bad "mod cap: $(cat "$c")"
grep -q "create_module('capm', \['course' => \$course->id\]);" "$tf" && grep -q 'class mod_capm_generator extends testing_module_generator' "$PN/tests/generator/lib.php" \
    && grep -q "mobile::mobile_capm_view(\['cmid' => \$cm->cmid, 'courseid' => \$course->id\]);" "$tf" \
    && grep -q "enrol_user(\$user->id, \$course->id, \$roleid);" "$tf" \
    && grep -q 'expectException(\\require_login_exception::class);' "$tf" \
    && ok "mod test: own module (generator added), enrolled student, cmid, view prohibit hides the cm" \
    || bad "mod test: $(cat "$tf")"
mmobile "$PN" "mod --capability"
render nocapm mod_nocapm; PQ="$T/nocapm/nocapm"
python3 "$K" "$PQ" --delegate CoreCourseModuleDelegate >"$T/out" 2>&1 && grep -q "no --capability and 2 capabilities" "$T/out" \
    && grep -q "require_login(\$course, false, \$cm, true, true);" "$PQ/classes/output/mobile.php" \
    && ! grep -q require_capability "$PQ/classes/output/mobile.php" && ok "mod without a capability still calls require_login" \
    || bad "mod no cap: $(cat "$T/out" "$PQ/classes/output/mobile.php")"

render capb block_capb; PX="$T/capb/capb"
python3 "$S/access.py" "$PX" view --type read --context block --archetypes student=allow >/dev/null 2>&1
python3 "$K" "$PX" --delegate CoreBlockDelegate --capability view >"$T/out" 2>&1 && ok "block --capability view renders" \
    || bad "block cap rc: $(cat "$T/out")"
c="$PX/classes/output/mobile.php"; tf="$PX/tests/output/mobile_test.php"
grep -q "^        require_capability('block/capb:view', \\\\context_block::instance(\$args\['blockid'\]));$" "$c" \
    && ! grep -q 'context_system' "$c" && ! grep -q warning "$T/out" \
    && ok "block: CONTEXT_BLOCK cap checked in the block context from \$args['blockid']" || bad "block cap: $(cat "$c" "$T/out")"
grep -q "create_block('capb', \['parentcontextid' => \\\\context_course::instance(\$course->id)->id\]);" "$tf" \
    && grep -q "roleid = \$DB->get_field('role', 'id', \['shortname' => 'student'\], MUST_EXIST);" "$tf" \
    && grep -q "enrol_user(\$user->id, \$course->id, \$roleid);" "$tf" \
    && grep -q 'contextid = \\context_course::instance(\$course->id)->id;' "$tf" \
    && grep -q "assign_capability('block/capb:view', CAP_ALLOW, \$roleid, \$contextid, true);" "$tf" \
    && grep -q "mobile::mobile_capb_view(\['contextlevel' => 'course', 'instanceid' => \$course->id, 'blockid' => \$block->id\]);" "$tf" \
    && ok "block test: enrolled student granted in the course opens, prohibited is refused" || bad "block test: $(cat "$tf")"
mmobile "$PX" "block --capability"

render capo local_capo; PO="$T/capo/capo"
python3 "$S/access.py" "$PO" view --type read --context course --archetypes student=allow >/dev/null 2>&1
python3 "$K" "$PO" --delegate CoreMainMenuDelegate >"$T/out" 2>&1 \
    && grep -q "warning: local/capo:view is a CONTEXT_COURSE capability but CoreMainMenuDelegate pages check it in the system context" "$T/out" \
    && ok "course capability on a system page warned" || bad "level warning: $(cat "$T/out")"
rm -r "$PO/db/mobile.php" "$PO/classes/output" "$PO/templates/mobileapp" "$PO/tests/output"
python3 "$K" "$PO" --delegate CoreCourseOptionsDelegate --handler opt >"$T/out" 2>&1 && ! grep -q warning "$T/out" \
    && grep -q "^        require_login(\$args\['courseid'\], false, null, true, true);$" "$PO/classes/output/mobile.php" \
    && grep -q "^        require_capability('local/capo:view', \\\\context_course::instance(\$args\['courseid'\]));$" "$PO/classes/output/mobile.php" \
    && grep -q "mobile::mobile_opt_view(\['courseid' => \$course->id\]);" "$PO/tests/output/mobile_test.php" \
    && ok "course options: require_login + course context from \$args['courseid']" || bad "course options: $(cat "$T/out" "$PO/classes/output/mobile.php")"
mmobile "$PO" "CoreCourseOptionsDelegate --capability"
python3 "$K" --help | grep -q -- '--delegate' && ok "--help names --delegate" || bad "--help"
python3 "$K" --help | grep -q -- '--table' && ok "--help names --table" || bad "--help --table"

lintfail=0; n=0
for f in "$T"/*/*/db/mobile.php "$T"/*/*/classes/output/mobile.php "$T"/*/*/tests/output/mobile_test.php; do
    n=$((n + 1)); php -l "$f" >/dev/null 2>&1 || { lintfail=1; bad "php -l $f: $(php -l "$f" 2>&1)"; }
done
[ "$lintfail" = 0 ] && ok "php -l clean ($n files)"
for p in "$PL" "$PM" "$PB" "$PK" "$PT" "$PN" "$PX" "$PO"; do
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker --max-warnings 0 "$p" 2>&1)"; rc=$?
        if grep -q '| ERROR |\|| WARNING |' <<<"$out"; then bad "$p codechecker: $(grep '| ERROR |\|| WARNING |' <<<"$out")"
        elif [ "$rc" -ne 0 ]; then bad "$p codechecker rc=$rc"
        else ok "codechecker 0/0 ${p#"$T"/}"; fi
    else
        echo "SKIP codechecker: moodle-plugin-ci absent"
    fi
done

[ "$fails" -eq 0 ] && echo "PASS mobile.test.sh" || { echo "FAIL mobile.test.sh ($fails)"; exit 1; }
