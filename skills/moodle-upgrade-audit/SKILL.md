---
name: moodle-upgrade-audit
description: Audit a Moodle site's add-on plugins for an upgrade - read every non-core plugin from the site's app container, check each against the moodle.org plugins directory API (pluglist.php) for a target release (default 5.3), and write a keep / replace / remove table as Markdown and responsive HTML. Use for "plugin audit", "upgrade audit", "which plugins support 5.3", "keep replace remove", step 1 of the upgrade offer.
---

# moodle-upgrade-audit — plugin list to keep / replace / remove

```bash
python3 ~/.claude/skills/moodle-upgrade-audit/audit.py --container moodle52-app-1 --label "Moodle 5.2 demo site" \
  --md ~/drop/money/samples/upgrade-audit-5.2.md --html ~/drop/money/samples/upgrade-audit-5.2.html
python3 ~/.claude/skills/moodle-upgrade-audit/audit.py --plugins site.json --target 5.3 --html out.html   # a customer's list
bash ~/.claude/skills/moodle-upgrade-audit/tests/audit.test.sh                                          # fixtures, no network
```

- Never point `--container` at the 4.5 / Vass env (customer code); money demos use 5.2 or a fresh env.
- `--json-site FILE` saves the collected plugin list so a customer's site is read once and re-audited offline.
- The directory list (15.6 MB) is cached in `~/.cache/moodle-upgrade-audit/` for 24 h; `--pluglist FILE` skips the download.

## Verdicts (first match wins)
1. remove: code missing from disk, or the plugin is disabled (`is_enabled() === false`).
2. keep: not in the directory (custom code, test it on a copy).
3. keep: a version supports the target (note says which release to update to).
4. replace: no target version and no release for over 365 days.
5. keep: no target version yet but released within 365 days (re-check before the upgrade).

## Architecture
- `collect` (I/O): PHP on stdin to `docker exec -i <container> php`, read-only `core_plugin_manager` → site JSON.
- `load_directory` (I/O): pluglist file or cached download → `{component: entry}`.
- `assess` / `audit` (pure): one plugin + its entry + target + date → row; the only place verdict rules live.
- `render_md` / `render_html` (pure): report → text; HTML reuses the offer pages' palette, table becomes cards under 48rem.
- Single responsibility per function; new outputs add a renderer without touching `assess` (open/closed).
- Guide: `~/agents/KB/guides/moodle-upgrade-audit.md`.
