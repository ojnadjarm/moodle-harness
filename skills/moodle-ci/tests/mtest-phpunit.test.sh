#!/usr/bin/env bash
# mtest phpunit on throwaway 4.x flat and 5.1+ public/ trees with stubbed docker: filter args, empty run, init, logs,
# anchored --changed filter, flat test fallback, grouped deprecations, stray test tables and --reset (refused drop,
# Moodle root, path after the flags).
set -uo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)/scripts/mtest"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.claude/hooks" "$T/bin" "$T/tmp"
for lay in flat public; do
    p="$T/$lay/local/x"; [ "$lay" = public ] && p="$T/$lay/public/local/x" && mkdir -p "$T/$lay/public/admin"
    mkdir -p "$T/$lay/vendor/bin" "$p/tests"
    touch "$T/$lay/vendor/bin/phpunit" "$p/tests/foo_test.php"
    printf "<?php\n\$CFG->dbtype    = 'pgsql';\n\$CFG->dbhost = 'db';\n\$CFG->phpunit_prefix = 'phpu_';\n" > "$T/$lay/config.php"
    echo "<?php \$plugin->component = 'local_x';" > "$p/version.php"
done
printf '#!/bin/sh\nprintf "c1\\t/var/www/html\\n"\n' > "$T/home/.claude/hooks/moodle-container.sh"
# docker stub: logs every command; --diag passes when READY=1; phpunit writes its --filter to $LOGF.filter and prints
# "No tests executed!" when EMPTY=1, the file $OUT when set; init.php prints $INITOUT and fails when INITFAIL=1;
# psql (mdb) logs its args to $LOGF.psql, its SQL to $LOGF.sql and lists the tables in $STRAY, or prints $PSQLERR on
# stderr and fails; util.php --drop refuses like a site with only phpu_ tables when DROPREFUSE=1.
cat > "$T/bin/docker" <<'EOF'
#!/bin/bash
c="${*: -1}"; echo "$c" >> "$LOGF"
case "$1" in inspect) echo proj; exit;; ps) echo db1; exit;; esac
case "$*" in *psql*) echo "$*" >> "$LOGF.psql"; cat >> "$LOGF.sql"; [ -n "${PSQLERR:-}" ] && { printf '%s\nsecond line\n' "$PSQLERR" >&2; exit 2; }; echo table_name; [ -n "${STRAY:-}" ] && printf '%s\n' $STRAY; exit 0;; esac
case "$c" in
    *init.php*) echo "${INITOUT:-}"; [ "${INITFAIL:-0}" != 1 ];;
    *util.php\ --diag*) [ "${READY:-0}" = 1 ];;
    *util.php\ --drop*) [ "${DROPREFUSE:-0}" = 1 ] && { echo "Can not drop non-test site!!"; exit 131; }; exit 0;;
    *vendor/bin/phpunit*) eval "set -- ${c#*&& }"; : > "$LOGF.filter"
        while [ $# -gt 0 ]; do [ "$1" = --filter ] && printf '%s' "$2" > "$LOGF.filter"; shift; done
        if [ "${EMPTY:-0}" = 1 ]; then echo "No tests executed!"; elif [ -n "${OUT:-}" ]; then cat "$OUT"; else echo "OK (1 test, 1 assertion)"; fi;;
esac
EOF
chmod +x "$T/bin/"* "$T/home/.claude/hooks/moodle-container.sh"
run() { : > "$T/log"; env HOME="$T/home" PATH="$T/bin:$PATH" LOGF="$T/log" TMPDIR="$T/tmp" XDG_STATE_HOME="$T/state" "$@" 2>&1; }
bad=0
check() { if eval "$1"; then echo "PASS $2"; else echo "FAIL $2"; bad=1; fi; }
F="$T/flat/local/x" P="$T/public/public/local/x"

run READY=1 "$M" phpunit "$F" --filter foo >/dev/null; a="$(grep phpunit "$T/log")"
run READY=1 "$M" phpunit "$F" --filter=foo >/dev/null; b="$(grep phpunit "$T/log")"
check '[ "$a" = "$b" ] && grep -q -- "--filter foo" <<<"$a"' "--filter=X and --filter X give the same args"
run READY=1 "$M" phpunit "$F/tests/foo_test.php" --filter=bar >/dev/null
check 'grep -q -- "--filter foo_test::bar" "$T/log"' "file target + --filter=X joins class::method"

out="$(run READY=1 EMPTY=1 "$M" phpunit "$F" --filter nomatch)"; rc=$?
check '[ $rc = 1 ] && grep -q "mtest: no tests matched" <<<"$out"' "empty run is rc 1"
run READY=1 "$M" phpunit "$F" >/dev/null; check '[ $? = 0 ]' "a run with tests stays rc 0"

out="$(run READY=0 "$M" init phpunit "$F")"; rc=$?
check '[ $rc = 0 ] && grep -q "nice -n 19 php admin/tool/phpunit/cli/init.php" "$T/log"' "4.x flat: stale -> niced init"
check 'grep -qE "init in [0-9]+s" <<<"$out" && ! grep -q vendor/bin/phpunit "$T/log"' "init prints seconds, runs no tests"
run READY=0 "$M" phpunit "$P" --init-only >/dev/null
check 'grep -q "nice -n 19 php public/admin/tool/phpunit/cli/init.php" "$T/log"' "5.1+ public/: --init-only inits"
out="$(run READY=1 "$M" init phpunit "$P")"; rc=$?
check '[ $rc = 0 ] && ! grep -q init.php "$T/log" && grep -q "fresh" <<<"$out"' "fresh env: no init"

out="$(run READY=1 "$M" phpunit "$F" --filter)"; rc=$?
check '[ $rc = 2 ] && grep -q "needs a value" <<<"$out" && ! grep -q vendor/bin/phpunit "$T/log"' "bare trailing --filter: usage rc 2, no run"
out="$(run READY=1 "$M" phpunit "$F")"; lp="${out##*full log }"
check '[[ "$lp" == "$T/state/moodle-harness/logs/local_x/mtest-phpunit-"*.log ]] && [ -s "$lp" ]' "log lands in the component's log home"
check '[ -z "$(ls -A "$T/tmp")" ]' "nothing written to TMPDIR"

# --changed on a git fixture: plugin repo with a class + its test, a class without a test, lib.php.
mkdir -p "$F/classes/sub" "$F/tests/sub"
touch "$F/classes/sub/a.php" "$F/tests/sub/a_test.php" "$F/classes/b.php" "$F/lib.php" "$F/README.md"
git -C "$F" init -q && git -C "$F" add -A && git -C "$F" -c user.email=t@t -c user.name=t commit -qm base
out="$(run READY=1 "$M" phpunit "$F" --changed)"; rc=$?
check '[ $rc = 0 ] && grep -q "mtest: no changes vs HEAD" <<<"$out" && [ ! -s "$T/log" ]' "--changed, clean tree: rc 0 no changes, no docker"
echo x >> "$F/classes/sub/a.php"; touch "$F/tests/new_test.php"; echo x >> "$F/README.md"
out="$(run READY=1 "$M" phpunit "$F" --changed)"; rc=$?
check '[ $rc = 0 ] && grep -q "classes/sub/a.php -> tests/sub/a_test.php" <<<"$out" && grep -q "tests/new_test.php -> tests/new_test.php" <<<"$out" && grep -q "README.md -> skip" <<<"$out"' "--changed prints the mapping (class->test, untracked test, non-PHP skip)"
check 'grep -q -- "--testsuite local_x_testsuite --filter" "$T/log" && [ "$(cat "$T/log.filter")" = "\\\\a_test(::|\$)|\\\\new_test(::|\$)" ]' "--changed runs only the mapped tests, each name anchored"
# PHPUnit wraps a filter that is not a valid regex in /…/i and matches it against Class::method.
matches() { php -r 'exit(preg_match("/" . str_replace("/", "\\/", $argv[1]) . "/i", $argv[2]) === 1 ? 0 : 1);' "$(cat "$T/log.filter")" "$1"; }
check 'matches "local_x\\sub\\a_test::test_one" && matches "local_x\\new_test::test_two with data set #0"' "anchored filter matches the mapped classes"
check '! matches "local_x\\banana_test::test_one" && ! matches "local_x\\data_test::test_one" && ! matches "local_x\\a_test_extra::test_one"' "anchored filter skips banana_test, data_test, a_test_extra"
check '[ "$(head -1 <<<"$out")" = "mtest: --changed vs HEAD" ]' "--changed prints the mapping first"
echo x >> "$F/classes/b.php"
out="$(run READY=1 "$M" phpunit "$F" --changed)"
check 'grep -q "classes/b.php -> local_x_testsuite" <<<"$out" && grep vendor/bin/phpunit "$T/log" | grep -q -- "--testsuite local_x_testsuite" && ! grep vendor/bin/phpunit "$T/log" | grep -q -- --filter' "class without a test -> whole suite, no filter"
git -C "$F" add -A && git -C "$F" -c user.email=t@t -c user.name=t commit -qm more
out="$(run READY=1 "$M" phpunit "$F" --changed)"
check 'grep -q "no changes vs HEAD" <<<"$out"' "--changed after commit: no changes vs HEAD"
out="$(run READY=1 "$M" phpunit "$F" --changed HEAD~1)"
check 'grep -q "mtest: --changed vs HEAD~1" <<<"$out" && grep -q "classes/b.php -> local_x_testsuite" <<<"$out"' "--changed HEAD~1 maps committed changes"
echo x >> "$F/README.md"
out="$(run READY=1 "$M" phpunit "$F" --changed)"; rc=$?
check '[ $rc = 0 ] && grep -q "no changes with PHPUnit tests" <<<"$out" && ! grep -q vendor/bin/phpunit "$T/log"' "--changed, only non-PHP: rc 0, no run"
mkdir -p "$F/classes/flat" "$F/classes/both" "$F/tests/both"
touch "$F/classes/flat/c.php" "$F/tests/c_test.php" "$F/classes/both/d.php" "$F/tests/both/d_test.php" "$F/tests/d_test.php"
git -C "$F" add -A && git -C "$F" -c user.email=t@t -c user.name=t commit -qm flat
echo x >> "$F/classes/flat/c.php"
out="$(run READY=1 "$M" phpunit "$F" --changed)"; rc=$?
check '[ $rc = 0 ] && grep -q "classes/flat/c.php -> tests/c_test.php" <<<"$out" && [ "$(cat "$T/log.filter")" = "\\\\c_test(::|\$)" ]' "--changed: classes/x/y.php with no tests/x/ -> flat tests/y_test.php, no whole suite"
git -C "$F" checkout -q -- classes/flat/c.php; echo x >> "$F/classes/both/d.php"
out="$(run READY=1 "$M" phpunit "$F" --changed)"
check 'grep -q "classes/both/d.php -> tests/both/d_test.php" <<<"$out"' "--changed: tests/x/y_test.php wins over the flat one"
git -C "$F" checkout -q -- classes/both/d.php
out="$(run READY=1 "$M" phpunit "$F" --changed nosuchref)"; rc=$?
check '[ $rc = 2 ] && grep -q "git diff vs nosuchref failed" <<<"$out"' "--changed bad base: rc 2"
out="$(run READY=1 "$M" phpunit "$F" --changed --filter x)"; rc=$?
check '[ $rc = 2 ]' "--changed with --filter: usage rc 2"

# Deprecations: PHPUnit 11 detail lists (public/ tree has the 11.x Builder.php, the flat 4.x tree has none).
b="$T/public/vendor/phpunit/phpunit/src/TextUI/Configuration/Cli/Builder.php"; mkdir -p "$(dirname "$b")"
echo "'display-deprecations', 'display-phpunit-deprecations'," > "$b"
run READY=1 "$M" phpunit "$F" >/dev/null
check '! grep -q -- --display-deprecations "$T/log"' "PHPUnit 9 tree: no display flags"
cat > "$T/dep.out" <<'EOF'
PHPUnit 11.5.55 by Sebastian Bergmann and contributors.

..                                                                  2 / 2 (100%)

Time: 00:00.093, Memory: 44.00 MB

There was 1 PHPUnit test runner deprecation:

1) Your XML configuration validates against a deprecated schema.

