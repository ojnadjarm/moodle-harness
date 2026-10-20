#!/usr/bin/env python3
"""Add a web service function to a plugin: classes/external/<name>.php, db/services.php entry, test, version bump."""

import argparse
import datetime
import re
import shutil
import subprocess
from pathlib import Path

from backup import read_tables
from generate import TEMPLATES, default_copyright, fail, header, render
import vphp

TPL = TEMPLATES / "external"
CORE_EXTERNAL = 2023042400
NAME = re.compile(r"[a-z][a-z0-9_]*")
RESERVED = {"context", "params", "this"}
PHPTOKEN = re.compile(r"""'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|(?://|#)[^\n]*|/\*.*?\*/|[][()]""", re.S)
TYPES = {
    "int": ("PARAM_INT", "int", "1"), "bool": ("PARAM_BOOL", "bool", "true"),
    "float": ("PARAM_FLOAT", "float", "1.5"), "text": ("PARAM_TEXT", "string", "'Example'"),
    "raw": ("PARAM_RAW", "string", "'Example'"), "notags": ("PARAM_NOTAGS", "string", "'Example'"),
    "alpha": ("PARAM_ALPHA", "string", "'abc'"), "alphanum": ("PARAM_ALPHANUM", "string", "'abc1'"),
    "alphanumext": ("PARAM_ALPHANUMEXT", "string", "'abc_1'"),
    "url": ("PARAM_URL", "string", "'https://example.com'"),
    "email": ("PARAM_EMAIL", "string", "'user@example.com'"),
}
CONTEXTS = {"cmid": "\\context_module::instance($params['cmid'])",
            "courseid": "\\context_course::instance($params['courseid'])",
            "contextid": "\\context::instance_by_id($params['contextid'])"}
XMLDB = {"int": ("PARAM_INT", "1", "2"), "number": ("PARAM_FLOAT", "1", "2"),
         "float": ("PARAM_FLOAT", "1", "2"), "char": ("PARAM_TEXT", "'a'", "'b'"),
         "text": ("PARAM_RAW", "'a'", "'b'"), "binary": ("PARAM_RAW", "'a'", "'b'")}
RETURNS = {
    "single": ("external_single_structure", "['status' => true]",
               "        return new external_single_structure([\n"
               "            'status' => new external_value(PARAM_BOOL, 'Whether the call succeeded'),\n"
               "        ]);"),
    "multiple": ("external_multiple_structure", "[]",
                 "        return new external_multiple_structure(\n"
                 "            new external_single_structure([\n"
                 "                'id' => new external_value(PARAM_INT, 'Record id'),\n"
                 "            ])\n"
                 "        );"),
}


def parse_params(spec):
    """'a:int,b:text' -> [(name, type)]."""
    params = []
    for item in filter(None, (p.strip() for p in (spec or "").split(","))):
        name, _, ptype = item.partition(":")
        if not NAME.fullmatch(name) or ptype not in TYPES:
            fail(f"bad param '{item}': use name:type, type one of {', '.join(TYPES)}")
        if name in RESERVED:
            fail(f"param '{name}' is reserved: execute() uses ${name}")
        if name in (n for n, _ in params):
            fail(f"duplicate param '{name}'")
        params.append((name, ptype))
    return params


def user_table(plugin, table, cols):
    """Field types of --table in db/install.xml; it needs a userid field and every --cols column."""
    installxml = plugin / "db/install.xml"
    if not installxml.is_file():
        fail(f"--table needs {installxml}")
    tables = read_tables(installxml)
    if table not in tables:
        fail(f"table '{table}' not in {installxml} (tables: {', '.join(tables) or '-'})")
    names, types, _ = tables[table]
    if "userid" not in names:
        fail(f"table '{table}' has no userid field: --table returns the current user's rows")
    missing = [c for c in cols if c not in names]
    if missing:
        fail(f"table '{table}' has no field {', '.join(missing)} (fields: {', '.join(names)})")
    return names, types


