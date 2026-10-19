---
name: moodle-web
description: Drive a local Moodle env through the browser (Playwright MCP) - log in as admin, reach the admin pages (notifications/upgrade, purge caches, plugin overview, plugin settings) and verify a plugin in the real UI. Use for any "check it in the Moodle UI" task; not for bulk admin work the CLI does better.
---

# `/moodle-web <ver> <task>`

Machine-local skill. Envs live in `~/moodle-envs/<ver>`; `moodle-envs` lists them (version, release,
URL, state, containers; `--json`). `moodle-login-check <ver>` is a curl-only reachability probe.

## Procedure
1. `moodle-envs` → take `URL` for `<ver>`. If state is not `up`: `docker compose -f ~/moodle-envs/<ver>/docker-compose.yml up -d`.
2. `moodle-login-check <ver>` — if that fails, it is not a browser problem; stop and report.
3. Browser (see the `browser` skill): `browser_navigate` → `<URL>/login/index.php` → `browser_snapshot`.
   - If the snapshot already shows the user menu, the persistent profile is still logged in: skip to step 4.
   - Otherwise `browser_fill_form` username/password, click **Log in**, `browser_snapshot`.
   - Credentials: user `admin`; password is `MOODLE_ADMIN_PASSWORD` in `~/.config/pc-harness/config.env`, or the one
     printed on `/moodle-install`'s `Site:` line (random when the key is unset). Never write the value down.
4. Verify: the page footer / user menu shows **"You are logged in as ..."**. Never assume — snapshot after every action.
5. Navigate to the task page from the table below, `browser_snapshot`, read the answer off the snapshot.
6. Screenshot with `browser_take_screenshot` **without a filename** so it lands in `~/agents/browser/out/`;
   report the absolute path the tool returns.

## URL table (append to `<URL>`)
| Page | Path |
|---|---|
| Login | `/login/index.php` |
| Notifications / pending upgrade | `/admin/index.php` |
| Purge caches | `/admin/purgecaches.php` (confirm button) |
| Plugins overview | `/admin/plugins.php` |
| Install plugin from ZIP | `/admin/tool/installaddon/index.php` |
| Plugin settings | `/admin/settings.php?section=<sectionname>` |
| Site admin search | `/admin/search.php?query=<term>` |
| Dashboard | `/my/` |
| Course list | `/course/` |
| Mailhog (shared) | http://localhost:8025 |
| Selenium VNC (shared) | http://localhost:7900 |

## Use the CLI instead when…
Anything non-visual is faster and more reliable in the container
(`docker exec moodle<MM>-app-1 php admin/cli/<script>`, cwd `/var/www/html` on every version; admin/cli stays at the repo root, only `admin/tool/*/cli` moves under `public/` on 5.1+):
- upgrade after code changes → `admin/cli/upgrade.php --non-interactive`
- purge caches → `admin/cli/purge_caches.php`
- config → `admin/cli/cfg.php --name=<x> --set=<y>`
- create users/courses, run PHPUnit/Behat, read logs.
Use the browser only to see what a human would see: rendered pages, forms, JS behaviour, plugin settings pages, layout.

## Gotchas
- One browser per profile — do not run two Playwright sessions on `profile-default` at once.
- Logins persist across sessions on `profile-default`; don't re-enter credentials on every run.
- Moodle 5.1+ serves from `www/public`; 4.x from `www`.
- `/admin/index.php` may redirect straight into an upgrade form when plugin versions changed — read the
  snapshot before clicking anything.
- After a code change, an upgrade is required before the UI reflects it: run the CLI upgrade, then reload.