--

2 tests triggered 5 PHPUnit deprecations:

1) local_x\foo_test::test_a
* Metadata found in doc-comment for class local_x\foo_test. Metadata in doc-comments is deprecated and will no longer be supported in PHPUnit 12. Update your test code to use attributes instead.
* Metadata found in doc-comment for method local_x\foo_test::test_a(). Metadata in doc-comments is deprecated and will no longer be supported in PHPUnit 12. Update your test code to use attributes instead.
* Metadata found in doc-comment for method local_x\foo_test::test_b(). Metadata in doc-comments is deprecated and will no longer be supported in PHPUnit 12. Update your test code to use attributes instead.

/var/www/html/public/local/x/tests/foo_test.php:30

2) local_x\bar_test::test_c
Metadata found in doc-comment for method local_x\bar_test::test_c(). Metadata in doc-comments is deprecated and will no longer be supported in PHPUnit 12. Update your test code to use attributes instead.

/var/www/html/public/local/x/tests/bar_test.php:12

--

2 tests triggered 2 deprecations:

1) /var/www/html/public/local/x/lib.php:44
Function old_api() is deprecated

Triggered by:

* local_x\foo_test::test_a (3 times)
  /var/www/html/public/local/x/tests/foo_test.php:30

* local_x\bar_test::test_c
  /var/www/html/public/local/x/tests/bar_test.php:12

