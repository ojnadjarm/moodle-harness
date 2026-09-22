#!/usr/bin/env python3
"""Build INDEX.md for the moodle-devdocs mirror: one line per API/guide page."""

import re
import sys
from pathlib import Path

TITLE_RE = re.compile(r"^---\s*\n.*?^title:\s*(.+?)\s*$.*?^---\s*$", re.S | re.M)
HEADING_RE = re.compile(r"^#\s+(.+)$", re.M)


def title_of(path):
    text = path.read_text(errors="replace")
    match = TITLE_RE.match(text) or HEADING_RE.search(text)
    if match:
        return match.group(1).strip().strip("'\"")
    return path.stem


def main():
    root = Path(sys.argv[1])
    lines = ["# moodle-devdocs index (in-dev version, `docs/` = latest branch)",
             "", "For an older Moodle branch, swap the `docs/` prefix for "
             "`versioned_docs/version-<X.Y>/` — filenames match.", ""]
    for section in ("apis", "guides", "gettingstarted"):
        base = root / "docs" / section
        if not base.exists():
            continue
        lines.append(f"## docs/{section}")
        for path in sorted(base.rglob("*.md*")):
            if any(part.startswith("_") for part in path.relative_to(base).parts):
                continue
            rel = path.relative_to(root)
            lines.append(f"- {rel} — {title_of(path)}")
        lines.append("")
    out = root / "INDEX.md"
    out.write_text("\n".join(lines) + "\n")
    print(f"wrote {out} ({len(lines)} lines)")


if __name__ == "__main__":
    main()
