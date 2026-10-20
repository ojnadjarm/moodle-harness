#!/usr/bin/env bash
# Render mod_ and block_ recipes into mktemp; check file lists, php -l, install.xml, codechecker.
set -uo pipefail
G="$(cd "$(dirname "$0")/.." && pwd)/generate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

expected_mod="t760/version.php
t760/lang/en/t760.php
t760/classes/privacy/provider.php
t760/db/access.php
t760/db/install.xml
t760/lib.php
t760/mod_form.php
t760/view.php
t760/index.php"
expected_block="t760/version.php
t760/lang/en/block_t760.php
t760/classes/privacy/provider.php
t760/db/access.php
t760/block_t760.php"

for type in mod block; do
    d="$T/$type"; mkdir -p "$d"; p="$d/t760"
    printf 'component: %s_t760\nname: T760 %s\ncopyright: 2026 onwards, Example Author <author@example.com>\n' \
        "$type" "$type" > "$d/recipe.yaml"
    python3 "$G" --target-dir "$d" "$d/recipe.yaml" >/dev/null 2>"$d/err" \
        && ok "$type renders" || { bad "$type renders: $(cat "$d/err")"; continue; }
    want="expected_$type"
    got="$(cd "$d" && find t760 -type f | sort)"
    [ "$got" = "$(sort <<<"${!want}")" ] && ok "$type file list ($(wc -l <<<"$got"))" || bad "$type file list: $got"
    lint=0
    while IFS= read -r f; do php -l "$f" >/dev/null 2>&1 || { bad "$type php -l ${f#$d/}"; lint=1; }; done \
        < <(find "$p" -name '*.php')
    [ "$lint" -eq 0 ] && ok "$type php -l clean"
    if [ "$type" = mod ]; then
        python3 -c 'import sys, xml.etree.ElementTree as E; t = E.parse(sys.argv[1]).find("TABLES/TABLE[@NAME=\"t760\"]"); \
            sys.exit(0 if t is not None and {f.get("NAME") for f in t.find("FIELDS")} >= {"id", "course", "name", "intro", "introformat", "timemodified"} else 1)' \
            "$p/db/install.xml" && ok "mod install.xml table t760 with required fields" || bad "mod install.xml"
        for s in "t760_supports" "t760_add_instance" "t760_update_instance" "t760_delete_instance"; do
            grep -q "^function $s(" "$p/lib.php" || bad "mod lib.php lacks $s"
        done
        for s in modulename modulenameplural pluginadministration 't760:addinstance' 't760:view'; do
            grep -q "^\$string\['$s'\]" "$p/lang/en/t760.php" || bad "mod lang lacks $s"
        done
        for c in addinstance view; do grep -q "'mod/t760:$c'" "$p/db/access.php" || bad "mod access lacks $c"; done
    else
        for m in init get_content applicable_formats; do
            grep -q "public function $m(" "$p/block_t760.php" || bad "block class lacks $m"
        done
        for c in addinstance myaddinstance; do grep -q "'block/t760:$c'" "$p/db/access.php" || bad "block access lacks $c"; done
    fi
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker "$p" 2>&1)"; rc=$?
        if grep -q '| ERROR |' <<<"$out"; then bad "$type codechecker: $(grep -c '| ERROR |' <<<"$out") errors"; echo "$out" | grep -B2 '| ERROR |' | head -20
        elif [ "$rc" -ne 0 ]; then bad "$type codechecker rc=$rc"
        else ok "$type codechecker 0 errors"; fi
    else
        echo "SKIP $type codechecker: moodle-plugin-ci absent"
    fi
done

d="$T/override"; mkdir -p "$d"
printf 'component: block_t760\ncapabilities:\n  - name: addinstance\n    title: Custom add\n' > "$d/recipe.yaml"
python3 "$G" --target-dir "$d" "$d/recipe.yaml" >/dev/null 2>&1 \
    && [ "$(grep -c "'block/t760:addinstance'" "$d/t760/db/access.php")" = 1 ] \
    && grep -q "'Custom add'" "$d/t760/lang/en/block_t760.php" \
    && ok "recipe capability overrides the default one" || bad "capability override"
