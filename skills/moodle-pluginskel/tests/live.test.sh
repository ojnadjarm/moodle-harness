#!/usr/bin/env bash
# Live proof on a dev env: render mod_t803 with every helper, install, add an instance, test, back up, restore, remove.
# Runs only with MOODLE_HARNESS_LIVE=1 (else SKIP rc 0); env MOODLE_HARNESS_LIVE_ENV (default 5.2, mfixture allow-list).
set -uo pipefail
[ "${MOODLE_HARNESS_LIVE:-}" = 1 ] || { echo "SKIP live.test.sh: set MOODLE_HARNESS_LIVE=1 to run on a live env"; exit 0; }
K="$(cd "$(dirname "$0")/.." && pwd)"; S="$K/../moodle-ci/scripts"
ENV="${MOODLE_HARNESS_LIVE_ENV:-5.2}"; COMP=mod_t803
T="$(mktemp -d)"; P="$T/t803"; installed=""; bk=""
fails=0
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
indent() { sed 's/^/    /' | tail -"${1:-8}"; }
secs() { echo "$(($(date +%s) - $1)) s"; }
php_in() { docker exec -i -u www-data -w "$D" "$C" nice -n 19 php "$@"; }
phpq() { php_in <<<"<?php define('CLI_SCRIPT', true); require 'config.php'; $1"; }
site_clean() {
    phpq "require_once(\$CFG->dirroot . '/course/lib.php'); require_once(\$CFG->dirroot . '/user/lib.php');
        \\core\\session\\manager::set_user(get_admin());
        foreach (\$DB->get_records_select('course', \$DB->sql_like('shortname', '?'), ['${COMP}_testdata%']) as \$c) {
            delete_course(\$c, false);
        }
        foreach (\$DB->get_records_select('user', \$DB->sql_like('username', '?') . ' AND deleted = 0',
            ['${COMP}_testdata_%']) as \$u) {
            delete_user(\$u);
        }"
}
trap '[ -n "$bk" ] && docker exec "$C" rm -rf "$bk"; [ -n "$installed" ] && { site_clean; "$S/mfixture" rm "$ENV" "$COMP"; } >/dev/null 2>&1; rm -rf "$T"' EXIT

cat > "$T/recipe.yaml" <<'EOF'
component: mod_t803
name: T803 activity
requires: "5.2"
copyright: 2026 onwards, Example Author <author@example.com>
features:
  settings: true
capabilities:
  - name: submit
    title: Submit a T803 entry
    captype: write
    contextlevel: CONTEXT_MODULE
    archetypes:
      - role: student
        permission: CAP_ALLOW
EOF
out="$({ python3 -B "$K/generate.py" --target-dir "$T" "$T/recipe.yaml" && python3 -B "$K/backup.py" "$P" \
    && python3 -B "$K/external.py" "$P" get_items --params courseid:int --capability view \
    && python3 -B "$K/behat.py" "$P" basic_use && python3 -B "$K/testdata.py" "$P"; } 2>&1)" \
    && ok "render: generate + backup.py + external.py + behat.py + testdata.py, $(find "$P" -type f | wc -l) files" \
    || { bad "render"; indent <<<"$out"; exit 1; }
setup="$P/.research/testdata/setup.php"
sed -i "0,/^cli_writeln(\"Course/s//\$t803 = ${COMP}_testdata_module(\$course, 't803', '$COMP live instance');\n&/" "$setup"

t0=$(date +%s)
out="$("$S/mfixture" add "$ENV" "$P" 2>&1)"; rc=$?
dir="$(sed -n "s/^mfixture: installed $COMP at //p" <<<"$out")"
W="$(realpath "$HOME/moodle-envs/$ENV/www")"
ls -d "$W/mod/t803" "$W/public/mod/t803" >/dev/null 2>&1 && installed=1
IFS=$'\t' read -r C D < <("$HOME/.claude/hooks/moodle-container.sh" "${dir:-$HOME/moodle-envs/$ENV/www}")
cdir="$D${dir#"$W"}"
if [ "$rc" -ne 0 ] || [ ! -d "$dir" ]; then
    bad "install: mfixture add rc $rc"; indent <<<"$out"; exit 1
