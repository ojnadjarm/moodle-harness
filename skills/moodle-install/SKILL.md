---
name: moodle-install
description: Create a Moodle 4.1-5.3 Docker dev env (app + DB in ~/moodle-envs/<ver>, matching PHP/DB, shared mailhog + selenium). Use when asked to install, create or spin up a Moodle X.Y env or container. Usage /moodle-install <version> [pgsql|mysql] [--name <x>] [--src --php --host --https --phpunit --behat]
---

# Install a Moodle environment

Run the installer with the user's arguments and relay its final summary (site URL, admin login,
containers, ports). It refuses (exit 3) an env dir or compose project that already exists; `--new-name <x>` makes a fresh dir and project `<x>`. It never acts on `~/moodle-envs/4.5`, `~/moodle-envs/vass*` or projects `moodle45`/`vass*` (the Vass work site), whatever the flags.

```bash
~/.claude/skills/moodle-install/install.sh $ARGUMENTS
```

## What it does

1. Starts the shared stack (`~/moodle-envs/shared`: nginx proxy, mailhog and selenium on the `moodle-shared` network).
2. Creates `~/moodle-envs/<ver>/` with `docker-compose.yml`, data dirs and a `git clone --depth 1` of `MOODLE_<MMM>_STABLE` into `www/` (`--src <path>` reuses an existing checkout instead).
3. Brings up `app` (`moodlehq/moodle-php-apache:<php>`) + `db`, waits for the DB.
4. Writes `config.php` (kept if it already exists) and installs the database (skipped if tables exist).
5. Runs `composer install --no-interaction` (fetching `composer.phar` if absent) in the app container whenever `vendor/bin/phpunit` is missing, so every env is CI-ready.
6. `--phpunit` / `--behat` run the corresponding `init.php` inside the container.

## Version matrix (defaults, from the release notes)

| Moodle | PHP | PostgreSQL | MySQL |
|---|---|---|---|
| 4.1 | 8.1 | 13 | 8.0 |
| 4.2 / 4.3 | 8.2 | 13 | 8.0 |
| 4.4 / 4.5 | 8.3 | 13 | 8.0 |
| 5.0 | 8.4 | 14 | 8.4 |
| 5.1 | 8.4 | 15 | 8.4 |
| 5.2 | 8.4 | 16 | 8.4 |
| 5.3 | 8.4 | 17 | 8.4 |

DB defaults to pgsql. Each site is `http://moodle<MM>.localhost` (4.5 → `http://moodle45.localhost`; `moodle-45.localhost` works too) through the shared nginx on port 80, which routes by hostname to the app alias. Direct ports follow the version as a fallback: web `80MM`, db `54MM` (pgsql) or `33MM` (mysql). Mailhog (1025/8025) and selenium (4444/5900/7900) are bound once, by the shared stack.
`--name <x>` (e.g. `/moodle-install 4.5 --name lts45`, a 4.5 LTS env beside the Vass site) makes env dir `~/moodle-envs/<x>` and project `moodle<x>`, takes the first ports past `80MM`/`54MM` (or `33MM`) that no running service or other env's compose file uses, and serves the site at `http://localhost:<web port>` (nginx routes only `moodle<MM>.localhost`).
`--host <name-or-ip>` (e.g. the laptop's LAN IP) makes the site URL `http://<host>:80MM` instead, so the env is reachable from other machines on its own port.
`--https` (needs `--host`, a tailnet MagicDNS name) adds a `tailscale serve` TLS mapping on port `84MM` -> `127.0.0.1:80MM` and makes `config.php` switch `wwwroot` to `https://<host>:84MM` with `$CFG->sslproxy = true` when the request arrives with `X-Forwarded-Proto: https`. The plain `http://<host>:80MM` URL keeps working for Behat/selenium and CLI. Undo with `tailscale serve --https=84MM off`.

## Afterwards

- Plugins go under `www/` (4.x, 5.0) or `www/public/` (5.1+). `/moodle-ci` discovers the container by its mount.
- CLI paths inside the container (workdir `/var/www/html`): `admin/cli/*.php` stays at the repo root on every version; `admin/tool/phpunit/cli/init.php` and `admin/tool/behat/cli/init.php` sit under `public/` on 5.1+.
- Behat reaches the site as `http://moodle<MM>` through the shared network; the app reaches `mailhog:1025` and `selenium:4444`.
- `*.localhost` resolves to loopback in browsers automatically. From curl/CLI (or a browser that does not resolve it), use `curl -H 'Host: moodle<MM>.localhost' http://localhost/` or add `127.0.0.1 moodle<MM>.localhost` to the hosts file (`/etc/hosts`).
- List environments: `docker compose ls`. Stop one (keep data): `docker compose -f ~/moodle-envs/<ver>/docker-compose.yml down`. Start again: `docker compose -f ~/moodle-envs/<ver>/docker-compose.yml up -d`.
- Remove an environment: `docker compose -f ~/moodle-envs/<ver>/docker-compose.yml down -v && rm -rf ~/moodle-envs/<ver>`.
- If the script fails, show the error, fix the cause, re-run the same command.
