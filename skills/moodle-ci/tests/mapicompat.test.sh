#!/usr/bin/env bash
# mapicompat on a throwaway local_hello with the trimmed UPGRADING fixture: requires 4.5 + a 5.3 method red,
# requires 5.3 green, comment-only and vendor/node_modules uses ignored, unchanged/old/skipped symbols green,
# visibility-only and unknown-receiver ->calls not red, heredoc/inline HTML, --since, --removed/--until (removed red,
# deprecated rc 0, replacements green, unknown receiver unverified once, global imports, "method" functions, strings), default env discovery (4.5/vass never read), usage rc 2, SKIP rc 3. 200-file plugin under timeout 5.
# Hook classes on fixture msrc trees: db/hooks.php and use red, shared/own/comment/tests green, SKIP, mtime cache.
set -uo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)"; M="$D/scripts/mapicompat"; F="$D/tests/fixtures/UPGRADING-sample.md"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export MOODLE_ENVS="$T/noenvs" XDG_CACHE_HOME="$T/cache"
P="$T/local/hello"; mkdir -p "$P/classes" "$P/vendor/x" "$P/node_modules/y"
bad=0
req() { echo "<?php \$plugin->component = 'local_hello'; \$plugin->requires = $1;" > "$P/version.php"; }
code() { printf '<?php\n%s\n' "$1" > "$P/classes/a.php"; }
expect() {  # name rc [grep] [args...]
    local name="$1" want="$2" pat="${3:-}" out rc; shift 3 2>/dev/null || shift $#
    out="$(nice -n 19 "$M" "$P" "$@" 2>&1)"; rc=$?
    if [ "$rc" = "$want" ] && { [ -z "$pat" ] || grep -q -- "$pat" <<<"$out"; }; then echo "PASS $name"
    else echo "FAIL $name (rc $rc, want $want): $out"; bad=1; fi
}
U=(--upgrading "$F")
echo '<?php $PAGE->set_show_navigation_footer(false);' | tee "$P/vendor/x/a.php" > "$P/node_modules/y/a.php"
code '// header
$PAGE->set_show_navigation_footer(false);'
req 2024100700; expect "requires 4.5 + 5.3 method red" 1 \
    'classes/a.php:3 moodle_page::set_show_navigation_footer() added in 5.3 (MDL-87575)' "${U[@]}"
req 2026100500; expect "requires 5.3 green" 0 '' "${U[@]}"
code '// $PAGE->set_show_navigation_footer(false);
# \core\session\manager::supports_cookies();
/* new \core\api\token_manager(); */
/**
 * Uses \core\authentication::plugin_exists() later.
 */
$s = 1;'
req 2024100700; expect "comment-only + vendor/node_modules uses green" 0 '0 uses' "${U[@]}"
code 'email_to_user($u, $f, "s", "m");
$a = get_auth_plugin("manual");
fake_changed_function();
$h = \core\hook\output\after_http_headers::class;
$x = new \core\output\action_menu\subpanel("a", $m);
function set_has_sticky_footer() {}'
expect "existing, Changed, 4.5, param-only and definitions green" 0 '' "${U[@]}"
code '$c = \core\session\manager::supports_cookies();
$t = new \core\api\token_manager();
$e = \core\authentication::plugin_exists("x");
$u = \core_customfield\api::is_shortname_unique($h, "n");'
expect "4 uses red" 1 'classes/a.php:5 \\core_customfield\\api::is_shortname_unique() added in 5.2 (MDL-87059)' "${U[@]}"
n="$("$M" "$P" "${U[@]}" 2>&1 | grep -c '^classes/a.php:')"
[ "$n" = 4 ] && echo "PASS 4 hits" || { echo "FAIL want 4 hits, got $n"; bad=1; }
code '$this->add_setting($s);
$r = $bc->get_results();
$d = $m->clear_description();
$f = get_groups_for_filtering();
$this->page->set_show_navigation_footer(false);'
expect "old/visibility-only APIs and unknown receivers green" 0 '0 uses, 3 unverified' "${U[@]}"
expect "unknown receiver listed as unverified" 0 'classes/a.php:3 unverified ->get_results() added in 5.2 (MDL-87648)' "${U[@]}"
out="$("$M" "$P" "${U[@]}" 2>&1)"; grep -q 'add_setting\|get_groups_for_filtering' <<<"$out" && { echo "FAIL add_setting/bare method listed"; bad=1; } || echo "PASS add_setting/bare method not listed"
cat > "$P/classes/a.php" <<'EOF'
Don't <?php
$a = <<<EOT
It's {$x}
EOT;
$b = <<<'NOW'
Isn't
NOW;
$u = 'http://x'; $c = \core\session\manager::supports_cookies();
?>
Won't
<?php $t = "a//b"; $k = new \core\api\token_manager();
EOF
expect "heredoc, nowdoc, inline HTML keep string tracking" 1 '2 uses' "${U[@]}"
code '$c = \core\session\manager::supports_cookies();
$t = new \core\api\token_manager();
$e = \core\authentication::plugin_exists("x");
$u = \core_customfield\api::is_shortname_unique($h, "n");'
expect "--since 5.2 drops the 5.2 use" 1 '3 uses' "${U[@]}" --since 5.2
expect "--since 5.3 green" 0 '' "${U[@]}" --since 5.3
R=("${U[@]}" --removed)
code 'cron_run();'
expect "--removed: removed function red" 1 'classes/a.php:2 cron_run() removed in 5.2 (MDL-87425)' "${R[@]}"
expect "--removed --until 5.1: deprecated only, rc 0" 0 'cron_run() deprecated in 5.0 (MDL-81070)' "${R[@]}" --until 5.1
expect "--removed --until 4.5 cuts every branch" 0 '0 symbols removed or deprecated' "${R[@]}" --until 4.5
expect "default mode ignores Removed sections" 0 '0 uses' "${U[@]}"
req 2026042000; expect "--removed: requires 5.2 drops the 5.2 removal" 0 '0 removed' "${R[@]}"
req 2024100700
code '$t = \core\task\manager::task_is_scheduled($x);
$s = external_format_string("a", $c);
if ($f === FEATURE_GROUPMEMBERSONLY) { $a = new \external_api(); }'
expect "--removed: method, table function, constant, global class deprecated rc 0" 0 \
    '0 removed, 4 deprecated, 0 unverified' "${R[@]}"
