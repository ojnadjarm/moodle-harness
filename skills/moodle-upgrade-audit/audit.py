#!/usr/bin/env python3
"""Moodle upgrade audit: every add-on plugin of a site checked against the moodle.org directory for a target release."""
import argparse
import html
import json
import os
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone

PLUGLIST_URL = "https://download.moodle.org/api/1.3/pluglist.php"
CACHE = os.path.expanduser("~/.cache/moodle-upgrade-audit/pluglist.json")
CACHE_TTL = 86400
STALE_DAYS = 365

COLLECT_PHP = r"""<?php
define('CLI_SCRIPT', true);
require('%s/config.php');
$out = [];
foreach (core_plugin_manager::instance()->get_plugins() as $plugins) {
    foreach ($plugins as $p) {
        if ($p->is_standard()) {
            continue;
        }
        $out[] = ['component' => $p->component, 'name' => (string)$p->displayname, 'version' => $p->versiondisk,
            'release' => $p->release, 'enabled' => $p->is_enabled(), 'status' => $p->get_status()];
    }
}
echo json_encode(['site' => ['release' => $CFG->release, 'version' => $CFG->version], 'plugins' => $out]);
"""


def collect(container, root):
    """Read the site's add-on plugins through core_plugin_manager inside the app container (read-only)."""
    run = subprocess.run(["docker", "exec", "-i", container, "php"], input=COLLECT_PHP % root,
                         capture_output=True, text=True, check=True)
    return json.loads(run.stdout[run.stdout.index("{"):])


def load_directory(path):
    """Load the moodle.org plugin list from a file, or from a cached download refreshed daily."""
    if not path:
        path = CACHE
        if not os.path.exists(path) or time.time() - os.path.getmtime(path) > CACHE_TTL:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            req = urllib.request.Request(PLUGLIST_URL, headers={"User-Agent": "moodle-upgrade-audit/1.0"})
            with urllib.request.urlopen(req, timeout=120) as r, open(path + ".tmp", "wb") as f:
                f.write(r.read())
            os.replace(path + ".tmp", path)
    with open(path) as f:
        data = json.load(f)
    return {p["component"]: p for p in data["plugins"]}


def _rel(release):
    return tuple(int(x) for x in release.split(".") if x.isdigit())


