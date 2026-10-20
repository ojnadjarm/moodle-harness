#!/usr/bin/env bash
# Drive vphp.read/bump on mktemp version.php files: quotes, decimals, comments, CRLF, missing file, bad version.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
S="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
py() { PYTHONPATH="$S" python3 -c "import sys, vphp; $1" "${@:2}"; }
check() { local got; got="$(py "$2" "$T/$3" 2>&1)"; [ "$got" = "$4" ] && ok "$1" || bad "$1: got '$got' want '$4'"; }
rd='i = vphp.read(sys.argv[1]); print(i and (i["component"], i["version"], i["decimal"], i["requires"], i["release"]))'

mkdir -p "$T/single" "$T/double" "$T/comments" "$T/crlf" "$T/none" "$T/noversion"
cat > "$T/single/version.php" <<'PHP'
<?php
defined('MOODLE_INTERNAL') || die();

$plugin->component = 'local_demo';
$plugin->version = 2026102000;
$plugin->requires = 2024100700;
$plugin->release = '1.0';
PHP
cat > "$T/double/version.php" <<'PHP'
<?php
$plugin->version   = 2026102000.05;
$plugin->requires  = 2022112800.00;
$plugin->component = "mod_quest";
$plugin->release   = "v2.1 'beta'";
PHP
cat > "$T/comments/version.php" <<'PHP'
<?php
/*
$plugin->version = 1111111111;
 * Don't read this.
 */
// $plugin->component = 'local_wrong';
# $plugin->requires = 1;
$plugin->component = 'block_real'; // Don't trip on this.
$plugin->version = 2026010100; /* Inline. */
$plugin->requires = 2024042200;
/* Old values:
$plugin->version = 2222222222;
$plugin->release = 'old';
*/
PHP
printf '<?php\r\n$plugin->component = %s;\r\n$plugin->version  =  2026010100.01 ;\r\n$plugin->requires = 2024042200;\r\n' \
    "'local_crlf'" > "$T/crlf/version.php"
printf '<?php\n$plugin->component = %s;\n$plugin->version = %s;\n' "'local_x'" "'2026'" > "$T/noversion/version.php"

check "single quotes" "$rd" single "('local_demo', 2026102000, '', 2024100700, '1.0')"
check "double quotes and decimals" "$rd" double "('mod_quest', 2026102000, '.05', 2022112800, \"v2.1 'beta'\")"
check "commented lines ignored" "$rd" comments "('block_real', 2026010100, '', 2024042200, None)"
check "CRLF read" "$rd" crlf "('local_crlf', 2026010100, '.01', 2024042200, None)"
check "no version.php -> None" "$rd" none "None"
check "quoted version is not numeric" "$rd" noversion "('local_x', None, '', None, None)"

cp "$T/single/version.php" "$T/single.orig"
check "bump int" 'print(vphp.bump(sys.argv[1], 2026102100))' single "('2026102000', '2026102100')"
diff <(sed 's/2026102100/2026102000/' "$T/single/version.php") "$T/single.orig" >/dev/null \
    && ok "bump int: only the number changed" || bad "bump int: other bytes changed"

check "bump decimal keeps .NN width" 'print(vphp.bump(sys.argv[1], 2026102101))' double "('2026102000.05', '2026102101.00')"
grep -q '^\$plugin->version   = 2026102101.00;$' "$T/double/version.php" && ok "bump decimal: spacing kept" \
    || bad "bump decimal: $(grep version "$T/double/version.php")"
check "bump str verbatim" 'print(vphp.bump(sys.argv[1], "2026102101.07"))' double "('2026102101.00', '2026102101.07')"

check "bump skips commented version" 'print(vphp.bump(sys.argv[1], 2026010101))' comments "('2026010100', '2026010101')"
grep -q '^\$plugin->version = 1111111111;$' "$T/comments/version.php" && ok "bump comments: block comment untouched" \
    || bad "bump comments: block comment changed"

check "bump CRLF" 'print(vphp.bump(sys.argv[1], 2026010200))' crlf "('2026010100.01', '2026010200.00')"
[ "$(grep -c $'\r$' "$T/crlf/version.php")" = 4 ] && grep -q $'^\\$plugin->version  =  2026010200.00 ;\r$' "$T/crlf/version.php" \
    && ok "bump CRLF: line endings and spacing kept" || bad "bump CRLF: $(od -c "$T/crlf/version.php" | head -5)"

cp "$T/noversion/version.php" "$T/noversion.orig"
py 'vphp.bump(sys.argv[1], 1)' "$T/noversion" 2>"$T/err" && bad "bump without numeric version accepted" \
    || { grep -q 'no numeric \$plugin->version' "$T/err" && cmp -s "$T/noversion/version.php" "$T/noversion.orig" \
         && ok "bump without numeric version refused, file untouched" || bad "bump refusal: $(cat "$T/err")"; }

[ "$fails" = 0 ] && echo "all vphp cases pass" || { echo "$fails vphp case(s) failed"; exit 1; }
