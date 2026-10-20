#!/usr/bin/env bash
# Drive msrc on mktemp envs and cache with a fake git and nice: env reuse, refused envs, requires mapping, fetch, exit codes.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/msrc"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" MOODLE_ENVS="$T/envs" XDG_CACHE_HOME="$T/cache" PATH="$T/bin:$PATH"
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
tree() { mkdir -p "$1/lib/classes"; printf "<?php\n\$version  = 1;\n\$branch   = '%s';\n" "$2" > "$1/version.php"; }
run() { out="$("$S" "$@" 2>"$T/err")"; rc=$?; }

mkdir -p "$T/bin" "$HOME"
cat > "$T/bin/nice" <<'EOF'
#!/usr/bin/env bash
echo "nice $*" >> "$T_LOG"; shift 2; exec "$@"
EOF
cat > "$T/bin/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >> "$T_LOG"
[ -n "${GIT_FAIL:-}" ] && { mkdir -p "${@: -1}"; exit 128; }
[ -n "${GIT_HANG:-}" ] && { mkdir -p "${@: -1}"; exec sleep 30; }
d="${@: -1}"; mkdir -p "$d/public/lib/classes"; printf "<?php\n\$branch   = '405';\n" > "$d/public/version.php"
EOF
chmod +x "$T/bin/nice" "$T/bin/git"; export T_LOG="$T/log"; : > "$T_LOG"

tree "$T/envs/5.3/www/public" 503
tree "$T/envs/5.2/www/public" 502
tree "$T/envs/4.5/www/public" 405
tree "$T/envs/vass/www/public" 405
tree "$T/envs/4.4/www" 404

run 5.3; [ "$rc" = 0 ] && [ "$out" = "$T/envs/5.3/www/public" ] && ok "5.3 reuses the env with \$branch 503" || bad "5.3: rc=$rc out=$out"
run 4.4; [ "$rc" = 0 ] && [ "$out" = "$T/envs/4.4/www" ] && ok "pre-public layout: www is the root" || bad "4.4: rc=$rc out=$out"
run 2026100500; [ "$out" = "$T/envs/5.3/www/public" ] && ok "requires 2026100500 maps to 5.3" || bad "requires 5.3: $out"
run 2026042004.02; [ "$out" = "$T/envs/5.2/www/public" ] && ok "requires 2026042004.02 maps to 5.2" || bad "requires 5.2: $out"
run 4.5; [ "$rc" = 3 ] && [ -z "$out" ] && grep -q 'msrc 4.5 --fetch' "$T/err" \
    && ok "4.5 and vass envs refused: rc 3 names --fetch" || bad "4.5 missing: rc=$rc out=$out err=$(cat "$T/err")"
run 2024100712; [ "$rc" = 3 ] && grep -q 'no 4.5 tree' "$T/err" && ok "requires 2024100712 maps to 4.5, rc 3" || bad "requires 4.5: rc=$rc"
for arg in 9.9 4.05 2010000000 abc; do
    run "$arg"; [ "$rc" = 2 ] && grep -q 'unknown branch' "$T/err" && ok "unknown '$arg' rc 2" || bad "unknown '$arg': rc=$rc"
done
run; [ "$rc" = 2 ] && ok "no argument rc 2" || bad "no argument: rc=$rc"
[ ! -s "$T_LOG" ] && ok "no git call without --fetch" || bad "git called: $(cat "$T_LOG")"

GIT_FAIL=1 run 4.5 --fetch; [ "$rc" = 1 ] && [ ! -e "$T/cache/moodle-harness/src/MOODLE_405_STABLE" ] \
    && [ -z "$(ls "$T/cache/moodle-harness/src")" ] && ok "failed clone rc 1, no tree or partial left" \
    || bad "failed clone: rc=$rc $(ls -a "$T/cache/moodle-harness/src")"
: > "$T_LOG"
run 4.5 --fetch; c="$T/cache/moodle-harness/src/MOODLE_405_STABLE"
[ "$rc" = 0 ] && [ "$out" = "$c/public" ] && ok "--fetch clones into the cache and prints its root" || bad "fetch: rc=$rc out=$out err=$(cat "$T/err")"
grep -q '^nice -n 19 git clone -q --depth 1 --branch MOODLE_405_STABLE https://github.com/moodle/moodle.git ' "$T_LOG" \
    && ok "clone is niced, depth 1, MOODLE_405_STABLE" || bad "clone args: $(cat "$T_LOG")"
: > "$T_LOG"
run 2024100700; [ "$out" = "$c/public" ] && [ ! -s "$T_LOG" ] && ok "requires 4.5 finds the cached tree, no git" || bad "cached: $out $(cat "$T_LOG")"
run 4.5 --fetch; [ "$rc" = 0 ] && [ ! -s "$T_LOG" ] && ok "--fetch on a present tree does not clone" || bad "refetch: $(cat "$T_LOG")"

for sig in INT TERM; do
    GIT_HANG=1 "$S" 5.1 --fetch >/dev/null 2>&1 & pid=$!
    s="$T/cache/moodle-harness/src"
    wait-for --every 0.1 --until "ls -d '$s'/MOODLE_501_STABLE.partial-* >/dev/null 2>&1" --job "$pid" >/dev/null 2>&1
    kill -s "$sig" "$pid"; wait "$pid"; rc=$?; want=130; [ "$sig" = TERM ] && want=143
    [ "$rc" = "$want" ] && [ -z "$(ls -d "$s"/MOODLE_501_STABLE* 2>/dev/null)" ] \
        && ok "$sig during --fetch: rc $want, partial clone removed" || bad "$sig: rc=$rc $(ls -a "$s")"
done

[ "$fails" -eq 0 ] && echo "PASS msrc.test.sh" || echo "FAIL msrc.test.sh: $fails"
[ "$fails" -eq 0 ]
