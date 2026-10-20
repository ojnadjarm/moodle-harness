#!/usr/bin/env bash
# Dogfood 6: build local_t1028 (course notifications, requires 2024100700) from one recipe plus the wave-9 helpers:
# message.py, cache.py, output.py, backup.py (local_), event.py --emit-in, external.py --mobile, mobile.py --capability.
# Offline (default): php -l, codechecker 0/0, mlang, mrules, mcovers --check, mprivacy --static, mmobile,
# mapicompat (+ --removed for hooks), mphpcompat in < 60 s.
# --live: one `mfixture with 5.2` holds the env lock: install, each PHPUnit file once, one `mws` call, remove.
# Hand steps and defects: ~/agent-work/research/2026-10-20/T1028/FRICTION.md.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
K="$(cd "$(dirname "$0")/.." && pwd)"; S="$K/../moodle-ci/scripts"
LIVE=0; [ "${1:-}" = --live ] && LIVE=1
ENV=5.2; COMP=local_t1028; TB=local_t1028_notice; WS=local_t1028_get_notices

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
    out="$(nice -n 19 "$S/mws" --env "$ENV" "$WS" 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && grep -q '^\[' <<<"$out" && echo "ok   mws $WS: $(tr -d '\n ' <<<"$out" | cut -c1-80)" \
        || { echo "FAIL mws $WS rc $rc"; sed 's/^/    /' <<<"$out" | tail -12; f=$((f + 1)); }
    [ "$n" -gt 0 ] && [ "$f" -eq 0 ]; exit
fi

MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
T="$(mktemp -d)"; P="$T/local/t1028"
trap 'rm -rf "$T"' EXIT
fails=0; t00=$(date +%s)
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
indent() { sed 's/^/    /' | tail -"${1:-8}"; }
step() { local name="$1"; shift; local out; out="$("$@" 2>&1)" && ok "$name" || { bad "$name"; indent <<<"$out"; }; }

mkdir -p "$T/local"
cat > "$T/recipe.yaml" <<'EOF'
component: local_t1028
name: T1028 course notifications
requires: 2024100700
copyright: 2026 onwards, Example Author <author@example.com>
tables:
  local_t1028_notice:
    comment: Course notices sent to users
    fields: [userid:int:10, courseid:int:10, subject:char:255, timecreated:int:10]
    keys: [userid->user.id, courseid->course.id]
    indexes: [timecreated]
EOF
step "generate.py recipe tables:" python3 "$K/generate.py" --target-dir "$T/local" "$T/recipe.yaml"
[ -f "$P/version.php" ] || { echo "1 failed"; exit 1; }
step "access.py view (course)" python3 "$K/access.py" "$P" view --type read --context course \
    --archetypes student=allow,teacher=allow,editingteacher=allow,manager=allow --title "View course notices"
step "access.py receive (system)" python3 "$K/access.py" "$P" receive --type read --context system \
    --archetypes user=allow --title "Receive course notices"
step "message.py course_notice --capability receive" python3 "$K/message.py" "$P" course_notice --capability receive
step "cache.py notice_count --simplekeys --ttl" python3 "$K/cache.py" "$P" notice_count --simplekeys --ttl 600
step "output.py notice_summary --renderer" python3 "$K/output.py" "$P" notice_summary \
    --fields subject:text,count:int,url:url --renderer
step "table.py --page index --param id" python3 "$K/table.py" "$P" notices --table "$TB" \
    --cols id,userid,subject,timecreated --context course --capability view --page index --param id
step "event.py notices_viewed --emit-in index.php" python3 "$K/event.py" "$P" notices_viewed --crud r \
    --edulevel participating --emit-in index.php
step "external.py get_notices --table --mobile" python3 "$K/external.py" "$P" get_notices --returns multiple \
    --type read --capability view --table "$TB" --cols courseid,subject,timecreated --mobile
step "mobile.py CoreCourseOptionsDelegate --capability view" python3 "$K/mobile.py" "$P" \
    --delegate CoreCourseOptionsDelegate --table "$TB" --cols subject --capability view
step "backup.py (local_ course data)" python3 "$K/backup.py" "$P"
step "privacy.py" python3 "$K/privacy.py" "$P"

for f in version.php db/install.xml db/access.php db/messages.php db/caches.php db/services.php db/mobile.php index.php \
    classes/local/notifier.php classes/local/cache/notice_count.php classes/output/notice_summary.php \
    classes/output/renderer.php classes/output/mobile.php classes/table/notices.php classes/event/notices_viewed.php \
    classes/external/get_notices.php classes/privacy/provider.php templates/notice_summary.mustache \
    templates/mobileapp/t1028.mustache backup/moodle2/backup_local_t1028_plugin.class.php \
    backup/moodle2/restore_local_t1028_plugin.class.php tests/local/notifier_test.php \
    tests/local/cache/notice_count_test.php tests/output/notice_summary_test.php tests/output/mobile_test.php \
    tests/backup/backup_restore_test.php tests/privacy/provider_test.php; do
    [ -f "$P/$f" ] || bad "missing $f"
