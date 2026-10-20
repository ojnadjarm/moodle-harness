#!/usr/bin/env bash
# mci on a throwaway 5.x tree with a stub moodle-plugin-ci, fake docker/node/container finder: placement, skips, table, rc.
set -uo pipefail
SD="$(cd "$(dirname "$0")/.." && pwd)/scripts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
M="$T/scripts/mci"
R="$T/moodle" P="$T/moodle/public/local/x"
mkdir -p "$T/scripts" "$T/bin" "$T/core" "$T/home/.claude/hooks" "$T/home/.moodle-plugin-ci/bin" "$T/home/.moodle-plugin-ci/vendor/moodlehq/moodle-local_moodlecheck" \
    "$T/home/.nvm/versions/node/v22.3.0/bin" "$R/vendor/bin" "$R/node_modules" "$R/public/local" "$P/tests"
# PATH is the stubs plus these real tools only.
for c in bash sh env git cat chmod cp date dirname basename find grep head tail ls mkdir mktemp realpath rm sed sort stat tar awk cut id ln seq wc tr tee python3; do
    ln -s "$(command -v "$c")" "$T/core/$c"; done
touch "$T/home/.moodle-plugin-ci/vendor/moodlehq/moodle-local_moodlecheck/a"
touch "$R/vendor/bin/phpunit" "$R/config.php" "$R/public/version.php" "$P/tests/a_test.php" "$T/home/.moodle-plugin-ci/composer.lock"
echo '{"engines": {"node": ">=22.11.0 <23"}}' > "$R/package.json"
echo "<?php \$plugin->component = 'local_x';" > "$P/version.php"
printf '#!/bin/sh\n[ -n "$NOCONT" ] || printf "c1\\t/var/www/html\\n"\n' > "$T/home/.claude/hooks/moodle-container.sh"
printf '#!/bin/sh\necho v24.1.0\n' > "$T/bin/node"
printf '#!/bin/sh\necho v22.3.0\n' > "$T/home/.nvm/versions/node/v22.3.0/bin/node"
# Stub MPC: logs "step args | node" and exits $RED_<step> (default 0).
cat > "$T/home/.moodle-plugin-ci/bin/moodle-plugin-ci" <<EOF
#!/usr/bin/env bash
echo "\$* | \$(node --version)" >> "$T/mpc.log"
v="RED_\$1"; exit "\${!v:-0}"
EOF
# Fake docker: exec -i (tar push) drains stdin; exec -u (container MPC) logs argv and whether moodlecheck is placed;
# cat of the stamp prints \$STAMP; bash -c (mtest) passes.
cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
[ "\$1" = exec ] || exit 0
case "\$2" in
    -i) cat >/dev/null; echo push >> "$T/docker.log";;
    -u) shift 4; echo "cont \$* mc=\$([ -d "$R/public/local/moodlecheck" ] && echo y || echo n)" >> "$T/docker.log"
        v="RED_\$3"; exit "\${!v:-0}";;
    c1) [ "\$3" = cat ] && { echo "\${STAMP:-}"; exit; }; echo "OK (1 test, 1 assertion)";;
esac
EOF
# mci beside stub mprivacy and an mtest that stubs behat (logs argv, exits $RED_behat) and runs the real phpunit;
# both exit 3 (no container) under NOCONT.
cp "$SD/mci" "$M"; ln -s "$SD/phpcs-delta" "$T/scripts/phpcs-delta"; ln -s "$SD/mlog" "$T/scripts/mlog"; ln -s "$SD/mcovers" "$T/scripts/mcovers"
cat > "$T/scripts/mtest" <<EOF
#!/usr/bin/env bash
[ "\$1" = behat ] || exec "$SD/mtest" "\$@"
echo "mtest \$*" >> "$T/mpc.log"; [ -n "\${NOCONT:-}" ] && exit 3; exit "\${RED_behat:-0}"
EOF
printf '#!/bin/sh\n[ -n "$NOCONT" ] && exit 3; exit "${RED_privacy:-0}"\n' > "$T/scripts/mprivacy"
printf '#!/bin/sh\n[ -z "$PHPC_REAL" ] || exec "%s/mphpcompat" "$@"\necho "mphpcompat $*" >> "%s/mpc.log"; [ -z "$PHPC_MSG" ] || echo "$PHPC_MSG" >&2\nexit "${RED_phpcompat:-0}"\n' \
    "$SD" "$T" > "$T/scripts/mphpcompat"
