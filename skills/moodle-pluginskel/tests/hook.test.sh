#!/usr/bin/env bash
# Drive hook.py on mktemp plugins against the fixture core: class and callback resolution, merge, notation, notes, refusal.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
D="$(cd "$(dirname "$0")/.." && pwd)"
H="$D/hook.py"; CORE="$D/tests/fixtures/hooks-core"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
version() { sed -n 's/^\$plugin->version = \([0-9]*\);/\1/p' "$P/version.php"; }
lint() { for f in "$P/classes/hook_callbacks.php" "$P/db/hooks.php"; do
    php -l "$f" >/dev/null 2>&1 || { bad "$1 php -l $f"; return; }; done; ok "$1 php -l clean"; }

plugin() {
    P="$T/$1"; mkdir -p "$P"
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
\$plugin->requires = $3;
EOF
    cat > "$P/lib.php" <<EOF
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
 * Library functions.
 *
 * @package    $2
 * @copyright  2026 onwards, Example Author <author@example.com>
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

/**
 * Legacy callback.
 *
 * @return string
 */
function $2_$4() {
    return '';
}
EOF
}

grep -q '^from codescan import hook_map' "$H" && ! grep -q 'def hook_map' "$H" \
    && ok "hook_map imported from codescan, not copied" || bad "hook_map not imported from codescan"

plugin demo local_demo 2024100700 before_standard_html_head
python3 "$H" "$P" '\core_user\hook\after_login_completed::class' --core "$CORE" >"$T/out" 2>&1 || bad "class rc: $(cat "$T/out")"
v1="$(version)"
grep -q "'hook' => \\\\core_user\\\\hook\\\\after_login_completed::class," "$P/db/hooks.php" \
    && grep -q "'callback' => \[\\\\local_demo\\\\hook_callbacks::class, 'after_login_completed'\]," "$P/db/hooks.php" \
    && grep -q '^        \\core_user\\hook\\after_login_completed $hook$' \
        "$P/classes/hook_callbacks.php" && grep -q '^namespace local_demo;' "$P/classes/hook_callbacks.php" \
    && ok "hook class: db/hooks.php + hook_callbacks.php created" || bad "hook class output: $(cat "$T/out")"
grep -q '\$hook,$' "$P/classes/hook_callbacks.php" && bad "trailing parameter comma needs PHP 8.0" \
    || ok "no trailing parameter comma (PHP 7.4 safe)"
[ "$v1" -gt 2026010100 ] && [ "$v1" -ge "$(date +%Y%m%d)00" ] && ok "version bumped to $v1" || bad "version after class: $v1"
lint "class"

python3 "$H" "$P" local_demo_before_standard_html_head --core "$CORE" >"$T/out" 2>&1 || bad "callback rc: $(cat "$T/out")"
grep -q 'hook: core\\hook\\output\\before_standard_head_html_generation' "$T/out" \
    && ok "callback name resolves to before_standard_head_html_generation" || bad "callback resolve: $(cat "$T/out")"
grep -q 'after_login_completed::class' "$P/db/hooks.php" && grep -q 'before_standard_head_html_generation::class' "$P/db/hooks.php" \
    && [ "$(grep -c "'hook' =>" "$P/db/hooks.php")" = 2 ] && ok "merge keeps the existing entry" || bad "merge: $(cat "$P/db/hooks.php")"
[ "$(grep -c 'public static function' "$P/classes/hook_callbacks.php")" = 2 ] \
    && grep -q 'Port local_demo_before_standard_html_head() from lib.php here.' "$P/classes/hook_callbacks.php" \
    && ok "method appended with the legacy pointer" || bad "methods: $(cat "$P/classes/hook_callbacks.php")"
grep -q 'local_demo_before_standard_html_head() in lib.php can be removed' "$T/out" \
    && grep -q 'function local_demo_before_standard_html_head' "$P/lib.php" && ok "requires 4.5: 'can be removed' printed, lib.php kept" \
    || bad "removable note: $(cat "$T/out")"
