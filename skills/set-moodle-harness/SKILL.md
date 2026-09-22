---
name: set-moodle-harness
description: Provision the current machine for the Moodle harness — install moodle-plugin-ci on the host, make the hook scripts executable, idempotently wire the SessionStart + Stop hooks into ~/.claude/settings.json, and verify the whole setup. Use when setting up the harness on a new machine, after cloning/syncing ~/.claude, or to repair/verify an existing harness install.
---

# Set up the Moodle harness

Idempotent installer for the harness (auto-loaded Moodle guidelines + `/moodle-ci`). Safe to
re-run. It provisions the **per-machine** pieces and verifies the **synced** pieces; it does
not overwrite the user's guideline files or hand-edited scripts.

Run the steps in order and report a readiness checklist at the end.

## 1. Check host tooling

```bash
for t in php composer docker python3 git; do printf '%-9s %s\n' "$t" "$(command -v $t || echo MISSING)"; done
```
- `php`, `composer`, `python3`, `git` are **required** (composer + php for moodle-plugin-ci;
  python3 for the settings merge in step 4; git for the devdocs mirror in step 6).
- `docker` is needed only for PHPUnit; static checks work without it. If missing, note it but
  continue.

## 2. Verify the harness files are present

These travel with `~/.claude` (hook scripts + skills). They are **not** recreated here — if any
is missing, the `~/.claude` sync is incomplete; tell the user and stop.

```bash
for f in \
  ~/.claude/hooks/moodle-detect.sh \
  ~/.claude/hooks/moodle-session-start.sh \
  ~/.claude/hooks/moodle-stop-reminder.sh \
  ~/.claude/hooks/moodle-container.sh \
  ~/.claude/skills/moodle-ci/SKILL.md \
  ~/.claude/skills/moodle-docs/SKILL.md \
  ~/.claude/skills/moodle-docs/sync.sh \
  ~/.claude/skills/moodle-docs/search.py \
  ~/.claude/skills/moodle-pluginskel/SKILL.md \
  ~/.claude/skills/moodle-guidelines/SKILL.md \
  ~/.claude/skills/moodle-install/SKILL.md \
  ~/.claude/skills/moodle-install/install.sh \
  ~/.claude/skills/moodle-install/docker-compose.shared.yml \
  ~/.claude/skills/moodle-install/nginx.conf \
  ~/.claude/skills/i-have-adhd/SKILL.md \
  ~/.claude/CLAUDE.md \
  ~/.claude/moodle-guidelines.md \
  ~/.claude/moodle-coding-style.md \
  ~/.claude/moodle-tips.md \
  ~/.claude/moodleapp-instructions.md ; do
  [ -f "$f" ] && echo "ok   $f" || echo "MISS $f"
done
```
- Missing hook script / `moodle-ci` skill → blocking; the harness can't run. Stop and report.
- Missing guideline/tips/CLAUDE.md files → warn (SessionStart still runs but injects less);
  these are user content, not recreated here.

## 3. Make hook scripts executable

```bash
chmod +x ~/.claude/hooks/moodle-detect.sh ~/.claude/hooks/moodle-session-start.sh \
         ~/.claude/hooks/moodle-stop-reminder.sh ~/.claude/hooks/moodle-container.sh \
         ~/.claude/skills/moodle-install/install.sh
```

## 4. Wire the hooks into settings.json (idempotent)

Uses python3 — adds exactly one entry per event pointing at our scripts, dropping any prior
copy of the same command, and preserving every other key and hook. Stores `$HOME/...` as a
literal so it stays portable across machines.

```bash
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
data = json.load(open(p)) if os.path.exists(p) else {}
hooks = data.setdefault("hooks", {})
def ensure(event, cmd):
    arr = [g for g in hooks.get(event, [])
           if not any(h.get("command") == cmd for h in g.get("hooks", []))]
    arr.append({"hooks": [{"type": "command", "command": cmd}]})
    hooks[event] = arr
ensure("SessionStart", "$HOME/.claude/hooks/moodle-session-start.sh")
ensure("Stop", "$HOME/.claude/hooks/moodle-stop-reminder.sh")
json.dump(data, open(p, "w"), indent=2)
print("settings.json wired:", json.dumps(data.get("hooks"), indent=2))
PY
```

## 5. Install moodle-plugin-ci on the host (if missing)

```bash
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
if "$MPC" --version >/dev/null 2>&1; then "$MPC" --version
else composer create-project moodlehq/moodle-plugin-ci ~/.moodle-plugin-ci '^4' --no-interaction; fi
```
Isolated install (won't collide with a globally-required phpcs). Static subcommands run on
host PHP, no DB needed.

## 6. Mirror the developer docs (if missing or stale)

```bash
bash ~/.claude/skills/moodle-docs/sync.sh
```
Idempotent — clones the moodledev.io sources into `~/.moodle-devdocs` (sparse, markdown only)
or fast-updates an existing mirror, then rebuilds `INDEX.md`.

## 7. Smoke-test

```bash
# Detector: from a Moodle dir it prints a root; elsewhere it's silent.
~/.claude/hooks/moodle-detect.sh && echo "[detect ok]" || echo "[not a moodle dir here]"
# SessionStart hook: valid JSON with the banner (ADHD always; Moodle guidelines on Moodle dirs).
echo '{}' | ~/.claude/hooks/moodle-session-start.sh | python3 -c 'import json,sys; print("[hook ok]", json.load(sys.stdin)["systemMessage"])'
# Container discovery (only if docker is up): prints "<container>\t<dirroot>".
~/.claude/hooks/moodle-container.sh "$PWD" || echo "[no moodle container running — fine for static checks]"
# moodle-plugin-ci usable:
"$MPC" --version
# Docs mirror present and fresh:
[ -f ~/.moodle-devdocs/INDEX.md ] && git -C ~/.moodle-devdocs log -1 --format='devdocs mirror: %cs'
```

## 8. Report readiness

Print a checklist: required tooling present, harness files ok, scripts executable, settings.json
wired (show the `hooks` block), moodle-plugin-ci version, docs mirror date, and docker/container
status. Remind the
user the **SessionStart/Stop hooks take effect in a new session**. Then they can run `/moodle-ci`.