2) /var/www/html/public/local/x/classes/y.php:9
Creation of dynamic property local_x\y::$z is deprecated

OK, but there were issues!
Tests: 2, Assertions: 2, Deprecations: 2, PHPUnit Deprecations: 6.
EOF
out="$(run READY=1 OUT="$T/dep.out" "$M" phpunit "$P")"; rc=$?
check '[ $rc = 0 ] && grep -q -- "--display-deprecations --display-phpunit-deprecations" "$T/log"' "PHPUnit 11 tree: display flags passed"
check 'grep -qF "  4x Metadata found in doc-comment: expected (@covers, guidelines) (first $T/public/public/local/x/tests/foo_test.php:30)" <<<"$out"' "metadata deprecations grouped, labelled expected, first host file:line"
check 'grep -qF "  4x Function old_api() is deprecated (first $T/public/public/local/x/lib.php:44)" <<<"$out" && grep -qF "  1x Creation of dynamic property" <<<"$out" && grep -qF "  1x Your XML configuration validates" <<<"$out"' "PHP and runner deprecations grouped with counts"
check '! grep -q "^There was 1 PHPUnit test runner deprecation" <<<"$out" && grep -q "^Tests: 2" <<<"$out"' "a deprecation list is not shown as a failure"
for i in 1 2 3 4 5 6 7; do printf '%s) /var/www/html/public/local/x/lib.php:%s\nmessage %s is deprecated\n\n' "$i" "$i" "$i"; done |
    { echo "7 tests triggered 7 deprecations:"; echo; cat; echo "OK, but there were issues!"; echo "Tests: 7, Assertions: 7, Deprecations: 7."; } > "$T/dep7.out"