def table_context(table, cols, names, types):
    """Template values for execute() reading the user's rows of table and a test seeding one own, one other row."""
    fields = ["id"] + [c for c in cols if c != "id"]
    xmldb = {n: XMLDB.get(types[n], ("PARAM_RAW", "'a'", "'b'")) for n in names}
    own = {n: "$USER->id" if n == "userid" else xmldb[n][1] for n in names if n != "id"}
    other = {n: "$other->id" if n == "userid" else xmldb[n][2] for n in own}
    returns = "".join(f"                '{f}' => new external_value({xmldb[f][0]}, '{f.capitalize()}'),\n" for f in fields)
    asserts = "".join(f"        $this->assertEquals({'$ownid' if f == 'id' else own[f]}, $result[0]['{f}']);\n"
                      for f in fields)
    return {
        "table": table, "fields": ", ".join(fields), "result": "array_values($records)",
        "returnsdesc": ("        return new external_multiple_structure(\n            new external_single_structure([\n"
                        f"{returns}            ])\n        );"),
        "ownrow": "".join(f"            '{n}' => {v},\n" for n, v in own.items()),
        "otherrow": "".join(f"            '{n}' => {v},\n" for n, v in other.items()),
        "asserts": asserts,
    }


def test_setup(params, component):
    """Fixture lines and execute() arguments for the generated test."""
    ptype, pname = component.split("_", 1)
    names = [n for n, _ in params]
    setup = ["        $course = $this->getDataGenerator()->create_course();"] if {"cmid", "courseid"} & set(names) else []
    if "cmid" in names:
        module = pname if ptype == "mod" else "page"
        setup.append(f"        $cm = $this->getDataGenerator()->create_module('{module}', ['course' => $course->id]);")
    special = {"courseid": "$course->id", "cmid": "$cm->cmid", "contextid": "\\context_system::instance()->id"}
    args = [special.get(n) or TYPES[t][2] for n, t in params]
    return "".join(f"{line}\n" for line in setup), ", ".join(args)


def array_end(text, pos):
    """Index of the bracket closing the one opened at pos, skipping PHP strings and comments."""
    depth = 0
    for m in PHPTOKEN.finditer(text, pos):
        if m.group() in ("[", "("):
            depth += 1
        elif m.group() in ("]", ")"):
            depth -= 1
            if not depth:
                return m.start()
    return None


def merge_array(text, name, entry, path):
    """Insert entry into the $name array of an existing PHP file, in that array's [ or array( style."""
    start = re.search(rf"^[ \t]*\${name}\s*=\s*(\[|array\s*\()", text, re.M)
    if not start:
        if re.search(rf"^[ \t]*\${name}\b", text, re.M):
            fail(f"{path}: ${name} is set but not as a [ or array( literal: add the entry by hand")
        return text.rstrip("\n") + f"\n\n${name} = [\n{entry}];\n"
    if start.group(1) != "[":
        entry = entry.replace("[", "array(").replace("]", ")")
    close = array_end(text, start.end() - 1)
    if close is None:
        fail(f"{path}: cannot find the end of ${name}")
    return append_entry(text, start.end(), close, entry)


def append_entry(text, lo, close, entry):
    """Insert entry before the bracket at close, after the last element and its trailing comments."""
    comments = {m.end(): m.start() for m in PHPTOKEN.finditer(text, lo, close) if m.group()[0] in "/#"}
    pos = close
    while True:
        while pos > lo and text[pos - 1].isspace():
            pos -= 1
        if pos not in comments:
            break
        pos = comments[pos]
    sep = "" if text[pos - 1] in ",[(" else ","
    return text[:pos] + sep + text[pos:close].rstrip() + "\n" + entry + text[close:]


