#!/usr/bin/env bash
# Fixture core tree (attribute + interface hooks) and plugins (legacy, migrated) -> callback hits, in a bwrap sandbox with no network.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cs=$here/../codescan.py
fx=$(mktemp -d)
out=$(mktemp -d)
trap 'rm -rf "$fx" "$out"' EXIT
sandbox=(bwrap --unshare-net --ro-bind / / --dev /dev --proc /proc --bind "$out" "$out")
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

mkdir -p "$fx/core/lib/classes/hook/output" "$fx/core/user/classes/hook" "$fx/core/mod/quiz/classes/hook" \
  "$fx/core/lib/tests/fixtures/classes/hook" "$fx/local_legacy" "$fx/local_done/db" "$fx/local_str/db" "$fx/mod_x"
: > "$fx/UPGRADING.md"
cat > "$fx/core/lib/classes/hook/output/before_footer_html_generation.php" <<'PHP'
<?php
namespace core\hook\output;

#[\core\attribute\label('Footer.')]
#[\core\attribute\hook\replaces_callbacks('before_footer')]
final class before_footer_html_generation {
}
PHP
cat > "$fx/core/lib/classes/hook/after_config.php" <<'PHP'
<?php
namespace core\hook;

use core\attribute;

#[attribute\hook\replaces_callbacks('after_config', 'after_require_login')]
class after_config {
}
PHP
cat > "$fx/core/user/classes/hook/extend_bulk_user_actions.php" <<'PHP'
<?php
namespace core_user\hook;

class extend_bulk_user_actions implements \core\hook\deprecated_callback_replacement {
    public static function get_deprecated_plugin_callbacks(): array {
        return ['bulk_user_actions'];
    }
}
PHP
cat > "$fx/core/mod/quiz/classes/hook/structure_modified.php" <<'PHP'
<?php
namespace mod_quiz\hook;

#[attribute\hook\replaces_callbacks('quiz_structure_modified::callback')]
class structure_modified {
}
PHP
cat > "$fx/core/lib/tests/fixtures/classes/hook/fake.php" <<'PHP'
<?php
namespace fake\hook;

#[\core\attribute\hook\replaces_callbacks('fake_callback')]
class fake {
}
PHP
cat > "$fx/local_legacy/version.php" <<'PHP'
<?php
$plugin->component = 'local_legacy';
PHP
cat > "$fx/local_legacy/lib.php" <<'PHP'
<?php
defined('MOODLE_INTERNAL') || die();

// function local_legacy_after_config() is commented out.
function local_legacy_before_footer() {
    return '';
}

function local_legacy_bulk_user_actions() {
    return [];
}

function local_legacy_after_require_login() {
}

function local_legacy_fake_callback() {
}

function local_legacy_helper() {
    local_other_before_footer();
}
PHP
cat > "$fx/local_done/lib.php" <<'PHP'
<?php
function local_done_before_footer() {
    return '';
}

function local_done_bulk_user_actions() {
    return [];
}
PHP
cat > "$fx/local_done/db/hooks.php" <<'PHP'
<?php
use core_user\hook\extend_bulk_user_actions;

$callbacks = [
    ['hook' => \core\hook\output\before_footer_html_generation::class, 'callback' => [\local_done\hooks::class, 'footer']],
    ['hook' => extend_bulk_user_actions::class, 'callback' => [\local_done\hooks::class, 'bulk']],
];
PHP
cat > "$fx/local_str/lib.php" <<'PHP'
<?php
function local_str_before_footer() {
    return '';
}

function local_str_bulk_user_actions() {
    return [];
}
PHP
cat > "$fx/local_str/db/hooks.php" <<'PHP'
<?php
$callbacks = [
    ['hook' => 'core\hook\output\before_footer_html_generation', 'callback' => 'local_str\hooks::footer'],
    ['hook' => "\\core_user\\hook\\extend_bulk_user_actions", 'callback' => 'local_str\hooks::bulk'],
];
PHP
cat > "$fx/mod_x/version.php" <<'PHP'
<?php
$plugin->component = 'mod_x';
PHP
cat > "$fx/mod_x/lib.php" <<'PHP'
<?php
function x_before_footer() {
    return '';
}