out="$(run READY=1 OUT="$T/dep7.out" "$M" phpunit "$P")"
check '[ "$(grep -c "^  1x message" <<<"$out")" = 5 ]' "at most 5 grouped lines"
out="$(run READY=1 "$M" phpunit "$P")"
check '! grep -q "deprecations by message" <<<"$out"' "no deprecations in the summary: no grouped lines"
printf 'OK, but there were issues!\nTests: 1, Assertions: 1, Deprecations: 1.\n' > "$T/dep0.out"
out="$(run READY=1 OUT="$T/dep0.out" "$M" phpunit "$P")"
check 'grep -q "^Tests: 1" <<<"$out" && ! grep -q "deprecations by message" <<<"$out"' "Deprecations > 0 with no detail: no empty header"

# Partly initialised test DB: stray phpu_ tables after a failed init, and --reset.
out="$(run READY=0 INITFAIL=1 STRAY=phpu_search_simpledb_index "$M" init phpunit "$F")"; rc=$?
check '[ $rc = 1 ] && grep -qxF "mtest: 1 stray phpu_ tables (e.g. phpu_search_simpledb_index); fix: mtest init phpunit --reset $T/flat" <<<"$out" && grep -q "init failed" <<<"$out"' "init fails: stray phpu_ tables counted with a --reset fix naming the Moodle root"
check 'grep -qF "table_schema = current_schema() AND table_name LIKE '"'"'phpu\_%'"'"'" "$T/log.sql"' "stray query: pgsql schema, phpunit_prefix with _ escaped"
out="$(run READY=0 INITFAIL=1 "$M" init phpunit "$F")"; rc=$?
check '[ $rc = 1 ] && grep -q "init failed" <<<"$out" && ! grep -q stray <<<"$out"' "init fails, no phpu_ tables: no stray line"
out="$(run READY=0 INITFAIL=1 PSQLERR="psql: error: connection refused" "$M" init phpunit "$F")"; rc=$?
check '[ $rc = 1 ] && grep -qxF "mtest: stray-table lookup failed (psql: error: connection refused)" <<<"$out" && ! grep -q "second line" <<<"$out" && grep -q "init failed" <<<"$out"' "stray lookup fails: named with the first mdb error line"
out="$(run READY=0 INITOUT="Database is partially installed" STRAY="phpu_config phpu_user" "$M" init phpunit "$F")"; rc=$?
check '[ $rc = 0 ] && grep -qF "mtest: 2 stray phpu_ tables (e.g. phpu_config)" <<<"$out"' "init output says partially: stray line even on rc 0"
: > "$T/log.sql"; out="$(run READY=0 STRAY=phpu_config "$M" init phpunit "$F")"
check '[ ! -s "$T/log.sql" ] && ! grep -q stray <<<"$out"' "clean init: no stray lookup"
: > "$T/log.sql"; out="$(run READY=1 "$M" init phpunit "$P" --reset)"; rc=$?
check '[ $rc = 0 ] && grep -n "" "$T/log" | grep -E "util.php --drop|init.php" | tr "\n" " " | grep -qE "public/admin/tool/phpunit/cli/util.php --drop.*nice -n 19 php public/admin/tool/phpunit/cli/init.php" && grep -qE "init in [0-9]+s" <<<"$out"' "--reset on a fresh env: drop, then a niced init"
check 'grep -qF "mtest: phpunit env reset -> init" <<<"$out" && ! grep -q "env stale" <<<"$out"' "--reset says env reset, not env stale"
out="$(run READY=1 "$M" phpunit "$F" --reset)"; rc=$?
check '[ $rc = 0 ] && grep -q "util.php --drop" "$T/log" && grep -q vendor/bin/phpunit "$T/log"' "phpunit --reset: drop, init, then the run"
out="$(run READY=1 "$M" behat "$F" --reset)"; rc=$?
check '[ $rc = 2 ] && grep -q "phpunit only" <<<"$out" && [ ! -s "$T/log" ]' "behat --reset: usage rc 2, no docker"

