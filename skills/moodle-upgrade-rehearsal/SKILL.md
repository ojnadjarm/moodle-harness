---
name: moodle-upgrade-rehearsal
description: Timed Moodle upgrade rehearsal on a throwaway site (default 4.5 -> 5.3 LTS). Use for "upgrade rehearsal", "how long does the upgrade take", "price the upgrade offer", "dry-run upgrade", "test rollback". Backup, PG 13->17, code swap, /public + PHP 8.4, upgrade.php, smoke login, rollback.
---

# moodle-upgrade-rehearsal — timed upgrade + rollback on a throwaway site

```bash
S=~/.claude/skills/moodle-upgrade-rehearsal/rehearse.sh
$S all                    # up -> run -> rollback -> report (~/drop/money/samples/rehearsal-4.5-to-5.3.md)
$S down                   # remove the throwaway env (containers, volumes, ~/moodle-envs/4.5-rehearsal)
bash ~/.claude/skills/moodle-upgrade-rehearsal/tests/guard.test.sh   # guard selftest on a fixture HOME
```

- Own compose project `moodle45r`, port 127.0.0.1:8145, dir `~/moodle-envs/4.5-rehearsal`. It never uses `/moodle-install 4.5`: that writes project `moodle45` and would recreate the Vass containers.
- The guard refuses `~/moodle-envs/{4.5,vass*,5.*,shared}` and the real project names before any action.
- Overrides: `REHEARSAL_DIR`, `REHEARSAL_PROJECT`, `REHEARSAL_PORT`, `REHEARSAL_SIZE` (generator size, default XS), `FROM_/TO_{BRANCH,PHP,PG}`.
- Each step appends `phase<TAB>step<TAB>seconds<TAB>ok|fail(rc)` to `timings.tsv`; a failed step stops the run.

## Architecture
- One script, one function per step (`backup`, `db_move`, `code_swap`, `docroot`, `upgrade`, `theme_check`, `smoke`, `restore`); `step` is the only place that times and records.
- `step` runs each function in a `set -e` subshell, because `set -e` is ignored inside `f || rc=$?`.
- Compose reads `PHP` and `DOCROOT` from `.env`, so the docroot move and PHP switch are one `.env` edit and a recreate.
- Reports come from `timings.tsv` + `notes.md` only, so a new step adds a row without changing `report`.
- Guide: `~/agents/KB/guides/moodle-upgrade-rehearsal.md`.