# Stub mlang/mapicompat exit $RED_lang/$RED_apicompat; LANG_REAL/APIC_REAL run the real ones.
for t in mlang:lang:LANG_REAL mapicompat:apicompat:APIC_REAL; do IFS=: read -r f v r <<<"$t"
    printf '#!/bin/sh\n[ -z "$%s" ] || exec "%s/%s" "$@"\nexit "${RED_%s:-0}"\n' "$r" "$SD" "$f" "$v" > "$T/scripts/$f"; done
chmod +x "$T/scripts/mlang" "$T/scripts/mapicompat" "$T/scripts/mtest" "$T/scripts/mprivacy" "$T/scripts/mphpcompat" "$T/bin/"* "$T/home/.claude/hooks/"* "$T/home/.moodle-plugin-ci/bin/"* "$T/home/.nvm/versions/node/v22.3.0/bin/node"

bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got '$1')"; bad=1; fi; }
run() { : > "$T/mpc.log"; : > "$T/docker.log"; (cd "$P" && env -u NVM_DIR HOME="$T/home" PATH="$T/bin:$T/core" TMPDIR="$T" XDG_STATE_HOME="$T/state" "$@" "$M" "${args[@]}" > "$T/out" 2>&1); echo $?; }
row() { awk -v s="$1" '$1 == s { print $2 }' "$T/out"; }

args=(full); rc="$(run env RED_phpmd=1 RED_phpdoc=1 RED_privacy=1 RED_phpcompat=1)"
check "$rc" 1 "full: a red step exits 1"
check "$(row phpmd) $(row phpdoc)" "1 1" "full: host and container red rows show rc 1"
check "$(grep -c '^[a-z-]\+ \+\(SKIP\|[0-9]\+\) \+[0-9]\+' "$T/out")" 16 "full: 16 step rows"
check "$(PATH="$T/core" git -C "$P" rev-parse --git-dir >/dev/null 2>&1; echo $?)" 128 "fixture: real git on PATH, plugin dir not in a repo"
check "$(row phpcs-delta)" SKIP "full: phpcs-delta outside git is a named SKIP"
check "$(grep '^phpcs-delta' "$T/out" | grep -c 'not in a git repo')" 1 "full: skip reason printed"
check "$(row phpunit)" 0 "full: phpunit via mtest is green"
check "$(row privacy)" 1 "full: privacy red row shows rc 1"
check "$(row phpcompat) $(grep -c "^mphpcompat $P$" "$T/mpc.log")" "1 1" "full: phpcompat red via mphpcompat on the plugin"
check "$(ls "$T"/state/moodle-harness/logs/local_x/mci-*.log 2>/dev/null | wc -l) $(grep -c "logs $T/state/moodle-harness/logs/local_x/mci-" "$T/out")" "1 1" "full: one mlog log per run, path printed"
check "$(grep '^behat' "$T/out" | grep -c 'SKIP .*no features')" 1 "full: behat without features is a named SKIP"
check "$(grep -c '^codechecker '"$P"' |' "$T/mpc.log")" 1 "codechecker on the host, no -m"
check "$(grep -c '^savepoints '"$P"' |' "$T/mpc.log")" 1 "savepoints on the host, no -m"
check "$(grep -c '^phpmd -m '"$R $P"' |' "$T/mpc.log")" 1 "phpmd on the host with -m root"
check "$(grep '^grunt -m' "$T/mpc.log" | awk '{print $NF}')" v22.3.0 "grunt runs with the node major package.json asks for"
check "$(grep -c '^validate\|^phpdoc' "$T/mpc.log")" 0 "validate and phpdoc never on the host"
check "$(grep -c '^cont php /tmp/mci-mpc/bin/moodle-plugin-ci validate -m /var/www/html /var/www/html/public/local/x mc=n' "$T/docker.log")" 1 "validate in the container with -m dirroot"
check "$(grep -c '^cont .* phpdoc .* mc=y' "$T/docker.log")" 1 "phpdoc in the container with moodlecheck placed"
check "$([ -e "$R/public/local/moodlecheck" ] && echo left || echo gone)" gone "moodlecheck removed after phpdoc"
check "$(grep -c '^push' "$T/docker.log")" 2 "MPC pushed to the container (no stamp yet)"

