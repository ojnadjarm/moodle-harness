#!/usr/bin/env bash
# Dogfood 5: build local_t983 (requires 2024100700, 4.5 LTS) from one recipe plus the helpers, checked against 4.5 code.
# Offline (default): php -l, codechecker 0/0, mlang, mmobile, mprivacy static, mcovers --check, mapicompat (+ --removed),
# mphpcompat, mrules in < 60 s; hook.py and event.py --observe resolve against `msrc 4.5`.
# --live: one `mfixture with 5.2` holds the env lock: install, each generated PHPUnit file once, remove.
# Hand steps and defects: ~/agent-work/research/2026-10-20/T983/FRICTION.md.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
K="$(cd "$(dirname "$0")/.." && pwd)"; S="$K/../moodle-ci/scripts"
LIVE=0; [ "${1:-}" = --live ] && LIVE=1
ENV=5.2; COMP=local_t983; TB=local_t983_visit

# --phpunit: the command `mfixture with` runs inside the env lock; it tests the installed copy.
if [ "${1:-}" = --phpunit ]; then
    dir="${MFIXTURE_DIR:-}"
    [ -d "$dir/tests" ] || { echo "FAIL live: installed $COMP not found (MFIXTURE_DIR '$dir')"; exit 1; }
    n=0; f=0
    while IFS= read -r t; do
        t0=$(date +%s); n=$((n + 1)); out="$(nice -n 19 "$S/mtest" phpunit "$t" 2>&1)"; rc=$?
        [ "$rc" -eq 0 ] && echo "ok   phpunit ${t#"$dir"/}, $(($(date +%s) - t0)) s" \
            || { echo "FAIL phpunit ${t#"$dir"/} rc $rc"; sed 's/^/    /' <<<"$out" | tail -12; f=$((f + 1)); }
    done < <(find "$dir/tests" -name '*_test.php' | sort)
    echo "live: $n PHPUnit files, $f failed"
    [ "$n" -gt 0 ] && [ "$f" -eq 0 ]; exit
fi

MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
T="$(mktemp -d)"; P="$T/local/t983"
trap 'rm -rf "$T"' EXIT
fails=0; t00=$(date +%s)
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
indent() { sed 's/^/    /' | tail -"${1:-8}"; }
step() { local name="$1"; shift; local out; out="$("$@" 2>&1)" && ok "$name" || { bad "$name"; indent <<<"$out"; }; }

CORE="$("$S/msrc" 4.5 2>&1)" && [ -f "$CORE/version.php" ] || { echo "FAIL msrc 4.5: $CORE"; echo "1 failed"; exit 1; }
grep -q "^\$branch *= *'405';" "$CORE/version.php" "$CORE/public/version.php" 2>/dev/null \
    && ok "msrc 4.5: $CORE" || bad "msrc 4.5 tree is not branch 405"

mkdir -p "$T/local"
cat > "$T/recipe.yaml" <<'EOF'
component: local_t983
name: T983 course visits
requires: 2024100700
copyright: 2026 onwards, Example Author <author@example.com>
tables:
  local_t983_visit:
    comment: Course visits per user
    fields: [userid:int:10, courseid:int:10, note:char:255, timecreated:int:10]
    keys: [userid->user.id, courseid->course.id]
    indexes: [timecreated]
EOF
step "generate.py recipe tables:" python3 "$K/generate.py" --target-dir "$T/local" "$T/recipe.yaml"
[ -f "$P/version.php" ] || { echo "1 failed"; exit 1; }
step "access.py view" python3 "$K/access.py" "$P" view --type read --context system \
    --archetypes user=allow,manager=allow --title "View own visits"
step "external.py get_visits --table --cols --ajax" python3 "$K/external.py" "$P" get_visits --returns multiple \
    --type read --ajax --capability view --table "$TB" --cols courseid,note,timecreated
step "mobile.py --table" python3 "$K/mobile.py" "$P" --delegate CoreMainMenuDelegate --table "$TB" --cols note
step "settings.py configint + configduration" python3 "$K/settings.py" "$P" --setting maxvisits:configint:50 \
    --setting retention:configduration:2592000
step "task.py --purge" python3 "$K/task.py" "$P" purge_old --scheduled "30 3 * * *" \
    --purge "$TB.timecreated" --setting retention
step "event.py --observe user_deleted --table" python3 "$K/event.py" "$P" user_deleted \
    --observe '\core\event\user_deleted' --table "$TB" --core "$CORE"
step "hook.py --core msrc 4.5" python3 "$K/hook.py" --core "$CORE" "$P" '\core\hook\output\before_footer_html_generation'
cp -r "$P" "$T/h983"
out="$(python3 "$K/hook.py" --core "$CORE" "$T/h983" '\core_course\hook\before_course_viewed' 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] || grep -q "before_course_viewed not found in $CORE" <<<"$out"; } && ok "hook.py: 5.0 hook before_course_viewed flagged vs 4.5" \
    || { bad "hook.py: 5.0 hook not flagged against msrc 4.5"; indent <<<"$out"; }
step "privacy.py" python3 "$K/privacy.py" "$P"

for f in version.php db/install.xml db/access.php db/services.php db/mobile.php db/tasks.php db/events.php \
    db/hooks.php settings.php classes/external/get_visits.php classes/output/mobile.php classes/task/purge_old.php \
    classes/observer.php classes/privacy/provider.php tests/privacy/provider_test.php templates/mobileapp/t983.mustache \
    tests/output/mobile_test.php; do
    [ -f "$P/$f" ] || bad "missing $f"