grep -q "'riskbitmask' => RISK_SPAM | RISK_XSS," "$d/t760/db/access.php" \
    && grep -q "'contextlevel' => CONTEXT_BLOCK," "$d/t760/db/access.php" \
    && grep -q "'clonepermissionsfrom' => 'moodle/site:manageblocks'," "$d/t760/db/access.php" \
    && ok "merged capability keeps the default riskbitmask, contextlevel, clonepermissionsfrom" || bad "capability merge"

d="$T/php74"; mkdir -p "$d"; p="$d/t790"
printf 'component: mod_t790\nname: Quiz\nrequires: "4.1"\nfeatures: {settings: true}\ncopyright: 2026 onwards, Example Author <author@example.com>\n' \
    > "$d/recipe.yaml"
if python3 "$G" --target-dir "$d" "$d/recipe.yaml" >/dev/null 2>"$d/err"; then
    ! grep -q 'match (' "$p/lib.php" && grep -q 'switch ($feature)' "$p/lib.php" \
        && ok "requires 4.1 lib.php uses switch, no match" || bad "requires 4.1 lib.php has match"
    grep -q "^\$string\['modulenameplural'\] = 'Quizzes';" "$p/lang/en/t790.php" \
        && ok "plural doubles a single-vowel z: Quizzes" || bad "plural: $(grep modulenameplural "$p/lang/en/t790.php")"
    pl="$(cd "$(dirname "$G")" && python3 -c 'import generate; print(generate.plural("QUIZ"))')"
    [ "$pl" = QUIZZes ] && ok "plural ignores case: QUIZZes" || bad "plural QUIZ: $pl"
    grep -q "'mod_t790/generalsettings'," "$p/settings.php" \
        && grep -q "^\$string\['generalsettings'\]" "$p/lang/en/t790.php" \
        && ok "fulltree holds a heading with its lang string" || bad "fulltree heading"
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker "$p" 2>&1)"; rc=$?
        if grep -q '| ERROR |' <<<"$out" || [ "$rc" -ne 0 ]; then bad "settings:true codechecker rc=$rc"; echo "$out" | grep -B2 '| ERROR |' | head -20
        else ok "settings:true codechecker 0 errors"; fi
    else
        echo "SKIP settings:true codechecker: moodle-plugin-ci absent"
    fi
else
    bad "requires 4.1 renders: $(cat "$d/err")"
fi

d="$T/dupkey"; mkdir -p "$d"; p="$d/t811"
printf 'component: mod_t811\nfeatures: {settings: true}\nlang_strings:\n  - {id: generalsettings, text: Own heading}\n' > "$d/recipe.yaml"
python3 "$G" --target-dir "$d" "$d/recipe.yaml" >/dev/null 2>&1 \
    && [ "$(grep -c "^\$string\['generalsettings'\]" "$p/lang/en/t811.php")" = 1 ] \
    && grep -q "^\$string\['generalsettings'\] = 'Own heading';" "$p/lang/en/t811.php" \
    && ok "recipe generalsettings kept, no duplicate key" || bad "generalsettings duplicate: $(grep generalsettings "$p/lang/en/t811.php")"

d="$T/archetypes"; mkdir -p "$d"; a="$d/t811/db/access.php"
printf 'component: mod_t811\ncapabilities:\n  - name: view\n    archetypes:\n      - {role: guest, permission: CAP_PROHIBIT}\n      - {role: coursecreator, permission: CAP_ALLOW}\n' > "$d/recipe.yaml"
if python3 "$G" --target-dir "$d" "$d/recipe.yaml" >/dev/null 2>&1; then
    v="$(sed -n "/'mod\/t811:view'/,/^    \],/p" "$a")"
    grep -q "'guest' => CAP_PROHIBIT," <<<"$v" && grep -q "'coursecreator' => CAP_ALLOW," <<<"$v" \
        && grep -q "'student' => CAP_ALLOW," <<<"$v" && grep -q "'manager' => CAP_ALLOW," <<<"$v" \
        && [ "$(grep -c "'guest'" <<<"$v")" = 1 ] && php -l "$a" >/dev/null 2>&1 \
        && ok "recipe archetypes merged by role into the defaults" || bad "archetypes merge: $v"
else
    bad "archetypes recipe renders"
fi

[ "$fails" -eq 0 ] && echo "PASS types.test.sh" || echo "FAIL types.test.sh ($fails)"
exit $((fails > 0))