def _day(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%d")


def assess(plugin, entry, target, now):
    """One plugin's directory status and keep/replace/remove verdict for the target release."""
    row = {"component": plugin["component"], "name": plugin.get("name") or plugin["component"],
           "installed": plugin.get("release") or str(plugin.get("version") or "")}
    if entry is None:
        row["status"] = "not in the moodle.org directory"
    else:
        ready = [v for v in entry["versions"] if any(s["release"] == target for s in v["supportedmoodles"])]
        best = max(ready, key=lambda v: int(v["version"]), default=None)
        top = max((s["release"] for v in entry["versions"] for s in v["supportedmoodles"]), key=_rel, default="?")
        last = entry.get("timelastreleased") or max((v["timecreated"] for v in entry["versions"]), default=0)
        row["status"] = (f"{target} version: {best['release']}" if best
                         else f"no {target} version (newest supports {top})")
    if plugin.get("status") == "missing":
        return {**row, "verdict": "remove", "note": "code missing from disk; uninstall before the upgrade"}
    if plugin.get("enabled") is False:
        return {**row, "verdict": "remove", "note": "disabled on this site; uninstall unless it is still needed"}
    if entry is None:
        return {**row, "verdict": "keep", "note": f"custom code: test it on a {target} copy"}
    if best:
        if int(best["version"]) > int(plugin.get("version") or 0):
            return {**row, "verdict": "keep", "note": f"update to {best['release']} ({best['version']})"}
        return {**row, "verdict": "keep", "note": f"installed version already supports {target}"}
    age = (now - last) / 86400
    if age > STALE_DAYS:
        return {**row, "verdict": "replace", "note": f"no release since {_day(last)}: find an alternative"}
    return {**row, "verdict": "keep", "note": f"maintainer active (last release {_day(last)}): re-check before the upgrade"}


def audit(site, directory, target, now):
    """The full report: site, target and one assessed row per add-on, sorted by component."""
    rows = [assess(p, directory.get(p["component"]), target, now) for p in site["plugins"]]
    rows.sort(key=lambda r: r["component"])
    counts = {v: sum(r["verdict"] == v for r in rows) for v in ("keep", "replace", "remove")}
    return {"site": site["site"], "target": target, "date": _day(now), "rows": rows, "counts": counts}


def _n(rows):
    return f"{len(rows)} add-on" + ("" if len(rows) == 1 else "s")


def render_md(rep, label):
    """Markdown table of the report."""
    c = rep["counts"]
    out = [f"# Plugin audit: {label} to Moodle {rep['target']}", "",
           f"Site: Moodle {rep['site']['release']} · checked {rep['date']} against {PLUGLIST_URL}", "",
           f"{_n(rep['rows'])} · keep {c['keep']} · replace {c['replace']} · remove {c['remove']}", "",
           "| Plugin | Component | Installed | Status | Verdict | Note |", "|---|---|---|---|---|---|"]
    cell = lambda s: str(s).replace("|", "\\|")
    for r in rep["rows"]:
        out.append("| " + " | ".join(cell(r[k]) for k in ("name", "component", "installed", "status", "verdict", "note")) + " |")
    return "\n".join(out) + "\n"


CSS = """*{box-sizing:border-box}
:root{--ink:#1f2328;--soft:#59636e;--paper:#fbfaf6;--card:#fff;--line:#e3e0d8;--accent:#2f6f5e;--accent-soft:#e7f1ed;--warn:#8a5a00;--warn-soft:#fbf1dc;--bad:#b4442f;--bad-soft:#fbeeea}
html{font-size:clamp(16px,0.9rem + 0.25vw,19px)}
body{margin:0;background:var(--paper);color:var(--ink);font:1rem/1.6 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{width:min(72rem,100% - 2.5rem);margin:0 auto;padding:clamp(1.5rem,4vw,3.5rem) 0}
h1{font-size:clamp(1.5rem,1.1rem + 1.6vw,2.3rem);line-height:1.2;margin:0 0 .5rem}
.lead{color:var(--soft);margin:0 0 1.5rem;overflow-wrap:anywhere}
.sum{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,9rem),1fr));gap:1rem;margin:0 0 1.5rem}
.sum div{background:var(--card);border:1px solid var(--line);border-radius:.6rem;padding:.8rem 1rem}
.sum strong{display:block;font-size:1.6rem;line-height:1.2}
table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:.6rem;overflow:hidden}
th,td{text-align:left;padding:.6rem .8rem;border-bottom:1px solid var(--line);vertical-align:top;overflow-wrap:anywhere}
th{font-size:.85rem;color:var(--soft);font-weight:600}
code{font-size:.85em}
.v{display:inline-block;border-radius:1rem;padding:0 .6rem;font-weight:600;font-size:.9rem}
.keep{background:var(--accent-soft);color:var(--accent)}.replace{background:var(--warn-soft);color:var(--warn)}.remove{background:var(--bad-soft);color:var(--bad)}
.src{font-size:.8rem;color:var(--soft);margin-top:2rem;overflow-wrap:anywhere}
@media (max-width:48rem){table,tbody,tr,td{display:block}thead{display:none}table{border:0;background:none}
tr{background:var(--card);border:1px solid var(--line);border-radius:.6rem;margin:0 0 1rem;padding:.4rem 0}
td{border:0;display:grid;grid-template-columns:6.5rem 1fr;gap:.6rem;padding:.3rem 1rem}
td::before{content:attr(data-label);color:var(--soft);font-size:.85rem}}
@media print{body{background:#fff}main{width:100%;padding:0}tr{break-inside:avoid}}"""


def render_html(rep, label):
    """Responsive stand-alone HTML page of the report."""
    e = html.escape
    c = rep["counts"]
    heads = ("Plugin", "Component", "Installed", "Status", "Verdict", "Note")
    body = []
    for r in rep["rows"]:
        cells = [e(r["name"]), f"<code>{e(r['component'])}</code>", e(r["installed"]), e(r["status"]),
                 f'<span class="v {e(r["verdict"])}">{e(r["verdict"])}</span>', e(r["note"])]
        body.append("<tr>" + "".join(f'<td data-label="{h}">{v}</td>' for h, v in zip(heads, cells)) + "</tr>")
    title = f"Plugin audit: {e(label)} to Moodle {e(rep['target'])}"
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width,initial-scale=1"><title>{title}</title><style>{CSS}</style></head>'
            f'<body><main><h1>{title}</h1><p class="lead">Every add-on on this Moodle {e(rep["site"]["release"])} site, '
            f'checked on {e(rep["date"])} against the moodle.org plugins directory for a {e(rep["target"])} version.</p>'
            f'<div class="sum"><div><strong>{len(rep["rows"])}</strong>{_n(rep["rows"]).split(" ")[1]}</div><div><strong>{c["keep"]}</strong>keep</div>'
            f'<div><strong>{c["replace"]}</strong>replace</div><div><strong>{c["remove"]}</strong>remove</div></div>'
            f'<table><thead><tr>{"".join(f"<th>{h}</th>" for h in heads)}</tr></thead><tbody>{"".join(body)}</tbody></table>'
            f'<p class="src">Source: <a href="{PLUGLIST_URL}">{PLUGLIST_URL}</a>. Keep = a {e(rep["target"])} version exists, '
            f'the maintainer is active, or it is custom code we test ourselves. Replace = no release for over a year. '
            f'Remove = disabled or its code is missing.</p></main></body></html>\n')


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--container", help="Moodle app container to read the plugins from")
    src.add_argument("--plugins", help="plugin list JSON written by an earlier --json-site run")
    ap.add_argument("--root", default="/var/www/html", help="Moodle root inside the container (holds config.php)")
    ap.add_argument("--pluglist", help="local copy of pluglist.php (default: cached download)")
    ap.add_argument("--target", default="5.3", help="Moodle release to audit for")
    ap.add_argument("--label", help="site name in the title (default: Moodle <release>)")
    ap.add_argument("--now", help="audit date YYYY-MM-DD (default: today)")
    ap.add_argument("--md"), ap.add_argument("--html"), ap.add_argument("--json"), ap.add_argument("--json-site")
    a = ap.parse_args(argv)
    if a.container:
        site = collect(a.container, a.root)
    else:
        with open(a.plugins) as f:
            site = json.load(f)
    if a.json_site:
        with open(a.json_site, "w") as f:
            json.dump(site, f, indent=1)
    now = datetime.strptime(a.now, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp() if a.now else time.time()
    rep = audit(site, load_directory(a.pluglist), a.target, now)
    label = a.label or f"Moodle {rep['site']['release'].split(' ')[0]}"
    for path, text in ((a.md, lambda: render_md(rep, label)), (a.html, lambda: render_html(rep, label)),
                       (a.json, lambda: json.dumps(rep, indent=1) + "\n")):
        if path:
            with open(path, "w") as f:
                f.write(text())
    c = rep["counts"]
    print(f"{_n(rep['rows'])} · keep {c['keep']} · replace {c['replace']} · remove {c['remove']}")
    if not (a.md or a.html or a.json):
        sys.stdout.write(render_md(rep, label))


if __name__ == "__main__":
    main()
