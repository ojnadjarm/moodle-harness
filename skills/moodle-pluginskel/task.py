#!/usr/bin/env python3
"""Add a scheduled or adhoc task to a plugin: classes/task/<name>.php, db/tasks.php entry, lang string, test."""

import argparse
import datetime
import re
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

from external import NAME, merge_array, php_lint
from generate import TEMPLATES, default_copyright, fail, header, render

TPL = TEMPLATES / "task"
CORE_TESTCASE_ADHOC = 2023100900
FIELDS = ("minute", "hour", "day", "month", "dayofweek")
RANGES = {"minute": (0, 59), "hour": (0, 23), "day": (1, 31), "month": (1, 12), "dayofweek": (0, 7)}
RANDOMFIELDS = ("minute", "hour", "dayofweek")
CRONFIELD = re.compile(r"[0-9*/,-]+")


def parse_cron(spec):
    """'<min> <hour> <day> <month> <dow>' -> {field: value}; R (random) only in minute, hour and dayofweek."""
    parts = spec.split()
    if len(parts) != 5:
        fail(f"bad --scheduled '{spec}': use \"<min> <hour> <day> <month> <dow>\"")
    for field, value in zip(FIELDS, parts):
        if not (CRONFIELD.fullmatch(value) or (value == "R" and field in RANDOMFIELDS)):
            fail(f"bad {field} '{value}' in --scheduled")
        low, high = RANGES[field]
        if any(not low <= int(n) <= high for n in re.findall(r"(?<![/0-9])[0-9]+", value)):
            fail(f"bad {field} '{value}' in --scheduled: values must be {low}-{high}")
    return dict(zip(FIELDS, parts))


def purge_target(plugin, spec):
    """'<table>.<timecol>' checked against db/install.xml -> (table, timecol, PHP fill for its other required fields)."""
    table, _, timecol = spec.partition(".")
    if not NAME.fullmatch(table) or not NAME.fullmatch(timecol):
        fail(f"bad --purge '{spec}': use <table>.<timecol>")
    installxml = plugin / "db/install.xml"
    if not installxml.is_file():
        fail(f"--purge needs {installxml}")
    node = ET.parse(installxml).find(f".//TABLE[@NAME='{table}']")
    if node is None:
        fail(f"table {table} not found in {installxml}")
    fields = {f.get("NAME"): f for f in node.findall("FIELDS/FIELD")}
    if fields.get(timecol) is None or fields[timecol].get("TYPE") != "int":
        fail(f"table {table} has no int field {timecol}")
    fill = ""
    for fname, field in fields.items():
        if fname in ("id", timecol) or field.get("NOTNULL") != "true" or field.get("DEFAULT") is not None:
            continue
        fill += f", '{fname}' => " + ("'x'" if field.get("TYPE") in ("char", "text", "binary") else "1")
    return table, timecol, fill


