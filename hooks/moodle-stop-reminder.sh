#!/usr/bin/env bash
# Stop hook: non-blocking nudge to run /moodle-ci when PHP changed in a Moodle project.

here="$(dirname "$0")"
root="$("$here/moodle-detect.sh" 2>/dev/null)" || exit 0

cd "$root" 2>/dev/null || exit 0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git status --porcelain -uall 2>/dev/null | grep -qiE '\.php"?$'; then
        echo "Reminder: PHP changed — run /moodle-ci (phpcs + PHPUnit) before wrapping up."
    fi
fi
exit 0