# util.php --drop refuses (only phpu_ tables, no phpu_config): --reset drops them through mdb --write, then inits.
: > "$T/log.sql"; : > "$T/log.psql"
out="$(run READY=0 DROPREFUSE=1 STRAY="phpu_local_aicharts_chart phpu_local_aicharts_point" "$M" init phpunit "$F" --reset)"; rc=$?
check '[ $rc = 0 ] && grep -qF "dropping 2 phpu_ tables: phpu_local_aicharts_chart phpu_local_aicharts_point" <<<"$out" && grep -qF "DROP TABLE phpu_local_aicharts_chart, phpu_local_aicharts_point" "$T/log.sql"' "drop refused: lists the phpu_ tables and drops them"
check '[ "$(wc -l < "$T/log.psql")" = 2 ] && head -1 "$T/log.psql" | grep -q read_only && ! tail -1 "$T/log.psql" | grep -q read_only && grep -E "util.php --drop|init.php" "$T/log" | tr "\n" " " | grep -qE "util.php --drop.*nice -n 19 php admin/tool/phpunit/cli/init.php"' "drop refused: the DROP is a --write mdb call, then a niced init"
: > "$T/log.sql"; out="$(run READY=0 DROPREFUSE=1 STRAY="phpu_config mdl_user" "$M" init phpunit "$F" --reset)"; rc=$?
check '[ $rc = 1 ] && grep -qF "mdl_user" <<<"$out" && ! grep -q DROP "$T/log.sql" && ! grep -q init.php "$T/log"' "drop refused, a listed table lacks the prefix: rc 1 naming it, no DROP, no init"
: > "$T/log.sql"; out="$(run READY=0 DROPREFUSE=1 "$M" init phpunit "$F" --reset)"; rc=$?
check '[ $rc = 1 ] && grep -q "no phpu_ tables" <<<"$out" && ! grep -q DROP "$T/log.sql"' "drop refused, no phpu_ tables: rc 1, no DROP"
cp "$T/flat/config.php" "$T/cfg.bak"; echo "\$CFG->prefix = 'phpu_';" >> "$T/flat/config.php"
: > "$T/log.sql"; out="$(run READY=0 DROPREFUSE=1 STRAY=phpu_user "$M" init phpunit "$F" --reset)"; rc=$?
check '[ $rc = 1 ] && grep -q "site prefix" <<<"$out" && ! grep -q DROP "$T/log.sql"' "drop refused, phpunit_prefix = site prefix: rc 1, no DROP"
cp "$T/cfg.bak" "$T/flat/config.php"
mkdir -p "$T/envs"; cp -r "$T/flat" "$T/envs/vass"
: > "$T/log.sql"; out="$(run READY=0 DROPREFUSE=1 STRAY=phpu_user "$M" init phpunit "$T/envs/vass/local/x" --reset)"; rc=$?
check '[ $rc = 1 ] && grep -q "vass/4.5" <<<"$out" && [ ! -s "$T/log.sql" ]' "drop refused in a vass env: rc 1, no mdb call"

