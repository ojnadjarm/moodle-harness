#!/usr/bin/env bash
# Stop hook: block once per PHP diff in a Moodle project until each changed component's mtest/mci log is newer than its change;
# lang/** and templates/** files never demand it (T1399: mci auto runs their class's checks).

grep -q '"stop_hook_active" *: *true' && exit 0

here="$(dirname "$0")"
mlog="$here/../skills/moodle-ci/scripts/mlog"
. "$mlog" 2>/dev/null && mlog="" || mlog="$(realpath -m "$mlog")"
root="$("$here/moodle-detect.sh" 2>/dev/null)" || exit 0
cd "$root" 2>/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
export GIT_OPTIONAL_LOCKS=0

base="$(git rev-parse -q --verify HEAD || git hash-object -t tree /dev/null)"
mapfile -t files < <({ git diff --name-only --relative "$base" -- '*.php'; git ls-files -o --exclude-standard -- '*.php'; } | grep -Ev '(^|/)(lang|templates)/')
[ "${#files[@]}" -gt 0 ] || exit 0

hash="$({ git diff --relative "$base" -- "${files[@]}"; for f in "${files[@]}"; do [ -f "$f" ] && printf '%s\n' "$f"; done | git hash-object --stdin-paths; } | sha1sum | cut -c1-40)"
stamp="${XDG_STATE_HOME:-$HOME/.local/state}/moodle-harness/stop-reminder/$(printf '%s' "$root" | sha1sum | cut -c1-12)"
[ "$(cat "$stamp" 2>/dev/null)" = "$hash" ] && exit 0

stale=()
if [ -z "$mlog" ]; then
    rootcomp="$(mlog_component "$root")"
    declare -A comp newest seen
    # In a core root each file belongs to its nearest plugin (one grep over its ancestors' version.php); others map to "core".
    if [ -z "$rootcomp" ]; then
        vers=()
        for f in "${files[@]}"; do
            d="$f"
            while [[ "$d" == */* ]]; do
                d="${d%/*}"; [ -n "${seen[$d]+x}" ] && break; seen[$d]=1
                [ -f "$d/version.php" ] && vers+=("$d/version.php")
            done
        done
        [ "${#vers[@]}" -gt 0 ] && while IFS= read -r -d '' p && IFS= read -r c; do
            comp[${p%/version.php}]="$c"
        done < <(grep -m1 -HZoP "\\\$plugin->component\s*=\s*['\"]\K[^'\"]+" "${vers[@]}")
    fi
    for f in "${files[@]}"; do
        c="$rootcomp"; d="$f"
        while [ -z "$c" ] && [[ "$d" == */* ]]; do d="${d%/*}"; c="${comp[$d]:-}"; done
        c="${c:-core}"
        # A deleted file counts from its nearest existing ancestor's mtime.
        ref="$f"; while [ ! -e "$ref" ] && [[ "$ref" == */* ]]; do ref="${ref%/*}"; done; [ -e "$ref" ] || ref=.
        { [ -z "${newest[$c]+x}" ] || [ "$ref" -nt "${newest[$c]}" ]; } && newest[$c]="$ref"
    done
    # "core" reads the whole log home: every plugin's logs count for core files.
    for c in "${!newest[@]}"; do
        logs="$(mlog_dir "$c")"; [ "$c" = core ] && logs="$(mlog_dir "")"
        [ -n "$(find "$logs" -maxdepth 2 -type f \( -name 'mtest-*.log' -o -name 'mci-*.log' \) -newer "${newest[$c]}" -print -quit 2>/dev/null)" ] || stale+=("$c")
    done
    [ "${#stale[@]}" -gt 0 ] || exit 0
fi

mkdir -p "$(dirname "$stamp")" && printf '%s\n' "$hash" > "$stamp"

python3 -c '
import json, sys
root, comps, mlog = sys.argv[1:4]
r = "PHP changed in %s%s and no mtest/mci run since: run /moodle-ci (mci auto: the checks the change class needs) before wrapping up, or say why it is skipped." % (root, " (" + comps + ")" if comps else "")
if mlog:
    r += " The log check is off: %s is missing." % mlog
print(json.dumps({"decision": "block", "reason": r}))' "$root" "$(IFS=,; printf '%s' "${stale[*]}" | sed 's/,/, /g')" "$mlog"
exit 0