fi
ok "install: mfixture add $ENV (upgrade rc 0, nothing pending), $(secs "$t0")"

out="$(php_in "$cdir/.research/testdata/setup.php" 2>&1 && php_in "$cdir/.research/testdata/setup.php" 2>&1)"; rc=$?
rows="$(phpq "echo \$DB->count_records('t803');" 2>&1 | tail -1)"
[ "$rc" -eq 0 ] && [ "$rows" = 1 ] && ok "instance: testdata setup.php twice rc 0, t803 rows = $rows" \
    || { bad "instance: setup.php rc $rc, t803 rows = $rows"; indent <<<"$out"; }

t0=$(date +%s)
out="$("$S/mtest" phpunit "$dir/tests/external/get_items_test.php" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "external: mtest phpunit get_items_test.php rc 0, $(secs "$t0")" \
    || { bad "external: mtest phpunit rc $rc"; indent <<<"$out"; }

out="$("$S/mprivacy" "$dir" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "privacy: mprivacy rc 0" || { bad "privacy: mprivacy rc $rc"; indent <<<"$out"; }

out="$("$S/msteps" --check "$dir/tests/behat/basic_use.feature" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "behat: msteps --check basic_use.feature, $(tail -1 <<<"$out" | sed 's/^msteps: //')" \
    || { bad "behat: msteps --check rc $rc"; indent <<<"$out"; }

t0=$(date +%s)
cid="$(phpq "echo \$DB->get_field('course', 'id', ['shortname' => '${COMP}_testdata']);" 2>&1 | tail -1)"
bk="$(docker exec -u www-data "$C" mktemp -d /tmp/t803-XXXX)"
out="$(php_in admin/cli/backup.php --courseid="$cid" --destination="$bk" 2>&1)"; rc=$?
mbz="$(docker exec "$C" sh -c "ls $bk/*.mbz" 2>/dev/null | head -1)"
if [ "$rc" -eq 0 ] && [ -n "$mbz" ]; then
    catid="$(phpq "echo \$DB->get_field_sql('SELECT MIN(id) FROM {course_categories}');" 2>&1 | tail -1)"
    out="$(php_in admin/cli/restore_backup.php --file="$mbz" --categoryid="$catid" 2>&1)"; rc=$?
    new="$(phpq "echo \$DB->count_records_sql('SELECT COUNT(1) FROM {t803} t JOIN {course_modules} cm
        ON cm.instance = t.id JOIN {modules} m ON m.id = cm.module AND m.name = ? WHERE t.course <> ?', ['t803', $cid]);" \
        2>&1 | tail -1)"
    [ "$rc" -eq 0 ] && [ "$new" = 1 ] && ok "backup: course $cid backed up and restored, restored course has 1 t803 cm, $(secs "$t0")" \
        || { bad "backup: restore rc $rc, t803 instances in the restored course = $new"; indent <<<"$out"; }
else
    bad "backup: backup.php rc $rc, no .mbz"; indent <<<"$out"
fi
docker exec "$C" rm -rf "$bk"; bk=""

site_clean >/dev/null 2>&1
out="$("$S/mfixture" rm "$ENV" "$COMP" 2>&1)"; rc=$?
cp="$(phpq "echo \$DB->count_records('config_plugins', ['plugin' => '$COMP']);" 2>&1 | tail -1)"
[ "$rc" -eq 0 ] && [ "$cp" = 0 ] && [ ! -e "$dir" ] && { installed=""; ok "remove: mfixture rm rc 0, config_plugins rows = 0, dir gone"; } \
    || { bad "remove: mfixture rm rc $rc, config_plugins rows = $cp"; indent <<<"$out"; }

echo "$fails failed"
[ "$fails" -eq 0 ]
