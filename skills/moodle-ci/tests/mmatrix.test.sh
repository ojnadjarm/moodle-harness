#!/usr/bin/env bash
# mmatrix with the real mfixture against a fake docker, a fake mci and throwaway envs: no real env is touched.
set -uo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)/scripts"
T="$(mktemp -d "${TMPDIR:-/tmp}/mmatrix-test-XXXX")"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/scripts" "$T/src/t768fix" "$T/tmp"
cp "$D/mmatrix" "$D/mfixture" "$D/mlog" "$D/mci-workflow" "$T/scripts/"
printf "<?php\n\$plugin->component = 'local_t768fix';\n\$plugin->version = 2026102000;\n\$plugin->requires = 2025100600;\n" \
    > "$T/src/t768fix/version.php"
mkenv() {
    local w="$T/envs/$1/www"
    mkdir -p "$w/vendor" "$w/public/local" "$T/state/$1"; touch "$w/config.php"
    printf "<?php\n\$version  = %s.00;\n\$branch   = '%s';\n" "$2" "$3" > "$w/public/version.php"
}
for v in 5.0:2025041400:500 5.1:2025100600:501 5.2:2026042004:502 5.3:2026100500:503 4.5:2024100700:405 vass:2024100700:405; do
    IFS=: read -r e n b <<<"$v"; mkenv "$e" "$n" "$b"
done
cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$T/calls"
case "\$1" in
    ps) printf 'm%s\n' 5.1 5.2 5.3 4.5 vass \${FAKE_UP:-}; exit 0 ;;
    inspect) printf '%s\t%s\n' "$T/envs/\${4#m}/www" /var/www/html; exit 0 ;;
esac
e="\${2#m}"; S="$T/state/\$e"; L="$T/envs/\$e/www/public/local"
[ "\$3" = sh ] && exit 0
cmd="\$5"
pending() { [ "\$(ls "\$L" | sort)" != "\$(ls "\$S" | sort)" ]; }
case "\$cmd" in
    *get_plugin_types*) echo /var/www/html/public/local ;;
    *get_config*) [ -e "\$S/t768fix" ] && echo 2026102000 ;;
    *upgrade.php\ --is-pending*) pending && exit 2 ;;
    *upgrade.php\ --non-interactive*) rm -f "\$S"/*; for d in "\$L"/*; do [ -e "\$d" ] && touch "\$S/\${d##*/}"; done ;;
    *uninstall_plugins.php*) rm -f "\$S/t768fix" ;;
    *purge_caches.php*) ;;
    *) echo "fake docker: unexpected \$cmd" >&2; exit 9 ;;
