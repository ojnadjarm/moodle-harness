# Moodle harness

Portable Claude Code harness for Moodle development. It (1) auto-loads the Moodle
guidelines + tips into context on any Moodle project (with a one-line banner telling you it
did), (2) provides `/moodle-ci` to run the code checker, PHPUnit and Behat (`mci`, `mtest`,
`mexec`, `mphp`, `mdb`, `mgrunt`, `mversion`, `mfixture`, `phpcs-delta`, `mfix`, `mphpcompat`, `mapicompat`, `mprivacy`,
`mlang`, `msteps`, `mmobile`, `mmatrix`, `mci-workflow`, `madopt`, `mlog`, `mupgrade`, `mrules`, `mcovers`, `msrc`, `mws`), (3) scaffolds plugins (with install.xml `tables:`), upgrade steps, backup/restore, web service
functions, Behat features, manual test data, privacy providers, tasks, hook callbacks, events/observers, table_sql reports, capabilities, admin settings, dynamic forms, MUC caches, message providers, renderable/templatable output classes and Moodle App handlers deterministically with `/moodle-pluginskel`, (4) mirrors the moodledev.io developer docs locally with ranked search
(`/moodle-docs`) — the guidelines mandate a docs research pass before any implementation,
(5) creates a Docker environment for any Moodle 4.1 … 5.3 with `/moodle-install <version>`,
(6) drives a local site in the browser (`/moodle-web`), sets up its AI subsystem
(`/moodle-ai-setup`), audits add-ons for an upgrade (`/moodle-upgrade-audit`) and rehearses a
timed 4.5 -> 5.3 upgrade (`/moodle-upgrade-rehearsal`), (7) applies the `i-have-adhd`
output shape in every session, and (8) ships `/moodle-guidelines` (reload the context),
`/set-moodle-harness` (provision a machine), `/systematic-debugging` and
`/verification-before-completion`.
Environment-agnostic — no hardcoded container names or paths.

## Contents

