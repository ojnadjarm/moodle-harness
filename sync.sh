#!/usr/bin/env bash
# Update this repo copy from the live harness in ~/.claude. One-way export;
# review the diff and commit manually.
set -e

SRC="$HOME/.claude"
DEST="$(cd "$(dirname "$0")" && pwd)"
SKILLS=(moodle-ci moodle-docs moodle-pluginskel moodle-guidelines moodle-install moodle-upgrade-audit moodle-upgrade-rehearsal moodle-ai-setup moodle-web set-moodle-harness i-have-adhd systematic-debugging verification-before-completion)
DOCS=(CLAUDE.md moodle-guidelines.md moodle-coding-style.md moodle-tips.md moodle-quickref.md moodleapp-instructions.md)

mkdir -p "$DEST/hooks" "$DEST/skills"
cp -p "$SRC"/hooks/moodle-*.sh "$DEST/hooks/"
for s in "${SKILLS[@]}"; do
    rm -rf "$DEST/skills/$s"
    cp -pr "$SRC/skills/$s" "$DEST/skills/$s"
done
for d in "${DOCS[@]}"; do
    cp -p "$SRC/$d" "$DEST/"
done
# Portable settings: hooks + UI prefs only (no machine-specific autoMode allow-list).
python3 - "$SRC/settings.json" "$DEST/settings.example.json" <<'PY'
import json, sys
src = json.load(open(sys.argv[1]))
keep = {k: src[k] for k in ("outputStyle", "effortLevel", "autoCompactEnabled",
                            "autoCompactWindow") if k in src}
json.dump(keep, open(sys.argv[2], "w"), indent=2)
PY
# Hooks come from the harness template, not from the live (possibly fleet-wrapped) settings.
python3 "$SRC/skills/set-moodle-harness/wire-hooks.py" "$DEST/settings.example.json" >/dev/null
find "$DEST/skills" -type d -name __pycache__ -exec rm -rf {} +

bash "$DEST/tests/no-machine-values.test.sh" "$DEST" >/dev/null || { echo "sync: a machine value reached the repo; run tests/no-machine-values.test.sh" >&2; exit 1; }
echo "Harness copy updated at $DEST — review the diff and commit."
