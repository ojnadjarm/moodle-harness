#!/usr/bin/env bash
# Detect whether the current project is a Moodle project.
# Prints the matched Moodle root and exits 0 if found; exits 1 otherwise.
# Shared by the SessionStart and Stop hooks so detection logic lives in one place.

start="${CLAUDE_PROJECT_DIR:-$PWD}"
dir="$start"

for _ in $(seq 1 8); do
    [ -z "$dir" ] && break

    # Plugin marker: a version.php declaring $plugin->component.
    if [ -f "$dir/version.php" ] && grep -q '\$plugin->component' "$dir/version.php" 2>/dev/null; then
        echo "$dir"
        exit 0
    fi

    # Moodle root markers (with or without a public/ docroot).
    if [ -f "$dir/lib/moodlelib.php" ] || [ -f "$dir/public/lib/moodlelib.php" ]; then
        echo "$dir"
        exit 0
    fi

    [ "$dir" = "$HOME" ] && break
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
done

exit 1
