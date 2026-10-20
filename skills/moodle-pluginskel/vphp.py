#!/usr/bin/env python3
"""Read and bump a plugin's version.php: decimal versions, both quote styles, commented lines ignored."""

import re
from pathlib import Path

TOKEN = re.compile(r"""'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|(?://|#)[^\r\n]*|/\*.*?\*/""", re.S)
FIELD = re.compile(r"""^[ \t]*\$plugin->(\w+)\s*=\s*(?:(\d+)(\.\d+)?|'((?:\\.|[^'\\])*)'|"((?:\\.|[^"\\])*)")\s*;""", re.M)


def _load(plugin):
    path = Path(plugin) / "version.php"
    if not path.is_file():
        return path, None
    with open(path, newline="") as handle:
        return path, handle.read()


def _fields(text):
    masked = TOKEN.sub(lambda m: m.group() if m.group()[0] in "'\"" else re.sub(r"[^\r\n]", " ", m.group()), text)
    return {m.group(1): m for m in FIELD.finditer(masked)}


def read(plugin):
    """Return component, version (int), decimal ('.NN' or ''), requires, release and text; None without version.php."""
    _, text = _load(plugin)
    if text is None:
        return None
    fields = _fields(text)

    def value(name, numeric=False):
        m = fields.get(name)
        if m is None or (numeric and m.group(2) is None):
            return None
        return int(m.group(2)) if numeric else next(g for g in m.group(2, 4, 5) if g is not None)

    version = fields.get("version")
    return {"component": value("component"), "version": value("version", True), "requires": value("requires", True),
            "decimal": (version.group(3) or "") if version else "", "release": value("release"), "text": text}


def bump(plugin, new):
    """Write version `new` in place (an int keeps a '.NN' decimal as zeros) and return (old, new) as written."""
    path, text = _load(plugin)
    m = _fields(text or "").get("version")
    if m is None or m.group(2) is None:
        raise ValueError(f"{path}: no numeric $plugin->version")
    decimal = m.group(3) or ""
    newtext = str(new) if isinstance(new, str) or not decimal else f"{new}.{'0' * (len(decimal) - 1)}"
    with open(path, "w", newline="") as handle:
        handle.write(text[:m.start(2)] + newtext + text[m.end(3) if decimal else m.end(2):])
    return m.group(2) + decimal, newtext
