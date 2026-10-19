#!/usr/bin/env bash
# mfixture against a fake docker and a throwaway envs dir: no real container or env is touched.
set -uo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)/scripts/mfixture"
T="$(mktemp -d "${TMPDIR:-/tmp}/mfixture-test-XXXX")"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state" "$T/envs/5.2/www/public/local" "$T/envs/4.5/www" "$T/src/t429fix"
mkdir -p "$T/envs/5.2/www/vendor"; touch "$T/envs/5.2/www/config.php"
ln -s "$T/envs/4.5" "$T/envs/5.3"
printf "<?php\n\$plugin->component = 'local_t429fix';\n\$plugin->version = 2026101900;\n" > "$T/src/t429fix/version.php"
cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
S="$T/state"; L="$T/envs/5.2/www/public/local"
echo "\$*" >> "$T/calls"
case "\$1" in
    ps) echo fake-app; exit 0 ;;
    inspect) printf '%s\t%s\n' "$T/envs/5.2/www" /var/www/html; exit 0 ;;
esac
[ "\$3" = sh ] && exit 0
cmd="\$5"
pending() { [ "\$(ls "\$L" | sort)" != "\$(ls "\$S" | sort)" ]; }
case "\$cmd" in
    *get_plugin_types*) echo /var/www/html/public/local ;;
    *get_config*) [ -e "\$S/t429fix" ] && echo 2026101900 ;;
    *upgrade.php\ --is-pending*) pending && exit 2 ;;
    *upgrade.php\ --non-interactive*) [ -n "\${FAIL_UPGRADE:-}" ] && exit 1; rm -f "\$S"/*; for d in "\$L"/*; do [ -e "\$d" ] && touch "\$S/\${d##*/}"; done ;;
    *uninstall_plugins.php*) [ -z "\${FAIL_UNINSTALL:-}" ] && rm -f "\$S/t429fix" ;;
    *purge_caches.php*) ;;
    *) echo "fake docker: unexpected \$cmd" >&2; exit 9 ;;
esac
exit 0
EOF
chmod +x "$T/bin/docker"
export PATH="$T/bin:$PATH" MFIXTURE_ENVS="$T/envs"
F="$T/envs/5.2/www/public/local/t429fix"
bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got $1)"; bad=1; fi; }
run() { "$M" "$@" >/dev/null 2>&1; echo $?; }

check "$(run add 4.5 "$T/src/t429fix")" 3 "refuses 4.5"
check "$(run add vass "$T/src/t429fix")" 3 "refuses vass"
check "$(run add 4.6 "$T/src/t429fix")" 3 "refuses env outside the allowlist"
check "$(run add 5.3 "$T/src/t429fix")" 3 "refuses an allowed name that resolves to 4.5"
check "$([ -e "$T/calls" ] && echo called || echo none)" none "refusals never call docker"

check "$(run add 5.2 "$T/src/t429fix")" 0 "add exits 0"
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
exit $bad
