# Moodle Tips & Gotchas

Hard-won fixes for recurring Moodle problems. Check here before deep-debugging a
symptom that matches one of these.

## Completion

- **A course report link never appears in course navigation, with no error** — many
  completion reports gate their `*_extend_navigation_course` node on BOTH
  `$completion->is_enabled()` AND `$completion->has_criteria()` (e.g.
  `report/adv_comp/lib.php`). A freshly built course with `enablecompletion = 1` but
  no activities still has zero rows in `course_completion_criteria`, so `has_criteria()`
  returns false and the node is silently skipped — it looks like a capability or config
  problem but is neither. Fix: add an activity with completion tracking and register it
  as a criterion:

  ```php
  require_once($CFG->dirroot . '/completion/criteria/completion_criteria_activity.php');
  $data = (object) ['id' => $courseid, 'criteria_activity' => [$cmid => 1]];
  (new completion_criteria_activity())->update_config($data);
  ```

  Writing `course_completions` rows directly does NOT create criteria — the two are
  independent, so completion overrides can exist on a course whose report stays hidden.

- **`create_module()` emits "Undefined property: stdClass::$cmidnumber"** — `course/modlib.php`
  reads `$moduleinfo->cmidnumber` unconditionally. Always pass `'cmidnumber' => ''`.

## DML / core APIs

- **`get_records_sql()` silently drops rows** — results are keyed by the first selected
  column, so a non-unique first column collapses rows. Use `get_recordset_sql()` (and
  `close()` it) or select a unique id first.
- **`quiz_slots.questionid` no longer exists (4.x question bank)** — join
  `question_references` (component `mod_quiz`, questionarea `slot`, itemid = slot id) →
  `question_bank_entries` → `question_versions` to reach the question id.
- **`grade_item::get_name(true)` mutates the object** — for a category item it assigns the
  *bare* category name to `$this->itemname` before returning "<Category> total". Anything
  reading `itemname` afterwards (e.g. `gradereport_user` `fill_table()`) sees the bare name;
  re-fetch the item (`grade_item::fetch()` has no instance cache) before calling it again.
- **SSO / external login without core patches** — `complete_user_login()` has no
  `logintoken`/password check (core uses it from `admin/tool/mobile/autologin.php` and
  `auth/lti/login.php`); only `authenticate_user_login()` validates the login CSRF token.
  A signed, single-use token verified in an `auth_*` plugin's login page then
  `complete_user_login()` + redirect is the clean pattern. Never set
  `$CFG->disablelogintoken` / `alternateloginurl` for this (site-wide CSRF regression).

## Distribution-specific plugins

- **Some behaviour only exists in a Moodle distribution that ships extra components** —
  detect the component at runtime (a class/function existence check, or the distribution's
  own environment helper) and gate those tests with `markTestSkipped()` so the base-Moodle
  CI matrix stays green.
- **A custom-field handler singleton survives PHPUnit's reset** — e.g. a plugin's
  `customfield\..._handler`: a second test saving custom-field data hits a duplicate-key
  `debugging()` notice. Call the handler's `reset_caches()` in `setUp()`.
- **Observer `mtrace()` noise from other installed plugins (e.g. on
  `user_enrolment_created`) fails tests under strict output mode** — `ob_start()` does not
  swallow it; use `$this->expectOutputRegex('/.../')`.

## Forms

- **Checkbox won't save in a modal/AJAX/fragment form** — a plain `checkbox`
  element only submits a value when checked and has no hidden companion field,
  so form serialization silently drops it; the state fails to round-trip and
  reads back as disabled even when enabled by default. Fix: use `advcheckbox`
  with explicit values so a hidden input always submits `0` or `1`:

  ```php
  $mform->addElement('advcheckbox', 'name', get_string('name', 'comp'), '', null, [0, 1]);
  $mform->setDefault('name', 1);
  ```

  Don't add `setType(..., PARAM_BOOL)` on it — advcheckbox handles its own typing.

## Moodle App (moodleapp)

- **Embedded file links break in the app when the filename contains `#` or `?`** —
  the app restores relative hrefs in module content to absolute pluginfile URLs by
  filename lookup in `CoreDom.restoreSourcesInHtml` (`src/core/static/dom.ts`). It
  URL-decodes the href *before* stripping query/fragment (`CoreUrl.removeUrlParts`
  does a naive `split('#')[0]`), so `%23`/`%3F` truncates the lookup key, the match
  fails, and tapping resolves the leftover relative path against the site root with
  `?lang=<applang>` appended by `CoreOpener` (`src/core/static/opener.ts`). Fix:
  rename the file, or hard-code the absolute `pluginfile.php` URL in the HTML —
  unmatched absolute URLs pass through untouched and `CoreLinkDirective` opens site
  pluginfile URLs with the user's token.
- **mod_page renders from the exported module package, not the web HTML** — the app
  downloads `index.html` (content with `@@PLUGINFILE@@/` stripped → relative hrefs)
  plus the files list from `core_course_get_contents`, then re-links them in
  `AddonModPageHelper.getPageHtml` (`src/addons/mod/page/services/page-helper.ts`).
- **`CoreUrl` (`src/core/static/url.ts`) is the app's URL toolbox** — `toAbsoluteURL`,
  `removeUrlParts`, `extractUrlParams`, pluginfile helpers. Check it (and `CoreDom`,
  `CoreText`) before hand-writing any URL/HTML string manipulation.

## Helpful commands

