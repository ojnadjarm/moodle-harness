#!/usr/bin/env bash
# Dogfood 3: build block_t937 (requires 2024100700) from one recipe plus the helpers, no hand steps.
# Offline (default): php -l, codechecker 0/0, mlang, mapicompat (+ --removed), mphpcompat, mrules, msteps --check in < 30 s.
# --live: one `mfixture with 5.2` holds the env lock: install, each generated PHPUnit file once, remove.
# Hand steps and defects: ~/agent-work/research/2026-10-20/T937/FRICTION.md.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
K="$(cd "$(dirname "$0")/.." && pwd)"; S="$K/../moodle-ci/scripts"; DL="$K/tests/fixtures/steps-5.2.txt"
LIVE=0; [ "${1:-}" = --live ] && LIVE=1
ENV=5.2; COMP=block_t937; TB=block_t937_mark

# --phpunit: the command `mfixture with` runs inside the env lock; it tests the installed copy.
if [ "${1:-}" = --phpunit ]; then
    dir="$(find "${MFIXTURE_ENVS:-$HOME/moodle-envs}/$ENV/www" -maxdepth 3 -type d -path '*/blocks/t937' | head -1)"
    [ -d "$dir/tests" ] || { echo "FAIL live: installed $COMP not found"; exit 1; }
    n=0; f=0
    while IFS= read -r t; do
        t0=$(date +%s); n=$((n + 1)); out="$(nice -n 19 "$S/mtest" phpunit "$t" 2>&1)"; rc=$?
        [ "$rc" -eq 0 ] && echo "ok   phpunit ${t#"$dir"/}, $(($(date +%s) - t0)) s" \
            || { echo "FAIL phpunit ${t#"$dir"/} rc $rc"; sed 's/^/    /' <<<"$out" | tail -12; f=$((f + 1)); }
    done < <(find "$dir/tests" -name '*_test.php' | sort)
    echo "live: $n PHPUnit files"
    [ "$n" -gt 0 ] && [ "$f" -eq 0 ]; exit
fi

MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
T="$(mktemp -d)"; W="$T/env/www"; P="$W/public/blocks/t937"
trap 'rm -rf "$T"' EXIT
fails=0; t00=$(date +%s)
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
indent() { sed 's/^/    /' | tail -"${1:-8}"; }
step() { local name="$1"; shift; local out; out="$("$@" 2>&1)" && ok "$name" || { bad "$name"; indent <<<"$out"; }; }

# Fake 5.2 tree and docker so msteps --check reads the fixture step dump offline (as behat.test.sh does).
mkdir -p "$T/bin" "$W/vendor/bin" "$W/public/blocks"
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
component: block_t937
name: T937 bookmarks
requires: 2024100700
copyright: 2026 onwards, Example Author <author@example.com>
tables:
  block_t937_mark:
    comment: Course bookmarks
    fields: [userid:int:10, courseid:int:10, title:char:255, url:char:1333, timecreated:int:10, timemodified:int:10]
    keys: [userid->user.id, courseid->course.id]
    indexes: [timecreated]
EOF
step "generate.py recipe tables:" python3 "$K/generate.py" --target-dir "$W/public/blocks" "$T/recipe.yaml"
[ -f "$P/version.php" ] || { echo "1 failed"; exit 1; }
step "access.py view" python3 "$K/access.py" "$P" view --type read --context block \
    --archetypes user=allow,manager=allow --title "View bookmarks"
step "access.py manage" python3 "$K/access.py" "$P" manage --type write --context block \
    --archetypes editingteacher=allow,manager=allow --title "Manage bookmarks"
step "external.py --ajax get_marks" python3 "$K/external.py" "$P" get_marks --params courseid:int --returns multiple \
    --type read --ajax --capability view
step "task.py --scheduled purge_old" python3 "$K/task.py" "$P" purge_old --scheduled "30 3 * * *"
step "event.py mark_created" python3 "$K/event.py" "$P" mark_created --crud c --edulevel participating \
    --objecttable "$TB"
step "event.py --observe user_deleted" python3 "$K/event.py" "$P" user_deleted --crud d --edulevel other \
    --observe '\core\event\user_deleted' --table "$TB"
step "table.py --dynamic marks" python3 "$K/table.py" "$P" marks --table "$TB" \
    --cols id,title,url,timecreated --datecols timecreated --dynamic --capability view
step "hook.py before_footer_html_generation" python3 "$K/hook.py" "$P" '\core\hook\output\before_footer_html_generation'
step "settings.py 2 settings + page" python3 "$K/settings.py" "$P" --setting maxmarks:configtext:20 \
    --setting retention:configduration:31536000 --page marks.php --cap block/t937:manage
step "privacy.py" python3 "$K/privacy.py" "$P"
step "behat.py add_block" python3 "$K/behat.py" "$P" add_block

for f in block_t937.php db/install.xml db/access.php db/services.php db/tasks.php db/events.php db/hooks.php settings.php \
    classes/external/get_marks.php classes/task/purge_old.php classes/event/mark_created.php classes/observer.php \
    classes/table/marks.php marks.php classes/privacy/provider.php tests/privacy/provider_test.php \
    tests/behat/add_block.feature; do
    [ -f "$P/$f" ] || bad "missing $f"
done
grep -q "TABLE NAME=\"$TB\"" "$P/db/install.xml" && ok "install.xml has $TB" || bad "install.xml tables"
grep -q "requires = 2024100700;" "$P/version.php" && ok "requires 2024100700" || bad "requires: $(grep requires "$P/version.php")"
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
chk mapicompat "$S/mapicompat" "$P"
chk "mapicompat --removed" "$S/mapicompat" "$P" --removed
chk mphpcompat "$S/mphpcompat" "$P"
chk mrules "$S/mrules" "$P"
out="$(PATH="$T/bin:$PATH" XDG_CACHE_HOME="$T/cache" "$S/msteps" --check "$P/tests/behat/add_block.feature" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q ', 0 undefined$' <<<"$out" && ok "msteps --check: $(tail -1 <<<"$out" | sed 's/^msteps: //')" \
    || { bad "msteps --check rc $rc"; indent <<<"$out"; }
off=$(($(date +%s) - t00))
[ "$off" -lt 30 ] && ok "offline in $off s" || bad "offline took $off s (>= 30)"

if [ "$LIVE" = 1 ]; then
    t0=$(date +%s)
    out="$("$S/mfixture" with "$ENV" "$P" -- bash "$0" --phpunit 2>&1)"; rc=$?
    dir="$(sed -n "s/^mfixture: installed $COMP at //p" <<<"$out")"
    grep '^\(ok  \|FAIL\|    \)' <<<"$out"
    nf="$(grep -c '^FAIL' <<<"$out")"; fails=$((fails + nf))
    grep -q '^live: [1-9][0-9]* PHPUnit files$' <<<"$out" && ok "$(grep '^live: ' <<<"$out")" || bad "live: 0 PHPUnit files run"
    [ "$rc" -eq 0 ] && ok "live: mfixture with $ENV rc 0, $(($(date +%s) - t0)) s" \
        || { [ "$nf" -gt 0 ] || bad "live: mfixture with $ENV rc $rc"; indent <<<"$out"; }
    [ -n "$dir" ] && [ ! -e "$dir" ] && ok "live remove: fixture dir gone" || bad "live remove: dir '$dir' left or never installed"
fi

echo "$fails failed"
[ "$fails" -eq 0 ]
