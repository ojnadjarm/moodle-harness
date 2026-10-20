---
name: moodle-pluginskel
description: Generate Moodle plugin code from a YAML recipe, no Moodle install. Use for a new plugin (mod_, block_, report_), install.xml tables, upgrade step, backup, web service, Behat, test data, privacy, task, hook, event, table_sql, capability, settings, dynamic form, mobile, message, cache, output class.
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
name_plural: Example tools       # mod_ only: modulenameplural (default: name + s, or es after s/x/z/ch/sh)
release: "0.1.0"                 # default 0.1.0
requires: "4.5"                  # branch 4.0–5.3 or a raw version number (default 4.5)
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
tables:                          # -> db/install.xml (a mod_ instance table merges into the default)
  tool_example_entry:
    fields: [userid, name:char:255, intro:text, timemodified]   # name[:type[:length]], type default int
    keys: [userid->user.id]
    indexes: ["unique:userid,name"]
```

Always generated: `version.php` and `lang/en/<component>.php`. `mod_` adds `lib.php`,
`mod_form.php`, `view.php`, `index.php`, `db/install.xml` and the `addinstance`/`view` caps;
`block_` adds `block_<name>.php` and the `addinstance`/`myaddinstance` caps (a recipe
capability with the same name merges its keys over the default); `report_` adds `lib.php`
(course navigation link, cap-checked, `index.php?id=`) and `index.php`. Version number is today's
date (`YYYYMMDD00`). Write the recipe to a temp file, e.g. `/tmp/recipe.yaml`.

## 2. Preview, then generate

```bash
python3 ~/.claude/skills/moodle-pluginskel/generate.py --list /tmp/recipe.yaml
python3 ~/.claude/skills/moodle-pluginskel/generate.py --target-dir <dir> /tmp/recipe.yaml
```

Writes `<dir>/<pluginname>` (default `<dir>` is the cwd). **Fails if the target already
exists** — never overwrites; generate into a fresh location and merge.

## Helpers for an existing plugin

- `python3 ~/.claude/skills/moodle-pluginskel/upgrade.py <plugin-dir> [--base REF | --base-file old.xml]
  [--add-field T.F:TYPE[:LEN]]... [--dry-run]` — turns a `db/install.xml` change (vs REF, default `HEAD`, or an old
  file without git) into a `db/upgrade.php` step, savepoint and version bump; `--add-field` adds the field to
  install.xml first (generate.py field grammar).
- `python3 ~/.claude/skills/moodle-pluginskel/testdata.py <plugin-dir> [--dir .research/testdata]` —
  idempotent `setup.php`, `reset.php` and `testing-instructions.md` for manual testing; never overwrites.
- `python3 ~/.claude/skills/moodle-pluginskel/backup.py <mod-or-local-dir> [--dry-run]` — from `db/install.xml`: the 4
  `backup/moodle2` files of a mod_ (flips `FEATURE_BACKUP_MOODLE2` to true), or a local_'s course-level
  `backup_local_<x>_plugin`/`restore_local_<x>_plugin` with a PHPUnit test; block_ is refused (core never loads it).
- `python3 ~/.claude/skills/moodle-pluginskel/external.py <plugin-dir> <verb_noun> [--params a:int,b:text]
  [--returns single|multiple] [--type read|write] [--ajax] [--capability view] [--table T [--cols a,b]]` — web
  service function: `classes/external/<name>.php`, `db/services.php` entry, a test and the version bump, per Moodle
  version; `--table` (install.xml table with a userid field) makes execute() return the user's rows (`--cols`, id
  always) with a seeded test. `--mobile` adds it to the Moodle app service (default when `db/mobile.php` exists).
- `python3 ~/.claude/skills/moodle-pluginskel/behat.py <plugin-dir> <feature> [--recipe f.yaml]` —
  `tests/behat/<feature>.feature` from real core steps only (plus the data generator for mod_); recipe
  `page: {path, param, instance: course, name}` writes a `behat_<component>` page resolver for a course page.
- `python3 ~/.claude/skills/moodle-pluginskel/privacy.py <plugin-dir> [--dry-run]` — replaces the null
  provider with a real one (metadata, request, userlist) from the user fields of `db/install.xml`, plus
  `tests/privacy/provider_test.php` (metadata, contexts, export, delete, userlist); a table with a courseid field
  maps to the course context (contexts, export, delete), else the system context.
- `python3 ~/.claude/skills/moodle-pluginskel/task.py <plugin-dir> <name> (--scheduled "<m h d M dow>"
  | --adhoc) [--purge T.TIMECOL [--setting NAME]]` — `classes/task/<name>.php`, `db/tasks.php` entry (scheduled),
  lang string, test, bump; `--purge` (scheduled) deletes rows of T older than the retention (`--setting`: seconds
  from get_config, 0 keeps all; default 30 days) with a seeded test.
- `python3 ~/.claude/skills/moodle-pluginskel/hook.py <plugin-dir> <hook-class|legacy-callback> [--core
  <root>]` — callback in `classes/hook_callbacks.php`, `db/hooks.php` entry, version bump. `--core` defaults to the
  `$S/msrc` tree of `$plugin->requires` (else the newest non-Vass env), so a 4.5 plugin resolves against 4.5.
  A hook class missing from that tree is rc 1 naming class and branch; `--force` writes it with a warning.
- `python3 ~/.claude/skills/moodle-pluginskel/event.py <plugin-dir> <target_action> --crud c|r|u|d --edulevel
  teaching|participating|other [--objecttable T] [--observe '\core\event\x' [--emit | --table T]]` —
  `classes/event/<name>.php`, lang string, bump; `--observe` adds the `db/events.php` entry, a
  `classes/observer.php` handler stub (debugging() spy test; `--table T` deletes the related user's rows,
  DB-row test; `--emit` re-triggers this event, event-sink test) and `tests/observer/<name>_test.php`.
  `--objecttable` with `--observe` needs `--emit`. Without `--observe` it also writes `tests/event/<name>_test.php`
  (event sink) and prints a trigger snippet; `--emit-in <page.php>` wires the trigger into that page after its
  `require_capability()` (else `require_login()`), alone it wires an existing event. The observer test copies
  crud/edulevel/context from the core event. `--core` as in hook.py.
- `python3 ~/.claude/skills/moodle-pluginskel/table.py <plugin-dir> <name> --table T --cols id,name,timemodified
  [--datecols a,b] [--dynamic] [--capability c] [--context system|course]` — `classes/table/<name>.php` (table_sql;
  `--dynamic` = core_table\dynamic, 4.0+), the `<name>.php` page, lang strings and a PHPUnit test; `--datecols`
  overrides the time*/*date guess of which columns are dates; `--context course` takes courseid,
  `require_login($course)`, checks the cap in the course context and lists that course's rows (T needs courseid);
  `--page index --param id` gives the report_ convention (`index.php?id=`).
- `python3 ~/.claude/skills/moodle-pluginskel/access.py <plugin-dir> <name> --type read|write --context
  system|user|coursecat|course|module|block [--archetypes manager=allow] [--clone C] [--risk R] [--title T]`
  — `db/access.php` capability, sorted lang string, version bump.
- `python3 ~/.claude/skills/moodle-pluginskel/settings.py <plugin-dir> [--setting NAME:TYPE[:DEFAULT]]...
  [--choices a,b] [--page p.php] [--cap C]` — admin settings (configtext, configint = PARAM_INT, configcheckbox,
  configselect, configduration) and `admin_externalpage` links in `settings.php`, plus lang strings; on a block_ it
  adds or patches `has_config()` to return true (else core never loads settings.php).
- `python3 ~/.claude/skills/moodle-pluginskel/form.py <plugin-dir> <name> --fields a:text,b:int --cap C
  [--context system|course|module] [--page view.php]` — `core_form\dynamic_form` in `classes/form/<name>.php`, an
  AMD ModalForm opener, lang strings and a test; `module` (mod_ only) passes cmid, `--page` adds the trigger
  button and `js_call_amd` to that page (refused with `module` when the page has no cm).
- `python3 ~/.claude/skills/moodle-pluginskel/mobile.py <plugin-dir> --delegate CoreMainMenuDelegate
  [--handler H] [--table T --cols a,b] [--capability C]` — Moodle App support: `db/mobile.php` handler,
  `classes/output/mobile.php` (`require_capability`, default the only db/access.php cap),
  `templates/mobileapp/<H>.mustache`, `tests/output/mobile_test.php` and lang (delegates:
  `moodle-ci/reference/mobile-delegates.json`); `--table` lists the
  user's rows of an install.xml table with a userid field, passed in `otherdata` (never `{{{ }}}`, which the app
  compiles as an Angular template); check it with `$S/mmobile`.
- `python3 ~/.claude/skills/moodle-pluginskel/cache.py <plugin-dir> <area> [--mode application|session|request]
  [--simplekeys] [--ttl N]` — MUC definition in `db/caches.php`, `cachedef_<area>` string, typed accessor
  `classes/local/cache/<area>.php` (get/set/purge), a test and the version bump.
- `python3 ~/.claude/skills/moodle-pluginskel/message.py <plugin-dir> <name> [--capability C]
  [--defaults popup,email]` — message provider: `db/messages.php` entry, `messageprovider:<name>` string,
  `classes/local/notifier.php` `send_<name>()`, a `redirectMessages` sink test and the version bump.
- `python3 ~/.claude/skills/moodle-pluginskel/output.py <plugin-dir> <name> --fields a:text,b:int,c:url
  [--renderer]` — renderable + templatable `classes/output/<name>.php`, `templates/<name>.mustache` with an Example
  context, `tests/output/<name>_test.php`; `--renderer` adds `render_<name>()` to `classes/output/renderer.php`.

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
- Mobile addons beyond one delegate handler (`mobile.py`) are out of scope —
  write those files by hand or extend `templates/`.
