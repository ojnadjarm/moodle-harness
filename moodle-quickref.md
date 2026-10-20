# Moodle harness quick reference: instead of raw, use

S=~/.claude/skills/moodle-ci/scripts (not on PATH; run from inside the plugin dir; each has --help)

| Instead of | Use |
|---|---|
| vendor/bin/phpunit, docker exec ... phpunit | `$S/mtest phpunit [file] [--filter X]` |
| vendor/bin/behat, docker exec ... behat | `$S/mtest behat [file.feature] [--tags X]` |
| util.php --drop + init.php for a broken test DB, dropping stray phpu_ tables by hand | `$S/mtest init phpunit --reset` (also from a Moodle root) |
| phpcs, phpcbf | `$S/phpcs-delta` (new violations), `$S/mfix`, `$S/mci` (quick CI) |
| docker compose exec php php admin/cli/x.php | `$S/mexec admin/cli/x.php` |
| admin/cli/upgrade.php + purge_caches.php after a version bump | `$S/mupgrade` (prints old -> new version) |
| docker exec ... php -r, a bootstrap script | `$S/mphp '<php code>'` |
| curl webservice/rest/server.php + a token, a call_external_function script | `$S/mws <function> key=value` (`--user`, `--list`) |
| psql, mysql in the DB container | `$S/mdb "SELECT ... FROM {user}"` (read-only; `--write`) |
| docker exec moodleNN-db-1 psql (outside a code tree) | `$S/mdb --env 5.2 "SELECT ..."` |
| cloning core to check an API on another branch | `$S/msrc 4.5` (`--fetch` clones it once) |
| hand-converting @covers / #[CoversClass] | `$S/mcovers --check`, `$S/mcovers --fix` |
| docker exec ... ps aux \| grep php (env busy?) | `$S/mfixture status <env>` |
| npx grunt amd, nvm use | `$S/mgrunt` (right node, this plugin only) |
| hand-editing `$plugin->version` | `$S/mversion bump\|resolve\|check` |
| guessing Behat step text | `$S/msteps <words>`, `$S/msteps --check f.feature` |
| grepping lang strings, copying them to lang/xx | `$S/mlang`, `$S/mlang --sync <xx>` |
| grepping for ticket ids, phpcs:ignore, Reflection | `$S/mrules` |

Code done: `/moodle-ci` (or `$S/mci`). Adoption meter: `$S/madopt --since 7d` (`--raw` lists the raw commands).
