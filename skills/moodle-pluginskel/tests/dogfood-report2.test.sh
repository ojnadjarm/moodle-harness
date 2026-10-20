#!/usr/bin/env bash
# Dogfood 7: build report_t1029 (a course report, report_ type files) from one recipe plus the helpers, no text edits, one hand step (rm index.php).
# Offline (default): php -l, codechecker 0/0, mlang, mapicompat --removed, mphpcompat, mrules, mcovers --check,
# msteps --check in < 60 s. --live: one `mfixture with 5.2` installs, runs each PHPUnit file and the one Behat
# feature once (niced), removes. Hand steps and defects: ~/agent-work/research/2026-10-20/T1029/FRICTION.md.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
K="$(cd "$(dirname "$0")/.." && pwd)"; S="$K/../moodle-ci/scripts"; DL="$K/tests/fixtures/steps-5.2.txt"
LIVE=0; [ "${1:-}" = --live ] && LIVE=1
ENV=5.2; COMP=report_t1029; TB=report_t1029_visit; FEAT=view_visits

# --inner: the command `mfixture with` runs inside the env lock; it tests the installed copy.
if [ "${1:-}" = --inner ]; then
    dir="${MFIXTURE_DIR:-}"
    [ -d "$dir/tests" ] || { echo "FAIL live: installed $COMP not found"; exit 1; }
    n=0; f=0
    while IFS= read -r t; do
        t0=$(date +%s); n=$((n + 1)); out="$(nice -n 19 "$S/mtest" phpunit "$t" 2>&1)"; rc=$?
        [ "$rc" -eq 0 ] && echo "ok   phpunit ${t#"$dir"/}, $(($(date +%s) - t0)) s" \
            || { echo "FAIL phpunit ${t#"$dir"/} rc $rc"; sed 's/^/    /' <<<"$out" | tail -12; f=$((f + 1)); }
    done < <(find "$dir/tests" -name '*_test.php' | sort)
    echo "live: $n PHPUnit files, $f failed"
    t0=$(date +%s); out="$(nice -n 19 "$S/mtest" behat "$dir/tests/behat/$FEAT.feature" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ] && grep -qE '^[1-9][0-9]* scenarios? \([0-9]+ passed\)' <<<"$out"; then
        echo "ok   behat $FEAT.feature: $(grep -E '^[0-9]+ (scenario|step)s? \(' <<<"$out" | tr '\n' ' ')$(($(date +%s) - t0)) s"
    else
        echo "FAIL behat $FEAT.feature rc $rc"; sed 's/^/    /' <<<"$out" | tail -20; f=$((f + 1))
    fi
    [ "$n" -gt 0 ] && [ "$f" -eq 0 ]; exit
fi

MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
T="$(mktemp -d)"; W="$T/env/www"; P="$W/public/report/t1029"
trap 'rm -rf "$T"' EXIT
fails=0; t00=$(date +%s)
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
indent() { sed 's/^/    /' | tail -"${1:-8}"; }
step() { local name="$1"; shift; local out; out="$("$@" 2>&1)" && ok "$name" || { bad "$name"; indent <<<"$out"; }; }

# Fake 5.2 tree and docker so msteps --check reads the fixture step dump offline (as behat.test.sh does).
mkdir -p "$T/bin" "$W/vendor/bin" "$W/public/report"
touch "$W/vendor/bin/phpunit" "$W/config.php"
echo '$version  = 2026042004.02;' > "$W/public/version.php"
cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
case "\$1" in
    ps) echo fake52-app-1 ;;
    inspect) printf '%s\t/var/www/html\n' "$W" ;;
    exec) case "\$*" in *"command -v php"*) exit 0 ;; *behat*) cat "$DL" ;; esac ;;
esac
EOF
chmod +x "$T/bin/docker"

cat > "$T/recipe.yaml" <<'EOF'
component: report_t1029
name: T1029 course visits
copyright: 2026 onwards, Example Author <author@example.com>
capabilities:
  - name: view
    title: View course visits
    contextlevel: CONTEXT_COURSE
    clonepermissionsfrom: moodle/site:viewreports
    archetypes:
      - {role: editingteacher, permission: CAP_ALLOW}
      - {role: teacher, permission: CAP_ALLOW}
      - {role: manager, permission: CAP_ALLOW}
tables:
  report_t1029_visit:
    comment: Course page visits per user
    fields: [userid:int:10, courseid:int:10, visits:int:10, timecreated:int:10, timemodified:int:10]
    keys: [userid->user.id, courseid->course.id]
    indexes: [timecreated]
