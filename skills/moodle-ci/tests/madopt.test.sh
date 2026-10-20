#!/usr/bin/env bash
# madopt on a 6-line fixture jsonl under <session>/subagents/: raw vs harness counts, --since window, usage;
# interpreter-launched tools, naive timestamps, unreadable files, heredoc bodies, quoted mentions, --raw shapes,
# excluded vass/other rows, sudo -u and python3 -W.
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/madopt"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got '$1')"; bad=1; fi; }

now="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
old="$(date -u -d '-30 days' +%Y-%m-%dT%H:%M:%S.000Z)"
call() { printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"%s"}}]}}\n' "$1" "$2"; }
mkdir -p "$T/p/sess/subagents"
{
    call "$now" 'cd /m/local/x && nice -n 19 $S/mtest phpunit tests/x_test.php'
    call "$now" 'docker exec moodle52 php vendor/bin/phpunit --filter x_test'
    call "$now" 'docker compose exec php php admin/cli/purge_caches.php'
    call "$now" 'cat ~/.claude/skills/moodle-ci/scripts/mtest | grep psql'
    printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","content":"psql ok"}]}}\n' "$now"
    call "$old" 'psql -U moodle -c \"select 1\"'
} > "$T/p/sess/subagents/agent-a.jsonl"
check "$(wc -l < "$T/p/sess/subagents/agent-a.jsonl")" 6 "fixture has 6 lines"

out="$("$S" "$T/p")"; rc=$?
check "$rc" 0 "default run rc 0"
check "$(grep '^raw' <<<"$out")" "raw 2: phpunit 1 behat 0 phpcs 0 grunt 0 psql 0 exec 1 version 0" "raw split, subagents read"
check "$(grep '^harness' <<<"$out")" "harness 1: mtest 1" "harness tool named; a cat of mtest is not a call"
check "$(grep '^adoption' <<<"$out")" "adoption 33% (harness 1 / 3 calls)" "ratio over 7d"

touch -d '-60 days' "$T/p/sess/subagents/agent-a.jsonl"
check "$("$S" --since 7d "$T/p" | grep '^adoption')" "adoption 0% (harness 0 / 0 calls)" "file older than window skipped"
check "$("$S" --since 90d "$T/p" | grep -o 'psql [0-9]')" "psql 1" "--since 90d takes the old psql"

"$S" --since 7x "$T/p" >/dev/null 2>&1; check $? 2 "bad --since: rc 2"
"$S" "$T/none" >/dev/null 2>&1; check $? 2 "missing dir: rc 2"
check "$("$S" --help | grep -c since)" 1 "--help names --since"

mkdir -p "$T/q/s"
naive="$(date -u +%Y-%m-%dT%H:%M:%S)"
{
    call "$now" 'bash $S/mtest phpunit tests/x_test.php'
    call "$now" 'nice -n 19 python3 ~/.claude/skills/moodle-ci/scripts/mdb -e x'
    call "$naive" 'phpunit --filter y'
} > "$T/q/s/a.jsonl"
call "$now" 'phpcs x.php' > "$T/q/s/locked.jsonl"; chmod 000 "$T/q/s/locked.jsonl"
out="$("$S" --since 1d "$T/q" 2>"$T/err")"; rc=$?
check "$(grep '^harness' <<<"$out")" "harness 2: mtest 1 mdb 1" "bash \$S/mtest and python3 .../mdb counted by script name"
check "$rc $(grep -o 'phpunit [0-9]' <<<"$out")" "0 phpunit 1" "naive timestamp read as UTC, rc 0"
check "$(cat "$T/err")" "madopt: 1 unreadable jsonl skipped" "unreadable jsonl skipped with a stderr count"