v2="$(version)"; [ "$v2" -gt "$v1" ] && ok "version bumped again to $v2" || bad "second bump: $v1 -> $v2"
lint "merge"

cp "$P/db/hooks.php" "$T/hooks.before"
python3 "$H" "$P" before_standard_html_head --core "$CORE" >"$T/out" 2>&1 && bad "duplicate accepted" \
    || { grep -q 'already registered' "$T/out" && cmp -s "$P/db/hooks.php" "$T/hooks.before" && [ "$(version)" = "$v2" ] \
        && ok "already-registered hook refused, nothing written" || bad "refusal: $(cat "$T/out")"; }
python3 "$H" "$P" before_standard_html_heed --core "$CORE" >"$T/out" 2>&1 && bad "unknown callback accepted" \
    || { grep -q 'nearest: before_standard_html_head' "$T/out" && ok "unknown callback refused with the nearest name" \
        || bad "unknown callback: $(cat "$T/out")"; }

if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
    cc="$(nice -n 19 "$MPC" codechecker "$P" 2>&1)"; rc=$?
    if grep -qE '\| (ERROR|WARNING) \|' <<<"$cc" || [ "$rc" -ne 0 ]; then bad "codechecker rc=$rc"; grep -E '\| (ERROR|WARNING) \|' <<<"$cc" | head -20
    else ok "codechecker 0 errors, 0 warnings"; fi
else
    echo "SKIP codechecker: moodle-plugin-ci absent"
fi

plugin old local_old 2023100900 after_config
python3 "$H" "$P" after_config --core "$CORE" >"$T/out" 2>&1 || bad "4.3 rc: $(cat "$T/out")"
grep -q "'callback' => 'local_old\\\\hook_callbacks::after_config'," "$P/db/hooks.php" \
    && ok "requires 4.3: string callback notation" || bad "4.3 notation: $(cat "$P/db/hooks.php")"
grep -q 'keep local_old_after_config() in lib.php' "$T/out" && ok "requires 4.3: legacy kept with a note" \
    || bad "keep note: $(cat "$T/out")"
lint "4.3"

plugin legacy local_legacy 2024100700 after_config
mkdir -p "$P/db"; cat > "$P/db/hooks.php" <<'EOF'
<?php
$callbacks = array(
    array(
        'hook' => \core\hook\after_config::class,
        'callback' => 'local_legacy\hook_callbacks::after_config',
    ),
);
EOF
python3 "$H" "$P" '\core_user\hook\after_login_completed' --core "$CORE" >"$T/out" 2>&1 || bad "array( rc: $(cat "$T/out")"
grep -q "^    array($" "$P/db/hooks.php" && [ "$(grep -c '^    array($' "$P/db/hooks.php")" = 2 ] \
    && grep -q "'callback' => array(\\\\local_legacy\\\\hook_callbacks::class, 'after_login_completed')," "$P/db/hooks.php" \
    && ! grep -q '\[' "$P/db/hooks.php" && php -l "$P/db/hooks.php" >/dev/null 2>&1 \
    && ok "array( style db/hooks.php gets an array( entry" || bad "array( merge: $(cat "$P/db/hooks.php")"

plugin nophp local_nophp 2024100700 after_config
mkdir -p "$T/bin"; ln -sf "$(command -v python3)" "$T/bin/python3"
PATH="$T/bin" python3 "$H" "$P" '\core_user\hook\after_login_completed' --core "$CORE" >"$T/out" 2>"$T/err" || bad "no-php rc: $(cat "$T/err")"
grep -q 'warning: php not on PATH' "$T/err" && ! grep -q 'warning' "$T/out" \
    && ok "php-missing warning on stderr, stdout clean" || bad "warning stream: out=$(cat "$T/out") err=$(cat "$T/err")"

