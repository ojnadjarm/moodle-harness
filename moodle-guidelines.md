# Moodle Development Guidelines

## Every task follows this workflow

1. **Research the docs first** so the code follows the official API; read the top pages of
   `python3 ~/.claude/skills/moodle-docs/search.py "<2-4 short specific terms>"`.
2. **Read the coding style** before writing or reviewing PHP: `~/.claude/moodle-coding-style.md`.
3. **End check**: `/moodle-ci` `mci auto` (the checks the change class needs; the Stop hook asks for a
   run after a PHP change); `mci full` before a release.
4. **Ship a manual-test fixture script and `testing-instructions.md`** ("Manual test data") so the
   feature can be tried by hand in the browser.

## Harness scripts

`S=~/.claude/skills/moodle-ci/scripts` (not on PATH; each has `--help`). Raw command ->
harness table: `~/.claude/moodle-quickref.md`.

- `$S/mci` runs each `/moodle-ci` step on the host or in the discovered container;
  `$S/mphpcompat`, `$S/mapicompat` (PHP/API compatibility). `$S/mdb "<sql>"` (env DB,
  `{table}` prefix, read-only unless `--write`; `--env <name>` from any cwd), `$S/mphp '<code>'` (PHP with Moodle bootstrapped),
  `$S/mws <function> key=value` (call a web service function as a user, no token; `--list`),
  `$S/mversion bump|resolve|check`, `$S/mgrunt` (AMD build), `$S/madopt` (raw vs harness calls),
  `$S/mupgrade` (upgrade.php + purge caches, old -> new version), `$S/mrules` (guideline rules phpcs
  misses), `$S/mfixture` (throwaway fixture plugin; `status <env>` before using a shared env),
  `$S/msrc <X.Y|requires> [--fetch]` (read-only core code tree of a branch, e.g. 4.5 for an LTS target),
  `$S/mcovers [--check|--fix]` (coverage style vs `$plugin->requires`).

## Developer docs

- `/moodle-docs` is the local moodledev.io mirror for any Moodle developer question (a WebFetch hook
  sends moodledev.io fetches there). A moodledev.io URL maps to a file under `~/.moodle-devdocs`
  (mapping in the skill).

## Coding style

- Never put ticket numbers (e.g. `DEF-1234`) or client/incident names in code, comments, test names
  or docblocks: the code says what it does, git history carries why (`$S/mrules` flags ticket ids).
- Leave `version.php` alone for refactors or pure class additions (no `db/` change): no upgrade runs.
- Events: `get_name()` uses `get_string()`; `get_description()` is hardcoded English (core convention).
- Confirmation dialogs: core modals (`core/notification` `saveCancel`/`deleteCancel`, `ModalForm`),
  a title and one question sentence, no extra paragraphs, custom bodies or `$OUTPUT->confirm` pages;
  a neutral palette in own markup (no `badge-*`, `btn-danger`, `alert-*`).
- A subplugin on an unmerged parent branch keeps the direct call and strict `$plugin->dependencies`
  pin, no `method_exists()` shims; its pipeline stays red until the parent PR merges (intended order).
- The local checkout may be newer than the deployment target (e.g. 5.1 locally, 4.5 in production):
  set `$plugin->requires` to the target and write code that runs on both.

## Moodle 5.1+ layout

- Plugin code lives under `public/`; composer `vendor/`, `phpunit.xml` and the grunt tooling
  (`Gruntfile.js`, `node_modules`) sit one level above at the repo root.
- Rebuild AMD with `$S/mgrunt` from the plugin dir (root Gruntfile, the nvm node matching the root
  `engines.node`, this plugin only); ship both `amd/src` and `amd/build`.

## Docker environments

- Before a command that needs a running env (unit tests, CLI scripts), run `docker ps`; if the
  relevant env is down, report which one rather than guess a version.
- `/moodle-install` envs: `~/moodle-envs/<ver>` (compose project `moodle<MM>`, port `80MM`, site
  address: the Moodle memory card); proxy, mailhog and selenium run once in `~/moodle-envs/shared`.

## Code checker (PHP CodeSniffer)

- `/moodle-ci` runs it. Auto-fix with `$S/mfix` (phpcbf on changed files, then the errors left;
  `--all` whole plugin); check `~/.moodle-plugin-ci/bin/moodle-plugin-ci codechecker <dir>`.
- Fix every error; on projects that already carry many warnings, leave those unless the user asks.
- Fix the code rather than add `phpcs:ignore` / `phpcs:disable` or other suppressions, unless the
  user asks; a warning left is reported (`$S/mrules` flags suppressions).