chmod 000 "$T/home/.moodle-plugin-ci/vendor/moodlehq/moodle-local_moodlecheck/a"
args=(full); rc="$(run env STAMP="$(stat -c %Y "$T/home/.moodle-plugin-ci/composer.lock")")"
chmod 644 "$T/home/.moodle-plugin-ci/vendor/moodlehq/moodle-local_moodlecheck/a"
check "$(row phpdoc) $(grep -c ' phpdoc ' "$T/docker.log")" "1 0" "partial moodlecheck copy: phpdoc red, MPC not run"
check "$(grep -c '^push' "$T/docker.log")" 0 "stamp matches composer.lock: no push"
check "$([ -e "$R/public/local/moodlecheck" ] && echo left || echo gone)" gone "partial moodlecheck copy removed"

mv "$T/home/.moodle-plugin-ci/composer.lock" "$T/lock"
args=(full); rc="$(run env)"
mv "$T/lock" "$T/home/.moodle-plugin-ci/composer.lock"
check "$(grep -c '^\(validate\|phpdoc\) \+SKIP .*composer.lock' "$T/out") $(grep -c '^push' "$T/docker.log")" "2 0" "no composer.lock: validate and phpdoc named SKIP, no push"

args=(full); rc="$(run env NOCONT=1 RED_validate=1)"
check "$rc" 0 "no container: skips are not red"
check "$(grep '^validate' "$T/out" | grep -c 'SKIP .*no running container')" 1 "no container: validate is a named SKIP"
check "$(row phpdoc)" SKIP "no container: phpdoc SKIP"
check "$(row phpunit)" SKIP "no container: phpunit SKIP (mtest rc 3)"

mkdir "$P/templates"
args=(full); rc="$(run env)"
check "$(grep '^mustache' "$T/out" | grep -c 'SKIP .*java')" 1 "templates without java: mustache named SKIP"

mkdir -p "$P/tests/behat"; touch "$P/tests/behat/a.feature"
args=(full); rc="$(run env RED_behat=1 MCI_BEHAT_PARALLEL=3)"
check "$rc $(row behat)" "1 1" "behat red: rc 1 and row rc 1"
check "$(grep -c "^mtest behat $P --parallel 3$" "$T/mpc.log")" 1 "behat via mtest with MCI_BEHAT_PARALLEL passthrough"

args=(full); rc="$(run env NOCONT=1)"
check "$rc $(row privacy) $(row behat)" "0 SKIP SKIP" "no container: privacy and behat SKIP (rc 3)"

args=(quick); rc="$(run env)"
check "$rc" 0 "quick: green exits 0"
check "$(awk '$1 ~ /^(codechecker|phpcs-delta|phpcompat|lang|apicompat|covers|phpunit)$/' "$T/out" | wc -l) $(grep -c '^phpmd\|^grunt\|^privacy\|^behat' "$T/out")" "7 0" "quick: only the 7 quick steps"
check "$(grep '^covers' "$T/out" | grep -c 'SKIP .*no \$plugin->requires')" 1 "covers: no requires is a named SKIP (mcovers rc 3)"

