# Moodle Docker stack

**New environments: use `/moodle-install <version>`** (`skills/moodle-install`). It creates one
app + db stack per Moodle version and a single shared nginx + mailhog + selenium stack. This
directory keeps the original single-stack dev compose for reference.

**Warning — ports collide.** This single stack binds host ports 80, 1025/8025 and 4444, the exact
ports the shared stack (`~/moodle-envs/shared`) now owns, and its host `moodle-dev.localhost` is not
matched by the shared nginx (only `moodle<MM>.localhost`). Run one or the other, not both. To fold a
legacy checkout into the new layout: `/moodle-install 5.1 --src <path/to/www>`. To keep a legacy
stack on its old hostname behind the shared proxy, see the "legacy single-stack env" note in
`moodle-tips.md`.

Portable copy of a standalone dev environment (`~/moodle-dev/docker-compose.yml`).

```
mkdir -p ~/moodle-dev/docker && cd ~/moodle-dev
cp ~/moodle-harness/docker/docker-compose.yml .
cp ~/moodle-harness/docker/000-default.conf docker/
git clone <moodle repo> http        # docroot is http/public on Moodle 5.1+
mkdir -p moodledata behatfaildumps && chmod 777 moodledata behatfaildumps
docker compose up -d
```

- Services: `app` (moodlehq/moodle-php-apache:8.4, port 80), `db` (mysql, port 3306),
  `mailhog` (8025 web UI), `selenium` (Behat). Site host: `moodle-dev.localhost`.
- Paths are relative to the compose file, so one copy per environment
  (`~/moodle-dev`, `~/moodlecore`, …). Two stacks can't share ports 80/3306 — stop one
  or override `ports: !reset []` on the second (see `moodle-tips.md`, Docker).
- No `restart: always`: on WSL2 it resurrects the app container before the compose
  network exists (container Up, DB unreachable). Start the stack by hand after a reboot.
- Differences from the live file: relative paths, `image: mysql` (the live file says
  `postsql`, a typo masked by the already-created container), `restart: always` removed,
  and the selenium `/dev/shm` volume line repaired.
- First run inside the container: `php admin/cli/install_database.php ...` or restore a
  DB dump, then `php admin/tool/phpunit/cli/init.php` (under `public/` on 5.1+) for tests.
