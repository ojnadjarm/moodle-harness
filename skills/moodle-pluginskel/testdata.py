#!/usr/bin/env python3
"""Scaffold a plugin's manual-test fixture: setup.php, reset.php, rows.php and testing-instructions.md."""

import argparse
import datetime
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from backup import read_tables
from generate import TEMPLATES, default_copyright, fail, header, render
from privacy import seed_rows, unique_fields
import vphp

FILES = [("setup.php", "Idempotent manual-test data for {component}: run it again to repair or extend."),
         ("reset.php", "Return the {component} manual-test scenario to its start state."),
         ("rows.php", "Rows of the {component} tables that setup.php seeds and reset.php deletes."),
         ("testing-instructions.md", "")]
PASSWORD = "Testdata1!"


def git(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True)


def exclude(target):
    """Add target to the repo's .git/info/exclude; return the line, or None outside git."""
    top = git(target, "rev-parse", "--show-toplevel")
    if top.returncode:
        return None
    line = "/" + target.relative_to(Path(top.stdout.strip()).resolve()).as_posix() + "/"
    path = Path(git(target, "rev-parse", "--path-format=absolute", "--git-path", "info/exclude").stdout.strip())
    current = path.read_text() if path.exists() else ""
    if line not in current.splitlines():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(current + ("" if not current or current.endswith("\n") else "\n") + line + "\n")
    return line


def unique_keys(installxml):
    """Map table name -> field lists of its unique keys and unique indexes."""
    found = {}
    for table in ET.parse(installxml).getroot().iter("TABLE"):
        for item in [*table.iter("KEY"), *table.iter("INDEX")]:
            if item.get("TYPE") in ("unique", "foreign-unique") or item.get("UNIQUE") == "true":
                found.setdefault(table.get("NAME"), []).append([f.strip() for f in item.get("FIELDS", "").split(",")])
    return found


def spec(tables, uniques, keys):
    """PHP array of the seed rows of every install.xml table, one indent level deep, and notes on broken cycles."""
    rows, notes = seed_rows(tables, list(tables), uniques, None)
    rows = re.sub(r"(?m)^        '(\w+)' => \[\n((?:            .*\n)*)",
                  lambda m: m.group(0) + "            'keys' => [" + ", ".join(
                      "[" + ", ".join(f"'{f}'" for f in key) + "]" for key in keys.get(m.group(1), [])) + "],\n", rows)
    return ("[\n" + re.sub(r"(?m)^    ", "", rows) + "\n]" if rows else "[]"), notes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory (holds version.php)")
    parser.add_argument("--dir", default=".research/testdata",
                        help="fixture directory, relative to the plugin (default .research/testdata)")
    parser.add_argument("--rows", type=int, default=5,
                        help="marked rows setup.php inserts per db/install.xml table (default 5)")
    args = parser.parse_args()
    if args.rows < 1:
        fail("--rows needs at least 1")

    plugin = Path(args.plugin).resolve()
    info = vphp.read(plugin) or fail(f"{plugin} has no version.php")
    vtext = info["text"]
    if not re.fullmatch(r"[a-z0-9]+_[a-z0-9_]+", info["component"] or ""):
        fail("version.php needs $plugin->component")
    target = (plugin / args.dir).resolve()
    existing = [name for name, _ in FILES if (target / name).exists()]
    if existing:
        fail(f"{target} already has {', '.join(existing)}: refusing to overwrite")

    installxml = plugin / "db/install.xml"
    try:
        tables = read_tables(installxml) if installxml.is_file() else {}
        uniques = unique_fields(installxml) if installxml.is_file() else {}
        keys = unique_keys(installxml) if installxml.is_file() else {}
    except ET.ParseError as error:
        fail(f"{installxml}: {error}")

    component = info["component"]
    pname = component.split("_", 1)[1]
    module = component.startswith("mod_") and pname in tables
    fields = {"user": "$student->id", "course": "$course->id", "courseid": "$course->id"}
    if module:
        fields.update({pname: "$instance->instance", f"{pname}id": "$instance->instance"})
    rows, notes = spec(tables, uniques, keys)
    copyright = re.search(r"@copyright\s+(.+)", vtext)
    ctx = {"component": component, "prefix": f"{component}_testdata", "shortname": f"{component}_testdata",
           "password": PASSWORD, "dir": Path(args.dir).as_posix(), "rows": args.rows, "spec": rows,
           "module": module, "system": not module, "pluginname": pname,
           "fields": ", ".join(f"'{k}' => {v}" for k, v in fields.items()),
           "copyright": copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year)}
    ctx["configphp"] = (TEMPLATES / "testdata/config.php.tpl").read_text().rstrip("\n")
    target.mkdir(parents=True, exist_ok=True)
    for name, description in FILES:
        text = render((TEMPLATES / f"testdata/{name}.tpl").read_text(),
                      {**ctx, "header": header(description.format(component=component), ctx)})
        (target / name).write_text(text)
        print(target / name)
    for table, (names, types, _) in tables.items():
        if not (module and table == pname) and not any(types[n] in ("char", "text") for n in names):
            notes.append(f"table {table} has no char or text column to mark: setup.php seeds no rows")
    for note in notes:
        print(f"note: {note}", file=sys.stderr)
    line = exclude(target)
    if line:
        print(f".git/info/exclude: {line}")


if __name__ == "__main__":
    main()