expect "--removed: deprecated line format" 0 \
    'classes/a.php:2 \\core\\task\\manager::task_is_scheduled() deprecated in 5.3 (MDL-88845)' "${R[@]}"
code '$q = \core\task\manager::get_queued_adhoc_task_record($t);
$u = \core_external\util::format_string("a", $c);
$e = new \core_external\external_api();
\core\cron::run_main_process();
// cron_run();
checkall();'
expect "--removed: replacements, comments and JS-only removals green" 0 '0 removed, 0 deprecated' "${R[@]}"
code '$c->get_copy();'
expect "--removed: unknown receiver unverified, rc 0" 0 'classes/a.php:2 unverified ->get_copy() removed in 5.2' "${R[@]}"
code 'class a extends external_api {}'
expect "--removed: bare global class in a global file" 0 'external_api deprecated in 5.3' "${R[@]}"
code 'namespace local_hello;
use core_external\external_api;
class a extends external_api {}'
expect "--removed: imported namespaced class not the global one" 0 '0 deprecated' "${R[@]}"
code 'namespace local_hello;
use external_api;
class a extends external_api {
    function f(): external_api { return new external_api(); } }'
expect "--removed: global class imported into a namespace" 0 'classes/a.php:4 \\external_api deprecated in 5.3' "${R[@]}"
expect "--removed: imported global class, both uses" 0 '0 removed, 2 deprecated' "${R[@]}"
code 'badges_get_default_issuer();
$i->badges_get_default_issuer();'
expect "--removed: \"method\" with no class is a function too" 0 'classes/a.php:2 badges_get_default_issuer() deprecated in 5.3' "${R[@]}"
expect "--removed: classless method call unverified" 0 '0 removed, 1 deprecated, 1 unverified' "${R[@]}"
code '$r->get_icons();'
expect "--removed: shared method name unverified once, removed wins" 0 '0 removed, 0 deprecated, 1 unverified' "${R[@]}"
expect "--removed: shared method name line" 0 'classes/a.php:2 unverified ->get_icons() removed in 5.2' "${R[@]}"
code '$s = "cron_run(";
$t = <<<EOT
cron_run()
EOT;
?>cron_run()<?php $u = 1;'
expect "--removed: function names in strings, heredocs, inline HTML green" 0 '0 removed, 0 deprecated' "${R[@]}"
expect "--until without --removed rc 2" 2 '' "${U[@]}" --until 5.1
expect "bad --until rc 2" 2 '' "${R[@]}" --until five
B="$T/big"; mkdir -p "$B/classes"; cp "$P/version.php" "$B/"
{ printf '## 5.2\n\n### core\n\n#### Removed\n\n'; for i in $(seq 400); do printf -- '- The `gone_fn%s()` function has been removed. MDL-%s\n' "$i" "$i"; done; } > "$T/big.md"
for f in $(seq 200); do
    { echo '<?php'; for l in $(seq 200); do echo "\$a$l = keep_fn$l(\$b, 'x') + \\core\\c$l::m(\$d); // note $l"; done; } > "$B/classes/f$f.php"
done
echo '<?php gone_fn7();' > "$B/classes/f0.php"
out="$(timeout 5 nice -n 19 "$M" "$B" --upgrading "$T/big.md" --removed 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -q '^classes/f0.php:1 gone_fn7() removed in 5.2 (MDL-7)$' <<<"$out" && grep -q '1 removed' <<<"$out" \
    && echo "PASS 200-file plugin x 400 symbols under 5 s" || { echo "FAIL 200-file plugin (rc $rc): ${out:0:300}"; bad=1; }
