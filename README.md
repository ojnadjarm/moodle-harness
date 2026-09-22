# Moodle harness

Portable Claude Code harness for Moodle development. It (1) auto-loads the Moodle
guidelines + tips into context on any Moodle project (with a one-line banner telling you it
did), (2) provides `/moodle-ci` to run the code checker + PHPUnit, (3) scaffolds plugins
deterministically with `/moodle-pluginskel`, (4) mirrors the moodledev.io developer docs
locally with ranked search (`/moodle-docs`) — the guidelines mandate a docs research pass
before any implementation, (5) creates a Docker environment for any Moodle 4.1 … 5.2 with
`/moodle-install <version>`, and (6) applies the `i-have-adhd` output shape in every session.
Environment-agnostic — no hardcoded container names or paths.

## Contents

```
CLAUDE.md                     # global Claude guidelines (think first, simplicity, git, Moodle)
moodle-guidelines.md          # injected into context on Moodle sessions (workflow + rules)
moodle-tips.md                # injected too: known gotchas with their fixes, by area
moodle-coding-style.md        # full Moodle coding style (read before writing PHP)
moodleapp-instructions.md     # install/run the official mobile app repo (Ionic/Angular)
settings.example.json         # hooks + UI prefs to merge into ~/.claude/settings.json
docker/                       # original single-stack dev compose, kept for reference
hooks/
  moodle-detect.sh            # is this a Moodle project? (shared by the hooks)
  moodle-session-start.sh     # SessionStart: ADHD rules always; guidelines + tips on Moodle projects
  moodle-stop-reminder.sh     # Stop: nudge to run /moodle-ci when PHP changed
  moodle-container.sh         # discover the Moodle container + dirroot by mount-matching
skills/
  moodle-ci/                  # /moodle-ci — run the CI suite (quick | full)
  moodle-pluginskel/          # /moodle-pluginskel — plugin skeleton from a YAML recipe
  moodle-docs/                # /moodle-docs — local moodledev.io mirror + BM25 search
  moodle-guidelines/          # /moodle-guidelines — reload guidelines + tips + style on demand
  moodle-install/             # /moodle-install <ver> — Docker env per Moodle version, shared mailhog+selenium
  set-moodle-harness/         # /set-moodle-harness — provision a machine
  i-have-adhd/                # /i-have-adhd — output shape, injected by the SessionStart hook
install.sh                    # copy the above into ~/.claude (backs up differing docs)
sync.sh                       # update this repo copy from the live ~/.claude harness
```

## Install on a new machine

```bash
git clone <this repo> ~/moodle-harness
~/moodle-harness/install.sh   # places files into ~/.claude
```
Then open Claude Code and run **`/set-moodle-harness`** — it installs `moodle-plugin-ci` on
the host, wires the SessionStart + Stop hooks into `~/.claude/settings.json` (idempotent),
mirrors the developer docs, and verifies the setup. The hooks take effect in a **new
session**. `settings.example.json` holds the other preferences (output style, model,
compaction) if you want the same UI defaults.

Project memories (`~/.claude/projects/*/memory/`) are machine-local and not part of this
repo; anything reusable from them has been folded into the guideline/tips files.

## How it works

- **Static checks (phpcs / codechecker / …) run on the host**; they survive container rebuilds.
- **PHPUnit runs inside the discovered Moodle container** (it needs the configured DB).
- Dirroot is found via `vendor/bin/phpunit`, so it's correct on 4.x/5.0 (code at repo root)
  and 5.1+ (code under `public/`).
- Scope PHPUnit to `<component>_testsuite` to avoid sibling-plugin class collisions.
- **Environments** (`/moodle-install <ver>`): one compose project per version under
  `~/moodle-envs/<ver>` (app + db, site `http://moodle<MM>.localhost`, direct web port
  `80MM`, db `54MM`/`33MM`), plus one shared project `~/moodle-envs/shared` holding the nginx
  proxy (port 80, routes `moodle<MM>.localhost` to the app alias), mailhog (1025/8025) and
  selenium (4444) on the `moodle-shared` network every app joins. PHP/DB per version come
  from the release notes.
- **Session banner**: the SessionStart hook prints `Harness: ADHD mode on · Moodle
  guidelines loaded (<root>)` (or just `ADHD mode on` outside Moodle). `/moodle-guidelines`
  reloads the same context on demand.

## Keeping it in sync

Edit the live files under `~/.claude`, then `./sync.sh`, review `git diff`, commit. Always edit the
live copy, never the repo copy directly: `sync.sh` overwrites the repo from `~/.claude`, and
`install.sh` overwrites `~/.claude` from the repo, so an edit in the wrong place is lost on the next
run.