args=(quick); rc="$(run env RED_phpcompat=3 PHPC_MSG='mphpcompat: SKIP: composer not found')"
check "$rc $(row phpcompat) $(grep '^phpcompat' "$T/out" | grep -c 'composer not found')" "0 SKIP 1" "phpcompat rc 3: named SKIP"

args=(quick); rc="$(run env PHPC_REAL=1)"
check "$rc $(row phpcompat) $(grep '^phpcompat' "$T/out" | grep -c 'requires.*--php X.Y')" "0 SKIP 1" "real mphpcompat, no requires: rc 3 named SKIP"

args=(quick); rc="$(run env RED_phpcompat=2 PHPC_MSG='mphpcompat: requires 2020061500 is older than 4.0 (use --php X.Y)')"
check "$rc $(row phpcompat)" "1 2" "phpcompat other rc 2 stays red"

args=(quick); rc="$(run env LANG_REAL=1 APIC_REAL=1 MFIXTURE_ENVS="$T/noenvs")"
check "$rc $(row lang) $(row apicompat) $(grep -c '^lang .*no lang/en/local_x.php' "$T/out") $(grep -c '^apicompat .*requires.*--since X.Y' "$T/out")" \
    "0 SKIP SKIP 1 1" "real mlang without lang/en and real mapicompat without requires: named SKIPs"

cp "$P/version.php" "$T/version.bak"
echo "\$plugin->requires = 2025041400;" >> "$P/version.php"
mkdir -p "$P/lang/en"; touch "$P/lang/en/local_x.php"
args=(quick); rc="$(run env RED_lang=1)"
check "$rc $(row lang) $(row apicompat)" "1 1 0" "lang: mlang rc 1 is red"

printf '<?php\n/**\n * @covers \\local_x\\a\n */\nfinal class a_test {\n}\n' > "$P/tests/a_test.php"
args=(quick); rc="$(run env)"
check "$rc $(row covers) $(grep -c 'tests/a_test.php:3 FAIL @covers' "$T/out")" "1 1 1" "covers: @covers under requires 5.0 is red with file:line"
: > "$P/tests/a_test.php"
mv "$P/tests" "$T/tests.bak"
args=(quick); rc="$(run env)"
check "$rc $(grep '^covers' "$T/out" | grep -c 'SKIP .*no tests/ dir')" "0 1" "covers: no tests/ dir is a named SKIP"
mv "$T/tests.bak" "$P/tests"

args=(quick); rc="$(run env RED_apicompat=1)"
check "$rc $(row apicompat) $(row lang)" "1 1 0" "apicompat: mapicompat rc 1 is red"

args=(quick); rc="$(run env APIC_REAL=1 MFIXTURE_ENVS="$T/noenvs")"
check "$rc $(row apicompat) $(grep '^apicompat' "$T/out" | grep -c 'no UPGRADING.md')" "0 SKIP 1" "apicompat: no UPGRADING.md is a named SKIP"

mkdir -p "$T/envs/5.3/www" "$P/lang/en"; cp "$(dirname "$SD")/tests/fixtures/UPGRADING-sample.md" "$T/envs/5.3/www/UPGRADING.md"
printf '<?php\n$string['"'"'pluginname'"'"'] = '"'"'X'"'"';\n$string['"'"'unused'"'"'] = '"'"'U'"'"';\n' > "$P/lang/en/local_x.php"
args=(quick); rc="$(run env LANG_REAL=1 APIC_REAL=1 MFIXTURE_ENVS="$T/envs")"
check "$rc $(row lang) $(row apicompat) $(grep -c 'WARN' "$(grep -oP 'logs \K\S+' "$T/out").lang")" "0 0 0 1" "both real: green, mlang WARN does not fail"
cp "$T/version.bak" "$P/version.php"

args=(full "$T"); rc="$(run env)"
check "$rc" 2 "no plugin above path: rc 2"
exit $bad
