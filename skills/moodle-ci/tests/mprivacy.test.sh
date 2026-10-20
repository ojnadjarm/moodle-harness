#!/usr/bin/env bash
# mprivacy on a throwaway 5.1+ tree with stubbed docker: null provider ok, missing lang string, user table, 0 matched,
# static FAIL without a container, init failure, no temp leaks, userlist (use imports resolved), export/delete coverage
# WARNs (no bare-name helper or bare-string false PASS, provider class only), bad flag / missing path rc 2, --static
# without docker, `mprivacy:kept` KEPT lines and unknown-table WARN, trait methods (namespaced, unresolved), aliased
# and core-namespaced Class::m() calls, persistent TABLE.
set -uo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)/scripts/mprivacy"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/moodle" P="$T/moodle/public/local/x"
mkdir -p "$T/home/.claude/hooks" "$T/bin" "$R/vendor/bin" "$R/public/admin" "$R/public/privacy/tests/privacy" \
    "$P/classes/privacy" "$P/lang/en" "$P/db"
touch "$R/vendor/bin/phpunit" "$R/config.php" "$R/public/privacy/tests/privacy/provider_test.php"
echo "<?php \$plugin->component = 'local_x';" > "$P/version.php"
echo "<?php class provider implements null_provider { static function get_reason(): string { return 'privacy:metadata'; } }" \
    > "$P/classes/privacy/provider.php"
printf '#!/bin/sh\n[ -n "${NOCONT:-}" ] && exit 1\nprintf "c1\\t/var/www/html\\n"\n' > "$T/home/.claude/hooks/moodle-container.sh"
# docker stub: logs every command; --diag passes unless $STALE; init.php fails; `cat` of the junit prints $JUNIT.
cat > "$T/bin/docker" <<'EOF'
#!/bin/bash
c="${*: -1}"; echo "$c" >> "$LOGF"
case "$c" in
    *util.php\ --diag*) [ -z "${STALE:-}" ];;
    *init.php*) echo "init boom"; exit 1;;
    *vendor/bin/phpunit*) echo "phpunit ran"; exit "${PRC:-0}";;
    cat\ *) cat "$JUNIT";;
esac
EOF
chmod +x "$T/bin/"* "$T/home/.claude/hooks/moodle-container.sh"
junit() {
    { echo '<testsuites><testsuite name="x">'
      for t in "$@"; do
          n="${t%:*}"; s="${t#*:}"
          echo "<testcase name='$n with data set \"local_x\"'>"
          [ "$s" = fail ] && echo '<failure>Failed asserting that false is true.</failure>'
          echo '</testcase>'
      done
      echo '</testsuite></testsuites>'; } > "$T/junit.xml"
}
run() { : > "$T/log"; timeout 10 env HOME="$T/home" PATH="$T/bin:$PATH" LOGF="$T/log" JUNIT="$T/junit.xml" TMPDIR="$T" "$@" 2>&1; }
bad=0
check() { if eval "$1"; then echo "PASS $2"; else echo "FAIL $2"; bad=1; fi; }

echo "<?php \$string['privacy:metadata'] = 'No data.';" > "$P/lang/en/local_x.php"
junit test_null_provider:ok test_all_providers_compliant:ok test_table_coverage:ok
out="$(run "$M" "$P")"; rc=$?
check '[ $rc = 0 ] && grep -q "^PASS null" <<<"$out" && grep -q "^n/a  metadata" <<<"$out" && grep -q "local_x ok" <<<"$out"' "null provider ok: rc 0"
check "grep -q -- \"--filter '@local_x'\" \"\$T/log\" && grep -q public/privacy/tests/privacy/provider_test.php \"\$T/log\"" "filters provider_test to the component data set"
check '! grep -q init.php "$T/log"' "fresh env: no init"

echo "<?php \$string['pluginname'] = 'X';" > "$P/lang/en/local_x.php"
junit test_null_provider:fail test_all_providers_compliant:ok test_table_coverage:ok
out="$(run PRC=1 "$M" "$P")"; rc=$?
check "[ \$rc = 1 ] && grep -q \"^FAIL lang .*'privacy:metadata'\" <<<\"\$out\" && grep -q '^FAIL null' <<<\"\$out\"" "missing lang string: red"