def add_string(text, stringid, value):
    """Insert $string[stringid] before the first later id, keeping the file sorted when it is."""
    line = f"$string['{stringid}'] = '{value}';\n"
    lines = text.splitlines(keepends=True)
    for i, current in enumerate(lines):
        m = re.match(r"\$string\['([^']+)'\]", current)
        if m and m.group(1) > stringid:
            return "".join(lines[:i] + [line] + lines[i:])
    return text.rstrip("\n") + "\n" + line


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory with version.php")
    parser.add_argument("name", help="task class name (e.g. send_reminders)")
    kind = parser.add_mutually_exclusive_group(required=True)
    kind.add_argument("--scheduled", metavar="CRON", help='default schedule "<min> <hour> <day> <month> <dow>"')
    kind.add_argument("--adhoc", action="store_true", help="queued task reading get_custom_data()")
    parser.add_argument("--purge", metavar="TABLE.TIMECOL",
                        help="with --scheduled: delete rows of an install.xml table whose TIMECOL is older than the retention")
    parser.add_argument("--setting", metavar="NAME",
                        help="with --purge: retention in seconds from get_config (0 keeps all); default 30 days")
    args = parser.parse_args()

    plugin = Path(args.plugin).resolve()
    name = args.name
    if not NAME.fullmatch(name):
        fail(f"bad task name '{name}': use [a-z][a-z0-9_]*")
    schedule = parse_cron(args.scheduled) if args.scheduled else None
    if args.purge and not schedule:
        fail("--purge needs --scheduled")
    if args.setting is not None and not args.purge:
        fail("--setting needs --purge")
    if args.setting is not None and not NAME.fullmatch(args.setting):
        fail(f"bad --setting '{args.setting}': use [a-z][a-z0-9_]*")
    table, timecol, fill = purge_target(plugin, args.purge) if args.purge else ("", "", "")
    versionphp = plugin / "version.php"
    if not versionphp.is_file():
        fail(f"{plugin} has no version.php")
    vtext = versionphp.read_text()
    vmatch = re.search(r"^\$plugin->version\s*=\s*(\d+);", vtext, re.M)
    cmatch = re.search(r"^\$plugin->component\s*=\s*'([a-z0-9]+_[a-z0-9_]+)';", vtext, re.M)
    rmatch = re.search(r"^\$plugin->requires\s*=\s*(\d+);", vtext, re.M)
    if not vmatch or not cmatch or not rmatch:
        fail("version.php needs $plugin->version, $plugin->component and $plugin->requires")
    component = cmatch.group(1)
    ptype, pname = component.split("_", 1)

    classfile = plugin / "classes/task" / f"{name}.php"
    testfile = plugin / "tests/task" / f"{name}_test.php"
    tasksphp = plugin / "db/tasks.php"
    langphp = plugin / "lang/en" / f"{pname if ptype == 'mod' else component}.php"
    stringid = f"task_{name}"
    for path in (classfile, testfile):
        if path.exists():
            fail(f"{path} already exists")
    if not langphp.is_file():
        fail(f"{langphp} not found")
    lang = langphp.read_text()
    if re.search(rf"""^\$string\[['"]{stringid}['"]\]""", lang, re.M):
        fail(f"string '{stringid}' already exists in {langphp}")
    tasks = tasksphp.read_text() if schedule and tasksphp.exists() else None
    if tasks and re.search(rf"""['"]\\?{component}\\+task\\+{name}['"]""", tasks):
        fail(f"{component}\\task\\{name} already exists in {tasksphp}")

    copyright = re.search(r"@copyright\s+(.+)", vtext)
    description = name.replace("_", " ").capitalize()
    ctx = {
        "component": component, "name": name, "description": description, "stringid": stringid,
        "copyright": copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year),
        "runadhoc": "$this->run_all_adhoc_tasks();" if int(rmatch.group(1)) >= CORE_TESTCASE_ADHOC
                    else "\\phpunit_util::run_all_adhoc_tasks();",
        "purge": bool(table), "plain": not table, "table": table, "timecol": timecol, "fill": fill,
        "setting": args.setting or "", "nosetting": not args.setting,
        **(schedule or {}),
    }
    label = "scheduled" if schedule else "adhoc"
    classtext = render((TPL / f"{label}.php.tpl").read_text(),
                       {**ctx, "header": header(f"{description} {label} task.", ctx)})
    testtext = render((TPL / f"{label}_test.php.tpl").read_text(),
                      {**ctx, "header": header(f"Tests for the {name} {label} task.", ctx)})
    outputs = [(classfile, classtext), (testfile, testtext), (langphp, add_string(lang, stringid, description))]
    if schedule:
        entry = render((TPL / "entry.php.tpl").read_text(), ctx)
        if tasks is None:
            tasks = render((TPL / "tasks.php.tpl").read_text(),
                           {**ctx, "entry": entry, "header": header("Scheduled task definitions.", ctx)})
        else:
            tasks = merge_array(tasks, "tasks", entry, tasksphp)
        outputs.append((tasksphp, tasks))
    if shutil.which("php"):
        for path, text in outputs:
            php_lint(path.relative_to(plugin), text)
    else:
        print("warning: php not on PATH: generated PHP is not linted")

    for path, text in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(path)
    if schedule:
        version = max(int(datetime.date.today().strftime("%Y%m%d00")), int(vmatch.group(1)) + 1)
        versionphp.write_text(vtext[:vmatch.start(1)] + str(version) + vtext[vmatch.end(1):])
        print(f"{versionphp}: {vmatch.group(1)} -> {version}")


if __name__ == "__main__":
    main()
