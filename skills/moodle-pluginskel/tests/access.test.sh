#!/usr/bin/env bash
# Drive access.py on mktemp plugins: db/access.php create and merge, sorted lang, version, php -l, codechecker, refusals.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
S="$(cd "$(dirname "$0")/.." && pwd)"
A="$S/access.py"; G="$S/generate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
version() { sed -n 's/^\$plugin->version = \([0-9]*\);/\1/p' "$1/version.php"; }
consts="define('MOODLE_INTERNAL', 1); define('CONTEXT_SYSTEM', 10); define('CONTEXT_COURSE', 50);
    define('CONTEXT_MODULE', 70); define('CAP_ALLOW', 1); define('CAP_PREVENT', -1); define('RISK_XSS', 4);
    define('RISK_CONFIG', 2);"

render() {
    mkdir -p "$T/$1"
    printf 'component: %s\nrequires: "4.5"\ncopyright: 2026 onwards, Example Author <author@example.com>\n' "$2" > "$T/$1/recipe.yaml"
    python3 "$G" --target-dir "$T/$1" "$T/$1/recipe.yaml" >/dev/null 2>"$T/err" || bad "$1 skeleton: $(cat "$T/err")"
}

python3 "$A" --help | grep -q archetypes && ok "--help names archetypes" || bad "--help"
render loc local_demo; P="$T/loc/demo"; ap="$P/db/access.php"; lang="$P/lang/en/local_demo.php"
v0="$(version "$P")"
[ ! -e "$ap" ] && python3 "$A" "$P" view --type read --context course --archetypes editingteacher=allow,student=allow \
    --clone moodle/course:view >"$T/out" 2>&1 && [ -f "$ap" ] && ok "creates db/access.php" || bad "create: $(cat "$T/out")"
v1="$(version "$P")"; [ "$v1" -gt "$v0" ] && ok "version bumped $v0 -> $v1" || bad "version not bumped: $v1"
php -r "$consts include '$ap'; \$c = \$capabilities['local/demo:view'] ?? [];
    exit(count(\$capabilities) == 1 && \$c['captype'] == 'read' && \$c['contextlevel'] == 50
        && \$c['archetypes'] == ['editingteacher' => 1, 'student' => 1]
        && \$c['clonepermissionsfrom'] == 'moodle/course:view' && !isset(\$c['riskbitmask']) ? 0 : 1);" \
    && ok "entry: captype, contextlevel, archetypes, clone" || bad "entry: $(cat "$ap")"
grep -q "^\$string\['demo:view'\] = 'View';" "$lang" && ok "lang string demo:view" || bad "lang: $(cat "$lang")"

python3 "$A" "$P" manage_items --type write --context system --risk xss,config --title "Manage the demo's items" \
    >"$T/out" 2>&1 || bad "merge rc: $(cat "$T/out")"
php -r "$consts include '$ap'; \$c = \$capabilities['local/demo:manage_items'] ?? [];
    exit(array_keys(\$capabilities) == ['local/demo:view', 'local/demo:manage_items'] && \$c['riskbitmask'] == 6
        && \$c['archetypes'] == ['manager' => 1] && \$c['captype'] == 'write' ? 0 : 1);" \
    && [ "$(grep -c '^\$capabilities = ' "$ap")" = 1 ] && ok "merge keeps the first entry, risk + default archetype" \
    || bad "merge: $(cat "$ap")"
[ "$(version "$P")" -gt "$v1" ] && ok "second capability bumps again" || bad "no second bump"
grep -q "^\$string\['demo:manage_items'\] = 'Manage the demo\\\\'s items';" "$lang" && ok "--title quoted" || bad "title: $(cat "$lang")"
python3 "$A" "$P" archive --type write --context course --archetypes manager=allow,teacher=prevent >/dev/null 2>&1 \
    || bad "third rc"
ids="$(sed -n "s/^\$string\['\([^']*\)'\].*/\1/p" "$lang")"
[ "$ids" = "$(LC_ALL=C sort <<<"$ids")" ] && ok "lang ids sorted" || bad "lang order: $ids"

mkdir -p "$T/arr/db" "$T/arr/lang/en"; cp "$P/version.php" "$T/arr/"; cp "$T/loc/demo/lang/en/local_demo.php" "$T/arr/lang/en/"
sed -i "/demo:/d" "$T/arr/lang/en/local_demo.php"
printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\$capabilities = array(\n    'local/demo:old' => array('captype' => 'read', 'contextlevel' => CONTEXT_SYSTEM, 'archetypes' => array())\n);\n" \
    > "$T/arr/db/access.php"
python3 "$A" "$T/arr" fresh --type read --context module --archetypes student=allow >/dev/null 2>"$T/err" \
    && php -r "$consts include '$T/arr/db/access.php';
        exit(count(\$capabilities) == 2 && \$capabilities['local/demo:fresh']['archetypes'] == ['student' => 1] ? 0 : 1);" \
    && ok "merge into array() keeps old entry" || bad "array() merge: $(cat "$T/err" "$T/arr/db/access.php")"

