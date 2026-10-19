#!/usr/bin/env bash
# mtest behat --parallel on a throwaway Moodle tree with stubbed docker/curl: capping, init flags, run fan-out.
set -uo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)/scripts/mtest"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.claude/hooks" "$T/bin" "$T/moodle/vendor/bin" "$T/moodle/public/admin" "$T/moodle/public/local/x/tests/behat"
touch "$T/moodle/vendor/bin/phpunit" "$T/moodle/config.php"
echo "<?php \$plugin->component = 'local_x';" > "$T/moodle/public/local/x/version.php"
for i in 1 2 3 4; do touch "$T/moodle/public/local/x/tests/behat/f$i.feature"; done
printf '#!/bin/sh\nprintf "c1\\t/var/www/html\\n"\n' > "$T/home/.claude/hooks/moodle-container.sh"
# docker stub: logs every command; env reports $ENVPAR runs, all ready when READY=1.
cat > "$T/bin/docker" <<'EOF'
#!/bin/bash
c="${*: -1}"; echo "$c" >> "$LOGF"; cat >/dev/null 2>&1 <&0 &
case "$c" in
    *behat_dataroot*) echo /var/www/behatdata/behatrun;;
    *run_environment.json*parallel*\?\?\ 0\)\;*) echo "${ENVPAR:-0}";;
    *for\ f\ in*) [ "${READY:-0}" = 1 ] && echo /var/www/behatdata/behatrun/behat/behat.yml;;
    *test_environment_enabled*behatrun*) [ "${READY:-0}" = 1 ];;
    *util.php\ --diag*) [ "${READY:-0}" = 1 ];;
    *vendor/bin/behat*) echo "1 scenario (1 passed)"; echo "5 steps (5 passed)";;
esac
EOF
printf '#!/bin/sh\necho "$BUSY"\n' > "$T/bin/curl"
chmod +x "$T/bin/"* "$T/home/.claude/hooks/moodle-container.sh"
run() { : > "$T/log"; env HOME="$T/home" PATH="$T/bin:$PATH" LOGF="$T/log" TMPDIR="$T" "$@" "$M" behat "$T/moodle/public/local/x" "${args[@]}" 2>&1; }
bad=0
check() { if eval "$1"; then echo "PASS $2"; else echo "FAIL $2"; bad=1; fi; }

"$M" --help | grep -q -- --parallel; check '[ $? = 0 ]' "--help documents --parallel"
args=(--parallel 0); run >/dev/null; check '[ $? = 2 ]' "--parallel 0 is a usage error"

args=(--parallel 6); out="$(run BUSY='{"id":"a"},{"id":"b"},{"id":"c"},{"id":"d"},{"id":"e"},{"id":"f"}' MTEST_SELENIUM_CAP=8)"
check 'grep -q "parallel 6 -> 2 (selenium cap 8, 6 busy, 4 features)" <<<"$out"' "busy hub sessions cap N"
check 'grep -q "init.php --disable-composer --parallel=2 --maxruns=3" "$T/log"' "stale env inits with --parallel=N"
check 'grep -q "util.php --drop" "$T/log"' "parallel init drops old run sites first"
check '[ "$(grep -c "vendor/bin/behat -c .*behatrun[12]/behat/mtest.yml. --config .*behatrun[12]/behat/behat.yml. *$" "$T/log")" = 2 ]' "one behat per run site"
check 'grep -q "^2 scenarios (2 passed)" <<<"$out"' "scenario counts are summed"

args=(--parallel 8); out="$(run BUSY= READY=1 ENVPAR=8)"
check 'grep -q "parallel 8 -> 4 (selenium cap 8, 0 busy, 4 features)" <<<"$out"' "N capped by feature count"
check '! grep -q "init.php" "$T/log"' "ready env is not re-initialised"

args=(); out="$(run BUSY= READY=1 ENVPAR=0)"
check '! grep -q "mtest.yml" "$T/log" && grep -q "vendor/bin/behat --config" "$T/log"' "no --parallel on a single env keeps the single run"
exit "$bad"
