---
name: moodle-docs
description: Instant offline access to the Moodle developer docs (a local mirror of moodledev.io sources). Use for ANY Moodle developer question — core APIs (DML, File, Access, Hooks…), subsystems, plugin-type guides, coding guides, release notes — instead of web-fetching moodledev.io. Also converts any moodledev.io URL to its local file.
---

# Moodle developer docs (local moodledev.io mirror)

The full moodledev.io markdown source lives at `~/.moodle-devdocs` — read it locally instead
of fetching the website. If the directory is missing, run
`bash ~/.claude/skills/moodle-docs/sync.sh` first (also refreshes a stale mirror).

## URL ↔ file mapping

| moodledev.io URL | Local path |
|---|---|
| `/docs/<latest>/...` (in-dev branch) | `~/.moodle-devdocs/docs/...` |
| `/docs/<X.Y>/...` (stable branch) | `~/.moodle-devdocs/versioned_docs/version-<X.Y>/...` |
| `/general/...` | `~/.moodle-devdocs/general/...` |

Pages are `<path>.md` or `<path>/index.md` (grep if unsure). Pick the version matching the
project's Moodle branch (check its `version.php` requires / docker env); use `docs/` for the
in-dev branch or when the branch has no `versioned_docs` snapshot.

## Finding the right page

1. **Ranked search (preferred)** — BM25 over the whole mirror, prints the top pages with
   matching snippets and line numbers:
   ```bash
   python3 ~/.claude/skills/moodle-docs/search.py "hook listener callback"
   python3 ~/.claude/skills/moodle-docs/search.py --version 5.1 "file storage"
   ```
   `--version X.Y` searches a stable snapshot instead of the in-dev `docs/`. Query tips:
   - Use 2–4 short, specific domain terms ("activity module", "privacy provider",
     "scheduled task") — full sentences and generic words (create, new, plugin, moodle,
     how) dilute the ranking.
   - Exact symbol names work well (`has_capability`, `\core\hook\manager`).
   - Top results look generic or wrong? Retry with a tighter query before falling back
     to grep.
   - Release-note changelogs are excluded by default; pass `--releases` when the question
     is about what changed in a specific Moodle release.
2. Browsing instead? `~/.moodle-devdocs/INDEX.md` lists every API/guide page with its title.
3. Exact strings (class/function names) not surfacing? Fall back to plain grep:
   ```bash
   grep -ril '<literal>' ~/.moodle-devdocs/docs ~/.moodle-devdocs/general
   ```
4. Read targeted sections of the matched file — many pages are long; use offset/limit or
   grep for the heading first rather than reading whole files.

Key entry points: `docs/apis.md` (API overview), `docs/apis/core/`, `docs/apis/subsystems/`,
`docs/apis/plugintypes/`, `docs/guides/`, `general/development/policies/`.

## Notes

- The mirror is a sparse, shallow git clone (markdown only). Refresh occasionally with
  `sync.sh`; `git -C ~/.moodle-devdocs log -1 --format=%cs` shows how fresh it is.
- Files are Docusaurus MDX — ignore JSX imports/components, the prose and code blocks are
  what matters.
- Known gap: some legacy APIs (e.g. the Events API) were never migrated to moodledev.io —
  if a topic is missing, use the closest modern page (e.g. Component Communication for
  events) or a web search of the legacy docs.moodle.org/dev wiki.
