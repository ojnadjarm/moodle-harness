#!/usr/bin/env bash
# SessionStart hook: always inject the i-have-adhd rules; on a Moodle project also inject the
# guidelines + tips. Emits hook JSON so a one-line banner is shown to the user.

here="$(dirname "$0")"
root="$("$here/moodle-detect.sh" 2>/dev/null)" || root=""

python3 - "$root" <<'PY'
import json, os, re, sys

root = sys.argv[1]
base = os.path.expanduser("~/.claude")

def read(rel):
    path = os.path.join(base, rel)
    return open(path).read() if os.path.exists(path) else ""

adhd = re.sub(r"\A---\n.*?\n---\n", "", read("skills/i-have-adhd/SKILL.md"), count=1, flags=re.S)
parts = ["=== ADHD OUTPUT MODE — active for this whole session ===", adhd]
banner = "Harness: ADHD mode on"

if root:
    parts += [
        "=== MOODLE PROJECT DETECTED — these rules are mandatory for this session ===",
        read("moodle-guidelines.md"),
        read("moodle-tips.md"),
        "BEFORE writing or reviewing any PHP, read $HOME/.claude/moodle-coding-style.md.\n"
        "WHEN code is complete, run the /moodle-ci skill (phpcs + PHPUnit).",
    ]
    banner += f" · Moodle guidelines loaded ({root})"

print(json.dumps({
    "systemMessage": banner,
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "\n\n".join(p for p in parts if p),
    },
}))
PY
exit 0
