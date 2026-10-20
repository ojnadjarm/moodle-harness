#!/usr/bin/env python3
"""Add a table_sql report page to a plugin: classes/table/<name>.php, <page>.php page, lang strings, PHPUnit test."""

import argparse
import datetime
import re
import shutil
import sys
from pathlib import Path

from backup import read_tables
from external import NAME, php_lint
from generate import REQUIRES, TEMPLATES, TYPE_PATHS, default_copyright, fail, header, render
from task import add_string

TPL = TEMPLATES / "table"
TIMECOL = re.compile(r"^time([a-z]*(created|modified)|start|end|open|close|due)?$|^date$|(start|end|due|cutoff|from|_)date$")
CAPABILITY = re.compile(r"[a-z]+/[a-z0-9_]+:[a-z0-9_]+")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory with version.php")
    parser.add_argument("name", help="table class and page name (e.g. questions)")
    parser.add_argument("--table", required=True, help="database table without prefix (e.g. question)")
    parser.add_argument("--cols", required=True, help="comma-separated columns (e.g. id,name,timemodified)")
    parser.add_argument("--datecols", help="comma-separated --cols shown as dates; overrides the time*/*date name guess ('' = none)")
    parser.add_argument("--dynamic", action="store_true", help="AJAX table: implements core_table\\dynamic (4.0+)")
    parser.add_argument("--capability", default="moodle/site:config", help="capability for the page and AJAX loads; a bare name (view) means <type>/<name>:view")
    parser.add_argument("--context", choices=("system", "course"), default="system",
                        help="course: the page takes --param, require_login($course), checks the capability in the course "
                             "context and lists that course's rows; --table needs a courseid field in db/install.xml")
    parser.add_argument("--page", help="page file name without .php (default: the table name; e.g. index)")
    parser.add_argument("--param", help="course id URL parameter of the page (--context course only; default courseid; e.g. id)")
    args = parser.parse_args()

    plugin = Path(args.plugin).resolve()
    name, dbtable = args.name, args.table
    page, param = args.page or name, args.param or "courseid"
    if args.param is not None and args.context != "course":
        fail("--param needs --context course")
    cols = [c.strip() for c in args.cols.split(",") if c.strip()]
    for label, value in [("table name", name), ("--table", dbtable), ("--page", page), ("--param", param)] + [("column", c) for c in cols]:
        if not NAME.fullmatch(value):
            fail(f"bad {label} '{value}': use [a-z][a-z0-9_]*")
    if not cols or len(set(cols)) != len(cols):
        fail(f"bad --cols '{args.cols}': give distinct columns")
    if args.datecols is None:
        datecols = {c for c in cols if TIMECOL.search(c)}
    else:
        datecols = {c.strip() for c in args.datecols.split(",") if c.strip()}
        if not datecols <= set(cols):
            fail(f"bad --datecols '{args.datecols}': {', '.join(sorted(datecols - set(cols)))} not in --cols")
    if "fullname" in cols:
        fail("bad column 'fullname': it would use core col_fullname() (user names): rename or alias it")
    versionphp = plugin / "version.php"
    if not versionphp.is_file():
        fail(f"{plugin} has no version.php")
    vtext = versionphp.read_text()
    cmatch = re.search(r"^\$plugin->component\s*=\s*'([a-z0-9]+_[a-z0-9_]+)';", vtext, re.M)
    rmatch = re.search(r"^\$plugin->requires\s*=\s*(\d+);", vtext, re.M)
    if not cmatch or not rmatch:
        fail("version.php needs $plugin->component and $plugin->requires")
    component, requires = cmatch.group(1), int(rmatch.group(1))
    ptype, pname = component.split("_", 1)
    if ptype not in TYPE_PATHS:
        fail(f"unknown plugin type '{ptype}'")
    capability = args.capability if "/" in args.capability else f"{ptype}/{pname}:{args.capability}"
    if not CAPABILITY.fullmatch(capability):
        fail(f"bad --capability '{args.capability}': use <type>/<name>:<cap> or <cap>")
    if args.dynamic and requires < REQUIRES["4.0"]:
        fail(f"--dynamic needs $plugin->requires >= {REQUIRES['4.0']} (4.0), version.php has {requires}")

    classfile = plugin / "classes/table" / f"{name}.php"
    filtersetfile = plugin / "classes/table" / f"{name}_filterset.php"
    pagefile = plugin / f"{page}.php"
    testfile = plugin / "tests/table" / f"{name}_test.php"
    langphp = plugin / "lang/en" / f"{pname if ptype == 'mod' else component}.php"
    for path in (classfile, testfile) + ((filtersetfile,) if args.dynamic else ()):
        if path.exists():
            fail(f"{path} already exists")
    if not langphp.is_file():
        fail(f"{langphp} not found")
    lang = langphp.read_text()
    strings = {name: name.replace("_", " ").capitalize()}
    strings.update({f"{name}_{c}": re.sub(r"^time(?=.)", "time ", c).replace("_", " ").capitalize() for c in cols})
    for stringid in strings:
        if re.search(rf"""^\$string\[['"]{stringid}['"]\]""", lang, re.M):
            fail(f"string '{stringid}' already exists in {langphp}")

    seed = []
    if args.context == "course":
        installxml = plugin / "db/install.xml"
        tables = read_tables(installxml) if installxml.is_file() else {}
        if "courseid" not in tables.get(dbtable, ([],))[0]:
            fail(f"--context course needs a courseid field in table {dbtable} of {installxml}")
        names, types, _ = tables[dbtable]
        seed = [{"field": f, "value": "'x' . $i" if types[f] in ("char", "text") else "$i"}
                for f in names if f not in ("id", "courseid")]

    accessphp = plugin / "db/access.php"
    if capability.startswith(f"{ptype}/{pname}:") and (
            not accessphp.is_file() or f"'{capability}'" not in accessphp.read_text()):
        print(f"warning: {capability} is not defined in {accessphp}", file=sys.stderr)

    copyright = re.search(r"@copyright\s+(.+)", vtext)
    typepath = TYPE_PATHS[ptype]
    columns = [{"col": c, "stringid": f"{name}_{c}",
                "sample": "86400" if c in datecols else "'<b>x</b>'",
                "expected": "userdate(86400)" if c in datecols else "'&lt;b&gt;x&lt;/b&gt;'"} for c in cols]
    course = args.context == "course"
    ctx = {
        "component": component, "name": name, "dbtable": dbtable, "dynamic": args.dynamic,
        "capability": capability, "columns": columns,
        "timecols": [c for c in columns if c["col"] in datecols],
        "columnlist": ", ".join(f"'{c}'" for c in cols),
        "fields": ", ".join(cols if "id" in cols else ["id"] + cols),
        "legacy": requires < REQUIRES["4.5"],
        "namedargs": requires >= REQUIRES["4.2"], "positional": requires < REQUIRES["4.2"],
        "parent": "\\core_table\\sql_table" if requires >= REQUIRES["4.5"] else "\\table_sql",
        "implements": " implements \\core_table\\dynamic" if args.dynamic else "",
        "url": f"/{typepath}/{pname}/{page}.php", "param": param, "configpath": "/.." * (typepath.count("/") + 2) + "/config.php",
        "uniqueid": f"{component}-{name}", "title": strings[name],
        "course": course, "system": not course, "seed": seed,
        "plaincourse": course and not args.dynamic, "dynamiccourse": course and args.dynamic,
        "dynamicsystem": args.dynamic and not course,
        "pageargs": ", $course->id" if course and not args.dynamic else "",
        "formatargs": ", SITEID" if course and not args.dynamic else "",
        "filters": "$filters" if course else "[]",
        "copyright": copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year),
    }
    block = render((TPL / "block.php.tpl").read_text(), ctx)
    outputs = [(classfile, render((TPL / "class.php.tpl").read_text(), {**ctx, "header": header(f"{ctx['title']} table.", ctx)}))]
    if not pagefile.exists():
        outputs.append((pagefile, render((TPL / "page.php.tpl").read_text(),
                                          {**ctx, "block": block, "header": header(f"{ctx['title']} page.", ctx)})))
    elif f"new \\{component}\\table\\{name}(" not in pagefile.read_text():
        fail(f"{pagefile} already exists: merge this table block into it, then rerun:\n{block}"
             "echo $OUTPUT->header();\n$table->out(30, false);")
    outputs += [
        (testfile, render((TPL / "test.php.tpl").read_text(),
                          {**ctx, "header": header(f"Tests for the {name} table.", ctx)})),
    ]
    if args.dynamic:
        outputs.append((filtersetfile, render((TPL / "filterset.php.tpl").read_text(),
                                              {**ctx, "header": header(f"{ctx['title']} table filterset.", ctx)})))
    for stringid, value in strings.items():
        lang = add_string(lang, stringid, value)
    outputs.append((langphp, lang))
    if shutil.which("php"):
        for path, text in outputs:
            php_lint(path.relative_to(plugin), text)
    else:
        print("warning: php not on PATH: generated PHP is not linted", file=sys.stderr)

    for path, text in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(path)


if __name__ == "__main__":
    main()