def add_mobile_service(text, key, path):
    """Add MOODLE_OFFICIAL_MOBILE_SERVICE to the 'services' of the key entry; None when already there."""
    start = re.search(rf"""['"]{key}['"]\s*=>\s*(\[|array\s*\()""", text)
    close = start and array_end(text, start.end() - 1)
    if not close:
        fail(f"{path}: cannot find the {key} entry")
    services = re.compile(r"""['"]services['"]\s*=>\s*(\[|array\s*\()""").search(text, start.end(), close)
    if not services:
        line = "        'services' => [MOODLE_OFFICIAL_MOBILE_SERVICE],\n"
        if start.group(1) != "[":
            line = line.replace("[", "array(").replace("]", ")")
        indent = text[text.rfind("\n", 0, close) + 1:close]
        return append_entry(text, start.end(), close, line + (indent if not indent.strip() else ""))
    end = array_end(text, services.end() - 1)
    if end is None:
        fail(f"{path}: cannot find the end of the {key} services")
    if "MOODLE_OFFICIAL_MOBILE_SERVICE" in text[services.end():end]:
        return None
    body = text[services.end():end].rstrip()
    sep = "" if not body.strip() else " " if body.endswith(",") else ", "
    return text[:services.end()] + body + sep + "MOODLE_OFFICIAL_MOBILE_SERVICE" + text[end:]


