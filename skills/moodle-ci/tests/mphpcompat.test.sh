#!/usr/bin/env bash
# mphpcompat on a throwaway local_hello: match on 4.1 red / 4.5 green, ?-> on 4.1 red / 4.5 green,
# readonly class on 4.5 red, vendor/ and node_modules/ skipped, quoted requires, usage rc 2.
set -uo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)/scripts/mphpcompat"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
P="$T/local/hello"; mkdir -p "$P/classes" "$P/vendor/x" "$P/node_modules/y"
bad=0
req() { echo "<?php \$plugin->component = 'local_hello'; \$plugin->requires = $1;" > "$P/version.php"; }
code() { printf '<?php\n%s\n' "$1" > "$P/classes/a.php"; }
expect() {  # name rc [grep]
    local out rc; out="$(nice -n 19 "$M" "$P" 2>&1)"; rc=$?
    if [ "$rc" = 3 ] && grep -qE 'SKIP: (composer|cannot create|phpcs failed)' <<<"$out"; then echo "SKIP $1: $out"; exit 0; fi
    if [ "$rc" = "$2" ] && { [ -z "${3:-}" ] || grep -q "$3" <<<"$out"; }; then echo "PASS $1"
    else echo "FAIL $1 (rc $rc, want $2): $out"; bad=1; fi
}
echo '<?php $a = match (1) { 1 => 2 };' | tee "$P/vendor/x/skip.php" > "$P/node_modules/y/skip.php"
code 'function e() { return 1; }'
req 2022112800; expect "clean classes/ + match in vendor/ and node_modules/ on 4.1 green" 0
code 'function f($x) { return match ($x) { 1 => "a", default => "b" }; }'
req 2022112800; expect "match + requires 4.1 red" 1 'classes/a.php:2 .*match'
req 2024100700; expect "match + requires 4.5 green" 0
code 'function g($o) { return $o?->name; }'
req 2022112800; expect "?-> + requires 4.1 red" 1 'classes/a.php:2 '
req "'2022112800'"; expect "quoted requires '4.1' parsed: ?-> red" 1 'PHP 7.4-'
req 2024100700; expect "?-> + requires 4.5 green" 0
code 'readonly class c {}'
expect "readonly class (8.2) + requires 4.5 red" 1 'classes/a.php:2 '
out="$("$M" "$P" --php 8.2 2>&1)" && echo "PASS --php 8.2 overrides" || { echo "FAIL --php 8.2: $out"; bad=1; }
rm "$P/version.php"
"$M" "$P" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && echo "PASS no version.php rc 2" || { echo "FAIL no version.php rc $rc"; bad=1; }
echo "<?php \$plugin->component = 'local_hello';" > "$P/version.php"
out="$("$M" "$P" 2>&1)"; rc=$?
[ "$rc" = 3 ] && grep -q 'SKIP: no \$plugin->requires' <<<"$out" && echo "PASS no requires: SKIP rc 3, reason printed" || { echo "FAIL no requires rc $rc: $out"; bad=1; }
exit $bad