```
CLAUDE.md                     # global Claude guidelines (think first, simplicity, git, Moodle)
moodle-guidelines.md          # injected into context on Moodle sessions (workflow + rules)
moodle-tips.md                # injected too: known gotchas with their fixes, by area
moodle-coding-style.md        # full Moodle coding style (read before writing PHP)
moodle-quickref.md            # raw command -> harness script table (instead of X, use Y)
moodleapp-instructions.md     # install/run the official mobile app repo (Ionic/Angular)
settings.example.json         # hooks + UI prefs to merge into ~/.claude/settings.json
docker/                       # original single-stack dev compose, kept for reference
hooks/
  moodle-detect.sh            # is this a Moodle project? (shared by the hooks)
  moodle-session-start.sh     # SessionStart: ADHD rules always; guidelines + tips on Moodle projects
  moodle-stop-reminder.sh     # Stop: blocks once when PHP changed and this plugin has no newer mtest/mci log
  moodle-container.sh         # discover the Moodle container + dirroot by mount-matching
skills/
  moodle-ci/                  # /moodle-ci — run the CI suite (quick | full)
    scripts/mci               #   every CI step where it works, one `step rc seconds` table
    scripts/mtest             #   PHPUnit or Behat for one plugin in its container, init only when stale; --changed: tests of the git change
    scripts/mexec             #   a Moodle CLI script as www-data in the container that mounts the cwd
    scripts/mphp              #   a PHP snippet, file or stdin with Moodle bootstrapped (--admin)
    scripts/mdb               #   SQL on the env DB of the cwd (--env <name>: any cwd), {table} prefix, read-only unless --write
    scripts/mws               #   call a web service function as a user (call_external_function, no token); --list
    scripts/mgrunt            #   grunt amd for one plugin with the node its root engines.node asks for
    scripts/mversion          #   bump, resolve a merge conflict in, or check $plugin->version
    scripts/madopt            #   raw vs harness calls in the transcripts (adoption ratio)
    scripts/mfixture          #   install / remove a throwaway fixture plugin cleanly
    scripts/phpcs-delta       #   only the phpcs violations a change adds vs its git base
    scripts/mfix              #   phpcbf on the changed files, then the codechecker errors left
    scripts/mphpcompat        #   PHPCompatibility against the minimum PHP of the plugin's requires
    scripts/mapicompat        #   core APIs and hook classes used that the requires branch does not have
    scripts/mprivacy          #   core privacy compliance tests + metadata/lang checks for one plugin; --static; mprivacy:kept marker
    scripts/mlang             #   missing (FAIL) and unused (WARN) lang strings; --sync <xx> copies missing ids to lang/<xx>
    scripts/mupgrade          #   upgrade.php + purge_caches for one plugin, prints old -> new DB version
    scripts/mrules            #   the owner's guideline rules phpcs misses (ticket ids, suppressions, test names)
    scripts/mcovers           #   coverage style vs requires (@covers below 5.0, #[CoversClass] from 5.0); --fix converts
    scripts/msrc              #   read-only core code root per branch (matching env or shallow clone cache; --fetch)
    scripts/msteps            #   Behat step lookup per env (cached); --check lists undefined steps
    scripts/mmobile           #   static check of a plugin's db/mobile.php (Moodle App support)
    scripts/mmatrix           #   mci quick on every running dev env, one table; --plan runs nothing
    scripts/mci-workflow      #   moodle-plugin-ci workflow (GitHub or Bitbucket) from version.php
    scripts/mlog              #   sourced: one pruned log home per plugin component
    reference/behat.md        #   Behat feature-writing reference
    tests/cli-contract.test.sh  #   every script --help rc 0 and --bogus usage rc within 5 s; every pluginskel *.py --help
  moodle-pluginskel/          # /moodle-pluginskel — plugin skeleton from a YAML recipe
    upgrade.py                #   install.xml change (vs git or --base-file) -> db/upgrade.php step + savepoint + version bump
    testdata.py               #   manual-test setup.php, reset.php, testing-instructions.md
    backup.py                 #   backup/moodle2 (4 files) of a mod_, or local_ course-level backup/restore plugin + test, from install.xml
    external.py               #   web service function: class, db/services.php, test, version bump; --table T --cols: the user's rows; --mobile
    behat.py                  #   Behat feature (+ mod_ data generator) from real core steps; behat_<component> page resolver
    privacy.py                #   real privacy provider + tests/privacy/provider_test.php from install.xml
    task.py                   #   scheduled or adhoc task: class, db/tasks.php, lang, test; --purge T.col: retention
    hook.py                   #   hook callback from a hook class or legacy callback name (--core: msrc tree of requires; --force)
    event.py                  #   event class + sink test; --observe adds db/events.php, observer method and its test; --emit-in page.php
    table.py                  #   table_sql (optionally dynamic) report class, page, lang strings, test; --context course --page --param
    access.py                 #   capability: db/access.php entry, lang string, version bump
    settings.py               #   admin settings (configint too) + admin_externalpage links, lang strings; block_ has_config()
    form.py                   #   core_form dynamic_form, AMD ModalForm opener, lang strings, test
    mobile.py                 #   Moodle App handler: db/mobile.php, output class, templates/mobileapp page (rows via otherdata), test, lang
    cache.py                  #   MUC definition: db/caches.php, cachedef_ string, typed accessor, test, version bump
    message.py                #   message provider: db/messages.php, string, notifier send method, sink test, version bump
    output.py                 #   renderable + templatable class, mustache with Example context, test; --renderer
    vphp.py                   #   shared version.php reader/bumper (decimal versions, both quotes, comments)
  moodle-docs/                # /moodle-docs — local moodledev.io mirror + BM25 search
  moodle-guidelines/          # /moodle-guidelines — reload guidelines + tips + style on demand
  moodle-install/             # /moodle-install <ver> — Docker env per Moodle version (4.1 … 5.3), shared mailhog+selenium
  moodle-web/                 # /moodle-web — log in and check a plugin in the real UI (Playwright MCP)
  moodle-ai-setup/            # /moodle-ai-setup — AI provider, placements, limits and policy (4.5+)
  moodle-upgrade-audit/       # /moodle-upgrade-audit — keep / replace / remove table for each add-on
  moodle-upgrade-rehearsal/   # /moodle-upgrade-rehearsal — timed 4.5 -> 5.3 upgrade + rollback on a throwaway site
  set-moodle-harness/         # /set-moodle-harness — provision a machine (wire-hooks.py wires the hooks)
  i-have-adhd/                # /i-have-adhd — output shape, injected by the SessionStart hook
  systematic-debugging/       # root cause before fixes (obra/superpowers, MIT)
  verification-before-completion/ # evidence before "done" (obra/superpowers, MIT)
install.sh                    # copy the above into ~/.claude (backs up differing docs)
sync.sh                       # update this repo copy from the live ~/.claude harness
tests/run.sh [-j N]           # every harness test, N files at a time (default 4; "# harness: serial" runs alone), one line each in file order (rc, seconds), slowest 5 and total last; live Docker parts only with MOODLE_HARNESS_LIVE=1 (-j 1)
tests/no-machine-values.test.sh   # fails if this machine's hosts, IPs, paths or dev passwords reach the repo (values from ~/.config/pc-harness)
```