echo "<?php \$string['privacy:metadata'] = 'No data.';" > "$P/lang/en/local_x.php"
cat > "$P/db/install.xml" <<'EOF'
<XMLDB><TABLES>
<TABLE NAME="local_x_log"><FIELDS><FIELD NAME="id"/><FIELD NAME="userid"/></FIELDS></TABLE>
<TABLE NAME="local_x_cfg"><FIELDS><FIELD NAME="id"/></FIELDS></TABLE>
</TABLES></XMLDB>
EOF
junit test_null_provider:ok test_all_providers_compliant:ok test_table_coverage:ok
out="$(run "$M" "$P")"; rc=$?
check '[ $rc = 1 ] && grep -q "^FAIL tables .*local_x_log" <<<"$out" && grep -q "^WARN tables .*local_x_cfg" <<<"$out"' "user table missing from get_metadata: red"

out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 1 ] && grep -q "^FAIL tables" <<<"$out" && grep -q "no running container" <<<"$out"' "static FAIL + no container: rc 1, reason printed"
rm "$P/db/install.xml"

out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 3 ] && grep -q "no running container" <<<"$out"' "static ok + no container: rc 3"

echo "<?php \$string['pluginname'] = 'X';" > "$P/lang/en/local_x.php"
echo "<?php class provider { function m(\$c) { \$c->add_database_table('local_x_log', [], 'privacy:metadata:log'); \$c->p('privacy:metadata:pref:' . \$k, \"privacy:metadata:x:\$k\"); } }" \
    > "$P/classes/privacy/provider.php"
echo '<XMLDB><TABLES><TABLE NAME="local_x_log"><FIELDS><FIELD NAME="userid"/></FIELDS></TABLE></TABLES></XMLDB>' > "$P/db/install.xml"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 1 ] && [ "$(grep -c "^FAIL lang" <<<"$out")" = 1 ] && grep -q "^PASS tables" <<<"$out"' "lang FAIL keeps PASS tables; dynamic ids skipped"
rm "$P/db/install.xml"
echo "<?php class provider implements null_provider { static function get_reason(): string { return 'privacy:metadata'; } }" \
    > "$P/classes/privacy/provider.php"
echo "<?php \$string['privacy:metadata'] = 'No data.';" > "$P/lang/en/local_x.php"

# Static completeness: userlist, every user-field table in export_user_data and the three delete_data_for_* methods.
echo "<?php \$string['privacy:metadata:log'] = 'Log.';" > "$P/lang/en/local_x.php"
echo '<XMLDB><TABLES><TABLE NAME="local_x_log"><FIELDS><FIELD NAME="userid"/></FIELDS></TABLE></TABLES></XMLDB>' > "$P/db/install.xml"
prov() {  # prov <implements> <export body> <delete_data_for_user> <..._all_users_in_context> <delete_data_for_users> [extra]
    cat > "$P/classes/privacy/provider.php" <<EOP
<?php
${USE:-use core_privacy\local\request;}
class provider implements \core_privacy\local\metadata\provider, $1 {
    public static function get_metadata(\$c) { \$c->add_database_table('local_x_log', [], 'privacy:metadata:log'); }
    public static function export_user_data(\$l) { $2 }
    public static function delete_data_for_user(\$l) { $3 }
    public static function delete_data_for_all_users_in_context(\$c) { $4 }
    public static function delete_data_for_users(\$l) { $5 }
    ${6:-}
}
EOP
}
I='request\plugin\provider, request\core_userlist_provider' D="\$DB->delete_records('local_x_log', []);"
E='$r = $DB->get_records_sql("SELECT * FROM {local_x_log} WHERE userid = ?", [1]);'
prov "$I" "$E" "$D" "$D" "$D"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 3 ] && grep -q "^PASS userlist" <<<"$out" && grep -q "^PASS delete .*delete_data_for_users" <<<"$out" && grep -q "^PASS export" <<<"$out"' "complete userlist provider: static PASS, rc 3"

prov "$I" "$E" "$D" "$D" "// \$DB->delete_records('local_x_log', []); /* {local_x_log} */"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 3 ] && grep -q "^WARN delete .*local_x_log.*not in delete_data_for_users" <<<"$out" && [ "$(grep -c "^WARN delete" <<<"$out")" = 1 ]' "table only in a comment of delete_data_for_users: WARN, not red"

prov "$I" "$E" "$D" "return;" "$D"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 3 ] && grep -q "^WARN delete .*not in delete_data_for_all_users_in_context" <<<"$out"' "table absent from delete_data_for_all_users_in_context: WARN"

prov "$I" "return;" "$D" "$D" "$D"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 3 ] && grep -q "^WARN export .*not in export_user_data" <<<"$out" && grep -q "^PASS delete" <<<"$out"' "table absent from export_user_data: WARN"

prov "$I" "$E" "self::wipe();" "static::wipe();" "self::wipe();" "protected static function wipe() { self::really(); } private static function really() { \$s = '{'; $D }"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 3 ] && grep -q "^PASS delete" <<<"$out"' "deletes through a helper chain (brace in a string): PASS"

