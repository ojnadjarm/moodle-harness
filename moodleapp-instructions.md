# Moodle App — Environment Setup & Run Instructions

How to install and run the official Moodle mobile app (moodlehq/moodleapp) on this
machine. Verified on WSL2 (Ubuntu) with nvm. Repo architecture and day-to-day
commands live in the repo's own `CLAUDE.md`.

## Prerequisites

- git
- nvm (`~/.nvm`) — the app pins Node via `.nvmrc` (currently `lts/krypton`,
  i.e. Node >=24.16 <25 per `package.json` engines). The system Node is NOT used.

## Install

```bash
git clone https://github.com/moodlehq/moodleapp.git ~/moodleapp
cd ~/moodleapp
source ~/.nvm/nvm.sh && nvm install   # reads .nvmrc, installs/activates Node 24
npm ci --no-audit --no-fund           # ~2 min; postinstall runs patch-package + cordova-plugin-moodleapp deps
```

Notes:
- `npm ci` may print `npm warn allow-scripts` for esbuild/lmdb/core-js install
  scripts. Harmless as long as `npx esbuild --version` works afterwards.
- Verify the install: `ls node_modules/.bin | wc -l` (non-trivial count),
  `ls cordova-plugin-moodleapp/node_modules` (must exist).

## Run (browser dev server)

Every npm command needs the nvm Node active in that shell first:

```bash
cd ~/moodleapp
source ~/.nvm/nvm.sh && nvm use
npx ionic serve --no-open
```

- Serves at http://localhost:8100 (WSL2: reachable from Windows at the same URL).
- Use `--no-open` on headless/WSL2 — the default `npm start` passes `--ssl` and
  `--browser=$MOODLE_APP_BROWSER`, which expects a local browser.
- First compile takes a few minutes (webpack, "Generating browser application
  bundles"); wait for the compiled/success message before testing.
- Gulp runs automatically before serve/build to generate `src/assets/lang/` and
  the runtime env from `moodle.config.json`.

## Point the app at a Moodle site

On the app's login screen enter the URL of a running Moodle site. For the local
Docker Moodle environments, start the matching container first (`docker ps`,
see `moodle-guidelines.md`) and use its web URL. The site must have mobile web
services enabled (Site administration → Mobile app).

## Tests & lint

```bash
npm test        # gulp + full Jest suite
npx jest <path> # single test file (run `NODE_ENV=testing npx gulp` first if assets are stale)
npm run lint
```

## Troubleshooting

- "Unsupported engine" / weird build errors → check `node --version` is 24.x in
  the current shell; re-run `source ~/.nvm/nvm.sh && nvm use`.
- Build out-of-memory → the npm scripts already set `--max-old-space-size`; use
  them (`npm run build`) instead of raw `ng build`.
- Port 8100 busy → `npx ionic serve --no-open --port=<other>`.