## Install on a new machine

```bash
git clone <this repo> ~/moodle-harness
~/moodle-harness/install.sh   # places files into ~/.claude
```
Then open Claude Code and run **`/set-moodle-harness`** — it installs `moodle-plugin-ci` on
the host, wires the SessionStart + Stop hooks into `~/.claude/settings.json` with
`skills/set-moodle-harness/wire-hooks.py` (idempotent; it skips SessionStart when a fleet
`session-start.sh` wrapper already injects the context), mirrors the developer docs, and
verifies the setup. The hooks take effect in a **new session**. `settings.example.json` holds
the same hook template plus the other preferences (output style, compaction) if you want the
same UI defaults. Check the install with `tests/run.sh` (exit 0 = green).

Project memories (`~/.claude/projects/*/memory/`) are machine-local and not part of this
repo; anything reusable from them has been folded into the guideline/tips files.

## How it works

- **`mci` places each step**: codechecker, phplint, phpcompat, savepoints (and phpmd, mustache,
  grunt with `-m <root>`) on the host, where they survive container rebuilds; validate, phpdoc,
  PHPUnit, Behat and privacy tests inside the discovered Moodle container (config, dataroot, DB).
- Dirroot is found via `vendor/bin/phpunit`, so it's correct on 4.x/5.0 (code at repo root)
  and 5.1+ (code under `public/`).
- Scope PHPUnit to `<component>_testsuite` to avoid sibling-plugin class collisions.
- **Environments** (`/moodle-install <ver>`): one compose project per version under
  `~/moodle-envs/<ver>` (app + db, site `http://moodle<MM>.localhost`, direct web port
  `80MM`, db `54MM`/`33MM`), plus one shared project `~/moodle-envs/shared` holding the nginx
  proxy (port 80, routes `moodle<MM>.localhost` to the app alias), mailhog (1025/8025) and
  selenium (4444) on the `moodle-shared` network every app joins. PHP/DB per version come
  from the release notes.
- **Session banner**: the SessionStart hook prints `Harness: ADHD mode on · Moodle
  guidelines loaded (<root>)` (or just `ADHD mode on` outside Moodle). `/moodle-guidelines`
  reloads the same context on demand.

## Keeping it in sync

Edit the live files under `~/.claude`, then `./sync.sh`, review `git diff`, commit. Always edit the
live copy, never the repo copy directly: `sync.sh` overwrites the repo from `~/.claude`, and
`install.sh` overwrites `~/.claude` from the repo, so an edit in the wrong place is lost on the next
run.