prov 'request\plugin\provider' "$E" "$D" "$D" "$D"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 1 ] && grep -q "^FAIL userlist .*without core_userlist_provider" <<<"$out"' "request\\plugin\\provider without core_userlist_provider: FAIL"

U='use core_privacy\local\request\plugin; use core_privacy\local\request\core_userlist_provider;'
USE="$U" prov 'plugin\provider' "$E" "$D" "$D" "$D"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 1 ] && grep -q "^FAIL userlist" <<<"$out"' "use ...\\request\\plugin; implements plugin\\provider, userlist only imported: FAIL"
G='use core_privacy\local\request\{plugin, core_userlist_provider as ul};'
USE="$G" prov 'plugin\provider, ul' "$E" "$D" "$D" "$D"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 3 ] && grep -q "^PASS userlist" <<<"$out"' "grouped use import with alias: PASS userlist"
USE="$G" prov 'plugin\provider' "$E" "$D" "$D" "$D"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 1 ] && grep -q "^FAIL userlist" <<<"$out"' "grouped use import without userlist: FAIL"

mkdir -p "$P/classes/task"
echo "<?php class unrelated { public function execute() { \$DB->delete_records('local_x_log', []); } }" > "$P/classes/task/unrelated.php"
prov "$I" "$E" "$D" "$D" "\$t->execute(); \$n = 'local_x_log'; helper::get();" \
    "} class helper { static function get() { return 1; }"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 3 ] && grep -q "^WARN delete .*not in delete_data_for_users" <<<"$out"' "unrelated execute() and a bare 'table' string: no false PASS"
echo "<?php class helper2 { static function get() { global \$DB; \$DB->delete_records('local_x_log', []); } }" > "$P/classes/task/helper2.php"
prov "$I" "$E" "$D" "$D" "helper2::get();"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 3 ] && grep -q "^PASS delete" <<<"$out"' "Class::method() helper in another file: PASS"
rm -r "$P/classes/task"

prov "$I" "return;" "$D" "$D" "$D"
echo "<?php class legacy { public static function export_user_data(\$l) { $E } }" > "$P/classes/privacy/zz_legacy.php"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check 'grep -q "^WARN export .*not in export_user_data" <<<"$out"' "export_user_data in a second privacy class: provider's own body checked"
rm "$P/classes/privacy/zz_legacy.php"

out="$(run "$M" --bogus "$P")"; rc=$?
check '[ $rc = 2 ] && grep -q "usage: mprivacy" <<<"$out"' "unknown flag: rc 2 with usage, no loop"
out="$(run "$M" "$T/nope/deeper")"; rc=$?
check '[ $rc = 2 ] && grep -q "no such path" <<<"$out"' "missing path: rc 2, no loop"
prov "$I" "$E" "$D" "$D" "$D"
out="$(run "$M" --static "$P")"; rc=$?
check '[ $rc = 0 ] && grep -q "^PASS export" <<<"$out" && grep -q "local_x static ok" <<<"$out" && [ ! -s "$T/log" ]' "--static clean: rc 0, no docker call"
prov "$I" "return;" "$D" "$D" "$D" "// mprivacy:kept local_x_log audit trail, kept for the site"
out="$(run "$M" --static "$P")"; rc=$?
check '[ $rc = 0 ] && grep -q "^KEPT export .*local_x_log not in export_user_data: audit trail, kept for the site" <<<"$out" && ! grep -q "^WARN export\|^PASS export" <<<"$out" && grep -q "^PASS delete" <<<"$out"' "mprivacy:kept: export WARN becomes KEPT"
prov "$I" "$E" "return;" "return;" "$D" "/* mprivacy:kept local_x_log */"
out="$(run "$M" --static "$P")"; rc=$?
check '[ "$(grep -c "^KEPT delete .*local_x_log" <<<"$out")" = 2 ] && ! grep -q "^WARN" <<<"$out"' "mprivacy:kept in a block comment: delete WARNs become KEPT"
prov "$I" "$E" "$D" "$D" "$D" "// mprivacy:kept local_x_lgo typo"
out="$(run "$M" --static "$P")"; rc=$?
check 'grep -q "^WARN kept .*local_x_lgo" <<<"$out"' "mprivacy:kept naming an unknown table: WARN"
cat > "$P/classes/privacy/provider.php" <<EOP
<?php
class provider implements \core_privacy\local\metadata\provider, \core_privacy\local\request\plugin\provider,
        \core_privacy\local\request\core_userlist_provider {
    use exporter;
    public static function get_metadata(\$c) { \$c->add_database_table('local_x_log', [], 'privacy:metadata:log'); }
    public static function delete_data_for_user(\$l) { self::wipe(); }
    public static function delete_data_for_all_users_in_context(\$c) { self::wipe(); }
    public static function delete_data_for_users(\$l) { self::wipe(); }
}
EOP
echo "<?php trait exporter { public static function export_user_data(\$l) { return; } static function wipe() { $D } }" \
    > "$P/classes/privacy/exporter.php"
