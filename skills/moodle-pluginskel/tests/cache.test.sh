#!/usr/bin/env bash
# Drive cache.py on mktemp plugins: db/caches.php create and merge, modes, cachedef_ string, version, accessor, test, refusals.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
S="$(cd "$(dirname "$0")/.." && pwd)"
K="$S/cache.py"; G="$S/generate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
version() { sed -n 's/^\$plugin->version = \([0-9]*\);/\1/p' "$1/version.php"; }
defs() { php -r "define('MOODLE_INTERNAL', 1); class cache_store { const MODE_APPLICATION = 1; const MODE_SESSION = 2;
    const MODE_REQUEST = 4; } include '$1/db/caches.php'; \$d = \$definitions; $2"; }

render() {
    mkdir -p "$T/$1"
    printf 'component: %s\nrequires: "%s"\ncopyright: 2026 onwards, Example Author <author@example.com>\n' "$2" "$1" > "$T/$1/recipe.yaml"
    python3 "$G" --target-dir "$T/$1" "$T/$1/recipe.yaml" >/dev/null 2>"$T/err" || bad "$1 skeleton: $(cat "$T/err")"
}

render 4.5 mod_demo; P45="$T/4.5/demo"
render 4.1 local_demo; P41="$T/4.1/demo"
cp="$P45/db/caches.php"; lang="$P45/lang/en/demo.php"
v0="$(version "$P45")"
python3 "$K" "$P45" course_summary --simplekeys --ttl 600 >"$T/out" 2>&1 && ok "application cache renders" || bad "rc: $(cat "$T/out")"
v1="$(version "$P45")"; [ "$v1" -gt "$v0" ] && ok "version bumped $v0 -> $v1" || bad "version not bumped: $v1"
grep -q "'mode' => cache_store::MODE_APPLICATION," "$cp" \
    && defs "$P45" "\$c = \$d['course_summary']; exit(count(\$d) == 1 && \$c['mode'] == cache_store::MODE_APPLICATION
        && \$c['simplekeys'] === true && \$c['ttl'] === 600 ? 0 : 1);" \
    && ok "db/caches.php: MODE_APPLICATION + simplekeys + ttl" || bad "caches.php: $(cat "$cp")"
grep -q "^\$string\['cachedef_course_summary'\] = 'Course summary';" "$lang" && ok "cachedef_ string added" || bad "lang: $(cat "$lang")"

python3 "$K" "$P45" user_prefs --mode session >"$T/out" 2>&1 \
    && python3 "$K" "$P45" lookup --mode request >>"$T/out" 2>&1 \
    && defs "$P45" "exit(count(\$d) == 3 && \$d['course_summary']['mode'] == cache_store::MODE_APPLICATION
        && \$d['user_prefs']['mode'] == cache_store::MODE_SESSION && \$d['lookup']['mode'] == cache_store::MODE_REQUEST
        && !isset(\$d['user_prefs']['simplekeys']) && !isset(\$d['lookup']['ttl']) ? 0 : 1);" \
    && [ "$(grep -c '^\$definitions = ' "$cp")" = 1 ] \
    && ok "merge keeps entries: session + request modes, no stray simplekeys/ttl" || bad "merge: $(cat "$T/out" "$cp")"
ids="$(sed -n "s/^\$string\['\([^']*\)'\].*/\1/p" "$lang" | grep -v '^pluginname$')"
grep -q 'cachedef_user_prefs' <<<"$ids" && [ "$ids" = "$(LC_ALL=C sort <<<"$ids")" ] \
    && ok "cachedef_ strings inserted in order" || bad "lang order: $ids"

ac="$P45/classes/local/cache/course_summary.php"; at="$P45/tests/local/cache/course_summary_test.php"
grep -q '^namespace mod_demo\\local\\cache;' "$ac" && grep -q 'public static function loader(): \\cache {' "$ac" \
    && grep -qF "return \\cache::make('mod_demo', 'course_summary');" "$ac" \
    && grep -q 'public static function get(string \$key) {' "$ac" && grep -q 'public static function set(string \$key, \$value): bool {' "$ac" \
    && grep -q 'public static function purge(): bool {' "$ac" && ok "accessor: typed loader/get/set/delete/purge" || bad "accessor: $(cat "$ac")"
