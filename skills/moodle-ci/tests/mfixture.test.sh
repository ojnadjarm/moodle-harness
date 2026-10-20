#!/usr/bin/env bash
# mfixture against a fake docker and a throwaway envs dir: no real container or env is touched.
set -uo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)/scripts/mfixture"
T="$(mktemp -d "${TMPDIR:-/tmp}/mfixture-test-XXXX")"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state" "$T/tmp" "$T/run" "$T/src/t917b" "$T/envs/5.2/www/public/local" "$T/envs/4.5/www" "$T/src/t429fix"
mkdir -p "$T/envs/5.2/www/vendor"; touch "$T/envs/5.2/www/config.php"
ln -s "$T/envs/4.5" "$T/envs/5.3"
printf "<?php\n\$plugin->component = 'local_t429fix';\n\$plugin->version = 2026101900;\n" > "$T/src/t429fix/version.php"
printf "<?php\n\$plugin->component = 'local_t917b';\n\$plugin->version = 2026102000;\n" > "$T/src/t917b/version.php"
cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
S="$T/state"; L="$T/envs/5.2/www/public/local"
echo "\$*" >> "$T/calls"
case "\$1" in
    ps) echo fake-app; exit 0 ;;
    inspect) printf '%s\t%s\n' "$T/envs/5.2/www" /var/www/html; exit 0 ;;
esac
[ "\$3" = sh ] && exit 0
[ "\$3" = ps ] && { printf '  PID ELAPSED COMMAND\n    1 01:00 apache2 -DFOREGROUND\n'; [ -n "\${PHP_BUSY:-}" ] && echo '   42 00:07 php admin/cli/upgrade.php --non-interactive'; exit 0; }
cmd="\$5"
pending() { [ "\$(ls "\$L" | sort)" != "\$(ls "\$S" | sort)" ]; }
case "\$cmd" in
    *get_plugin_types*) [ -n "\${PARSE:-}" ] && { echo 'PHP Parse error:  syntax error, unexpected end of file in /var/www/html/config.php on line 9'; exit 255; }; [ -n "\${UPGRADING:-}" ] && { echo '!!! Site is being upgraded, please retry later. !!!'; exit 1; }; echo /var/www/html/public/local ;;
    *get_config*) [ -e "\$S/t429fix" ] && echo 2026101900 ;;
    *upgrade.php\ --is-pending*) pending && exit 2 ;;
    *upgrade.php\ --non-interactive*) [ -n "\${EXCEPTION:-}" ] && { printf 'Default exception handler: Error reading from database Debug: boom\n!!! Error reading from database !!!\n'; exit 1; }; [ -n "\${FATAL:-}" ] && { echo 'PHP Fatal error:  Uncaught Error: boom in /var/www/html/lib/x.php:3'; exit 255; }; [ -n "\${FAIL_UPGRADE:-}" ] && exit 1; rm -f "\$S"/*; for d in "\$L"/*; do [ -e "\$d" ] && touch "\$S/\${d##*/}"; done ;;
    *uninstall_plugins.php*) [ -z "\${FAIL_UNINSTALL:-}" ] && rm -f "\$S/t429fix" ;;
    *purge_caches.php*) ;;
    *) echo "fake docker: unexpected \$cmd" >&2; exit 9 ;;
esac
exit 0
EOF
chmod +x "$T/bin/docker"
export PATH="$T/bin:$PATH" MFIXTURE_ENVS="$T/envs" TMPDIR="$T/tmp" XDG_STATE_HOME="$T/xdg" XDG_RUNTIME_DIR="$T/run"
F="$T/envs/5.2/www/public/local/t429fix"
bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got $1)"; bad=1; fi; }
run() { "$M" "$@" >/dev/null 2>&1; echo $?; }
logs() { ls "$T/xdg/moodle-harness/logs/local_t429fix" 2>/dev/null | grep -c '^mfixture-.*\.log$'; }