def php_lint(label, text):
    lint = subprocess.run(["php", "-l"], input=text, capture_output=True, text=True)
    if lint.returncode:
        fail(f"generated {label} does not parse, nothing written: {lint.stdout.strip()}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory with version.php")
    parser.add_argument("name", help="function name, verb_noun (e.g. get_items)")
    parser.add_argument("--params", help="comma list name:type, types: " + ", ".join(TYPES))
    parser.add_argument("--returns", choices=RETURNS, help="default single; multiple with --table")
    parser.add_argument("--type", choices=("read", "write"), help="default read for get_*, write otherwise")
    parser.add_argument("--ajax", action="store_true", help="allow AJAX calls from the web")
    parser.add_argument("--capability", help="full name or the plugin's own short name (view -> mod_x:view)")
    parser.add_argument("--table", help="install.xml table with a userid field: execute() returns the user's rows")
    parser.add_argument("--cols", help="comma-separated --table columns to return (id is always returned)")
    parser.add_argument("--mobile", action="store_true",
                        help="add the function to the Moodle app service (default when db/mobile.php exists); "
                             "on an existing function, adds only that")
    args = parser.parse_args()

    plugin = Path(args.plugin).resolve()
    if not NAME.fullmatch(args.name):
        fail(f"bad function name '{args.name}': use [a-z][a-z0-9_]*")
    info = vphp.read(plugin) or fail(f"{plugin} has no version.php")
    vtext = info["text"]
    if info["version"] is None or info["requires"] is None or not re.fullmatch(r"[a-z0-9]+_[a-z0-9_]+", info["component"] or ""):
        fail("version.php needs $plugin->version, $plugin->component and $plugin->requires")
    component, name = info["component"], args.name
    params = parse_params(args.params)
    if bool(args.table) != bool(args.cols):
        fail("--table and --cols go together")
    if args.table and args.returns == "single":
        fail("--table returns rows: use --returns multiple or leave it out")
    returns = args.returns or ("multiple" if args.table else "single")
    cols = [c.strip() for c in (args.cols or "").split(",") if c.strip()]
    if args.cols is not None and not cols:
        fail("--cols has no column names")
    if len(set(cols)) < len(cols):
        print(f"note: duplicate --cols dropped: {', '.join(sorted({c for c in cols if cols.count(c) > 1}))}")
        cols = list(dict.fromkeys(cols))
    if args.table:
        names, types = user_table(plugin, args.table, cols)

    classfile = plugin / "classes/external" / f"{name}.php"
    testfile = plugin / "tests/external" / f"{name}_test.php"
    servicesphp = plugin / "db/services.php"
    services = servicesphp.read_text() if servicesphp.exists() else None
    if services and re.search(rf"""['"]{component}_{name}['"]\s*=>""", services):
        if args.mobile:
            merged = add_mobile_service(services, f"{component}_{name}", servicesphp)
            if merged is None:
                print(f"{component}_{name} is already in MOODLE_OFFICIAL_MOBILE_SERVICE")
                return
            if shutil.which("php"):
                php_lint("db/services.php", merged)
            servicesphp.write_text(merged)
            print(servicesphp)
            old, new = vphp.bump(plugin, max(int(datetime.date.today().strftime("%Y%m%d00")), info["version"] + 1))
            print(f"{plugin / 'version.php'}: {old} -> {new}")
            return
        fail(f"{component}_{name} already exists in {servicesphp}")
    for path in (classfile, testfile):
        if path.exists():
            fail(f"{path} already exists")

    capability = args.capability
    if capability and "/" not in capability:
        capability = "{}/{}:{}".format(*component.split("_", 1), capability)
    if capability and capability.startswith(component.replace("_", "/", 1) + ":"):
        access = plugin / "db/access.php"
        if not access.exists() or f"'{capability}'" not in access.read_text():
            print(f"warning: {capability} is not defined in db/access.php")
    if not capability:
        print("warning: no --capability: add require_capability() by hand")

    legacy = info["requires"] < CORE_EXTERNAL
    returnclass, result, returnsdesc = RETURNS[returns]
    classes = ["external_api", "external_function_parameters"] + \
        (["external_multiple_structure"] if returns == "multiple" else []) + \
        ["external_single_structure", "external_value"]
    ns = "" if legacy else "core_external\\"
    copyright = re.search(r"@copyright\s+(.+)", vtext)
    description = name.replace("_", " ").capitalize()
    ctx = {
        "component": component, "name": name, "legacy": legacy, "description": description,
        "copyright": copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year),
        "uses": "".join(f"use {ns}{c};\n" for c in classes),
        "paramsdesc": "".join(f"            '{n}' => new external_value({TYPES[t][0]}, '{n.capitalize()}'),\n"
                              for n, t in params),
        "docparams": "".join(f"     * @param {TYPES[t][1]} ${n} {n.capitalize()}\n" for n, t in params),
        "signature": ", ".join(f"{TYPES[t][1]} ${n}" for n, t in params),
        "validate": "".join(f"            '{n}' => ${n},\n" for n, _ in params),
        "context": next((CONTEXTS[n] for n in CONTEXTS if n in dict(params)), "\\context_system::instance()"),
        "capability": capability or "", "result": result, "returnclass": returnclass, "returnsdesc": returnsdesc,
        "type": args.type or ("read" if name.startswith("get_") else "write"),
        "ajax": "true" if args.ajax else "false",
        "apiclass": "\\external_api" if legacy else "\\core_external\\external_api",
        "table": "", "notable": not args.table, "mobile": args.mobile or (plugin / "db/mobile.php").is_file(),
    }
    if args.table:
        ctx.update(table_context(args.table, cols, names, types))
    ctx["setup"], ctx["args"] = test_setup(params, component)

    classtext = render((TPL / "class.php.tpl").read_text(),
                       {**ctx, "header": header(f"External function {component}_{name}.", ctx)})
    testtext = render((TPL / "test.php.tpl").read_text(),
                      {**ctx, "header": header(f"Tests for the {component}_{name} external function.", ctx)})
    entry = render((TPL / "entry.php.tpl").read_text(), ctx)
    if services is None:
        services = render((TPL / "services.php.tpl").read_text(),
                          {**ctx, "entry": entry, "header": header("External functions and services.", ctx)})
    else:
        services = merge_array(services, "functions", entry, servicesphp)
    if shutil.which("php"):
        for label, text in (("class", classtext), ("test", testtext), ("db/services.php", services)):
            php_lint(label, text)
    else:
        print("warning: php not on PATH: generated PHP is not linted")

    version = max(int(datetime.date.today().strftime("%Y%m%d00")), info["version"] + 1)
    for path, text in ((classfile, classtext), (testfile, testtext), (servicesphp, services)):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(path)
    old, new = vphp.bump(plugin, version)
    print(f"{plugin / 'version.php'}: {old} -> {new}")


if __name__ == "__main__":
    main()