done
grep -q "requires = 2024100700;" "$P/version.php" && ok "requires 2024100700" || bad "requires: $(grep requires "$P/version.php")"
grep -q "PARAM_INT" "$P/settings.php" && ok "settings.php maxvisits PARAM_INT" || bad "settings.php: no PARAM_INT"
grep -q "'retention'" "$P/classes/task/purge_old.php" && grep -q "$TB" "$P/classes/task/purge_old.php" \
    && ok "purge_old reads retention, deletes $TB" || bad "purge_old: no retention/$TB"
grep -q "require_capability('local/t983:view', \\\\context_system::instance());" "$P/classes/output/mobile.php" \
    && grep -q "render_from_template('local_t983/mobileapp/t983', \[\])" "$P/classes/output/mobile.php" \
    && ok "mobile page: access.py cap local/t983:view, templates/mobileapp/t983" || bad "mobile page: no cap or old template path"
grep -q 'test_mobile_t983_view_requires_capability' "$P/tests/output/mobile_test.php" \
    && grep -q 'test_mobile_t983_view_with_capability' "$P/tests/output/mobile_test.php" \
    && grep -q "assertEquals('a', \$rows\[0\]\['note'\]);" "$P/tests/output/mobile_test.php" \
    && ok "mobile_test.php: own note row, capability grant and denial" || bad "mobile_test.php: $(cat "$P/tests/output/mobile_test.php")"
grep -q "'note'" "$P/classes/external/get_visits.php" && ok "get_visits returns note" || bad "get_visits: no note col"
[ -d "$P/templates" ] && ! grep -rqF '{{{' "$P/templates" && ok "mobile templates: no {{{" || bad "mobile templates missing or have {{{"
ntests="$(find "$P/tests" -name '*_test.php' | wc -l)"
[ "$ntests" -gt 0 ] || bad "0 PHPUnit files"
ok "plugin: $(find "$P" -type f | wc -l) files, $ntests PHPUnit files"

lint=0
while IFS= read -r f; do php -l "$f" >/dev/null 2>&1 || { bad "php -l ${f#"$P"/}"; lint=1; }; done \
    < <(find "$P" -name '*.php')
[ "$lint" = 0 ] && ok "php -l clean"
if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
    out="$(nice -n 19 "$MPC" codechecker --max-warnings 0 "$P" 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && ! grep -q '| \(ERROR\|WARNING\) |' <<<"$out" && ok "codechecker 0 errors 0 warnings" \
        || { bad "codechecker rc $rc"; indent 20 <<<"$out"; }
else
    bad "codechecker: moodle-plugin-ci absent"
fi
chk() {
    local name="$1"; shift; local out rc
    out="$(nice -n 19 "$@" 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && ok "$name: $(tail -1 <<<"$out")" || { bad "$name rc $rc"; indent <<<"$out"; }
}
chk mlang "$S/mlang" "$P"
out="$(nice -n 19 "$S/mmobile" "$P" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ! grep -q '^\(FAIL\|WARN\)' <<<"$out" && ok "mmobile: 0 FAIL 0 WARN" || { bad "mmobile rc $rc"; indent <<<"$out"; }
# Offline there is no Moodle root above $P: mprivacy runs its static part, then exits 3 (no container).
out="$(nice -n 19 "$S/mprivacy" "$P" 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] || [ "$rc" -eq 3 ]; } && ! grep -q '^FAIL' <<<"$out" && grep -q '^PASS userlist' <<<"$out" \
    && ok "mprivacy static: $(grep -c '^PASS' <<<"$out") PASS, 0 FAIL" || { bad "mprivacy static rc $rc"; indent <<<"$out"; }
chk "mcovers --check (@covers below 5.0)" "$S/mcovers" --check "$P"
chk mapicompat "$S/mapicompat" "$P"
chk "mapicompat --removed" "$S/mapicompat" "$P" --removed
chk mphpcompat "$S/mphpcompat" "$P"
chk mrules "$S/mrules" "$P"
off=$(($(date +%s) - t00))
[ "$off" -lt 60 ] && ok "offline in $off s" || bad "offline took $off s (>= 60)"

if [ "$LIVE" = 1 ]; then
    t0=$(date +%s)
    out="$("$S/mfixture" with "$ENV" "$P" -- bash "$0" --phpunit 2>&1)"; rc=$?
    dir="$(sed -n "s/^mfixture: installed $COMP at //p" <<<"$out")"
    grep '^\(ok  \|FAIL\|    \)' <<<"$out"
    nf="$(grep -c '^FAIL' <<<"$out")"; fails=$((fails + nf))
    l="$(grep '^live: ' <<<"$out")"
    if grep -q '^live: [1-9][0-9]* PHPUnit files, 0 failed$' <<<"$l"; then ok "$l"
    elif [ "$nf" -gt 0 ]; then echo "     $l"; else bad "${l:-live: 0 PHPUnit files run}"; fi
    [ "$rc" -eq 0 ] && ok "live: mfixture with $ENV rc 0, $(($(date +%s) - t0)) s" \
        || { [ "$nf" -gt 0 ] || bad "live: mfixture with $ENV rc $rc"; indent <<<"$out"; }
    [ -n "$dir" ] && [ ! -e "$dir" ] && ok "live remove: fixture dir gone" || bad "live remove: dir '$dir' left or never installed"
fi

echo "$fails failed"
[ "$fails" -eq 0 ]