esac
exit 0
EOF
cat > "$T/scripts/mci" <<EOF
#!/usr/bin/env bash
p="\$2"; echo "\$p nice=\$(nice) installed=\$([ -f "\$p/version.php" ] && echo y)" >> "$T/mci-calls"
[ -n "\${MCI_SLEEP:-}" ] && { touch "$T/started"; sleep "\$MCI_SLEEP"; }
pu=0; case "\$p" in */5.3/*) pu=1;; esac
printf 'step rc sec note\ncodechecker  0  1\nphpunit      %s  2\n' "\$pu"
exit \$pu
EOF
chmod +x "$T/bin/docker" "$T/scripts/mci"
export PATH="$T/bin:$PATH" MFIXTURE_ENVS="$T/envs" MFIXTURE_ALLOW="5.0 5.1 5.2 5.3" TMPDIR="$T/tmp" XDG_STATE_HOME="$T/xdg"
LH="$T/xdg/moodle-harness/logs/local_t768fix"
M="$T/scripts/mmatrix" P="$T/src/t768fix"
bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got $1)"; bad=1; fi; }
row() { awk -v e="$1" '$1 == e { print $2, $3 }' "$T/out"; }
left() { ls "$T"/envs/*/www/public/local "$T"/state/* 2>/dev/null | grep -c t768fix; }

"$M" "$P" --envs 5.2,vass >/dev/null 2>&1; check $? 3 "refuses vass in --envs"
"$M" "$P" --envs 4.5 >/dev/null 2>&1; check $? 3 "refuses 4.5 in --envs"
check "$([ -e "$T/calls" ] && echo called || echo none)" none "refusals never call docker"

"$M" "$P" --envs 5.0,5.1,5.2,5.3 > "$T/out" 2>&1; check $? 1 "one red env exits 1"
check "$(row 5.0)" "SKIP SKIP" "env below requires is skipped"
check "$(row 5.1)" "0 0" "5.1 green"
check "$(row 5.2)" "0 0" "5.2 green"
check "$(row 5.3)" "0 1" "5.3 phpunit red"
check "$(grep -c 'nice=19 installed=y' "$T/mci-calls")" 3 "mci runs niced on the installed copy per env"
check "$(grep -c "^$T/envs/5.[123]/www/public/local/t768fix " "$T/mci-calls")" 3 "mci gets the env's fixture dir"
check "$(left)" 0 "fixture removed from every env"
check "$(ls "$LH" | grep -cE '^mmatrix-5\.[123]-[0-9]{8}-[0-9]{6}-.{4}\.log$')" 3 "one log per run env in the plugin's log home, none for SKIP"
check "$(grep -c "red; logs $LH\$" "$T/out")" 1 "summary points at the log home"
check "$(find "$T/tmp" -name 'mmatrix-*' | wc -l)" 0 "no mmatrix dir in TMPDIR"

: > "$T/calls"; "$M" "$P" > "$T/out" 2>&1
check "$(awk 'NR > 1 && $1 ~ /^[0-9]/ { print $1 }' "$T/out" | grep -v mmatrix | tr '\n' ' ')" "5.1 5.2 5.3 " "default: running envs, 4.5/vass excluded"
check "$(grep -cE 'exec m(4\.5|vass) ' "$T/calls")" 0 "default run never execs into 4.5/vass"

Q="$T/src/plan"; mkdir -p "$Q"
printf "<?php\n\$plugin->component = 'local_t768fix';\n\$plugin->requires = 2024100700;\n\$plugin->supported = [405, 503];\n" > "$Q/version.php"
: > "$T/calls"; n0="$(wc -l < "$T/mci-calls") $(ls "$LH" | wc -l)"
"$M" "$Q" --plan > "$T/out" 2>&1; check $? 0 "plan exits 0"
prow() { awk -v e="$1" '$1 == e { $1 = ""; $2 = ""; print }' "$T/out" | tr -s ' ' | sed 's/^ //'; }
check "$(awk 'NR > 1 { print $1 }' "$T/out" | tr '\n' ' ')" "4.5 5.0 5.1 5.2 5.3 " "plan: one row per branch requires..supported"
check "$(awk '$1 == "5.2" { print $2 }' "$T/out")" 8.3 "plan: PHP floor from mci-workflow"
check "$(prow 4.5)" "refused - - no env: CI only via mci-workflow" "plan: 4.5 refused"
check "$(prow 5.0)" "${T}/envs/5.0 down - start env" "plan: down env says start, never-run env has no seconds"
check "$(prow 5.2)" "${T}/envs/5.2 up 3 run" "plan: running env says run with last mci quick seconds"
check "$(wc -l < "$T/mci-calls") $(ls "$LH" | wc -l) $(grep -cE 'exec m(4\.5|vass) |upgrade.php' "$T/calls")" "$n0 0" "plan runs nothing, no log, no 4.5/vass probe"
mv "$T/envs/5.0" "$T/off-5.0"; "$M" "$Q" --plan > "$T/out" 2>&1
check "$(prow 5.0)" "none - - no env: CI only via mci-workflow" "plan: missing env is CI only"
mv "$T/off-5.0" "$T/envs/5.0"
mkenv lts45 2024100700 405; mkenv x51 2025100600 504; : > "$T/calls"; "$M" "$Q" --plan > "$T/out" 2>&1
check "$(prow 4.5)" "${T}/envs/lts45 down - start env" "plan: 4.5 row takes the env whose \$branch is 405 (lts45), never 4.5/vass"
check "$(prow 5.1)" "${T}/envs/5.1 up 3 run" "plan: a dir name never sets the branch (x51 has \$branch 504)"
check "$(grep -cE 'exec m(4\.5|vass) |upgrade.php' "$T/calls")" 0 "plan: no exec into 4.5/vass"
FAKE_UP=lts45 env -u MFIXTURE_ALLOW "$M" "$Q" --envs lts45 > "$T/out" 2>&1
check "$?:$(row lts45)" "0:0 0" "default MFIXTURE_ALLOW runs the --name lts45 env"
rm -rf "$T/envs/lts45" "$T/envs/x51"
"$M" "$Q" --plan --envs 5.3 > "$T/out" 2>&1
check "$?:$(awk 'NR > 1 { print $1 }' "$T/out" | tr '\n' ' ')" "0:5.3 " "plan --envs 5.3 lists only 5.3"
"$M" "$Q" --plan --envs 4.1 > "$T/out" 2>&1
check "$?:$(grep -c 'mmatrix: no branch 4.1 in 4.5..5.3' "$T/out")" "2:1" "plan --envs outside requires..supported is a named rc 2"
I="$T/envs/5.2/www/public/local/plan"; cp -a "$Q" "$I"
printf 'step rc sec note\ncodechecker  0  7\nmci: quick plan: 1 ok, 0 red, 0 skip; logs x\n' > "$LH/mci-20991231-000000-aaaa.log"
printf 'step rc sec note\ncodechecker  0  90\nmci: full plan: 1 ok, 0 red, 0 skip; logs x\n' > "$LH/mci-20991231-000001-bbbb.log"
touch -d '+1 min' "$LH/mci-20991231-000000-aaaa.log"; touch -d '+2 min' "$LH/mci-20991231-000001-bbbb.log"
"$M" "$I" --plan > "$T/out" 2>&1
check "$(awk '$1 == "5.2" || $1 == "5.1" { print $1 "=" $5 }' "$T/out" | tr '\n' ' ')" "5.1=3 5.2=7 " "plan: newest direct mci quick log counts for the env the plugin lives in"
F="$LH/mci-20991231-000002-cccc.log"
printf 'step rc sec note\ncodechecker  0  50\nmci: quick plan: 1 ok, 0 red, 0 skip; logs %s\n' "$F" > "$F"
cp "$F" "$LH/mmatrix-5.3-20991231-000002-dddd.log"; touch -d '+3 min' "$F" "$LH/mmatrix-5.3-20991231-000002-dddd.log"
"$M" "$I" --plan > "$T/out" 2>&1
check "$(awk '$1 == "5.2" || $1 == "5.3" { print $1 "=" $5 }' "$T/out" | tr '\n' ' ')" "5.2=7 5.3=50 " "plan: an mci log from an mmatrix run on another env never counts for the plugin's env"
rm -f "$LH"/mmatrix-5.3-2099*
rm -rf "$I" "$LH"/mci-2099*
cp "$T/scripts/mci-workflow" "$T/mciwf"; sed -i 's/, "5.3": "8.3"}/}/' "$T/scripts/mci-workflow"
"$M" "$Q" --plan > "$T/out" 2>&1; rc=$?
check "$rc:$(grep -c 'mmatrix: no PHP floor for 5.3 in mci-workflow' "$T/out"):$(grep -c Traceback "$T/out")" "2:1:0" "plan: branch without a PHP floor is a clean rc 2"
mv "$T/mciwf" "$T/scripts/mci-workflow"

cp -a "$P" "$T/envs/5.2/www/public/local/t768fix"; : > "$T/calls"
"$M" "$T/envs/5.2/www/public/local/t768fix" --envs 5.2 > "$T/out" 2>&1; check $? 0 "plugin inside an env runs in place"
check "$(grep -c upgrade.php "$T/calls") $(grep -c 'in place' "$T/out")" "0 1" "in place: no fixture round trip"
rm -rf "$T/envs/5.2/www/public/local/t768fix"

MCI_SLEEP=5 "$M" "$P" --envs 5.2 > "$T/out" 2>&1 & mp=$!
for _ in $(seq 50); do [ -e "$T/started" ] && break; sleep 0.1; done
kill -TERM "$mp"; wait "$mp"; check $? 130 "TERM exits 130"
check "$(left)" 0 "fixture removed on TERM"
exit $bad
