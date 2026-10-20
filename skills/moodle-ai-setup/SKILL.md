---
name: moodle-ai-setup
description: Set up a Moodle 4.5+ site's AI subsystem idempotently. Use for "AI setup", "Moodle AI", "AI provider", "AI placements", "AI rate limit", "AI policy", "who gets AI", days 3-6 of the AI offer (ai-en). Provider (Ollama, OpenAI, Claude), placements, role caps, hourly limits, policy; `--check`.
---

# moodle-ai-setup - provider, placements, roles, limits, policy

```bash
~/.claude/skills/moodle-ai-setup/ai-setup moodle53 --provider ollama --roles editingteacher --limit 20
~/.claude/skills/moodle-ai-setup/ai-setup moodle53 --check          # exit 1 and `drift` lines when a value moved
bash ~/.claude/skills/moodle-ai-setup/tests/setup.test.sh           # fake docker offline + live on moodle53
```

- Options: `--site-limit N` (default 10 x `--limit`), `--endpoint URL` (Ollama default `http://127.0.0.1:11434`),
  `--apikey-file F` (cloud providers; passed by env name, never printed or stored), `--policy F` (default
  `policy.en.html`, a draft the customer approves), `--name TEXT` (instance name; default `AI setup (<provider>)`).
- Never point it at the 4.5 / Vass env (refused) or at the 5.2 dev site (its aicharts uses the owner's real key).
  Tests use a keyless Ollama instance with a dummy endpoint; no real provider key.

## Architecture

| Module | Role |
|---|---|
| `ai-setup` (bash) | validates flags, builds the JSON spec, picks `<env>-app-1`, pipes `apply.php` to `php` as www-data |
| `apply.php` (Moodle CLI) | one reconciler per area; each compares want vs have, prints `ok`/`set`/`drift`, writes only in apply mode |
| `$CFG->dataroot/ai-setup.json` | the last applied spec; `--check` without flags reads it back |

Reconcilers: provider (instance by name, all actions on, `enableuserratelimit/userratelimit`,
`enableglobalratelimit/globalratelimit`), placements (`aiplacement::enable_plugin` + each action's config),
capabilities (every `aiplacement_*` cap: listed roles allow, any other role's system allow becomes prevent),
policy (`core_ai/userpolicy` in `langlocalroot/en_local/ai.php`, merged with other local strings). Each one is a
single function with one reason to change (SRP); a new area is a new function, nothing else moves (OCP).
Summary line: `changed: N` (apply) or `drift: N` (check).