(cd "$D" && python3 -c 'import hook; print(hook.merge_hooks("<?php\n$functions = [\n];\n", "functions", "    [],\n", "x"), end="")') >"$T/out" 2>&1
grep -q '^\$functions = \[$' "$T/out" && grep -q '^    \[\],$' "$T/out" \
    && ok "merge_hooks takes the array name" || bad "merge_hooks name: $(cat "$T/out")"

i=0
for start in '$callbacks = array (' '    $callbacks = [' '$callbacks=['; do
    i=$((i + 1)); plugin "merge$i" "local_merge$i" 2024100700 after_config
    close="]"; [ "${start%(}" != "$start" ] && close=")"
    mkdir -p "$P/db"; printf '<?php\n%s\n    [\n        %s\n        %s\n    ],\n%s;\n' "$start" \
        "'hook' => \\core\\hook\\after_config::class," "'callback' => 'local_old\\hook_callbacks::after_config'," \
        "$close" > "$P/db/hooks.php"
    python3 "$H" "$P" '\core_user\hook\after_login_completed' --core "$CORE" >"$T/out" 2>&1 || bad "'$start' rc: $(cat "$T/out")"
    grep -q "local_old\\\\hook_callbacks::after_config" "$P/db/hooks.php" && grep -q 'after_login_completed' "$P/db/hooks.php" \
        && [ "$(grep -c 'callbacks *=' "$P/db/hooks.php")" = 1 ] && php -l "$P/db/hooks.php" >/dev/null 2>&1 \
        && ok "'$start' merge keeps the old entry, one assignment, php -l" || bad "'$start' merge: $(cat "$P/db/hooks.php")"
done
plugin merge4 local_merge4 2024100700 after_config
mkdir -p "$P/db"; printf '<?php\n$callbacks = array_merge([], [\n    %s\n]);\n' \
    "['hook' => \\core\\hook\\after_config::class, 'callback' => 'local_old\\hook_callbacks::after_config']," > "$P/db/hooks.php"
before="$(md5sum "$P/db/hooks.php" "$P/version.php")"
python3 "$H" "$P" '\core_user\hook\after_login_completed' --core "$CORE" >"$T/out" 2>&1 && bad "unparseable \$callbacks accepted" \
    || { grep -q "$P/db/hooks.php: \$callbacks is set" "$T/out" && [ "$before" = "$(md5sum "$P/db/hooks.php" "$P/version.php")" ] \
        && php -l "$P/db/hooks.php" >/dev/null 2>&1 && ok "unparseable \$callbacks refused naming the file, nothing written" \
        || bad "unparseable refusal: $(cat "$T/out")"; }

core() { mkdir -p "$1"; cp -r "$CORE/." "$1/"; printf "<?php\n\$branch   = '%s';\n" "$2" > "$1/version.php"; }
core "$T/envs/5.3/www/public" 503
core "$T/cache/moodle-harness/src/MOODLE_405_STABLE/public" 405
dc() { (cd "$D" && MOODLE_ENVS="$T/envs" XDG_CACHE_HOME="$1" python3 -c "import hook; print(hook.default_core($2))") >"$T/out" 2>"$T/err"; }
dc "$T/cache" 2024100700
[ "$(cat "$T/out")" = "$T/cache/moodle-harness/src/MOODLE_405_STABLE/public" ] && [ ! -s "$T/err" ] \
    && ok "default_core(requires 4.5) takes the msrc 4.5 tree" || bad "requires core: $(cat "$T/out" "$T/err")"
dc "$T/nocache" 2024100700
[ "$(cat "$T/out")" = "$T/envs/5.3/www/public" ] && grep -q 'warning: no 4.5 tree.*msrc 4.5 --fetch.*; using ' "$T/err" \
    && ok "no 4.5 tree: newest env with a warning naming 4.5" || bad "fallback: $(cat "$T/out" "$T/err")"