check "$(run add 4.5 "$T/src/t429fix")" 3 "refuses 4.5"
check "$(run add vass "$T/src/t429fix")" 3 "refuses vass"
check "$(run add 4.6 "$T/src/t429fix")" 3 "refuses env outside the allowlist"
check "$(run add 5.3 "$T/src/t429fix")" 3 "refuses an allowed name that resolves to 4.5"
check "$([ -e "$T/calls" ] && echo called || echo none)" none "refusals never call docker"
check "$(logs)" 0 "refusals write no log"

check "$(run add 5.2 "$T/src/t429fix")" 0 "add exits 0"
check "$(logs)" 1 "add writes one log via mlog_new mfixture <component>"
check "$([ -f "$F/version.php" ] && [ -e "$T/state/t429fix" ] && echo yes)" yes "add copies and installs"
check "$(grep -c 'upgrade.php --non-interactive' "$T/calls")" 1 "add runs upgrade.php --non-interactive"
check "$(run add 5.2 "$T/src/t429fix")" 1 "add refuses an existing fixture"
check "$(run rm 5.2 local_t429fix)" 0 "rm exits 0"
check "$([ -e "$F" ] || [ -e "$T/state/t429fix" ] && echo left || echo gone)" gone "rm uninstalls and deletes the dir"
check "$(grep -c 'uninstall_plugins.php --plugins=local_t429fix --run' "$T/calls")" 1 "rm runs uninstall_plugins.php --run"

check "$(FAIL_UPGRADE=1 run add 5.2 "$T/src/t429fix")" 1 "failed upgrade exits 1"
check "$([ -e "$F" ] && echo left || echo gone)" gone "failed upgrade removes the fixture"

run add 5.2 "$T/src/t429fix" >/dev/null
check "$(FAIL_UNINSTALL=1 run rm 5.2 local_t429fix)" 1 "rm exits 1 when uninstall fails"
check "$([ -e "$F" ] && echo kept)" kept "rm keeps the dir of a still-installed plugin"
run rm 5.2 local_t429fix >/dev/null