# A Moodle root (no plugin) and a path after the flags.
out="$(cd "$T/flat" && run READY=1 "$M" init phpunit --reset)"; rc=$?
check '[ $rc = 0 ] && grep -q "util.php --drop" "$T/log" && grep -q "nice -n 19 php admin/tool/phpunit/cli/init.php" "$T/log" && ! grep -q vendor/bin/phpunit "$T/log"' "init --reset from a Moodle root: drop, init, no run"
out="$(cd "$T" && run READY=1 "$M" init phpunit --reset "$T/public")"; rc=$?
check '[ $rc = 0 ] && grep -q "nice -n 19 php public/admin/tool/phpunit/cli/init.php" "$T/log"' "init --reset <root> after the flags uses that root"
out="$(cd "$T" && run READY=1 "$M" phpunit --filter foo "$F")"; rc=$?
check '[ $rc = 0 ] && grep vendor/bin/phpunit "$T/log" | grep -q -- "--testsuite local_x_testsuite --filter foo"' "plugin path after the flags runs that plugin"
out="$(cd "$T/flat" && run READY=1 "$M" phpunit)"; rc=$?
check '[ $rc = 2 ] && grep -q "Moodle root takes init or --reset only" <<<"$out" && [ ! -s "$T/log" ]' "phpunit run from a Moodle root: usage rc 2, no docker"
exit "$bad"