dc "$T/nocache" ""
[ "$(cat "$T/out")" = "$T/envs/5.3/www/public" ] && [ ! -s "$T/err" ] \
    && ok "default_core() without requires: newest env, no warning (event.py)" || bad "no requires: $(cat "$T/out" "$T/err")"
plugin auto local_auto 2024100700 before_standard_html_head
MOODLE_ENVS="$T/envs" XDG_CACHE_HOME="$T/cache" python3 "$H" "$P" before_standard_html_head >"$T/out" 2>"$T/err" \
    && grep -q 'hook: core\\hook\\output\\before_standard_head_html_generation' "$T/out" && [ ! -s "$T/err" ] \
    && ok "no --core: callback resolved in the requires tree" || bad "no --core: $(cat "$T/out" "$T/err")"

plugin strict local_strict 2024100700 after_config
before="$(md5sum "$P/version.php")"
MOODLE_ENVS="$T/envs" XDG_CACHE_HOME="$T/cache" python3 "$H" "$P" '\core_course\hook\before_course_viewed' >"$T/out" 2>&1 \
    && bad "hook class missing from the requires tree accepted" \
    || { grep -q 'core_course\\hook\\before_course_viewed not found in the Moodle 4.5 tree .*--force' "$T/out" \
        && [ "$before" = "$(md5sum "$P/version.php")" ] && [ ! -e "$P/db" ] && [ ! -e "$P/classes" ] \
        && ok "class missing from the requires tree: rc 1 names class and 4.5, nothing written" || bad "strict: $(cat "$T/out")"; }
MOODLE_ENVS="$T/envs" XDG_CACHE_HOME="$T/cache" python3 "$H" "$P" '\core_course\hook\before_course_viewed' --force >"$T/out" 2>"$T/err" \
    && grep -q 'warning: core_course\\hook\\before_course_viewed not found in ' "$T/err" \
    && grep -q 'before_course_viewed::class' "$P/db/hooks.php" \
    && ok "--force writes the missing class with a warning" || bad "--force: $(cat "$T/out" "$T/err")"
plugin strictcore local_strictcore 2024100700 after_config
python3 "$H" "$P" '\core_course\hook\before_course_viewed' --core "$T/envs/5.3/www/public" >"$T/out" 2>&1 \
    && bad "--core: missing class accepted" \
    || { grep -q 'not found in the Moodle 5.3 tree' "$T/out" && [ ! -e "$P/db" ] \
        && ok "--core tree: missing class rc 1 names 5.3" || bad "--core strict: $(cat "$T/out")"; }
plugin notree local_notree 2024100700 after_config
MOODLE_ENVS="$T/envs" XDG_CACHE_HOME="$T/nocache" python3 "$H" "$P" '\core_course\hook\before_course_viewed' >"$T/out" 2>"$T/err" \
    && grep -q 'warning: no 4.5 tree' "$T/err" && grep -q 'warning: core_course\\hook\\before_course_viewed not found in ' "$T/err" \
    && [ -e "$P/db/hooks.php" ] && ok "no requires tree: fallback env only warns, as before" || bad "no tree: $(cat "$T/out" "$T/err")"

! grep -q 'REFUSED_ENVS' "$H" && grep -q 'msrc\.REFUSED' "$H" && ok "env scan uses msrc's REFUSED, no second list" \
    || bad "hook.py keeps its own refused-env list"
core "$T/refused/4.5/www/public" 405; core "$T/refused/vass/www/public" 405
(cd "$D" && MOODLE_ENVS="$T/refused" XDG_CACHE_HOME="$T/nocache" python3 -c "import hook; print(hook.default_core())") >"$T/out" 2>&1
[ "$(cat "$T/out")" = "None" ] && ok "fallback scan skips the 4.5 env" || bad "refused env used: $(cat "$T/out")"

[ "$fails" -eq 0 ] && echo "PASS hook.test.sh" || echo "FAIL hook.test.sh: $fails"
[ "$fails" -eq 0 ]
