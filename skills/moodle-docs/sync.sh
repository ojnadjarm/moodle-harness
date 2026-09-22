#!/usr/bin/env bash
# Mirror the moodledev.io markdown sources (moodle/devdocs) into ~/.moodle-devdocs.
set -euo pipefail

DEST="$HOME/.moodle-devdocs"
REPO="https://github.com/moodle/devdocs.git"

if [ ! -d "$DEST/.git" ]; then
    git clone --depth 1 --no-checkout "$REPO" "$DEST"
    git -C "$DEST" sparse-checkout set docs versioned_docs general
    git -C "$DEST" checkout main
else
    git -C "$DEST" fetch --depth 1 origin main
    git -C "$DEST" reset --hard origin/main
fi

python3 "$(dirname "$0")/build-index.py" "$DEST"

echo
for d in docs general "$DEST"/versioned_docs/version-*; do
    d="${d#"$DEST"/}"
    [ -d "$DEST/$d" ] || continue
    printf '%-28s %4d pages\n' "$d" "$(find "$DEST/$d" \( -name '*.md' -o -name '*.mdx' \) | wc -l)"
done
printf '%-28s %s\n' "total size" "$(du -sh "$DEST" | cut -f1)"
