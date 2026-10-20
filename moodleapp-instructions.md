# Moodle App — Environment Setup, Run, and Plugin Side

How to run the official Moodle mobile app (moodlehq/moodleapp) on this machine
(Ubuntu, native) and add app support to a Moodle plugin. Verified 2026-10-20
against upstream `main` 5.3.0 (curl 14:10: engines `>=v24.16 <25`,
`.nvmrc` `lts/krypton` = Node 24); no local clone exists yet (`~/moodleapp`). Upstream ships no agent file; repo
overview: its `README.md`; dev guide: https://moodledev.io/general/app/development/setup
and https://moodledev.io/general/app/development/development-guide (offline:
`~/.moodle-devdocs/general/app/development/`).

## Prerequisites

- git
- Node 24: `.nvmrc` is `lts/krypton`, engines `>=v24.16 <25`. The host `node`
  on PATH (`~/.local/bin/node`, v24.20.0) satisfies it; nvm (`~/.nvm`, v22 +
  v24) also works: `source ~/.nvm/nvm.sh && nvm use`.

## Install

```bash
git clone https://github.com/moodlehq/moodleapp.git ~/moodleapp
cd ~/moodleapp
node --version                        # must be 24.x
nice -n 19 npm ci --no-audit --no-fund  # postinstall: patch-package + cordova-plugin-moodleapp deps
```

- `npm warn allow-scripts` for esbuild/lmdb/core-js is harmless if
  `npx esbuild --version` works afterwards.
- Check: `ls cordova-plugin-moodleapp/node_modules` must exist.

## Run (headless dev server)

```bash
cd ~/moodleapp
npm run serve:test     # NODE_ENV=testing ionic serve --no-open
```

- Serves http://localhost:8100. Never `npm start`: it passes `--ssl` and
  `--browser=$MOODLE_APP_BROWSER` and opens a headed browser.
- Drive it headless (Playwright MCP). First compile takes minutes; wait for
  the compiled message (`wait-for`), not a sleep.
- Gulp runs before serve/build (lang files, env from `moodle.config.json`).
- For plugin work you do not need a build: use https://main.apps.moodledemo.net
  or https://latest.apps.moodledemo.net in headless Chromium.

## Point the app at a local Moodle

Start the matching env (`docker ps`, see `moodle-guidelines.md`) and enter its
web URL on the login screen. The site needs mobile web services on; the default
is off on http sites (`is_https() ? 1 : 0`):

```bash
cd <env code tree> && ~/.claude/skills/moodle-ci/scripts/mexec \
  admin/cli/cfg.php --name=enablemobilewebservice --set=1
```

## Plugin side (`tool_mobile` site plugins)

Docs: `~/.moodle-devdocs/general/app/development/plugins-development-guide/`
(`index.md`, `api-reference.md`, `examples/`, `troubleshooting.md`).

Scaffold, check, serve (`S=~/.claude/skills/moodle-ci/scripts`):

```bash
python3 ~/.claude/skills/moodle-pluginskel/mobile.py <plugin> \
  --delegate CoreMainMenuDelegate [--handler <h>] [--table <t> --cols a,b] \
  [--capability <cap>]   # writes templates/mobileapp/<h>.mustache + tests/output/mobile_test.php
$S/mmobile <plugin>     # static check of db/mobile.php, exit 1 on FAIL
cd ~/moodleapp && npm run serve:test   # log in with the site URL
```

The 23 delegates: `moodle-ci/reference/mobile-delegates.json`.

- `db/mobile.php`: `$addons = ['<component>' => ['handlers' => [...],
  'lang' => [['<id>', '<component>'], ...]]]`. Addon key = the frankenstyle
  component. Each handler: `delegate` (e.g. `CoreMainMenuDelegate`,
  `CoreCourseModuleDelegate`), `method`, `displaydata` (`title`, `icon`),
  optional `init`, `styles`, `moodlecomponent`, `restricttocurrentuser`,
  `restricttoenrolledcourses`; per-delegate keys: `api-reference.md`
  (Handlers). `restrict` (`users`, `courses`) and `disabled` go only in the
  `init` method's response.
- `classes/output/mobile.php`: class `<component>\output\mobile`, one
  `public static function <method>(array $args)` per handler, returning
  `['templates' => [['id' => 'main', 'html' => ...]], 'javascript' => ...,
  'otherdata' => [...]]`. Served via the `tool_mobile_get_content` web service.
- Templates in `templates/mobileapp/`, JS in `js/mobileapp/`. Ionic markup,
  not Bootstrap. Start each template with `{{=<% %>=}}` so Angular keeps
  `{{ }}`. Strings in templates: `plugin.<component>.<id>` (listed in `lang`).
- Site checks: `enablemobilewebservice` = 1; the plugin appears in
  `tool_mobile_get_plugins_supporting_mobile` (cached in `tool_mobile`
  `plugininfo`).
- Changes not showing: `db/mobile.php` → reload the app; template/method →
  pull to refresh; else `php admin/cli/purge_caches.php`; else log out/in; an
  install change → bump `version.php` and upgrade.

## Tests & lint (single files only)

```bash
NODE_ENV=testing npx gulp            # if assets are stale
nice -n 19 npx jest <path>           # one test file; never the full `npm test`
nice -n 19 npx eslint <path>
```

## Troubleshooting

- "Unsupported engine" or odd build errors → `node --version` must be 24.x.
- Build out-of-memory → use the npm scripts (`npm run build`); they set
  `--max-old-space-size=8192`.
- Port 8100 busy → `npx ionic serve --no-open --port=<other>`.