EOF
cat > "$T/behat.yaml" <<'EOF'
page: {path: report/t1029/index.php, param: id, instance: course, name: Visits}
heading: Visits
as: teacher
EOF
step "generate.py recipe report_ type" python3 "$K/generate.py" --target-dir "$W/public/report" "$T/recipe.yaml"
[ -f "$P/version.php" ] || { echo "1 failed"; exit 1; }
grep -q 'function report_t1029_extend_navigation_course' "$P/lib.php" \
    && grep -q "moodle_url('/report/t1029/index.php', \['id' => \$course->id\])" "$P/lib.php" \
    && grep -q "has_capability('report/t1029:view'" "$P/lib.php" \
    && ok "lib.php: course nav callback, cap-checked, links index.php?id=" || bad "lib.php nav callback"
# Hand step (FRICTION #1): table.py --page index refuses generate.py's index.php; the generated stub is dropped.
rm "$P/index.php"
step "table.py --context course --dynamic --page index --param id" python3 "$K/table.py" "$P" visits --table "$TB" \
    --cols id,userid,visits,timemodified --context course --dynamic --capability view --page index --param id
step "event.py report_viewed --emit-in index.php" python3 "$K/event.py" "$P" report_viewed --crud r \
    --edulevel teaching --emit-in index.php
[ "$(grep -c 'report_viewed::create' "$P/index.php")" = 1 ] && ok "index.php triggers report_viewed" \
    || bad "index.php report_viewed trigger"
step "privacy.py" python3 "$K/privacy.py" "$P"
step "behat.py page resolver" python3 "$K/behat.py" --recipe "$T/behat.yaml" "$P" "$FEAT"

for f in lib.php index.php db/install.xml db/access.php classes/table/visits.php classes/table/visits_filterset.php \
    classes/event/report_viewed.php classes/privacy/provider.php tests/table/visits_test.php \
    tests/event/report_viewed_test.php tests/privacy/provider_test.php tests/behat/$FEAT.feature \
    tests/behat/behat_report_t1029.php; do
    [ -f "$P/$f" ] || bad "missing $f"
done
grep -q "TABLE NAME=\"$TB\"" "$P/db/install.xml" && ok "install.xml has $TB" || bad "install.xml tables"
grep -q "'contextlevel' => CONTEXT_COURSE" "$P/db/access.php" && ok "view is a course capability" || bad "access.php context"
grep -q "required_param('id', PARAM_INT)" "$P/index.php" && grep -q 'context_course::instance' "$P/index.php" \
    && ok "index.php takes id and checks the course context" || bad "index.php param/context"
grep -q 'CONTEXT_COURSE' "$P/classes/privacy/provider.php" && ok "privacy maps rows to course contexts" \
    || bad "privacy provider course context"
grep -q 'resolve_page_instance_url' "$P/tests/behat/behat_report_t1029.php" \
    && grep -q 'I am on the "C1" "report_t1029 > Visits" page' "$P/tests/behat/$FEAT.feature" \
    && ok "behat opens the course page through the resolver" || bad "behat page resolver"
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
chk "mapicompat --removed" "$S/mapicompat" "$P" --removed
chk mphpcompat "$S/mphpcompat" "$P"
chk mrules "$S/mrules" "$P"
chk "mcovers --check" "$S/mcovers" --check "$P"
out="$(PATH="$T/bin:$PATH" XDG_CACHE_HOME="$T/cache" "$S/msteps" --check "$P/tests/behat/$FEAT.feature" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q ', 0 undefined$' <<<"$out" && ok "msteps --check: $(tail -1 <<<"$out" | sed 's/^msteps: //')" \
    || { bad "msteps --check rc $rc"; indent <<<"$out"; }
off=$(($(date +%s) - t00))
[ "$off" -lt 60 ] && ok "offline in $off s" || bad "offline took $off s (>= 60)"

if [ "$LIVE" = 1 ]; then
    t0=$(date +%s)
    out="$("$S/mfixture" with "$ENV" "$P" -- bash "$0" --inner 2>&1)"; rc=$?
    dir="$(sed -n "s/^mfixture: installed $COMP at //p" <<<"$out")"
    grep '^\(ok  \|FAIL\|    \)' <<<"$out"
    nf="$(grep -c '^FAIL' <<<"$out")"; fails=$((fails + nf))
    grep -q '^live: [1-9][0-9]* PHPUnit files, 0 failed$' <<<"$out" && ok "$(grep '^live: ' <<<"$out")" \
        || [ "$nf" -gt 0 ] || bad "live: 0 PHPUnit files run"
    [ "$rc" -eq 0 ] && ok "live: mfixture with $ENV rc 0, $(($(date +%s) - t0)) s" \
        || [ "$nf" -gt 0 ] || { bad "live: mfixture with $ENV rc $rc"; indent <<<"$out"; }
    [ -n "$dir" ] && [ ! -e "$dir" ] && ok "live remove: fixture dir gone" || bad "live remove: dir '$dir' left or never installed"
fi

echo "$fails failed"
[ "$fails" -eq 0 ]