out="$(run "$M" --static "$P")"; rc=$?
check 'grep -q "^WARN export .*not in export_user_data" <<<"$out" && grep -q "^PASS delete" <<<"$out"' "methods from a trait in another file: export checked, helper followed"
sed -i '1a namespace local_x\\privacy;' "$P/classes/privacy/provider.php" "$P/classes/privacy/exporter.php"
out="$(run "$M" --static "$P")"; rc=$?
check 'grep -q "^WARN export .*not in export_user_data" <<<"$out" && grep -q "^PASS delete" <<<"$out" && ! grep -q "^WARN delete" <<<"$out"' "unqualified trait use in a namespace: resolved to the namespace"
rm "$P/classes/privacy/exporter.php"
out="$(run "$M" --static "$P")"; rc=$?
check 'grep -q "^WARN export .*export_user_data not found in provider" <<<"$out" && ! grep -q "^PASS export" <<<"$out"' "export_user_data only in an unresolved trait: WARN not found, not silent"
mkdir -p "$P/classes/local"
echo "<?php class helper { static function wipe() { global \$DB; \$DB->delete_records('local_x_log', []); } }" > "$P/classes/local/helper.php"
prov "$I" "$E" "$D" "$D" '\core_privacy\local\request\helper::wipe();'
out="$(run "$M" --static "$P")"; rc=$?
check 'grep -q "^WARN delete .*not in delete_data_for_users" <<<"$out"' "core-namespaced helper::m() not taken for the plugin's helper: no false PASS"
echo "<?php namespace local_x\local; class wiper { static function go() { global \$DB; \$DB->delete_records('local_x_log', []); } }" \
    > "$P/classes/local/wiper.php"
USE='use core_privacy\local\request; use local_x\local\wiper as w;' prov "$I" "$E" "$D" "$D" "w::go();"
out="$(run "$M" --static "$P")"; rc=$?
check 'grep -q "^PASS delete" <<<"$out"' "aliased plugin class w::go(): followed, PASS"
echo "<?php namespace local_x; class entry extends \\core\\persistent { const TABLE = 'local_x_log'; }" > "$P/classes/local/entry.php"
USE='use local_x\entry;' prov "$I" "$E" "$D" "$D" "foreach (entry::get_records(['userid' => 1]) as \$e) { \$e->delete(); }"
out="$(run "$M" --static "$P")"; rc=$?
check 'grep -q "^PASS delete" <<<"$out"' "persistent class with const TABLE: followed, PASS"
rm -r "$P/classes/local"

echo "<?php \$string['privacy:metadata'] = 'No data.';" > "$P/lang/en/local_x.php"
echo "<?php class provider implements \\core_privacy\\local\\metadata\\null_provider { static function get_reason(): string { return 'privacy:metadata'; } }" \
    > "$P/classes/privacy/provider.php"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check 'grep -q "^WARN null .*null_provider but user-field tables: local_x_log" <<<"$out" && ! grep -q "^FAIL userlist\|^FAIL delete" <<<"$out"' "null_provider with a user table: WARN"
rm "$P/db/install.xml"
out="$(run NOCONT=1 "$M" "$P")"; rc=$?
check '[ $rc = 3 ] && ! grep -q "^WARN null" <<<"$out"' "null_provider without user tables: no WARN"

junit
out="$(run "$M" "$P")"; rc=$?
check '[ $rc = 1 ] && grep -q "0 provider_test data sets matched" <<<"$out"' "0 matched: red"

rm -f "$T"/mprivacy-*
out="$(run STALE=1 "$M" "$P")"; rc=$?
check '[ $rc = 1 ] && grep -q "init failed" <<<"$out" && ! grep -q "vendor/bin/phpunit" "$T/log"' "init failure: rc 1, phpunit not run"
check '[ "$(ls "$T"/mprivacy-* | wc -l)" = 1 ] && grep -q "init boom" "$T"/mprivacy-*.log' "init failure: init output in the .log, only the .log left"

out="$(run "$M" "$T")"; rc=$?
check '[ $rc = 2 ]' "no version.php: rc 2"
check '! ls "$T"/mprivacy-*.init "$T"/mprivacy-*.xml >/dev/null 2>&1 && ls "$T"/mprivacy-*.log >/dev/null 2>&1' "no leftover .init/.xml, only .log"
exit "$bad"
