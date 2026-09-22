#!/usr/bin/env bash
# Update this repo copy from the live harness in ~/.claude. One-way export;
# review the diff and commit manually.
set -e

SRC="$HOME/.claude"
DEST="$(cd "$(dirname "$0")" && pwd)"
SKILLS=(moodle-ci moodle-docs moodle-pluginskel moodle-guidelines moodle-install set-moodle-harness i-have-adhd)
DOCS=(CLAUDE.md moodle-guidelines.md moodle-coding-style.md moodle-tips.md moodleapp-instructions.md)

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
keep = {k: src[k] for k in ("hooks", "outputStyle", "effortLevel", "autoCompactEnabled",
                            "autoCompactWindow") if k in src}
# Keep only the harness hooks; machine-specific ones stay out of the repo.
keep["hooks"] = {ev: [g for g in groups
                      if any("moodle-" in h.get("command", "") for h in g.get("hooks", []))]
                 for ev, groups in keep.get("hooks", {}).items()}
json.dump(keep, open(sys.argv[2], "w"), indent=2)
open(sys.argv[2], "a").write("\n")
PY
find "$DEST/skills" -type d -name __pycache__ -exec rm -rf {} +

echo "Harness copy updated at $DEST — review the diff and commit."
