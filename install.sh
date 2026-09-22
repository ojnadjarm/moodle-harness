#!/usr/bin/env bash
# Install the Moodle harness files into ~/.claude. Idempotent (plain file copy).
# After running this, open Claude Code and run /set-moodle-harness to provision the
# machine (install moodle-plugin-ci, wire the hooks into settings.json, verify).
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude"
DOCS=(CLAUDE.md moodle-guidelines.md moodle-coding-style.md moodle-tips.md moodleapp-instructions.md)

mkdir -p "$DEST/hooks" "$DEST/skills"
cp -p  "$SRC"/hooks/*.sh        "$DEST/hooks/"
cp -pr "$SRC"/skills/*          "$DEST/skills/"
for d in "${DOCS[@]}"; do
    if [ -f "$DEST/$d" ] && ! cmp -s "$SRC/$d" "$DEST/$d"; then
        cp -p "$DEST/$d" "$DEST/$d.bak"
        echo "backed up existing $d -> $d.bak"
    fi
    cp -p "$SRC/$d" "$DEST/"
done
chmod +x "$DEST"/hooks/*.sh

echo "Moodle harness files installed into $DEST"
echo "Next: in Claude Code, run /set-moodle-harness to finish provisioning."
echo "Optional: merge settings.example.json into ~/.claude/settings.json for the same UI prefs."