check "$(run with 5.2 "$T/src/t429fix" -- test -f "$F/version.php")" 0 "with runs the command while installed"
check "$([ -e "$F" ] || [ -e "$T/state/t429fix" ] && echo left || echo gone)" gone "with removes the fixture on exit"
check "$(run with 5.2 "$T/src/t429fix" -- false)" 1 "with returns the command's exit code"
check "$([ -e "$F" ] && echo left || echo gone)" gone "with removes the fixture after a failing command"
check "$(run with 5.2 "$T/src/t429fix" -- sh -c 'kill -TERM $PPID; sleep 0.2')" 130 "with exits 130 on TERM"
check "$([ -e "$F" ] || [ -e "$T/state/t429fix" ] && echo left || echo gone)" gone "with removes the fixture on TERM"
check "$(run status 5.2) $("$M" status 5.2 2>&1 | tr '\n' '|')" "0 lock: free|php processes in fake-app: none|" "status: free env exits 0"
check "$(PHP_BUSY=1 run status 5.2) $(PHP_BUSY=1 "$M" status 5.2 2>&1 | grep -c 'php admin/cli/upgrade.php')" "1 1" "status: a php process in the container is busy, exit 1"
hold() { rm -f "$T/held"; "$M" with 5.2 "$T/src/t429fix" -- sh -c "touch '$T/held'; sleep $1" >/dev/null 2>&1 & A=$!; for _ in $(seq 50); do [ -e "$T/held" ] && break; sleep 0.1; done; }
hold 2
check "$(run status 5.2) $("$M" status 5.2 | grep -c "^lock: pid $A, [0-9]*s, mfixture with 5.2 ")" "1 1" "status: lock holder pid, age and command, exit 1"
check "$(run --no-wait add 5.2 "$T/src/t917b") $([ -e "$T/envs/5.2/www/public/local/t917b" ] && echo copied || echo untouched)" "4 untouched" "--no-wait on a locked env exits 4 and changes nothing"
check "$(MFIXTURE_WAIT=0.3 run add 5.2 "$T/src/t917b")" 4 "MFIXTURE_WAIT timeout exits 4"
o="$("$M" with 5.2 "$T/src/t917b" -- sh -c "[ ! -e '$F' ] && echo second-ran-after-first" 2>&1; echo "rc=$?")"; wait "$A"; ra=$?
check "$(grep -c "^mfixture: waiting for pid $A, " <<<"$o") $(grep -c second-ran-after-first <<<"$o") ${o##*$'\n'} $ra" "1 1 rc=0 0" "contention: the second run waits for the first, then both succeed"
check "$(ls "$T/envs/5.2/www/public/local" | wc -l) $(ls "$T/state" | wc -l)" "0 0" "contention: both fixtures removed"
o="$(UPGRADING=1 "$M" add 5.2 "$T/src/t429fix" 2>&1; echo "rc=$?")"
check "$(grep -c 'Site is being upgraded' <<<"$o") $(grep -c 'unknown plugin type' <<<"$o") ${o##*$'\n'}" "1 0 rc=1" "a Site is being upgraded error is printed, not unknown plugin type"
o="$(FATAL=1 "$M" add 5.2 "$T/src/t429fix" 2>&1; echo "rc=$?")"
check "$(grep -c '^mfixture: PHP Fatal error:  Uncaught Error: boom' <<<"$o") ${o##*$'\n'} $([ -e "$F" ] && echo left || echo gone)" "1 rc=1 gone" "a PHP fatal error in the upgrade is printed"
o="$(PARSE=1 "$M" add 5.2 "$T/src/t429fix" 2>&1; echo "rc=$?")"
check "$(grep -c '^mfixture: PHP Parse error:  syntax error' <<<"$o") $(grep -c 'unknown plugin type' <<<"$o") ${o##*$'\n'}" "1 0 rc=1" "a PHP Parse error is printed, not unknown plugin type"
o="$(EXCEPTION=1 "$M" add 5.2 "$T/src/t429fix" 2>&1; echo "rc=$?")"
check "$(grep -c '^mfixture: !!! Error reading from database !!!$' <<<"$o") ${o##*$'\n'} $([ -e "$F" ] && echo left || echo gone)" "1 rc=1 gone" "a !!! exception !!! line in the upgrade is printed"
o="$("$M" with 5.2 "$T/src/t429fix" -- sh -c 'echo "comp=$MFIXTURE_COMP dir=$MFIXTURE_DIR"; test -f "$MFIXTURE_DIR/version.php"' 2>/dev/null; echo "rc=$?")"
check "$(grep -cxF "comp=local_t429fix dir=$F" <<<"$o") ${o##*$'\n'}" "1 rc=0" "with exports MFIXTURE_COMP and MFIXTURE_DIR (host path of the copy)"
for h in --help -h; do
    o="$("$M" $h 2>&1; echo "rc=$?")"
    check "$(grep -c '^usage: mfixture' <<<"$o") $(grep -c '^Examples:' <<<"$o") $(grep -c '^Exit:' <<<"$o") $(grep -c 'status <env>' <<<"$o") $(grep -c 'MFIXTURE_DIR' <<<"$o") $(grep -c 'MFIXTURE_COMP' <<<"$o") ${o##*$'\n'}" "1 1 1 2 1 1 rc=0" "$h: usage, examples, exit codes, status, MFIXTURE_DIR/COMP, rc 0"
done
n="$(logs)"; c="$(wc -l < "$T/calls")"; run --help >/dev/null
check "$(( $(wc -l < "$T/calls") - c ))" 0 "--help never calls docker"
run >/dev/null; run add 4.5 "$T/src/t429fix" >/dev/null
check "$(ls "$T/xdg/moodle-harness/logs" | tr '\n' ' ')$(( $(logs) - n ))" "local_t429fix local_t917b 0" "usage errors and refusals add no log"
check "$(find "$T/tmp" -mindepth 1 | wc -l)" 0 "nothing written to TMPDIR"
exit $bad