code '$c = \core\session\manager::supports_cookies();'
E="$T/envs"; mkdir -p "$E/4.5/www" "$E/5.3/www" "$E/vass/www"
echo '## 9.9' > "$E/4.5/www/UPGRADING.md"; cp "$F" "$E/5.3/www/UPGRADING.md"; cp "$F" "$E/vass/www/UPGRADING.md"
MFIXTURE_ENVS="$E" expect "default UPGRADING = newest non-Vass env" 1 "in $E/5.3/www/UPGRADING.md"
rm "$E/5.3/www/UPGRADING.md"
MFIXTURE_ENVS="$E" expect "no non-Vass UPGRADING.md SKIP rc 3" 3 SKIP
expect "missing --upgrading SKIP rc 3" 3 SKIP --upgrading "$T/none.md"
expect "bad --since rc 2" 2 '' "${U[@]}" --since five
echo "<?php \$plugin->component = 'local_hello';" > "$P/version.php"
expect "no requires rc 2" 2 'requires' "${U[@]}"
H="$T/trees"; for t in old:405 new:503; do
    mkdir -p "$H/${t%%:*}/www/lib/classes/hook/output"
    printf "<?php\n\$branch = '%s';\n" "${t#*:}" > "$H/${t%%:*}/www/version.php"
    printf '<?php\nnamespace core\\hook\\output;\nfinal class before_footer_html_generation {}\n' \
        > "$H/${t%%:*}/www/lib/classes/hook/output/before_footer_html_generation.php"
done
mkdir -p "$H/new/www/course/classes/hook" "$H/new/www/lib/tests/fixtures/classes/hook" "$P/db"
printf '<?php\n/** Hook. */\nnamespace core_course\\hook;\nfinal class before_course_viewed implements described_hook {}\n' \
    > "$H/new/www/course/classes/hook/before_course_viewed.php"
printf '<?php\nnamespace core\\hook;\nclass fixture_only {}\n' > "$H/new/www/lib/tests/fixtures/classes/hook/fixture_only.php"
cat > "$P/db/hooks.php" <<'PHP'
<?php
$callbacks = [
    ['hook' => \core\hook\output\before_footer_html_generation::class, 'callback' => 'x'],
    ['hook' => \core_course\hook\before_course_viewed::class, 'callback' => 'y'],
];
PHP
code 'namespace local_hello;
use core_course\hook\before_course_viewed;
// \core_course\hook\before_course_viewed
$h = \local_hello\hook\mine::class; $f = \core\hook\fixture_only::class;'
req 2024100700
export MOODLE_ENVS="$H"
expect "hook: db/hooks.php reference to a newer hook red" 1 \
    'db/hooks.php:4 \\core_course\\hook\\before_course_viewed added after 4.5$' "${U[@]}"
expect "hook: use statement red" 1 'classes/a.php:3 \\core_course\\hook\\before_course_viewed added after 4.5$' "${U[@]}"
expect "hook: summary 1 class, 2 uses (shared, own, comment, tests/ fixture green)" 1 \
    "1 hook classes in $H/new/www not in $H/old/www: 2 uses" "${U[@]}"
expect "hook: requires = newest branch, no hook check" 0 '' "${U[@]}" --since 5.3
c="$(ls "$T"/cache/moodle-harness/hookidx/*new_www.json 2>/dev/null)"
[ -f "$c" ] && grep -q before_course_viewed "$c" && echo "PASS hook index cached per tree" || { echo "FAIL no hook index cache"; bad=1; }
printf '<?php\nnamespace core\\hook;\nfinal class after_cache {}\n' > "$H/new/www/lib/classes/hook/after_cache.php"
echo '<?php $x = \core\hook\after_cache::class;' > "$P/classes/b.php"
expect "hook: same version.php mtime reuses the cache" 1 '2 uses$' "${U[@]}"
touch -d '+1 min' "$H/new/www/version.php"
expect "hook: newer version.php mtime rebuilds the index" 1 'classes/b.php:1 \\core\\hook\\after_cache added after 4.5' "${U[@]}"
rm "$P/classes/b.php"; mv "$H/old" "$T/old-out"
a="$("$M" "$P" "${U[@]}" 2>&1)"; rc=$?
b="$(MOODLE_ENVS="$T/noenvs" "$M" "$P" "${U[@]}" 2>&1)"
[ "$rc" = 0 ] && [ "$a" = "$b" ] && [ "$(tail -1 <<<"$a")" = "mapicompat: SKIP hook classes: no 4.5 tree (msrc 4.5 --fetch)" ] \
    && [ "$(wc -l <<<"$a")" = 2 ] && grep -Eq "^mapicompat: requires 4.5, [0-9]+ symbols added later in $F: 0 uses, 0 unverified\$" <<<"$a" \
    && echo "PASS hook: no requires tree = named SKIP, rest unchanged" || { echo "FAIL hook SKIP (rc $rc): $a"; bad=1; }
exit $bad
