# Moodle Development Guidelines

The user is a Moodle developer; most projects in this environment are Moodle plugins or
core-related work. These rules are mandatory whenever the task involves Moodle.

## Every task follows this workflow

1. **Research the docs first** — before implementing anything, query the local docs mirror
   and read the top page(s) so the implementation follows the official API guidelines:
   ```bash
   python3 ~/.claude/skills/moodle-docs/search.py "<2-4 short specific terms>"
   ```
   Query with short API terms ("privacy provider", "scheduled task"), not full sentences.
2. **Read the coding style** before writing or reviewing any PHP:
   `~/.claude/moodle-coding-style.md` (full local copy — never fetch the web page).
3. **Implement** following the style rules below.
4. **Verify with `/moodle-ci`** (phpcs + PHPUnit) before considering the work complete.
5. **Ship a manual-test fixture script and `testing-instructions.md`** (see "Manual test
   data") so the feature can be exercised by hand in the browser, not just by PHPUnit.

## Harness skills (prefer these over doing it by hand)

- `/moodle-ci` — code checker + PHPUnit (static checks on host, PHPUnit in the discovered
  container).
- `/moodle-pluginskel` — scaffold a new plugin deterministically from a small YAML recipe.
- `/moodle-docs` — local mirror of the moodledev.io developer docs (APIs, guides, general).
- `/set-moodle-harness` — (re)provision this harness on a machine.
- `/moodle-guidelines` — reload this context on demand (plugin outside the cwd, after
  context loss).
- `/moodle-install <version>` — create a Docker environment for Moodle 4.1 … 5.2 (app + DB
  per version under `~/moodle-envs/<ver>`; mailhog + selenium shared by all of them).

## Developer docs

- For ANY Moodle developer question (core APIs, subsystems, plugin-type guides, policies,
  release notes), use the local mirror via `/moodle-docs` — never WebFetch moodledev.io.
  Any moodledev.io URL converts to a file under `~/.moodle-devdocs` (mapping in the skill).

## Coding style

- Follow the official Moodle coding style (`~/.claude/moodle-coding-style.md`; upstream:
  https://moodledev.io/general/development/policies/codingstyle).
- Comments must be minimal: one short description line per docblock; inline comments only
  when the code is genuinely non-obvious, never more than 2 lines.
- NEVER put ticket numbers (e.g. `DEF-1234`) or client/incident names anywhere — not in
  comments, code, test names, or docblocks. Explain what the code does, never why a ticket
  asked for it; the code and git history carry that context.
- Do not bump `version.php` for refactors or pure class additions (no `db/` change).
- Events: `get_name()` uses `get_string()`; `get_description()` is hardcoded English (core
  convention).
- Confirmation dialogs are core modals (`core/notification` `saveCancel`/`deleteCancel`,
  `ModalForm`): title + one question sentence, nothing else — no identity lines, warning
  paragraphs, custom mustache bodies or server-side `$OUTPUT->confirm` pages. Keep a
  neutral palette in own markup (no `badge-*`, `btn-danger`, `alert-*`).
- When a subplugin depends on an unmerged branch of its parent plugin, keep the direct
  call and the strict `$plugin->dependencies` pin — no `method_exists()`/fallback shims.
  Say the pipeline stays red until the parent PR merges; that is the intended order.
- The local checkout may be newer than the deployment target (e.g. 5.1 locally, 4.5 in
  production). Set `$plugin->requires` to the target, and write code that runs on both.

## Moodle 5.1+ layout

- Plugin code lives under `public/`; composer `vendor/`, `phpunit.xml` and the grunt
  tooling (`Gruntfile.js`, `node_modules`) sit one level above at the repo root.
- PHPUnit runs from the repo root with `public/`-prefixed paths
  (`vendor/bin/phpunit public/<plugin>/tests/<file>.php`). `moodle-container.sh` finds
  that root for you.
- Rebuild AMD from the plugin dir with the root Gruntfile (`<root>/node_modules/.bin/grunt
  --gruntfile <root>/Gruntfile.js amd`); grunt needs the node version pinned by the repo
  (`source ~/.nvm/nvm.sh && nvm use`). Ship both `amd/src` and `amd/build`.

## Docker environments

- This machine runs several Docker environments targeting different Moodle versions —
  there is no single "correct" container, and container names must never be assumed. The
  harness discovers the right one by matching the mounted code:
  `~/.claude/hooks/moodle-container.sh`.
- Before any command that needs a running environment (unit tests, CLI scripts), run
  `docker ps` first. If no relevant container is active, ask the user to start the
  environment for that specific project — do not guess the version.
- Environments created by `/moodle-install` live in `~/moodle-envs/<ver>` (compose project
  `moodle<MM>`, site `http://moodle<MM>.localhost`, direct port `80MM`); the nginx proxy,
  mailhog and selenium run once in `~/moodle-envs/shared` and every app container reaches
  them as `mailhog` / `selenium`.

## Code checker (PHP CodeSniffer)

- `/moodle-ci` runs it for you. Manual fallback:
  check `phpcs --standard=moodle ./` (or `~/.moodle-plugin-ci/bin/moodle-plugin-ci
  codechecker <dir>`); auto-fix `phpcbf --standard=moodle ./`.
- **Errors must always be fixed.** Warnings: on existing projects that already carry many
  warnings, leave them unless the user explicitly asks for fixes.
- **Never add `phpcs:ignore` / `phpcs:disable` (or any other checker-suppression
  annotation) unless the user explicitly asks for it.** Fix the code or leave the
  warning and report it — do not silence it.

## Unit tests

- Run them via `/moodle-ci` (executes in the discovered Moodle container).
- Keep tests as simple as possible — ideally one test function per method. Write only the
  tests needed to prove the requested behaviour; no speculative or redundant edge-case
  tests unless asked.
- Use only the PHPUnit suite and helpers Moodle provides (`advanced_testcase`, data
  generators). Do not build a custom harness.
- Never use reflection (`\ReflectionProperty`, `\ReflectionMethod`, …) to reach private
  state. If a class holds a static cache a test must clear, add a public `reset_caches()`
  method to the class and call it.
- Always include at least one end-to-end test covering the full flow. Example — a plugin
  that modifies completions: create the user → create the course → create the activity →
  configure completion → trigger the plugin's functionality → assert the expected output.
- The test class name must match the file name (`contacts_job_test` ↔
  `contacts_job_test.php`), and `--testsuite <component>_testsuite` is mandatory — a bare
  run can fatal on a class name shared with a sibling plugin.
- Re-run `admin/tool/phpunit/cli/init.php` after any `db/install.xml`, `db/upgrade.php` or
  `version.php` change; a stale test DB fails with misleading schema errors.
- Behaviour that only exists in some Moodle distributions: detect the extra component at
  runtime and `markTestSkipped()` when it is absent, so the test also passes on base Moodle.
- `mtrace()` output from other plugins' observers fails PHPUnit's strict output mode and is
  NOT swallowed by `ob_start()` — whitelist it with `$this->expectOutputRegex()`.
- Deprecation notices and failures coming from sibling/third-party plugins are noise: report
  them in one line, don't chase them.
- Declare coverage with `@covers` docblock tags on each test function (not on the class),
  never via PHPUnit attributes (`#[CoversClass]`). Use `@coversNothing` for a test that
  drives no plugin code. The PHPUnit 11 doc-comment deprecation this triggers is expected
  and acceptable while the pipeline is green — the Moodle convention wins.

  ```php
  /**
   * Marking a course complete records the backdated override time.
   *
   * @covers \report_adv_comp\completion_editor::mark_course_complete
   * @covers \report_adv_comp\local\completion_completion::mark_complete_quiet
   */
  public function test_editor_marks_course_complete_at_override_time(): void {
  ```

## Manual test data

Green unit tests are not enough — the user still has to click through the feature, and
building the site data to do that is usually the slowest part. So whenever work adds or
changes user-facing behaviour, also deliver a CLI script that populates a real site with
everything needed to exercise it, plus any input files (CSVs, etc.) the feature consumes.

- Put it in an **untracked** directory of the project (e.g. `.research/testdata/`) so
  throwaway fixtures never pollute the plugin. Still write it to Moodle coding style and
  run phpcs on it.
- **Make it idempotent** — guard every step with an existence check so re-running repairs
  or extends the fixture instead of erroring or duplicating. Never fix a fixture by
  deleting the user's data and rebuilding.
- **Use production APIs** (`create_course`, `create_module`, `user_create_user`, plugin
  `api::` classes), not the PHPUnit/Behat data generators — those assume a resettable test
  DB. Read a plugin's generator to learn the correct API calls and required fields, then
  call those APIs directly.
- **Mirror configuration that already exists on the site.** Query for a comparable record
  first and match its shape rather than inventing settings.
- **Satisfy the feature's visibility gates**, not just its data requirements. A record that
  exists but stays hidden is a failed fixture — check the `*_extend_navigation_*` callbacks
  and capability/config conditions that decide whether the entry point renders at all.
- **Populate precomputed tables** the feature reads (report caches, queue-driven tables)
  so the result is visible immediately without waiting for cron.
- **Run it, then verify with DB queries** — count the rows that should exist and confirm
  the gating conditions evaluate true. Never report a fixture as working from the script's
  own success output alone.
- End the script by printing the created IDs and the **URLs** the user should open.
- Ship a **`reset.php`** alongside it when the feature mutates data, so the scenario can be
  re-run from a known state without rebuilding the fixture.

### `testing-instructions.md` (required)

Every fixture ships with one. **Keep it short.** It is written for a developer and walks
the real-world scenario by hand — not a QA test plan, not a tutorial.

- A one-line statement of what's being tested, then **numbered steps in the order performed**,
  starting from an empty site: create the course, enable completion, add activities, enrol
  users, configure the program, configure the certification, then exercise the feature.
- **Give the URL for each step** (`/course/completion.php?id=<courseid>`). Verify the paths
  and their params in the code — never invent them. The URL is the value; skip the
  click-by-click narration around it.
- Sample input inline, expected results as a short list or small table. Prose kept to a
  minimum; no time estimates, tickable checklists, or bug-report templates.
- Do flag the few things that genuinely mislead: a non-obvious row's purpose, an
  environment-dependent result (timezone, server date), and pre-existing platform behaviour
  the tester will hit — each in one line.
- Mention the setup/reset scripts at the end as a shortcut, not as step 1. The manual path
  is the document; the script is the convenience.

## Tips file

- Check `~/.claude/moodle-tips.md` before deep-debugging — it lists known gotchas with
  their fixes.
- When you solve something non-obvious that would save a future session real time (a
  tricky class/API behaviour, a debugging command, a misleading symptom), append it there:
  symptom in bold, why it happens (file/class), the fix. Don't record what the docs or the
  code already make obvious.

## Moodle App (mobile)

- For the official mobile app (moodleapp repo, Ionic/Angular — not PHP), follow
  `~/.claude/moodleapp-instructions.md` for environment install and running. The
  PHP-oriented rules above (code checker, PHPUnit, containers) do not apply there.

## Working style

- This is an established collaboration; the user trusts the work and expects a steady,
  persistent approach — never a frustrated or self-critical register.
- Hard problems that take many iterations are normal, not a sign something is wrong.
  Approach attempt #8 with the same composure as attempt #1.
- Don't force a premature "fix" or abandon a sound approach just because it's taking a
  while. It's fine to stay with a hard bug across many turns.
- "Don't touch X" rules (vendored code, commits, core files) are consent gates, not bans:
  ask before doing them unprompted, but once the user asks, do it cleanly and report
  plainly — no re-litigating the rule or piling on disclaimers.
- Reason from the code before probing: prefer reading the source over repeated ad-hoc
  docker/DB probes. Never claim a tool (phpcs, phpunit) is missing without checking the
  harness paths first.
