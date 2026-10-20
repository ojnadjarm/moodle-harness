#!/usr/bin/env bash
# Dogfood: build local_t843desk (an owner-shaped local plugin) from one recipe plus every pluginskel helper.
# Offline (default): php -l, codechecker 0/0, mlang, mapicompat, mphpcompat green in < 60 s.
# --live: also install on 5.2 via mfixture, run each generated PHPUnit file once, msteps --check, then remove.
# Hand steps left are marked HAND (rows in ~/agent-work/research/2026-10-20/T891/FRICTION.md).
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
K="$(cd "$(dirname "$0")/.." && pwd)"; S="$K/../moodle-ci/scripts"
LIVE=0; [ "${1:-}" = --live ] && LIVE=1
ENV="${MOODLE_HARNESS_LIVE_ENV:-5.2}"; COMP=local_t843desk
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
T="$(mktemp -d)"; P="$T/t843desk"; installed=""
trap '[ -n "$installed" ] && "$S/mfixture" rm "$ENV" "$COMP" >/dev/null 2>&1; rm -rf "$T"' EXIT
fails=0; t00=$(date +%s)
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
indent() { sed 's/^/    /' | tail -"${1:-8}"; }
step() { local name="$1"; shift; local out; out="$("$@" 2>&1)" && ok "$name" || { bad "$name"; indent <<<"$out"; }; }

cat > "$T/recipe.yaml" <<'EOF'
component: local_t843desk
name: T843 help desk
requires: "4.5"
copyright: 2026 onwards, Example Author <author@example.com>
features:
  settings: true
  upgrade: true
capabilities:
  - name: view
    title: View help desk tickets
  - name: manage
    title: Manage help desk tickets
    captype: write
tables:
  local_t843desk_ticket:
    comment: Help desk tickets
    fields: [userid:int:10, subject:char:255, status:int:2, timecreated:int:10, timemodified:int:10]
    keys: [userid->user.id]
EOF
step "generate.py recipe" python3 "$K/generate.py" --target-dir "$T" "$T/recipe.yaml"
[ -f "$P/version.php" ] || { echo "1 failed"; exit 1; }

cp "$P/db/install.xml" "$T/install-v1.xml"
# HAND H3: the schema change itself (a new field) is typed into install.xml.
sed -i 's#^\(        <FIELD NAME="status".*\)#\1\n        <FIELD NAME="priority" TYPE="int" LENGTH="2" NOTNULL="true" DEFAULT="1" SEQUENCE="false"/>#' \
    "$P/db/install.xml"

step "upgrade.py --base-file: priority field step" python3 "$K/upgrade.py" --base-file "$T/install-v1.xml" "$P"
step "task.py --scheduled close_stale" python3 "$K/task.py" "$P" close_stale --scheduled "0 2 * * *"
step "task.py --adhoc notify_assignee" python3 "$K/task.py" "$P" notify_assignee --adhoc
step "external.py --ajax get_tickets" python3 "$K/external.py" "$P" get_tickets --params status:int --returns multiple \
    --type read --ajax --capability view
step "event.py ticket_created" python3 "$K/event.py" "$P" ticket_created --crud c --edulevel participating
step "event.py --observe user_deleted --table" python3 "$K/event.py" "$P" user_deleted \
    --observe '\core\event\user_deleted' --table local_t843desk_ticket
step "table.py --dynamic tickets" python3 "$K/table.py" "$P" tickets --table local_t843desk_ticket \
    --cols id,subject,status,timemodified --dynamic --capability local/t843desk:view
step "privacy.py provider" python3 "$K/privacy.py" "$P"
step "behat.py view_tickets" python3 "$K/behat.py" "$P" view_tickets
step "testdata.py" python3 "$K/testdata.py" "$P"
mkdir -p "$P/lang/es"
step "mlang --sync es" "$S/mlang" --sync es "$P"

for f in classes/external/get_tickets.php classes/task/close_stale.php classes/task/notify_assignee.php \
    classes/event/ticket_created.php classes/observer.php db/events.php classes/table/tickets.php tickets.php \
    classes/privacy/provider.php tests/privacy/provider_test.php tests/behat/view_tickets.feature db/services.php db/tasks.php; do
    [ -f "$P/$f" ] || bad "missing $f"
done
grep -q 'oldversion < ' "$P/db/upgrade.php" && ok "upgrade.php has a step" || bad "upgrade.php has no step"
ntests="$(find "$P/tests" -name '*_test.php' | wc -l)"
[ "$ntests" -gt 0 ] || bad "0 PHPUnit files"
ok "plugin: $(find "$P" -type f -not -path '*/.git/*' | wc -l) files, $ntests PHPUnit files"

t0=$(date +%s); lint=0
while IFS= read -r f; do php -l "$f" >/dev/null 2>&1 || { bad "php -l ${f#"$P"/}"; lint=1; }; done \
    < <(find "$P" -name '*.php' -not -path '*/.git/*')
[ "$lint" = 0 ] && ok "php -l clean"
if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
    out="$(nice -n 19 "$MPC" codechecker --max-warnings 0 "$P" 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && ! grep -q '| \(ERROR\|WARNING\) |' <<<"$out" && ok "codechecker 0 errors 0 warnings" \
        || { bad "codechecker rc $rc"; indent 20 <<<"$out"; }
else
    bad "codechecker: moodle-plugin-ci absent"
fi
for c in mlang mapicompat mphpcompat; do
    out="$(nice -n 19 "$S/$c" "$P" 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && ok "$c: $(tail -1 <<<"$out")" || { bad "$c rc $rc"; indent <<<"$out"; }
done
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
        out="$(nice -n 19 "$S/msteps" --check "$dir/tests/behat/view_tickets.feature" 2>&1)"; rc=$?
        [ "$rc" -eq 0 ] && ok "msteps --check view_tickets.feature" || { bad "msteps --check rc $rc"; indent <<<"$out"; }
        out="$("$S/mfixture" rm "$ENV" "$COMP" 2>&1)"; rc=$?
        [ "$rc" -eq 0 ] && [ ! -e "$dir" ] && { installed=""; ok "live remove: mfixture rm rc 0, dir gone"; } \
            || { bad "live remove: mfixture rm rc $rc"; indent <<<"$out"; }
    fi
fi

echo "$fails failed"
[ "$fails" -eq 0 ]
