#!/usr/bin/env bash
# mversion on throwaway local_x fixtures: bump (today, +1, XX 99 -> next day, month end), resolve (version-only
# conflict -> max+1, other conflicts kept rc 1, diff3 style), check (10 digits, below savepoint, not ascending, $result args), bad date, CRLF kept, usage.
set -uo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)/scripts/mversion"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
P="$T/local/x"; mkdir -p "$P/db" "$P/classes"
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
ver() { grep -o 'version = [0-9.]*' "$P/version.php" | cut -d' ' -f3; }
setv() { printf "<?php\n\$plugin->component = 'local_x';\n\$plugin->version = %s; // Bumped.\n\$plugin->requires = 2024100700;\n" "$1" > "$P/version.php"; }
export MVERSION_TODAY=20261020

setv 2026081001; (cd "$P/classes" && "$M" bump >/dev/null)
[ "$(ver)" = 2026102000 ] && ok "bump older -> today 00 (walks up from classes/)" || bad "bump today: $(ver)"
grep -q "Bumped." "$P/version.php" && ok "bump keeps the rest of the line" || bad "bump comment lost"
setv 2026102003; "$M" bump "$P" >/dev/null
[ "$(ver)" = 2026102004 ] && ok "bump same day -> +1" || bad "bump +1: $(ver)"
setv 2026102099; "$M" bump "$P" >/dev/null
[ "$(ver)" = 2026102100 ] && ok "bump XX 99 -> next day 00" || bad "bump 99: $(ver)"
setv 2026103199; MVERSION_TODAY=20261031 "$M" bump "$P" >/dev/null
[ "$(ver)" = 2026110100 ] && ok "bump 99 on month end -> 1st of next month" || bad "bump month end: $(ver)"
v=$(ver); [ ${#v} -eq 10 ] && ok "bump result 10 digits" || bad "bump digits: $v"

cat > "$P/version.php" <<'EOF'
<?php
$plugin->component = 'local_x';
<<<<<<< HEAD
$plugin->version = 2026081001;
=======
$plugin->version = 2026101300;
>>>>>>> feature
$plugin->requires = 2024100700;
EOF
out=$("$M" resolve "$P"); rc=$?
[ $rc -eq 0 ] && [ "$(ver)" = 2026101301 ] && ! grep -q '^[<=>]\{7\}' "$P/version.php" \
  && ok "resolve version-only conflict -> max+1 ($out)" || bad "resolve: rc $rc $(ver)"
cat > "$P/version.php" <<'EOF'
<?php
<<<<<<< HEAD
$plugin->version = 2026102099;
||||||| base
$plugin->version = 2026081000;
=======
$plugin->version = 2026101300;
>>>>>>> feature
<<<<<<< HEAD
$plugin->release = '1.1';
=======
$plugin->release = '1.2';
>>>>>>> feature
EOF
out=$("$M" resolve "$P"); rc=$?
[ $rc -eq 1 ] && [ "$(ver)" = 2026102100 ] && echo "$out" | grep -q 'CONFLICT version.php:3' \
  && grep -q "release = '1.2'" "$P/version.php" && [ "$(grep -c '^<<<<<<<' "$P/version.php")" -eq 1 ] \
  && ok "resolve diff3 + 99 overflow, other conflict kept and named rc 1" || bad "resolve mixed: rc $rc $(ver) $out"
"$M" bump "$P" >/dev/null 2>&1; [ $? -eq 1 ] && ok "bump refuses conflict markers" || bad "bump on conflict"
cat > "$P/version.php" <<'EOF'
<?php
<<<<<<< HEAD
$plugin->version = 2026081001;
$plugin->requires = 2024100700;
=======
$plugin->version = 2026101300;
$plugin->requires = 2025041400;
>>>>>>> feature
EOF
"$M" resolve "$P" >/dev/null; [ $? -eq 1 ] && grep -q 2026081001 "$P/version.php" \
  && ok "resolve leaves a conflict that also changes requires" || bad "resolve mixed block"

setv 2026102000
cat > "$P/db/upgrade.php" <<'EOF'
<?php
function xmldb_local_x_upgrade($oldversion) {
    if ($oldversion < 2026090100) {
        upgrade_plugin_savepoint(true, 2026090100, 'local', 'x');
    }
    if ($oldversion < 2026101300) {
        upgrade_plugin_savepoint(true, 2026101300, 'local', 'x');
    }
    return true;
}
EOF
out=$("$M" check "$P"); [ $? -eq 0 ] && ok "check green ($out)" || bad "check green: $out"
setv 2026100100; out=$("$M" check "$P"); [ $? -eq 1 ] && echo "$out" | grep -q 'savepoint 2026101300' \
  && ok "check version below savepoint FAILs" || bad "check below: $out"
setv 2026102000; sed -i 's/true, 2026090100/true, 2026110100/' "$P/db/upgrade.php"
out=$("$M" check "$P"); [ $? -eq 1 ] && echo "$out" | grep -q 'not above' \
  && ok "check non-ascending savepoints FAIL" || bad "check order: $out"
cat > "$P/db/upgrade.php" <<'EOF'
<?php
function xmldb_local_x_upgrade($oldversion) {
    $result = true;
    upgrade_mod_savepoint($result, 2026090100, 'x');
    upgrade_plugin_savepoint(true, 2026100100, 'local', 'x');
    upgrade_block_savepoint($x, 2026110100, 'x');
    return $result;
}
EOF
setv 2026110100; out=$("$M" check "$P"); [ $? -eq 0 ] && echo "$out" | grep -q ', 3 savepoints' \
  && ok "check counts \$result, true and \$x savepoint arguments" || bad "check \$result: $out"
setv 2026083299; out=$("$M" bump "$P" 2>&1); rc=$?
[ $rc -eq 2 ] && [ "$out" = "mversion: 2026083299 is not YYYYMMDDXX" ] \
  && ok "bump on a bad date: clean rc 2" || bad "bad date: rc $rc $out"
printf '<?php\r\n$plugin->component = '"'local_x'"';\r\n$plugin->version = 2026101300;\r\n' > "$P/version.php"
"$M" bump "$P" >/dev/null; [ "$(grep -c $'\r$' "$P/version.php")" -eq 3 ] && [ "$(ver)" = 2026102000 ] \
  && ok "bump keeps CRLF line endings" || bad "CRLF lost: $(od -c "$P/version.php" | head -3)"
printf '<?php\r\n<<<<<<< HEAD\r\n$plugin->version = 2026081001;\r\n=======\r\n$plugin->version = 2026101300;\r\n>>>>>>> f\r\n' > "$P/version.php"
"$M" resolve "$P" >/dev/null; [ $? -eq 0 ] && [ "$(cat "$P/version.php")" = $'<?php\r\n$plugin->version = 2026101301;\r' ] \
  && ok "resolve keeps CRLF line endings" || bad "resolve CRLF: $(od -c "$P/version.php" | head -3)"
rm "$P/db/upgrade.php"; setv 202610200; out=$("$M" check "$P"); [ $? -eq 1 ] && echo "$out" | grep -q '10 digits' \
  && ok "check 9-digit version FAILs" || bad "check digits: $out"

"$M" >/dev/null 2>&1; [ $? -eq 2 ] && ok "usage rc 2" || bad "usage"
"$M" check "$T/nowhere" >/dev/null 2>&1; [ $? -eq 2 ] && ok "no version.php rc 2" || bad "no version.php"
"$M" --help | grep -q resolve && ok "--help names resolve" || bad "--help"
exit $fail
