#!/usr/bin/env bash
# Lists upstream coding-style headings missing from the local copy; exits 1 if any non-whitelisted one is missing.
set -euo pipefail
export LC_ALL=C

upstream="${STYLE_UPSTREAM:-$HOME/.moodle-devdocs/general/development/policies/codingstyle/index.md}"
local_copy="${STYLE_LOCAL:-$HOME/.claude/moodle-coding-style.md}"
whitelist=(
    'overview'
    'overview > scope'
    'overview > goals'
    'naming conventions > examples'
    'credits'
    'see also'
)

[[ -r "$upstream" ]] || { echo "SKIP: upstream mirror not found: $upstream"; exit 0; }
[[ -r "$local_copy" ]] || { echo "FAIL: local copy not found: $local_copy"; exit 1; }

keys() {
    awk '
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }
        /^#+ / {
            level = index($0, " ") - 1
            text = substr($0, level + 2)
            gsub(/\{\/\*[^}]*\*\/\}/, "", text)
            gsub(/`/, "", text)
            text = tolower(text)
            gsub(/[^a-z0-9@]+/, " ", text)
            gsub(/^ +| +$/, "", text)
            if (level == 1) next
            if (level == 2) { h2 = text; print text; next }
            print h2 " > " text
        }' "$1" | sort -u
}

missing=$(comm -23 <(keys "$upstream") <(keys "$local_copy") | grep -vxF -f <(printf '%s\n' "${whitelist[@]}") || true)
total=$(keys "$upstream" | wc -l)

if [[ -d "$(dirname "$upstream")" ]] && date=$(git -C "$(dirname "$upstream")" log -1 --format=%cs -- "$upstream" 2>/dev/null) && [[ -n "$date" ]]; then
    grep -q "$date" "$local_copy" || echo "NOTE: local source date line does not mention upstream date $date"
fi

if [[ -n "$missing" ]]; then
    echo "FAIL: $(wc -l <<<"$missing")/$total upstream headings missing locally:"
    sed 's/^/  - /' <<<"$missing"
    exit 1
fi
echo "PASS: all $total upstream headings covered (${#whitelist[@]} whitelisted)"
