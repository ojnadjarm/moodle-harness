#!/usr/bin/env bash
# Dogfood 2: build mod_t891 (requires 2024100700) from one recipe plus the wave-6 helpers, no hand steps.
# Offline (default): php -l, codechecker 0/0, mlang, mapicompat, mphpcompat (PHP 8.1), mmobile, msteps --check in < 60 s.
# --live: also install on 5.2 via mfixture, run each generated PHPUnit file once, msteps --check, then remove.
# Hand steps left: ~/agent-work/research/2026-10-20/T891/FRICTION.md.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
K="$(cd "$(dirname "$0")/.." && pwd)"; S="$K/../moodle-ci/scripts"; DL="$K/tests/fixtures/steps-5.2.txt"
LIVE=0; [ "${1:-}" = --live ] && LIVE=1
ENV=5.2; COMP=mod_t891
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
T="$(mktemp -d)"; W="$T/env/www"; P="$W/public/mod/t891"; installed=""
trap '[ -n "$installed" ] && "$S/mfixture" rm "$ENV" "$COMP" >/dev/null 2>&1; rm -rf "$T"' EXIT
fails=0; t00=$(date +%s)
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
indent() { sed 's/^/    /' | tail -"${1:-8}"; }
step() { local name="$1"; shift; local out; out="$("$@" 2>&1)" && ok "$name" || { bad "$name"; indent <<<"$out"; }; }

# Fake 5.2 tree and docker so msteps --check reads the fixture step dump offline (as behat.test.sh does).
mkdir -p "$T/bin" "$W/vendor/bin" "$W/public/mod"
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
component: mod_t891
name: T891 journal
requires: 2024100700
copyright: 2026 onwards, Example Author <author@example.com>
tables:
  t891:
    fields: [maxentries:int:10]
  t891_entry:
    comment: Journal entries
    fields: [t891:int:10, userid:int:10, entrytext:text, timecreated:int:10, timemodified:int:10]
    keys: [t891->t891.id, userid->user.id]
    indexes: [timecreated]
EOF
cat > "$T/behat.yaml" <<'EOF'
page: /admin/settings.php?section=modsettingt891
heading: T891 journal
EOF
step "generate.py recipe tables:" python3 "$K/generate.py" --target-dir "$W/public/mod" "$T/recipe.yaml"
[ -f "$P/version.php" ] || { echo "1 failed"; exit 1; }
step "access.py addentry" python3 "$K/access.py" "$P" addentry --type write --context module \
    --archetypes student=allow,editingteacher=allow,manager=allow --title "Add a journal entry"
step "settings.py 2 settings" python3 "$K/settings.py" "$P" --setting maxentries:configtext:10 \
    --setting allowedit:configcheckbox:1
step "form.py entry" python3 "$K/form.py" "$P" entry --fields entrytext:textarea --cap addentry --context course
step "backup.py" python3 "$K/backup.py" "$P"
step "privacy.py" python3 "$K/privacy.py" "$P"
step "mobile.py CoreCourseModuleDelegate" python3 "$K/mobile.py" "$P" --delegate CoreCourseModuleDelegate
step "behat.py page: basic_use" python3 "$K/behat.py" "$P" basic_use --recipe "$T/behat.yaml"
step "testdata.py --rows 3" python3 "$K/testdata.py" "$P" --rows 3

for f in db/install.xml db/access.php settings.php classes/form/entry.php amd/src/entry.js tests/form/entry_test.php \
    backup/moodle2/backup_t891_activity_task.class.php backup/moodle2/backup_t891_stepslib.php \
    backup/moodle2/restore_t891_activity_task.class.php backup/moodle2/restore_t891_stepslib.php \
    classes/privacy/provider.php tests/privacy/provider_test.php db/mobile.php classes/output/mobile.php \
    templates/mobileapp/t891.mustache tests/behat/basic_use.feature tests/generator/lib.php .research/testdata/rows.php; do
    [ -f "$P/$f" ] || bad "missing $f"
done
grep -q 'TABLE NAME="t891_entry"' "$P/db/install.xml" && grep -q 'FIELD NAME="maxentries"' "$P/db/install.xml" \
    && ok "install.xml: instance table merged, t891_entry added" || bad "install.xml tables"
grep -q "requires = 2024100700;" "$P/version.php" && ok "requires 2024100700" || bad "requires: $(grep requires "$P/version.php")"
grep -q "I visit \"/admin/settings.php?section=modsettingt891\"" "$P/tests/behat/basic_use.feature" \
    && ok "feature opens the settings page" || bad "feature has no page visit"
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
for c in mlang mapicompat mphpcompat mmobile; do
    out="$(nice -n 19 "$S/$c" "$P" 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && ok "$c: $(tail -1 <<<"$out")" || { bad "$c rc $rc"; indent <<<"$out"; }
    [ "$c" = mphpcompat ] && ! grep -q 'PHP 8\.1' <<<"$out" && bad "mphpcompat floor is not PHP 8.1"
done
out="$(PATH="$T/bin:$PATH" XDG_CACHE_HOME="$T/cache" "$S/msteps" --check "$P/tests/behat/basic_use.feature" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q ', 0 undefined$' <<<"$out" && ok "msteps --check: $(tail -1 <<<"$out" | sed 's/^msteps: //')" \
    || { bad "msteps --check rc $rc"; indent <<<"$out"; }
off=$(($(date +%s) - t00))
[ "$off" -lt 60 ] && ok "offline in $off s" || bad "offline took $off s (>= 60)"

if [ "$LIVE" = 1 ]; then
    t0=$(date +%s)
    installed=1; out="$("$S/mfixture" add "$ENV" "$P" 2>&1)"; rc=$?
    dir="$(sed -n "s/^mfixture: installed $COMP at //p" <<<"$out")"
    if [ "$rc" -ne 0 ] || [ ! -d "$dir" ]; then
        bad "live install: mfixture add $ENV rc $rc"; indent <<<"$out"
    else
        ok "live install: mfixture add $ENV rc 0, $(($(date +%s) - t0)) s"
        nrun=0
        while IFS= read -r f; do
            t0=$(date +%s); rel="${f#"$dir"/}"; nrun=$((nrun + 1))
            out="$(nice -n 19 "$S/mtest" phpunit "$f" 2>&1)"; rc=$?
            [ "$rc" -eq 0 ] && ok "phpunit $rel, $(($(date +%s) - t0)) s" || { bad "phpunit $rel rc $rc"; indent 12 <<<"$out"; }
        done < <(find "$dir/tests" -name '*_test.php' | sort)
        [ "$nrun" -gt 0 ] || bad "live: 0 PHPUnit files run"
        out="$(nice -n 19 "$S/msteps" --check "$dir/tests/behat/basic_use.feature" 2>&1)"; rc=$?
        [ "$rc" -eq 0 ] && ok "live msteps --check basic_use.feature" || { bad "live msteps --check rc $rc"; indent <<<"$out"; }
        out="$("$S/mfixture" rm "$ENV" "$COMP" 2>&1)"; rc=$?
        [ "$rc" -eq 0 ] && [ ! -e "$dir" ] && { installed=""; ok "live remove: mfixture rm rc 0, dir gone"; } \
            || { bad "live remove: mfixture rm rc $rc"; indent <<<"$out"; }
    fi
fi

echo "$fails failed"
[ "$fails" -eq 0 ]
