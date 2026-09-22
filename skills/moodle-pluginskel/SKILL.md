---
name: moodle-pluginskel
description: Generate a Moodle plugin skeleton deterministically from a small YAML recipe — standalone, no Moodle install, container, or plugin needed. Use when creating a new Moodle plugin/subplugin or scaffolding boilerplate (version.php, lang, settings, db/access, install/upgrade, privacy provider, PHPUnit and CLI stubs). The LLM writes the recipe; the bundled generator writes the files — saving tokens.
---

# Generate a Moodle plugin skeleton (standalone)

Don't hand-write plugin boilerplate. Write a **small YAML recipe** and run the bundled
generator — it renders the whole tree deterministically, passes the Moodle code checker
cleanly, and costs no output tokens for the generated files.

Requirements: host `python3` with PyYAML. No Moodle, no docker.

## 1. Write the recipe

Only `component` is required; everything else has sensible defaults. Full grammar:

```yaml
component: tool_example          # required, frankenstyle
name: Example tool               # plugin display name (default: plugin name)
release: "0.1.0"                 # default 0.1.0
requires: "4.5"                  # branch 4.0–5.1 or a raw version number (default 4.5)
maturity: MATURITY_ALPHA         # default
copyright: 2026 onwards, Example Author <author@example.com>   # optional — defaults to git config user.name/email
features:
  settings: true                 # settings.php (page for tool/report/local, fulltree otherwise)
  install: true                  # db/install.php
  upgrade: true                  # db/upgrade.php
  privacy: true                  # default true — null provider + privacy:metadata string
capabilities:                    # -> db/access.php + lang strings
  - name: view
    title: View example
    captype: read                # default
    contextlevel: CONTEXT_SYSTEM # default
    archetypes:                  # default: manager CAP_ALLOW
      - role: manager
        permission: CAP_ALLOW
lang_strings:                    # extra lang strings
  - id: taskname
    text: Scheduled task
phpunit_tests:                   # -> tests/<classname>_test.php stubs
  - classname: example
cli_scripts:                     # -> cli/<filename>.php (known plugin types only)
  - filename: run
```

Always generated: `version.php` and `lang/en/<component>.php`. Version number is today's
date (`YYYYMMDD00`). Write the recipe to a temp file, e.g. `/tmp/recipe.yaml`.

## 2. Preview, then generate

```bash
python3 ~/.claude/skills/moodle-pluginskel/generate.py --list /tmp/recipe.yaml
python3 ~/.claude/skills/moodle-pluginskel/generate.py --target-dir <dir> /tmp/recipe.yaml
```

Writes `<dir>/<pluginname>` (default `<dir>` is the cwd). **Fails if the target already
exists** — never overwrites; generate into a fresh location and merge.

## 3. Verify and finish

- Generated code passes `phpcs --standard=moodle` cleanly; run `/moodle-ci` after adding
  real logic.
- Fill in the actual plugin logic — the skeleton only scaffolds boilerplate.
- If the plugin will run in a live Moodle, purge caches after dropping it in so the new
  classes are picked up.

## Notes

- Supported plugin types for path-dependent files (cli config.php depth, settings style)
  are mapped in `generate.py` (`TYPE_PATHS`); unknown/custom subplugin types still generate
  everything except `cli_scripts`. Extend the map when a new type is needed.
- Unsupported pluginskel features (mod/block feature blocks, observers, events, external
  services, mobile addons) are out of scope — write those files by hand or extend
  `templates/`.