## Unit tests

- Via `/moodle-ci`: `$S/mtest phpunit <file>` (one file; `--changed [base]` only the tests
  covering the git change), `$S/phpcs-delta` (new violations only), `$S/mfixture` (throwaway fixture
  plugins), `$S/mprivacy` (privacy compliance), `$S/mlang` (missing/unused lang strings), `$S/mmatrix`
  (every running env; `--plan` lists branches to test, runs nothing).
- Behat: write features from `skills/moodle-ci/reference/behat.md`; take step text from
  `$S/msteps <words>` and run `$S/msteps --check <file.feature>` first, since an invented step fails.
- No reflection on private state: a class with a static cache a test must clear gets a public
  `reset_caches()` (`$S/mrules` flags reflection).
- Include at least one end-to-end test of the full flow (e.g. create user, course, activity,
  configure completion, trigger the plugin, assert the output).
- Name the test class after its file (`contacts_job_test` in `contacts_job_test.php`); `$S/mrules`
  flags a mismatch.
- Behaviour that only exists in some Moodle distributions: detect the extra component at runtime and
  `markTestSkipped()` when it is absent, so the test also passes on base Moodle.
- Other plugins' observer `mtrace()` output fails strict output mode and `ob_start()` does not
  swallow it: whitelist it with `$this->expectOutputRegex()`.
- Deprecations and failures from sibling/third-party plugins are noise: one line in the report.
- Changed existing tests: the `mci` step `testchanges` stays red until `MCI_TEST_NOTE` names a Test
  changes note; the lead reads that list (`guide test-changes`).

## Manual test data

The user still clicks through every feature, and building site data is the slowest part: a
user-facing change also ships a CLI script that populates a real site, plus any input files (CSVs).

- An **untracked** project dir (e.g. `.research/testdata/`) keeps it out of the plugin; Moodle style,
  phpcs run on it.
- **Idempotent**: guard every step with an existence check so a re-run repairs or extends the
  fixture. Never fix a fixture by deleting the user's data and rebuilding.
- **Production APIs** (`create_course`, `create_module`, `user_create_user`, plugin `api::`), not the
  PHPUnit/Behat generators, which assume a resettable test DB; a generator shows the calls and fields.
- **Mirror configuration already on the site**: query a comparable record and match its shape.
- **Satisfy the feature's visibility gates**, not just its data: check the `*_extend_navigation_*`
  callbacks and capability/config conditions that decide whether the entry point renders.
- **Populate precomputed tables** the feature reads (report caches, queue tables) so results show
  without cron.
- End the script by printing the created IDs and the **URLs** to open.
- Ship a **`reset.php`** when the feature mutates data, so the scenario re-runs from a known state.

### `testing-instructions.md` (required)

Every fixture ships one, **short**, for a developer walking the scenario by hand (no QA plan or tutorial).

- One line on what is tested, then **numbered steps in order** from an empty site (course,
  completion, activities, enrolments, program, certification, then the feature).
- **A URL per step** (`/course/completion.php?id=<courseid>`), its path and params verified in the
  code; the URL replaces click-by-click narration.
- Sample input inline, expected results as a short list or table; no time estimates, checklists
  or bug-report templates.
- Flag the few things that mislead (a non-obvious row, a timezone/date-dependent result,
  pre-existing platform behaviour), one line each.
- Setup/reset scripts go at the end as a shortcut, not step 1: the manual path is the document.

## Tips file

- Check `~/.claude/moodle-tips.md` before deep-debugging: known gotchas with their fixes.
- A solved non-obvious problem that would save a future session time goes there: symptom in bold,
  why (file/class), the fix; not what the docs or code make obvious.

## Moodle App (mobile)

- The official app (moodleapp, Ionic/Angular): `~/.claude/moodleapp-instructions.md`; the PHP rules
  above (code checker, PHPUnit, containers) do not apply there.
- Plugin side (`db/mobile.php`, `classes/output/mobile.php`): its "Plugin side" section; check with
  `$S/mmobile`.

## Working style

- The user trusts the work and expects a steady, persistent register, not a frustrated or self-critical one.
- Hard problems take many iterations; approach attempt #8 with attempt #1's composure.
- Don't force a premature "fix" or abandon a sound approach because it takes a while.
- Reason from the code: read the source rather than repeat ad-hoc docker/DB probes.
- Prefer the core API or AMD module (`core_table/dynamic`, `dynamic_form`, modals) in new code; a fix
  to hand-written code that duplicates core stays local unless it is complicated and core already
  does it. Working code is not refactored to core just because an equivalent exists.
