#!/usr/bin/env bash
# Checks that every `$S/<tool> <verb|--flag>` named in moodle-tips.md is a whole word of that tool's --help.
set -uo pipefail
export LC_ALL=C

tips="${TIPS:-$HOME/.claude/moodle-tips.md}"
S="${TIPS_SCRIPTS:-$HOME/.claude/skills/moodle-ci/scripts}"

# check <tips> <scripts-dir>: prints FAIL lines and the checked count; rc 1 on any miss.
check() {
    local tips=$1 S=$2 fail=0 n=0 span tool help w re i b='[^[:alnum:]_./-]'
    [[ -r "$tips" ]] || { echo "FAIL: tips not found: $tips"; return 1; }
    while IFS= read -r span; do
        read -ra words <<<"${span#\$S/}"
        tool="${words[0]}"
        if [[ ! -x "$S/$tool" ]]; then
            echo "FAIL: $span: no tool $S/$tool"; fail=1; continue
        fi
        help=$("$S/$tool" --help 2>&1)
        for i in "${!words[@]}"; do
            w="${words[$i]}"
            (( i == 0 )) && continue
            if [[ $i -eq 1 && "$w" =~ ^[a-z][a-z-]*$ ]]; then
                # A verb counts only in a synopsis: after the tool name (and bracketed options) or a `|`.
                re="(${tool}( +\[[^]]*\])*|\|) *${w}( |\||<|:|$)"
            elif [[ "$w" == -* ]]; then
                re="(^|$b)${w}($|$b)"
            else
                continue
            fi
            n=$((n + 1))
            grep -qE -- "$re" <<<"$help" || { echo "FAIL: $span: '$w' not a word in $tool --help"; fail=1; }
        done
    done < <(tr '\n' ' ' <"$tips" | grep -o '`\$S/[^`]*`' | tr -d '`' | tr -s ' ')
    (( n > 0 )) || { echo "FAIL: no \$S/<tool> <flag> found in $tips"; return 1; }
    echo "checked $n"
    return $fail
}

# Self-test: verbs and flags that appear only inside prose words must be red.
fx=$(mktemp -d)
trap 'rm -rf "$fx"' EXIT
printf '%s\n' '#!/bin/sh' 'echo "usage: tool run <x>"' 'echo "Re-initialises via init.php; prints statuses; --resetall."' >"$fx/tool"
chmod +x "$fx/tool"
for span in 'tool init' 'tool status' 'tool --reset'; do
    printf '`$S/%s`\n' "$span" >"$fx/tips.md"
    check "$fx/tips.md" "$fx" >/dev/null && { echo "FAIL: selftest: prose-only '$span' passed"; exit 1; }
done
printf '`$S/tool run`\n' >"$fx/tips.md"
check "$fx/tips.md" "$fx" >/dev/null || { echo "FAIL: selftest: synopsis verb 'tool run' red"; exit 1; }

out=$(check "$tips" "$S"); rc=$?
grep '^FAIL' <<<"$out"
(( rc )) && exit 1
echo "PASS: ${out##*checked } tool flags in $(basename "$tips") are whole words in --help (selftest: 3 prose-only spans red)"
