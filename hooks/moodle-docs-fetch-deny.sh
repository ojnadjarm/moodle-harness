#!/usr/bin/env bash
# PreToolUse WebFetch hook: denies a moodledev.io fetch with a pointer to the local mirror; fails open.
url=$(grep -oE '"url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/^"url"[[:space:]]*:[[:space:]]*"//; s/"$//')
[[ $url =~ ^https?://([a-z0-9-]+\.)*moodledev\.io([/:?#]|$) ]] || exit 0
[[ $url == *'#not-in-mirror'* ]] && exit 0
reason='moodledev.io is mirrored locally: use /moodle-docs (python3 ~/.claude/skills/moodle-docs/search.py "<terms>", pages under ~/.moodle-devdocs); a page missing there passes with #not-in-mirror appended to the URL.'
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "${reason//\"/\\\"}"