before="$(md5sum "$ap" "$lang" "$P/version.php")"
python3 "$A" "$P" view --type read --context course >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'local/demo:view already exists' "$T/out" && [ "$before" = "$(md5sum "$ap" "$lang" "$P/version.php")" ] \
    && ok "duplicate capability refused rc 1, nothing written" || bad "duplicate rc=$rc: $(cat "$T/out")"
printf "\$string['demo:taken'] = 'Taken';\n" >> "$lang"; before="$(md5sum "$ap" "$P/version.php")"
python3 "$A" "$P" taken --type read --context course >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "string 'demo:taken' already exists" "$T/out" && [ "$before" = "$(md5sum "$ap" "$P/version.php")" ] \
    && ok "existing lang string refused rc 1" || bad "lang refusal rc=$rc: $(cat "$T/out")"
sed -i "/demo:taken/d" "$lang"
for spec in "--archetypes boss=allow" "--archetypes student=yes" "--archetypes student=allow,student=prevent" \
        "--clone moodle-course-view" "--risk xss,evil"; do
    # shellcheck disable=SC2086
    python3 "$A" "$P" badcase --type read --context course $spec >"$T/out" 2>&1; rc=$?
    [ "$rc" = 1 ] && grep -q '^error: ' "$T/out" && ! grep -q 'badcase' "$ap" && ok "refused: $spec" || bad "$spec rc=$rc: $(cat "$T/out")"
done
python3 "$A" "$P" Bad-Name --type read --context course >/dev/null 2>&1 && bad "bad name accepted" || ok "bad name refused"
before="$(md5sum "$ap" "$lang" "$P/version.php")"
python3 "$A" "$P" twoline --type read --context course --title $'Two\nlines' >"$T/out" 2>&1; rc=$?
[ "$rc" = 2 ] && grep -q 'one line' "$T/out" && [ "$before" = "$(md5sum "$ap" "$lang" "$P/version.php")" ] \
    && ok "multi-line --title refused rc 2" || bad "multi-line title rc=$rc: $(cat "$T/out")"
sed -i "s|^\$capabilities = \[|&\n    // 'local/demo:ghost' => [],\n    /* 'local/demo:ghost' => [], */|" "$ap"
python3 "$A" "$P" ghost --type read --context course >"$T/out" 2>&1 \
    && php -r "$consts include '$ap'; exit(isset(\$capabilities['local/demo:ghost']) ? 0 : 1);" \
    && ok "commented-out capability not a duplicate" || bad "ghost: $(cat "$T/out" "$ap")"
sed -i "/demo:ghost' => \[\],/d" "$ap"
python3 "$A" "$P" dedupe --type write --context course --risk xss,config,xss >"$T/out" 2>&1 \
    && grep -q "'riskbitmask' => RISK_CONFIG | RISK_XSS," "$ap" && ok "--risk deduped and ordered" \
    || bad "risk dedupe: $(cat "$T/out"; grep riskbitmask "$ap")"

render mod mod_demo; M="$T/mod/demo"; ml="$M/lang/en/demo.php"
python3 "$A" "$M" view --type read --context module >"$T/out" 2>&1 && bad "mod view duplicate accepted" \
    || { grep -q 'mod/demo:view already exists' "$T/out" && ok "mod skeleton view refused" || bad "mod refusal: $(cat "$T/out")"; }
python3 "$A" "$M" grade --type write --context module --archetypes teacher=allow,editingteacher=allow --risk xss \
    >"$T/out" 2>&1 && grep -q "^\$string\['demo:grade'\] = 'Grade';" "$ml" && grep -q "'mod/demo:grade' => \[" "$M/db/access.php" \
    && ok "mod_: merge into skeleton access.php, lang/en/demo.php" || bad "mod grade: $(cat "$T/out")"

lintfail=0; n=0
for f in "$ap" "$lang" "$T/arr/db/access.php" "$M/db/access.php" "$ml"; do
    n=$((n + 1)); php -l "$f" >/dev/null 2>&1 || { lintfail=1; bad "php -l $f: $(php -l "$f" 2>&1)"; }
done
[ "$lintfail" = 0 ] && ok "php -l clean ($n files)"
for p in "$P" "$M"; do
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker --max-warnings 0 "$p" 2>&1)"; rc=$?
        if grep -q '| \(ERROR\|WARNING\) |' <<<"$out"; then bad "$p codechecker: $(grep -c '| \(ERROR\|WARNING\) |' <<<"$out") issues"
        elif [ "$rc" -ne 0 ]; then bad "$p codechecker rc=$rc"
        else ok "codechecker 0/0 ${p#"$T"/}"; fi
    else
        echo "SKIP codechecker: moodle-plugin-ci absent"
    fi
done

[ "$fails" -eq 0 ] && echo "PASS access.test.sh" || { echo "FAIL access.test.sh ($fails)"; exit 1; }
