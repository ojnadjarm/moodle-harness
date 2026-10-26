---
name: moodle-ci
description: Moodle CI for a plugin. Use after PHP code: code checker, phpcs-delta, phpcbf, PHPUnit, Behat, privacy, lang, PHP/API compat, coverage (mcovers), rules (mrules), App checks, version matrix, CI workflow, fixture plugin, upgrade, web service calls (mws), "the full CI". `mci full` = pipeline.
---

# Moodle CI runner

Runs the same checks as the Bitbucket pipeline against the **current plugin**, on any
machine / any environment (nothing is hardcoded — the container and paths are discovered).

**Architecture:** the Moodle app container has PHP + PHPUnit + the DB, but typically **no
composer or phpcs**; those live on the **host** and survive container rebuilds. So:
- **On the host:** codechecker, phplint, savepoints, phpcompat on the plugin files; phpmd, mustache
  and grunt with `-m <moodle root>`; the static half of privacy.
- **In the discovered container:** validate and phpdoc (they need Moodle's config.php and dataroot),
  PHPUnit, Behat and the privacy provider tests (DB). `mci`/`mtest` place each step; never hand-write
  `docker exec`.

`$ARGUMENTS` selects the mode: `auto` (default in git — the steps the change class needs, `change-class`), `quick` (codechecker, phpcs-delta, mphpcompat, mlang, mapicompat, mcovers, PHPUnit) or `full` (whole suite).

## Scripts (use these before hand-written commands)

`S=~/.claude/skills/moodle-ci/scripts`
- `$S/mci [auto|quick|full] [plugin-dir]` — the whole run: each step where it works (host; host `-m root`;
  validate/phpdoc in the container, which has Moodle's config and dataroot; grunt with the node major
  `package.json` asks for, from nvm). A step that cannot run here is a named SKIP. Prints red steps' log
  tails, then one `step rc sec` table; exit 1 if any step is red.
- `$S/mtest phpunit [plugin-dir|file_test.php] [--filter X] [args]` — finds plugin, container
  and dirroot; runs `init.php --disable-composer` only when `util.php --diag` says stale; always
  `--testsuite <component>_testsuite` (a single file becomes `--filter <class>`, so base
  testcases in `tests/` load); prints failures + summary, full log path last. Run from any cwd.
  `--reset` drops the test DB (`util.php --drop`) and re-inits it; when the drop refuses ("Can not drop non-test
  site") it drops the stray `phpu_` tables through `mdb --write` (never vass/4.5). Works from a Moodle root too.
  `--changed [base]` runs only the tests covering the git change vs base (default `HEAD` + untracked):
  changed tests, `classes/x/y.php` -> `tests/x/y_test.php`, else the whole suite; mapping printed first.
- `$S/mtest behat [plugin-dir|file.feature|dir] [--tags X] [args]` — same for Behat (init when
  stale or not enabled; default target `<plugin>/tests/behat`). `--parallel N` splits features over N
  sites (cap 8 minus busy Selenium sessions; 6 features: 2.4× faster at N=6).
  The shared Selenium is stopped after 2 h idle (`selenium-idle.timer`); `mtest behat` runs
  `docker start moodle-shared-selenium-1` itself when it is exited (by hand: the same command).
- `$S/mtest init phpunit|behat [plugin-dir]` — only the init (niced, only when stale), prints seconds.
- `$S/mphpcompat [plugin-dir] [--php X.Y]` — PHPCompatibility against the minimum PHP of `requires`
  (4.1 = 7.4 … 5.2 = 8.3); `file:line message`, exit 1 on any error, SKIP rc 3 when not installable.
- `$S/mapicompat [plugin-dir] [--upgrading FILE] [--since X.Y]` — core APIs from UPGRADING.md "Added"
  bullets newer than `requires`: `file:line symbol added in X.Y (MDL-n)`, exit 1 on hits, SKIP rc 3.
  `--removed [--until X.Y]`: APIs a later branch removed (fail) or deprecated (warn) instead. Also hook classes
  newer than `requires` (msrc trees): `file:line \x\hook\y added after X.Y`.
- `$S/mfix [plugin-dir] [--all] [--base REF]` — phpcbf on the changed .php files (whole plugin with `--all`
  or outside git), then the codechecker errors left; exit 1 if any remain, SKIP rc 3 without MPC.
- `$S/mlang [plugin-dir]` — lang ids used in PHP, mustache, JS, db/access, messages, caches: missing id
  FAIL `file:line id` (exit 1), unused id WARN. `--sync <xx>` copies lang/en ids missing from lang/<xx> in.
- `$S/phpcs-delta [--base REF] [paths]` — only the violations your change adds: each changed
  or new `.php` file vs the merge-base with REF (default `HEAD`), matched by sniff + message +
  line text. Exit 1 on new errors. Use it for scope-only work instead of whole-plugin
  codechecker output or hand-made `git show` base copies.
- `$S/mfixture add|rm|with <env> <plugin-dir|component> [-- cmd]` — fixture plugins in dev envs
  (5.2/5.3; refuses 4.5/vass): `add` copies + `upgrade.php --non-interactive`, `rm` runs
  `uninstall_plugins.php --run` then deletes the dir, `with` removes it on exit, error or TERM. One lock per
  env (waits `MFIXTURE_WAIT` s, `--no-wait` rc 4); `mfixture status <env>` shows the holder and php processes
  (rc 1 busy) — use it instead of `docker exec ... ps aux`. `with` exports `MFIXTURE_DIR` and `MFIXTURE_COMP` to cmd.
- `$S/mexec <script.php|cmd> [args]` — run any Moodle CLI as www-data in the container mounting the cwd (public/-aware); use instead of hand-written `docker compose exec`.
- `$S/mphp [--admin] <'php code'|file.php|->` — PHP with CLI_SCRIPT, config.php and `$CFG/$DB/$USER` in the
  cwd's container (www-data; `--admin` logs in admin); rc is PHP's. Instead of `php -r 'require config.php'`.
  The header goes after a leading `declare()`/`namespace`; code that requires config.php itself runs as is
  (no header, `--admin` ignored) in the file's dir.
- `$S/mupgrade [plugin-dir]` — `upgrade.php --non-interactive` + `purge_caches.php`, then prints
  `<component> <old> -> <new>` read back from the DB; exit 1 when the DB version differs. Never init.
- `$S/mdb [--env <name>] [--write] [--json] "<sql>" [param...]` — SQL on the env DB of the cwd (pgsql/mysql from
  config.php, `{table}` -> prefix, `?` params); TSV with header; read-only transaction unless `--write`. `--env 5.2`
  reads `~/moodle-envs/<name>` from any cwd (vass*/4.5*/unknown refused, rc 64). Instead of psql.
- `$S/mws [--env <name>] [--user <u|id>] [--ajax] <function> [key=value ...] [--json '{...}']` — call a web service
  function as a user (default admin) through `call_external_function`, no token setup; prints the JSON result or the
  exception with debuginfo. `--list [pattern]` lists external functions. rc 64 usage/refusal (vass*/4.5*).
- `$S/mgrunt [plugin-dir]` — `grunt amd` for this plugin only, with the nvm node matching the root
  `engines.node`; lists changed amd/build files; rc 3 with the fix when no node or no `npm ci`.
- `$S/mversion bump|resolve|check [plugin-dir]` — bump `$plugin->version` (YYYYMMDDXX), resolve a version-only
  merge conflict to max+1, check it against the `db/upgrade.php` savepoints.
- `$S/madopt [--since 7d] [--raw [N]] [dir]` — raw vs harness calls in the transcripts (adoption ratio);
  `--raw` lists the top raw command shapes (`bash -c`/`sh -c` broken down to the inner command); Vass and
  non-Moodle calls count as `excluded`, outside the ratio. Raw -> harness table for briefs: `~/.claude/moodle-quickref.md`.
- `$S/mrules [plugin-dir]` — the owner's rules phpcs misses: ticket ids, suppressions, Reflection in tests,
  test class names, `#[Covers]` before 5.0 (FAIL); confirm pages, banned template classes (WARN). Exit 1 on FAIL.
  Ticket ids in UPGRADING.md, readme*, upgrade.txt, CHANGES* and thirdpartylibs.xml are skipped (MDL ids are the norm).
- `$S/mprivacy [--static] [plugin-dir]` — core privacy compliance tests for the plugin's data sets, plus install.xml
  tables missing from `get_metadata`, `privacy:metadata*` ids without a lang string, a provider without
  `core_userlist_provider` (FAIL), and a user table missing from export or a delete method (WARN). `--static`: host
  checks only, no container. `// mprivacy:kept <table> <reason>` in classes/privacy turns that WARN into `KEPT`.
- `$S/mcovers [--check|--fix] [plugin-dir]` — coverage style vs `requires`: `@covers` tags below 5.0, `#[CoversClass]`
  attributes from 5.0; `--check` prints `file:line FAIL`, `--fix` converts (idempotent); SKIP rc 3 without tests/. In `mci quick`.
- `$S/msrc <X.Y|requires> [--fetch]` — prints a read-only core code root for a branch: a matching ~/moodle-envs tree
  (never 4.5/vass) or a shallow clone cache; `--fetch` clones it (niced), rc 3 when absent. hook.py/event.py `--core` default.
- `$S/msteps [words...]` — Behat step definitions of the env (cached per version + core root); `--check f.feature`
  lists undefined steps. Write features from `reference/behat.md`.
- `$S/mmobile [plugin-dir]` — static check of `db/mobile.php` (addon key, handler methods, templates, lang;
  WARN on `{{{` in a template, CONTENT_OTHERDATA.k without k in the method's `otherdata`; NOTE when `otherdata`
  is not a lone literal array; js paths resolve after `/<type-dir>/<name>/`, core js via `msrc`).
- `$S/mmatrix [plugin-dir] [--envs 5.2,5.3]` — `mci quick` on every running dev env (never 4.5/vass), one table.
  `--plan` runs nothing: one row per branch from `requires` to `supported` (PHP floor, env, up/down, action).
- `$S/mlog` (sourced) — one log home per plugin: `~/.local/state/moodle-harness/logs/<component>/`,
  pruned to 7 days / 50 logs; mtest, mci, mmatrix and the Stop hook read it.
- `$S/mci-workflow [plugin-dir] [--format gha|bitbucket] [--print]` — moodle-plugin-ci workflow, one job per branch
  from `requires` to `supported`; `--print` to stdout; never overwrites (exit 3).

## 0. Discover environment (do this first)

```bash
PLUGIN="$PWD"                                   # or the plugin dir under test
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
```
- `PLUGIN` — host path of the plugin (the dir whose `version.php` sets `$plugin->component`).
  Works for any Moodle version (code at repo root on 4.x/5.0, under `public/` on 5.1+).
- `mci`/`mtest`/`mexec` find the Moodle root and the running container that mounts it
  (`~/.claude/hooks/moodle-container.sh`, by mounts, not by name). No container: container steps
  SKIP with the reason; tell the user to start their Moodle docker environment (don't guess the
  version); host steps still run.

## 1. Auto mode (default) — the after-coding gate

Verify with `mci auto`; `mci full` before a release (T1399). `change-class` maps the plugin's diff vs HEAD to its
highest class: docs/content (lang, pix) run codechecker, phpcs-delta, lang; ui (templates, CSS) adds mustache; logic
runs quick with `mtest phpunit --changed`; schema (db/, version.php) runs quick with the whole PHPUnit suite, savepoints
and privacy; security (privacy, access, services, `require_capability` in the diff), unknown files or no change-class run
full. A nightly `mci full` covers every component with an mci log that day (`tier-nightly`).
```bash
$S/mci "$PLUGIN"           # auto in git; the first line names the class and the steps
$S/mci quick "$PLUGIN"     # codechecker + phpcs-delta (in git) + mphpcompat + mlang + mapicompat + mcovers + mtest phpunit (--changed on a dirty tree)
```
- Fix all codechecker **errors**. Auto-fix with `$S/mfix "$PLUGIN"` (phpcbf on changed files, then what is left).
- Leave pre-existing **warnings** on legacy code unless asked (per the Moodle guidelines); on scope-only
  work read the phpcs-delta row, not the whole-plugin codechecker output.
- PHPUnit always runs via `mtest` (plugin testsuite, init only when stale); focused run:
  `$S/mtest phpunit <file_test.php> [--filter <method>]`. Behat: `$S/mtest behat`.

## 2. Full mode — mirrors the Bitbucket pipeline

```bash
$S/mci full "$PLUGIN"      # quick + phplint phpmd validate savepoints phpdoc mustache grunt privacy behat
```
Read the table: every red row is a finding to fix (its log tail is printed above the table); every SKIP
names why it could not run here (no container, no java for mustache templates, no matching node).

## 3. Install moodle-plugin-ci (host, one-time, if `$MPC` missing)

```bash
composer create-project moodlehq/moodle-plugin-ci ~/.moodle-plugin-ci '^4' --no-interaction
```
Isolated install (avoids colliding with a globally-required phpcs). Static subcommands need
no DB; they run on host PHP.

## 4. Report

Summarize: phpcs errors fixed vs warnings left, PHPUnit pass/fail counts, and any failing
full-mode step. If anything fails, fix and re-run before declaring the work complete.