function mod_x_bulk_user_actions() {
    return [];
}
PHP

check "selftest: sandbox has no network" '! "${sandbox[@]}" python3 -c "import socket; socket.create_connection((\"1.1.1.1\", 443), 3)" 2>/dev/null'
check "selftest: fixture tree is read-only in the sandbox" '! "${sandbox[@]}" touch "$fx/local_legacy/x" 2>/dev/null'
"${sandbox[@]}" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import codescan
for k, v in sorted(codescan.hook_map(sys.argv[2]).items()): print(k, v, sep="\t")' "$here/.." "$fx/core" > "$out/map"
check "hook map: attribute (both forms, 2 callbacks) + interface; ::callback and tests/ skipped" 'diff <(printf "after_config\tcore\\\\hook\\\\after_config\nafter_require_login\tcore\\\\hook\\\\after_config\nbefore_footer\tcore\\\\hook\\\\output\\\\before_footer_html_generation\nbulk_user_actions\tcore_user\\\\hook\\\\extend_bulk_user_actions\n") "$out/map"'
"${sandbox[@]}" python3 "$cs" "$fx/local_legacy" --upgrading "$fx/UPGRADING.md" --core "$fx/core" --json "$out/legacy.json" > "$out/legacy.txt"
check "legacy plugin: 3 callback hits with hook class" 'diff <(printf "lib.php:5\tlocal_legacy_before_footer\tcore\\\\hook\\\\output\\\\before_footer_html_generation\nlib.php:9\tlocal_legacy_bulk_user_actions\tcore_user\\\\hook\\\\extend_bulk_user_actions\nlib.php:13\tlocal_legacy_after_require_login\tcore\\\\hook\\\\after_config\n") <(python3 -c "import json,sys; [print(h[\"file\"]+\":\"+str(h[\"line\"]),h[\"name\"],h[\"hook\"],sep=\"\t\") for h in json.load(open(sys.argv[1]))[\"hits\"]]" "$out/legacy.json")'
check "legacy plugin: deprecated severity, hours in summary" 'grep -qx "local_legacy: 3 hits · removed 0 · deprecated 3 · estimate 0.75 h" "$out/legacy.txt"'
check "legacy plugin: report line names the hook" 'grep -q "^deprecated lib.php:5  local_legacy_before_footer  (hook core.hook.output.before_footer_html_generation)$" "$out/legacy.txt"'
"${sandbox[@]}" python3 "$cs" "$fx/local_done" --upgrading "$fx/UPGRADING.md" --core "$fx/core" > "$out/done.txt"
check "migrated plugin (FQN and use-imported short name): 0 hits" 'grep -qx "local_done: 0 hits · removed 0 · deprecated 0 · estimate 0 h" "$out/done.txt"'
"${sandbox[@]}" python3 "$cs" "$fx/local_str" --upgrading "$fx/UPGRADING.md" --core "$fx/core" > "$out/str.txt"
check "migrated plugin (string-form hook names): 0 hits" 'grep -qx "local_str: 0 hits · removed 0 · deprecated 0 · estimate 0 h" "$out/str.txt"'
"${sandbox[@]}" python3 "$cs" "$fx/mod_x" --upgrading "$fx/UPGRADING.md" --core "$fx/core" > "$out/mod.txt"
check "mod_ plugin: short and full prefix both flagged" '[ "$(grep -c "^deprecated lib.php:[26]  \(x_before_footer\|mod_x_bulk_user_actions\)  (hook " "$out/mod.txt")" -eq 2 ] && grep -qx "mod_x: 2 hits · removed 0 · deprecated 2 · estimate 0.5 h" "$out/mod.txt"'
"${sandbox[@]}" python3 "$cs" "$fx/local_legacy" --upgrading "$fx/UPGRADING.md" --core "$fx/nonexistent" > "$out/nocore.txt" 2> "$out/nocore.err"
check "no hook map (bad --core): warning on stderr" 'grep -q "^warning: no hook classes found under .*nonexistent" "$out/nocore.err"'
exit $fail