- Moodle App shells need the repo's Node first: `source ~/.nvm/nvm.sh && nvm use`
  (engines pin Node 24; the system Node silently differs). Serve headless with
  `npx ionic serve --no-open` — `npm start` assumes a local browser and SSL.
- Trace how the app transforms a URL/HTML string:
  `grep -rn "removeUrlParts\|toAbsoluteURL\|restoreSourcesInHtml" src/core --include=*.ts`
- Run a single app test file: `npx jest <path/to/file.test.ts>` (run
  `NODE_ENV=testing npx gulp` first if lang/env assets are stale).

## Docker

- **`git clone`/`ls-remote` from github.com fails with "could not read Username" although
  `curl` gets 200** — git 2.43 over HTTP/2 gets a 401 on its second request (the
  upload-pack POST); intermittent. Fix per command: `git -c http.version=HTTP/1.1 clone …`
  (`/moodle-install` already does this).
- **Run a legacy single-stack env behind the shared proxy** — a standalone stack that binds
  host port 80 (and its own mailhog/selenium) can't run beside `~/moodle-envs/shared`. Add a
  `docker-compose.override.yml` next to its compose that clears the clashing ports and joins
  its app to the shared network with an alias (`ports: !reset []`; `networks: {default:,
  moodle-shared: {aliases: [<alias>]}}`; `networks: {moodle-shared: {external: true}}`), then
  add a `server_name <host>` block to `~/moodle-envs/shared/nginx.conf` proxying to that alias
  and `nginx -s reload`. Keeps the original wwwroot working with no change to the base compose.
  (Done for a legacy `~/moodle-5.1` stack → `moodle-dev.localhost`.)
- **Container shows "Up" but Moodle 500s with "Database connection failed"** — after a
  WSL2/Docker Desktop restart, a `restart: always` app container can start before its
  compose network exists and comes up with NO networks attached (`docker inspect <app>
  --format '{{json .NetworkSettings.Networks}}'` returns `{}`), so DNS for the `db`
  service fails; host port bindings also come up corrupted. Neither `docker restart` nor
  a plain `docker compose up -d` fixes it (config unchanged → no recreate). Fix:
  `docker compose up -d --force-recreate app` from the compose directory. Permanent
  prevention: remove `restart: always` from the app service and start the stack
  manually with `docker compose up -d` after each boot.

- **Compose force-recreate fails with "pull access denied" after the network-loss bug** —
  if `docker-compose.yml` drifted since the containers were created (e.g. a service now
  names an image that doesn't exist), `docker compose up -d --force-recreate` can't run.
  Instead reattach the existing containers to the compose network with the service DNS
  aliases: `docker network connect --alias db <project>_default <project>-db-1` (and the
  app container likewise), then verify with `docker exec <app> getent hosts db`.

- **Site dead (curl exit 000) while the app container is Up, Apache healthy** — `docker
  port <app>` prints nothing: the container was created while another stack held the same
  host port (two Moodle stacks both binding 80 and 3306 can't run together). Stop the other
  stack, then `docker compose up -d --force-recreate app`; verify with `docker port <app>`.
  To run both stacks at once, start the second one with a compose override that drops the
  host ports (`ports: !reset []` on `app` and `db`) and reach it via `docker exec`.
- **Containers are often stopped after a reboot** — `docker start <db> <app>` (and give the
  DB ~8s) before running PHPUnit or CLI scripts; never assume a version, list with
  `docker ps -a`.

## Upgrade / plugin testing

- **`admin/cli/upgrade.php` says "No upgrade needed" after rolling a plugin's version
  back in `config_plugins` (to re-test a migration)** — `moodle_needs_upgrading()` only
  compares `$CFG->allversionshash` against a hash of the on-disk `version.php` files;
  DB-recorded plugin versions are not part of the check, so a DB rollback changes
  nothing. Fix: `php admin/cli/cfg.php --name=allversionshash --unset`, then run
  `admin/cli/upgrade.php` — the upgrade process itself does per-plugin DB-vs-disk
  comparison and runs the pending upgrade steps. (On Moodle 5.1+ the CLI scripts live at
  the repo root `admin/cli/`, not under `public/`.)
- **PHPUnit fails with schema/version errors right after a `version.php` or
  `db/install.xml` change** — the test DB is stale; re-run
  `admin/tool/phpunit/cli/init.php` in the container (path is under `public/` on 5.1+).
- **A whole-site PHPUnit run fatals on "Cannot declare class …_test"** — two plugins ship
  a test class with the same name (e.g. `event_processor_test` in `tool_example` and
  `tool_trigger`). Always scope with `--testsuite <component>_testsuite`.
- **A fragment loaded with `core/fragment` empties the target node instead of filling it** —
  `Fragment.loadFragment()` resolves a jQuery Deferred with TWO arguments (`html`, processed
  `js`), so `const r = await Fragment.loadFragment(...)` gives the html string and `r.html` is
  `undefined`; `Templates.replaceNodeContents(node, undefined, undefined)` then empties the node
  silently. Consume it as
  `await Fragment.loadFragment(...).then((html, js) => Templates.replaceNodeContents(node, html, js))`.
- **`output_fragment_*` callbacks must not render through `$OUTPUT`** — in the web-service flow
  `$OUTPUT` is a real renderer only because `core_external::get_fragment()` calls
  `$OUTPUT->header()` first; under PHPUnit it is still `core\output\bootstrap_renderer`, so a
  `renderer_base` type hint fatals. Use `$PAGE->get_renderer('core')` inside the callback.
