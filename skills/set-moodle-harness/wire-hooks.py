#!/usr/bin/env python3
"""Wire the Moodle SessionStart + Stop hooks into a Claude settings file, idempotently."""
import json
import os
import sys

SESSION = "$HOME/.claude/hooks/moodle-session-start.sh"
STOP = "$HOME/.claude/hooks/moodle-stop-reminder.sh"


def commands(groups):
    return [h.get("command", "") for g in groups for h in g.get("hooks", [])]


def fleet_session_start(groups):
    """True when a non-Moodle session-start.sh (the fleet wrapper) already injects the context."""
    return any(c.split()[0].endswith("/session-start.sh") for c in commands(groups) if c.strip())


def wire(data):
    hooks = data.setdefault("hooks", {})
    session = hooks.get("SessionStart", [])
    if SESSION not in commands(session) and not fleet_session_start(session):
        hooks["SessionStart"] = session + [{"hooks": [{"type": "command", "command": SESSION}]}]
    stop = hooks.get("Stop", [])
    if STOP not in commands(stop):
        hooks["Stop"] = stop + [{"hooks": [{"type": "command", "command": STOP}]}]
    return data


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.claude/settings.json")
    before = json.load(open(path)) if os.path.exists(path) and os.path.getsize(path) else {}
    after = wire(json.loads(json.dumps(before)))
    if after == before:
        print(f"wire-hooks: no changes ({path})")
        return
    with open(path, "w") as f:
        json.dump(after, f, indent=2)
        f.write("\n")
    print(f"wire-hooks: wired {path}")
    print(json.dumps(after["hooks"], indent=2))


if __name__ == "__main__":
    main()