grep -qF "\$cache = \\cache::make('mod_demo', 'course_summary');" "$at" && grep -q "course_summary::set('key1', 'value1')" "$at" \
    && grep -qF "\$this->assertSame('value1', \$cache->get('key1'));" "$at" && grep -q 'course_summary::purge()' "$at" \
    && grep -qF "\$this->assertFalse(\$cache->get('key1'));" "$at" && grep -q '@covers     \\mod_demo\\local\\cache\\course_summary' "$at" \
    && ok "test: set/get/purge through cache::make" || bad "test: $(cat "$at")"

mkdir -p "$T/arr/db" "$T/arr/lang/en"; cp "$P41/version.php" "$T/arr/"; cp "$P41/lang/en/local_demo.php" "$T/arr/lang/en/"
printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\$definitions = array(\n    'old' => array('mode' => cache_store::MODE_APPLICATION), // Old.\n);\n" > "$T/arr/db/caches.php"
python3 "$K" "$T/arr" fresh --simplekeys >/dev/null 2>"$T/err" && php -l "$T/arr/db/caches.php" >/dev/null \
    && defs "$T/arr" "exit(count(\$d) == 2 && isset(\$d['old']) && \$d['fresh']['simplekeys'] === true ? 0 : 1);" \
    && ! grep -q "'fresh' => \[" "$T/arr/db/caches.php" && ok "merge into array() style keeps old entry" \
    || bad "array() merge: $(cat "$T/err" "$T/arr/db/caches.php")"
python3 "$K" "$P41" stats >/dev/null 2>"$T/err" && [ -f "$P41/db/caches.php" ] \
    && grep -q "^\$string\['cachedef_stats'\]" "$P41/lang/en/local_demo.php" && ok "local_ plugin: caches.php + string in local_demo.php" \
    || bad "local_: $(cat "$T/err")"

lintfail=0; n=0
for f in "$cp" "$lang" "$P45"/classes/local/cache/*.php "$P45"/tests/local/cache/*.php "$P41"/db/caches.php \
    "$P41"/classes/local/cache/*.php "$P41"/tests/local/cache/*.php; do
    n=$((n + 1)); php -l "$f" >/dev/null 2>&1 || { lintfail=1; bad "php -l $f: $(php -l "$f" 2>&1)"; }
done
[ "$lintfail" = 0 ] && ok "php -l clean ($n files)"
for p in "$P45" "$P41"; do
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker "$p" 2>&1)"; rc=$?
        if grep -q '| ERROR |' <<<"$out"; then bad "$p codechecker: $(grep '| ERROR |' <<<"$out" | head -3)"
        elif [ "$rc" -ne 0 ]; then bad "$p codechecker rc=$rc"
        else ok "codechecker 0 errors ${p#"$T"/}"; fi
    else
        echo "SKIP codechecker: moodle-plugin-ci absent"
    fi
done

snap() { md5sum "$cp" "$P45/version.php" "$lang"; }
before="$(snap)"
for a in "Bad" "1area" "bad-name" "a.b"; do
    python3 "$K" "$P45" "$a" >"$T/out" 2>&1; rc=$?
    [ "$rc" = 1 ] && grep -q 'bad area name' "$T/out" && [ "$before" = "$(snap)" ] \
        && ok "area '$a' refused rc 1, nothing written" || bad "area '$a' rc=$rc: $(cat "$T/out")"
done
python3 "$K" "$P45" course_summary --mode session >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "cache area 'course_summary' already exists" "$T/out" && [ "$before" = "$(snap)" ] \
    && ok "duplicate area refused rc 1, nothing written" || bad "duplicate rc=$rc: $(cat "$T/out")"
printf "\$string['cachedef_taken'] = 'Taken';\n" >> "$lang"; before="$(snap)"
python3 "$K" "$P45" taken >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "string 'cachedef_taken' already exists" "$T/out" && [ "$before" = "$(snap)" ] \
    && [ ! -e "$P45/classes/local/cache/taken.php" ] && ok "existing cachedef_ string refused rc 1" || bad "string rc=$rc: $(cat "$T/out")"
python3 "$K" "$P45" short --ttl 0 >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'bad --ttl' "$T/out" && [ "$before" = "$(snap)" ] && ok "--ttl 0 refused rc 1" || bad "ttl rc=$rc: $(cat "$T/out")"
python3 "$K" "$P45" other --mode disk >"$T/out" 2>&1 && bad "--mode disk accepted" || ok "--mode disk refused"
python3 "$K" "$T/none" area >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'has no version.php' "$T/out" && ok "no version.php refused rc 1" || bad "no version rc=$rc: $(cat "$T/out")"

[ "$fails" -eq 0 ] && echo "PASS cache.test.sh" || { echo "FAIL cache.test.sh ($fails)"; exit 1; }
