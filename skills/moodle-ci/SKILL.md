---
name: moodle-ci
description: Run the Moodle CI suite for the current plugin. Use after finishing PHP code, or when the user asks to run moodle checks, the code checker, phpcs, PHPUnit, or "the full CI". Defaults to a quick run (phpcs + PHPUnit); supports a full run mirroring the Bitbucket pipeline. Static checks run on the host; PHPUnit runs in the discovered Moodle container. Environment-agnostic — no hardcoded container names or paths.
---

# Moodle CI runner

Runs the same checks as the Bitbucket pipeline against the **current plugin**, on any
machine / any environment (nothing is hardcoded — the container and paths are discovered).

**Architecture:** the Moodle app container has PHP + PHPUnit + the DB, but typically **no
composer or phpcs**; those live on the **host** and survive container rebuilds. So:
- **Static checks (phpcs / codechecker / phpmd / validate / …) run on the HOST** against the
  plugin files directly.
- **PHPUnit runs inside the discovered container** (it needs the configured Moodle + DB).

`$ARGUMENTS` selects the mode: `quick` (default — phpcs + PHPUnit) or `full` (whole suite).

## 0. Discover environment (do this first)

```bash
PLUGIN="$PWD"                                   # or the plugin dir under test
COMPONENT=$(grep -hoP "\\\$plugin->component\s*=\s*'\K[^']+" "$PLUGIN/version.php")
read -r CONTAINER DIRROOT < <(~/.claude/hooks/moodle-container.sh "$PLUGIN")
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
```
- `PLUGIN` — host path of the plugin (the dir whose `version.php` sets `$plugin->component`).
  Works for any Moodle version (code at repo root on 4.x/5.0, under `public/` on 5.1+).
- `COMPONENT` — e.g. `tool_example`; the PHPUnit testsuite is `${COMPONENT}_testsuite`.
- `~/.claude/hooks/moodle-container.sh` discovers the running container that mounts this code
  and the in-container dirroot (where phpunit runs), by matching mounts — not by name.
- If it prints nothing: docker isn't reachable or the env isn't running. Tell the user to
  start their Moodle docker environment (don't guess the version); static checks below still
  work without it.

## 1. Quick mode (default) — the after-coding gate

**Code Checker (host).** Moodle-standard phpcs via moodle-plugin-ci (takes a directory):
```bash
"$MPC" codechecker "$PLUGIN"
```
Fallback if moodle-plugin-ci is absent: `phpcs --standard=moodle "$PLUGIN"` (use whatever
`phpcs` is on PATH / the user's composer global bin).
- Fix all **errors**. Auto-fix with `phpcbf --standard=moodle <path>` (or `"$MPC" codefixer`).
- Leave pre-existing **warnings** on legacy code unless asked (per the Moodle guidelines).

**PHPUnit (container).** Always scope to the plugin's testsuite — a bare run can collide with
sibling plugins (e.g. tool_example vs tool_trigger both declaring `event_processor_test`):
```bash
docker exec "$CONTAINER" bash -lc "cd '$DIRROOT' && vendor/bin/phpunit --testsuite ${COMPONENT}_testsuite"
```
- Focused run: add `--filter <method>` or pass a single test file path.
- First-ever run needs init (path is relative to the moodle code root inside the container;
  on 5.1+ it's under `public/`):
  `docker exec "$CONTAINER" bash -lc "cd '$DIRROOT' && php $(…)/admin/tool/phpunit/cli/init.php --no-composer-self-update"`

## 2. Full mode — mirrors the Bitbucket pipeline

Static steps on the **host** (no DB); PHPUnit in the container.
```bash
for step in codechecker phplint phpmd validate savepoints phpdoc mustache grunt; do
  "$MPC" "$step" "$PLUGIN"
done
docker exec "$CONTAINER" bash -lc "cd '$DIRROOT' && vendor/bin/phpunit --testsuite ${COMPONENT}_testsuite"
```
If a `moodle-plugin-ci` step errors on environment, fall back to the raw tool (e.g. grunt →
`(cd "$PLUGIN" && npx grunt)`).

## 3. Install moodle-plugin-ci (host, one-time, if `$MPC` missing)

```bash
composer create-project moodlehq/moodle-plugin-ci ~/.moodle-plugin-ci '^4' --no-interaction
```
Isolated install (avoids colliding with a globally-required phpcs). Static subcommands need
no DB; they run on host PHP.

## 4. Report

Summarize: phpcs errors fixed vs warnings left, PHPUnit pass/fail counts, and any failing
full-mode step. If anything fails, fix and re-run before declaring the work complete.
