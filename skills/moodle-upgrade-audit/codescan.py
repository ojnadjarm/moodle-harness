#!/usr/bin/env python3
"""Scan a Moodle plugin tree for APIs that UPGRADING.md marks removed or deprecated, with an hours estimate."""
import argparse
import json
import os
import re
import sys
from dataclasses import asdict, dataclass

DEFAULT_UPGRADING = os.path.expanduser("~/moodle-envs/5.3/www/UPGRADING.md")
HOURS = {"removed": 0.5, "deprecated": 0.25}
RANK = {"removed": 0, "deprecated": 1}
VERBS = re.compile(r"deprecat|remov|no longer|dropped", re.I)
REPLACEMENT = re.compile(r"in favou?r of|instead|replace|moved to|successor|alternative|\buse\b|\bnew\b", re.I)
TICK = re.compile(r"`([^`]+)`")
REF = re.compile(r"MDL-\d+")
IDENT = r"[A-Za-z_]\w*"
NS = rf"\\?{IDENT}(?:\\{IDENT})*"
PLAIN = re.compile(rf"(?<![\w\\/$>])({NS}::{IDENT}(?:\(\))?|{IDENT}\(\))")


@dataclass
class Symbol:
    name: str
    kind: str
    severity: str
    version: str
    component: str
    ref: str


def vkey(v):
    """Version string to a comparable tuple."""
    return tuple(int(p) for p in v.split("."))


def classify(tok):
    """Backtick token to (kind, canonical name), or None when it is not a PHP symbol."""
    tok = tok.strip()
    m = re.fullmatch(rf"\$CFG->({IDENT})", tok)
    if m:
        return "cfg", m.group(1)
    m = re.fullmatch(rf"({NS})::([a-z_]\w*)(?:\(.*\))?", tok)
    if m:
        return "method", m.group(1).lstrip("\\") + "::" + m.group(2)
    m = re.fullmatch(rf"\\?({IDENT})\(.*\)", tok)
    if m:
        return "function", m.group(1)
    if re.fullmatch(r"[A-Z][A-Z0-9]*_[A-Z0-9_]+", tok):
        return "constant", tok
    if re.fullmatch(rf"\\?{IDENT}(?:\\{IDENT})+", tok):
        return "class", tok.lstrip("\\")
    return None


def tokens(s):
    """Backticked tokens plus bare `name()` / `Class::method` tokens in the rest of the text."""
    return TICK.findall(s) + PLAIN.findall(TICK.sub(" ", s))


def bullet_symbols(lines):
    """Symbols a bullet names as removed/deprecated, skipping replacements and context."""
    found = []
    prose = []
    for line in lines:
        s = line.strip()
        if s.startswith("|"):
            cells = [c for c in s.strip("|").split("|")]
            found += tokens(cells[0]) if cells else []
        elif re.match(r"^(- )?[-*] ", s) and line.startswith(" "):
            item = re.sub(r"^(- )?[-*] ", "", s)
            found += tokens(item) + ([item] if classify(item) else [])
        else:
            prose.append(s)
    for sentence in re.split(r"(?<=[.:])\s+", " ".join(prose)):
        if not VERBS.search(sentence):
            continue
        cut = REPLACEMENT.search(sentence)
        found += tokens(sentence[: cut.start()] if cut else sentence)
    typed = [c for c in map(classify, found) if c]
    if any(k in ("function", "method") for k, _ in typed):
        typed = [c for c in typed if c[0] != "class"]
    return typed


def parse_upgrading(text, since="4.5", until="5.3"):
    """UPGRADING.md text to {name: Symbol} for versions in (since, until]; removed wins over deprecated."""
    out = {}
    version = component = severity = None
    bullet = []

    def flush():
        if not (bullet and severity and version):
            return
        ref = (REF.findall("\n".join(bullet)) or [""])[-1]
        for kind, name in bullet_symbols(bullet):
            sym = Symbol(name, kind, severity, version, component, ref)
            old = out.get(name)
            if not old or (RANK[severity], vkey(version)) < (RANK[old.severity], vkey(old.version)):
                out[name] = sym

    for line in text.splitlines():
        h = re.match(r"^(#{2,4}) (.+)", line)
        if h:
            flush()
            bullet = []
            level, title = len(h.group(1)), h.group(2).strip()
            if level == 2:
                version = title if re.fullmatch(r"\d+\.\d+", title) and vkey(since) < vkey(title) <= vkey(until) else None
            elif level == 3:
                component = title
            else:
                severity = {"Removed": "removed", "Deprecated": "deprecated"}.get(title)
            continue
        if line.startswith("- "):
            flush()
            bullet = [line[2:]]
        elif bullet:
            bullet.append(line)
    flush()
    return out