mkdir -p "$T/r/s"
{
    call "$now" "cat > x.sh <<'EOF'\\nphp vendor/bin/phpunit\\nEOF\\nphpcs y.php"
    call "$now" 'python3 - <<PY\nimport os; os.system(\"psql -c 1\")\nPY'
    call "$now" 'echo \"step 1; phpunit next\"'
    call "$now" 'bash -x $S/mtest phpunit tests/x_test.php'
    call "$now" 'docker exec moodle52 ps aux'
    call "$now" 'docker exec moodle52 ps aux'
    call "$now" 'docker exec -u www-data moodle52 php admin/cli/purge_caches.php --x'
} > "$T/r/s/a.jsonl"
out="$("$S" --raw "$T/r")"
check "$(grep '^raw [0-9]' <<<"$out")" "raw 2: phpunit 0 behat 0 phpcs 1 grunt 0 psql 0 exec 1 version 0" "heredoc bodies and quoted mentions not counted"
check "$(grep '^harness' <<<"$out")" "harness 1: mtest 1" "bash -x \$S/mtest: interpreter flags skipped"
check "$(sed -n '/^raw shapes/,$p' <<<"$out" | tr '\n' '|')" "raw shapes (top 10):|1 php admin/cli/purge_caches.php --x|1 phpcs y.php|" "--raw lists shapes after docker exec <c> or the tool"
check "$("$S" --raw 1 "$T/r" | sed -n '/^raw shapes/,$p' | wc -l)" 2 "--raw 1 prints one shape"
check "$("$S" --help | grep -c -- '--raw')" 2 "--help names --raw"

mkdir -p "$T/c/s"
{
    call "$now" 'bash -c \"cd /var/www && vendor/bin/phpunit --filter x_test\"'
    call "$now" 'bash -o pipefail -c \"mtest phpunit x\"'
    call "$now" 'sh -euo pipefail -c \"cd /m && mci\"'
    call "$now" 'bash -O extglob $S/mdb x'
    call "$now" 'python3 -I $S/mexec x'
    call "$now" 'docker exec moodle52 bash -c \"cd /var/www/html && php admin/cli/purge_caches.php\"'
    call "$now" "docker exec moodle52-db-1 sh -c \\\"psql -U moodle -c 'select 1'\\\""
} > "$T/c/s/a.jsonl"
out="$("$S" --raw "$T/c")"
check "$(grep '^harness' <<<"$out")" "harness 4: mtest 1 mci 1 mdb 1 mexec 1" "bash -o pipefail -c, sh -euo pipefail -c, bash -O x, python3 -I: harness inside"
check "$(grep '^raw [0-9]' <<<"$out")" "raw 3: phpunit 1 behat 0 phpcs 0 grunt 0 psql 1 exec 1 version 0" "bash -c \"cd X && phpunit\" is raw phpunit; sh -c psql is psql"
check "$(sed -n '/^raw shapes/,$p' <<<"$out" | tr '\n' '|')" "raw shapes (top 10):|1 php admin/cli/purge_caches.php|1 psql -U moodle|1 vendor/bin/phpunit --filter x_test|" "--raw shows the inner command of bash -c / sh -c, no '-c cd' row"

mkdir -p "$T/v/s"
callc() { printf '{"type":"assistant","timestamp":"%s","cwd":"%s","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"%s"}}]}}\n' "$now" "$1" "$2"; }
{
    callc /h/moodle-envs/vass/moodle 'docker exec db psql -U moodle -c 1'
    callc /h 'cd ~/moodle-envs/4.5 && docker compose exec -T db psql -U moodle'
    callc /h 'docker exec moodle45-app-1 php admin/cli/purge_caches.php'
    callc /h 'docker exec t456-godot ps -eo pid,etime,args'
    callc /h 'docker exec moodle52-app-1 bash -c \"ps aux | grep -v grep\"'
    callc /h 'docker exec moodle52-app-1 pgrep -af php'
    callc /h/moodle-envs/5.2 'docker exec moodle52-db-1 psql -U moodle -c 1'
    callc /h 'sudo -u www-data bash -c \"mtest phpunit x\"'
    callc /h 'python3 -W ignore $S/mdb x'
} > "$T/v/s/a.jsonl"
out="$("$S" "$T/v")"
check "$(grep '^excluded' <<<"$out")" "excluded 5: vass 3 other 2" "vass cwd, cd ~/moodle-envs/4.5, moodle45-*; ps/pgrep without php/moodle: excluded"
check "$(grep '^raw [0-9]' <<<"$out")" "raw 2: phpunit 0 behat 0 phpcs 0 grunt 0 psql 1 exec 1 version 0" "pgrep php and 5.2 psql stay raw"
check "$(grep '^harness' <<<"$out")" "harness 2: mtest 1 mdb 1" "sudo -u X and python3 -W ignore skipped"
check "$(grep '^adoption' <<<"$out")" "adoption 50% (harness 2 / 4 calls)" "ratio without excluded calls"
check "$("$S" --help | grep -c excluded)" 1 "--help names excluded"

[ "$bad" = 0 ] && echo "madopt: all PASS"
exit "$bad"
