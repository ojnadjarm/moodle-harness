#!/usr/bin/env bash
# mci-workflow on throwaway plugin dirs: branch range, PHP/pg per branch, bitbucket shape, refused overwrite.
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/mci-workflow"
T="$(mktemp -d "${TMPDIR:-/tmp}/mci-workflow-test-XXXX")"; trap 'rm -rf "$T"' EXIT
fail=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
plugin() { mkdir -p "$T/$1"; printf "<?php\n\$plugin->component = 'local_%s';\n\$plugin->requires = %s;\n%s" "$1" "$2" "$3" > "$T/$1/version.php"; }
yq() { python3 -I -c "import yaml, sys; d = yaml.safe_load(open(sys.argv[1])); print($2)" "$1"; }

plugin a 2024100700 "\$plugin->supported = [405, 503];\n"
"$S" "$T/a" >/dev/null; ok "gha written, exit 0" "[ $? -eq 0 ]"
G="$T/a/.github/workflows/moodle-ci.yml"
ok "gha parses" "yq '$G' 1 >/dev/null"
inc="d['jobs']['test']['strategy']['matrix']['include']"
ok "4.5..5.3 = 5 branches" "[ \"\$(yq '$G' \"len({x['moodle-branch'] for x in $inc})\")\" = 5 ]"
ok "6 jobs (5 max-PHP + 4.5 min-PHP)" "[ \"\$(yq '$G' \"len($inc)\")\" = 6 ]"
ok "4.5 min PHP 8.1, max 8.3, pg 13" "[ \"\$(yq '$G' \"sorted(x['php'] for x in $inc if x['moodle-branch'] == 'MOODLE_405_STABLE')\")\" = \"['8.1', '8.3']\" ]"
ok "5.3 PHP 8.4 pg 17" "yq '$G' \"[x for x in $inc if x['moodle-branch'] == 'MOODLE_503_STABLE']\" | grep -q \"'php': '8.4'.*'pg': '17'\""
ok "moodle-plugin-ci 4 steps" "grep -q 'moodle-plugin-ci ci \^4' '$G' && grep -q 'moodle-plugin-ci phpunit' '$G' && grep -q 'moodle-plugin-ci behat' '$G'"

echo "# edited" >> "$G"
"$S" "$T/a" 2>/dev/null; ok "refuse overwrite, exit 3" "[ $? -eq 3 ]"
ok "file kept" "tail -1 '$G' | grep -q '# edited'"

"$S" "$T/a" --format bitbucket >/dev/null; ok "bitbucket written" "[ $? -eq 0 ]"
B="$T/a/bitbucket-pipelines.yml"
par="d['pipelines']['default'][0]['parallel']"
ok "bitbucket parses, 6 parallel steps" "[ \"\$(yq '$B' \"len($par)\")\" = 6 ]"
ok "bitbucket services postgres13..17" "[ \"\$(yq '$B' \"sorted(d['definitions']['services'])\")\" = \"['postgres13', 'postgres14', 'postgres15', 'postgres16', 'postgres17']\" ]"
ok "bitbucket step image per PHP" "yq '$B' \"$par[0]['step']['image']\" | grep -qx 'moodlehq/moodle-php-apache:8.1'"
"$S" "$T/a" --format bitbucket 2>/dev/null; ok "bitbucket refuse overwrite" "[ $? -eq 3 ]"

plugin b 2025041400 ""
out="$("$S" "$T/b" --print)"; ok "--print, no file" "[ ! -e '$T/b/.github' ]"
ok "no supported: 5.0..newest = 4 branches" "[ \$(grep -c 'moodle-branch:' <<<\"\$out\") -eq 5 ] && [ \$(grep -o 'MOODLE_50[0-3]_STABLE' <<<\"\$out\" | sort -u | wc -l) -eq 4 ]"

"$S" "$T/nope" 2>/dev/null; ok "missing version.php exit 2" "[ $? -eq 2 ]"

ok "bitbucket keeps going: no default-jre, || rc=1, exit \$rc" "! grep -q default-jre '$B' && [ \$(grep -c 'moodle-plugin-ci .* || rc=1' '$B') -eq 48 ] && [ \$(grep -c 'exit \\\$rc' '$B') -eq 6 ]"
plugin c 2024100700 "\$plugin->supported = array(405, 501);\n"
ok "array(405, 501) = 3 branches" "[ \$(\"$S\" '$T/c' --print 2>&1 | grep -o 'MOODLE_[0-9]*_STABLE\|unparsable' | sort -u | wc -l) -eq 3 ]"
plugin d 2024100700 "\$plugin->supported = [ 405, 501, ];\n"
ok "[405, 501,] = 3 branches" "[ \$(\"$S\" '$T/d' --print 2>&1 | grep -o 'MOODLE_[0-9]*_STABLE\|unparsable' | sort -u | wc -l) -eq 3 ]"
plugin e 2024100700 "\$plugin->supported = [FOO, 501];\n"
ok "unparsable supported warns on stderr" "\"$S\" '$T/e' --print 2>&1 >/dev/null | grep -q 'warning: unparsable'"
plugin f 2024100700 ""; chmod 000 "$T/f/version.php"
err="$("$S" "$T/f" --print 2>&1 >/dev/null)"; rc=$?
ok "unreadable version.php: one line, exit 2" "[ $rc -eq 2 ] && [ \$(wc -l <<<\"\$err\") -eq 1 ] && grep -q 'cannot read' <<<\"\$err\""
plugin g 2024100700 ""; printf '// caf\xe9\n' >> "$T/g/version.php"
err="$("$S" "$T/g" --print 2>&1 >/dev/null)"; rc=$?
ok "non-UTF-8 version.php: one line, exit 2, no traceback" "[ $rc -eq 2 ] && [ \$(wc -l <<<\"\$err\") -eq 1 ] && ! grep -q Traceback <<<\"\$err\""
ok "phpmd advisory in gha and bitbucket" "grep -B2 'moodle-plugin-ci phpmd' '$G' | grep -q 'continue-on-error: true' && [ \$(grep -c 'moodle-plugin-ci phpmd || true' '$B') -eq 6 ] && ! grep -q 'phpmd || rc=1' '$B'"
plugin h 2024100700 "// \$plugin->supported is not set yet.\n/* \$plugin->supported = [405, 501]; */\n"
ok "commented supported: no warning, newest branch" "out=\$(\"$S\" '$T/h' --print 2>&1) && ! grep -q unparsable <<<\"\$out\" && grep -q MOODLE_503_STABLE <<<\"\$out\""
exit $fail