def matcher(sym):
    """Regex for a call site or reference of a symbol in PHP code."""
    if sym.kind == "cfg":
        return re.compile(rf"\$CFG->{sym.name}\b")
    if sym.kind == "constant":
        return re.compile(rf"(?<![\w$>:]){sym.name}\b")
    if sym.kind == "function":
        return re.compile(rf"(?<![\w$>:\\])(?<!function )\\?{sym.name}\s*\(")
    if sym.kind == "method":
        cls, meth = sym.name.split("::")
        return re.compile(rf"(?<![\w\\])\\?{re.escape(cls)}::{meth}\s*\(|(?<![\w\\]){cls.split(chr(92))[-1]}::{meth}\s*\(")
    return re.compile(rf"(?<![\w\\])\\?{re.escape(sym.name)}\b")


def needs_use(sym):
    """Short-name matches of a namespaced method need a matching `use` line."""
    return sym.kind == "method" and "\\" in sym.name.split("::")[0]


def code_lines(text):
    """Line number and text of PHP lines that are not comments."""
    for n, line in enumerate(text.splitlines(), 1):
        s = line.lstrip()
        if not s.startswith(("//", "#", "*", "/*")):
            yield n, line


def scan(root, symbols):
    """Walk a plugin tree and return hits sorted by severity, file, line."""
    rules = [(s, matcher(s)) for s in symbols.values()]
    hits = []
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in (".git", "node_modules", "vendor"))
        for f in sorted(files):
            if not f.endswith(".php"):
                continue
            path = os.path.join(dirpath, f)
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            for sym, rx in rules:
                cls = sym.name.split("::")[0] if needs_use(sym) else None
                for n, line in code_lines(text):
                    m = rx.search(line)
                    if not m:
                        continue
                    if cls and not m.group(0).lstrip("\\").startswith(cls) and not re.search(
                            rf"^use \\?{re.escape(cls)}\s*;", text, re.M):
                        continue
                    hits.append({"file": os.path.relpath(path, root), "line": n, **asdict(sym)})
    hits.sort(key=lambda h: (RANK[h["severity"]], h["file"], h["line"]))
    return hits


def estimate(hits):
    """Rewrite hours: a fixed rate per removed and per deprecated hit."""
    return sum(HOURS[h["severity"]] for h in hits)


def render(hits, root):
    """Plain-text report: one line per hit, then a summary."""
    rows = [f"{h['severity']:<10} {h['file']}:{h['line']}  {h['name']}  ({h['version']} {h['component']} {h['ref']})".rstrip()
            for h in hits]
    r = sum(h["severity"] == "removed" for h in hits)
    rows.append(f"{os.path.basename(os.path.normpath(root))}: {len(hits)} hits · removed {r} · "
                f"deprecated {len(hits) - r} · estimate {estimate(hits):g} h")
    return "\n".join(rows)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("plugin", nargs="?", help="plugin directory to scan")
    p.add_argument("--upgrading", default=DEFAULT_UPGRADING, help="UPGRADING.md of the target release")
    p.add_argument("--from", dest="since", default="4.5", help="current site release (exclusive)")
    p.add_argument("--to", dest="until", default="5.3", help="target release (inclusive)")
    p.add_argument("--json", help="write hits and summary as JSON")
    p.add_argument("--symbols", action="store_true", help="print symbol counts per version and exit")
    a = p.parse_args(argv)
    with open(a.upgrading, encoding="utf-8") as fh:
        symbols = parse_upgrading(fh.read(), a.since, a.until)
    if a.symbols:
        counts = {}
        for s in symbols.values():
            counts.setdefault(s.version, {"removed": 0, "deprecated": 0})[s.severity] += 1
        for v in sorted(counts, key=vkey):
            print(f"{v}\tremoved {counts[v]['removed']}\tdeprecated {counts[v]['deprecated']}")
        return 0
    if not a.plugin:
        p.error("plugin directory required")
    hits = scan(a.plugin, symbols)
    print(render(hits, a.plugin))
    if a.json:
        with open(a.json, "w", encoding="utf-8") as fh:
            json.dump({"plugin": a.plugin, "hits": hits, "hours": estimate(hits)}, fh, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