done
grep -q "requires = 2024100700;" "$P/version.php" && ok "requires 2024100700" || bad "requires: $(grep requires "$P/version.php")"
grep -q "'course_notice'" "$P/db/messages.php" && grep -q "local/t1028:receive" "$P/db/messages.php" \
    && ok "messages.php course_notice, capability receive" || bad "messages.php: $(cat "$P/db/messages.php")"
grep -q "'notice_count'" "$P/db/caches.php" && grep -q "'ttl' => 600" "$P/db/caches.php" \
    && ok "caches.php notice_count ttl 600" || bad "caches.php: $(cat "$P/db/caches.php")"
grep -q 'Example context' "$P/templates/notice_summary.mustache" && grep -q 'render_notice_summary' \
    "$P/classes/output/renderer.php" && ok "notice_summary: Example context, renderer method" || bad "output.py files"
[ "$(grep -c 'notices_viewed::create' "$P/index.php")" = 1 ] && ok "index.php triggers notices_viewed" \
    || bad "index.php notices_viewed trigger"
grep -q "required_param('id'" "$P/index.php" && ok "index.php takes id" || bad "index.php param"
grep -q 'MOODLE_OFFICIAL_MOBILE_SERVICE' "$P/db/services.php" && ok "get_notices in the app service" \
    || bad "services.php: no MOODLE_OFFICIAL_MOBILE_SERVICE"
grep -q "require_capability('local/t1028:view', \\\\context_course::instance(" "$P/classes/output/mobile.php" \
    && ok "mobile page checks view in the course context" || bad "mobile page cap: $(grep -n capability "$P/classes/output/mobile.php")"
grep -q "$TB" "$P/backup/moodle2/backup_local_t1028_plugin.class.php" && ok "backup plugin holds $TB" \
    || bad "backup plugin: no $TB"
[ -d "$P/templates/mobileapp" ] && ! grep -rqF '{{{' "$P/templates/mobileapp" && ok "app templates: no {{{" \
    || bad "app templates missing or have {{{"
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
chk mrules "$S/mrules" "$P"
chk "mcovers --check" "$S/mcovers" --check "$P"
out="$(nice -n 19 "$S/mprivacy" --static "$P" 2>&1)"; rc=$?
# WARN export/delete: the static scan does not follow privacy.py's tables() map (FRICTION #5).
[ "$rc" -eq 0 ] && ! grep -q '^FAIL' <<<"$out" && grep -q '^PASS userlist' <<<"$out" \
    && ok "mprivacy --static: $(grep -c '^PASS' <<<"$out") PASS, $(grep -c '^WARN' <<<"$out") WARN, 0 FAIL" \
    || { bad "mprivacy --static rc $rc"; indent <<<"$out"; }
out="$(nice -n 19 "$S/mmobile" "$P" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ! grep -q '^\(FAIL\|WARN\)' <<<"$out" && ok "mmobile: 0 FAIL 0 WARN" || { bad "mmobile rc $rc"; indent <<<"$out"; }
chk mapicompat "$S/mapicompat" "$P"
chk "mapicompat --removed" "$S/mapicompat" "$P" --removed
chk mphpcompat "$S/mphpcompat" "$P"
off=$(($(date +%s) - t00))
[ "$off" -lt 60 ] && ok "offline in $off s" || bad "offline took $off s (>= 60)"

if [ "$LIVE" = 1 ]; then
    t0=$(date +%s)
    out="$("$S/mfixture" with "$ENV" "$P" -- bash "$0" --phpunit 2>&1)"; rc=$?
    grep '^\(ok  \|FAIL\|    \)' <<<"$out"
    nf="$(grep -c '^FAIL' <<<"$out")"; fails=$((fails + nf))
    l="$(grep '^live: ' <<<"$out")"
    if grep -q '^live: [1-9][0-9]* PHPUnit files, 0 failed$' <<<"$l"; then ok "$l"
    elif [ "$nf" -gt 0 ]; then echo "     $l"; else bad "${l:-live: 0 PHPUnit files run}"; fi
    [ "$rc" -eq 0 ] && ok "live: mfixture with $ENV rc 0, $(($(date +%s) - t0)) s" \
        || { [ "$nf" -gt 0 ] || bad "live: mfixture with $ENV rc $rc"; indent <<<"$out"; }
    n="$("$S/mdb" --env "$ENV" "SELECT count(*) FROM {config_plugins} WHERE plugin = ?" "$COMP" 2>&1 | tail -1)"
    [ "$n" = 0 ] && ok "live remove: 0 config_plugins rows" || bad "live remove: config_plugins rows '$n'"
fi

echo "$fails failed"
[ "$fails" -eq 0 ]
