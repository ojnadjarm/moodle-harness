#!/usr/bin/env python3
"""Render a Moodle plugin skeleton from a small YAML recipe."""

import argparse
import datetime
import re
import subprocess
import sys
from pathlib import Path
from xml.sax.saxutils import escape

import yaml

TEMPLATES = Path(__file__).parent / "templates"


def default_copyright(year):
    """Copyright line from git config user.name/email, else a generic placeholder."""
    try:
        name = subprocess.run(["git", "config", "user.name"], capture_output=True,
                               text=True, timeout=2).stdout.strip()
        email = subprocess.run(["git", "config", "user.email"], capture_output=True,
                                text=True, timeout=2).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        name = email = ""
    if name and email:
        return f"{year} onwards, {name} <{email}>"
    if name:
        return f"{year} onwards, {name}"
    return f"{year} onwards, plugin author"

TYPE_PATHS = {
    "mod": "mod", "block": "blocks", "local": "local", "tool": "admin/tool",
    "report": "report", "auth": "auth", "enrol": "enrol", "theme": "theme",
    "qtype": "question/type", "qbank": "question/bank", "format": "course/format",
    "filter": "filter", "repository": "repository", "message": "message/output",
    "atto": "lib/editor/atto/plugins", "tiny": "lib/editor/tiny/plugins",
    "availability": "availability/condition", "customfield": "customfield/field",
    "gradereport": "grade/report", "profilefield": "user/profile/field",
}

SETTINGS_CATEGORIES = {"tool": "tools", "report": "reports", "local": "localplugins"}

TYPE_FILES = {
    "mod": [("lib.php", "mod/lib.php", "Library of interface functions and constants."),
            ("mod_form.php", "mod/mod_form.php", "The main activity configuration form."),
            ("view.php", "mod/view.php", "Displays an activity instance."),
            ("index.php", "mod/index.php", "Lists all activity instances in a course.")],
    "block": [("block_{pluginname}.php", "block/block.php", "Block definition class.")],
    "report": [("lib.php", "report/lib.php", "Library functions of the report."),
               ("index.php", "report/index.php", "Displays the report for a course.")],
}

TYPE_CAPABILITIES = {
    "mod": [
        {"name": "addinstance", "title": "Add a new {name}", "captype": "write",
         "contextlevel": "CONTEXT_COURSE", "riskbitmask": "RISK_XSS",
         "clonepermissionsfrom": "moodle/course:manageactivities",
         "archetypes": [{"role": "editingteacher", "permission": "CAP_ALLOW"},
                        {"role": "manager", "permission": "CAP_ALLOW"}]},
        {"name": "view", "title": "View {name}", "contextlevel": "CONTEXT_MODULE",
         "archetypes": [{"role": r, "permission": "CAP_ALLOW"} for r in
                        ("guest", "student", "teacher", "editingteacher", "manager")]},
    ],
    "block": [
        {"name": "addinstance", "title": "Add a new {name} block", "captype": "write",
         "contextlevel": "CONTEXT_BLOCK", "riskbitmask": "RISK_SPAM | RISK_XSS",
         "clonepermissionsfrom": "moodle/site:manageblocks",
         "archetypes": [{"role": "editingteacher", "permission": "CAP_ALLOW"},
                        {"role": "manager", "permission": "CAP_ALLOW"}]},
        {"name": "myaddinstance", "title": "Add a new {name} block to the Dashboard",
         "captype": "write", "contextlevel": "CONTEXT_SYSTEM",
         "clonepermissionsfrom": "moodle/my:manageblocks",
         "archetypes": [{"role": "user", "permission": "CAP_ALLOW"}]},
    ],
}

MOD_TABLE = {
    "comment": "Instances of the {pluginname} activity",
    "fields": ["id", "course:int:10", "name:char:255", "intro:text", "introformat:int:4",
               "timemodified:int:10"],
    "keys": ["course->course.id"],
}

FIELD_TYPES = {"int": "10", "number": "10", "float": "", "char": "255", "text": "", "binary": ""}
NAME_RE = re.compile(r"[a-z][a-z0-9_]*")
DIGITS_RE = re.compile(r"[0-9]+")
PAGE_RE = re.compile(r"[a-z][a-z0-9_]*(?:/[a-z][a-z0-9_]*)*\.php")
MAX_LENGTH = {"int": 20, "number": 38, "float": 20, "char": 1333}
FIELD_NAME_MAX, TABLE_NAME_MAX = 63, 53

REQUIRES = {
    "4.0": 2022041900, "4.1": 2022112800, "4.2": 2023042400, "4.3": 2023100900,
    "4.4": 2024042200, "4.5": 2024100700, "5.0": 2025041400, "5.1": 2025100600,
    "5.2": 2026042000, "5.3": 2026100500,
}

GPL = """\
// This file is part of Moodle - https://moodle.org/
//
// Moodle is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Moodle is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Moodle.  If not, see <https://www.gnu.org/licenses/>."""

SECTION_RE = re.compile(r"[ \t]*\{\{#(\w+)\}\}[ \t]*\n(.*?)[ \t]*\{\{/\1\}\}[ \t]*\n", re.S)
VAR_RE = re.compile(r"\{\{(\w+)\}\}")


def render(template, ctx):
    def section(match):
        value = ctx[match.group(1)]
        if isinstance(value, list):
            return "".join(render(match.group(2), {**ctx, **item}) for item in value)
        return render(match.group(2), ctx) if value else ""

    def var(match):
        if match.group(1) not in ctx:
            fail(f"template variable '{match.group(1)}' missing from recipe context")
        return str(ctx[match.group(1)])

    return VAR_RE.sub(var, SECTION_RE.sub(section, template))


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def php_quote(text):
    return str(text).replace("\\", "\\\\").replace("'", "\\'")


def header(description, ctx):
    return (f"{GPL}\n\n/**\n * {description}\n *\n"
            f" * @package    {ctx['component']}\n"
            f" * @copyright  {ctx['copyright']}\n"
            f" * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later\n */")


def plural(word):
    """English plural: a single vowel + z doubles the z, es after s/x/z/ch/sh, else s."""
    if re.search(r"(?:^|[^aeiou]|qu)[aeiou]z$", word, re.I):
        word += word[-1]
    return word + ("es" if re.search(r"(?:[sxz]|[cs]h)$", word, re.I) else "s")


def xml_attr(text):
    return escape(str(text), {'"': "&quot;"})


def parse_field(spec, table):
    """XMLDB field from `name[:type[:length]]`; id is the sequence, int defaults 0, text may be null."""
    name, ftype, length = (str(spec).split(":") + ["", ""])[:3]
    if name == "id":
        return {"name": "id", "attrs": 'TYPE="int" LENGTH="10" NOTNULL="true" SEQUENCE="true"'}
    ftype = ftype or "int"
    if not NAME_RE.fullmatch(name) or ftype not in FIELD_TYPES:
        fail(f"table '{table}': bad field '{spec}' — use name[:type[:length]], "
             f"type one of {', '.join(FIELD_TYPES)}")
    if len(name) > FIELD_NAME_MAX:
        fail(f"table '{table}': field name '{name}' is {len(name)} chars, max {FIELD_NAME_MAX}")
    length, _, decimals = (length or FIELD_TYPES[ftype]).partition(",")
    if length and ftype not in MAX_LENGTH:
        fail(f"table '{table}': field '{spec}' — {ftype} takes no length")
    if length and not (DIGITS_RE.fullmatch(length) and 1 <= int(length) <= MAX_LENGTH[ftype]):
        fail(f"table '{table}': field '{spec}' — {ftype} length must be 1..{MAX_LENGTH[ftype]}")
    if decimals and not (ftype in ("number", "float") and length and DIGITS_RE.fullmatch(decimals)
                         and int(decimals) < int(length)):
        fail(f"table '{table}': field '{spec}' — decimals need number or float and must be below the length")
    length, decimals = (str(int(n)) if n else "" for n in (length, decimals))
    attrs = f'TYPE="{ftype}"' + (f' LENGTH="{length}"' if length else "")
    if ftype in ("text", "binary"):
        attrs += ' NOTNULL="false" SEQUENCE="false"'
    else:
        attrs += ' NOTNULL="true"' + (' DEFAULT="0"' if ftype != "char" else "") + ' SEQUENCE="false"'
    return {"name": name, "attrs": attrs + (f' DECIMALS="{decimals}"' if decimals else "")}


def build_tables(ptype, pname, recipe_tables):
    """XMLDB tables from recipe `tables:`; a mod_ instance table merges into the default one."""
    specs = {}
    if ptype == "mod":
        specs[pname] = {**MOD_TABLE, "comment": MOD_TABLE["comment"].format(pluginname=pname)}
    for tname, spec in (recipe_tables or {}).items():
        spec = spec or {}
        base = specs.get(tname, {})
        specs[tname] = {"comment": spec.get("comment", base.get("comment", f"{tname} table")),
                        "fields": (base.get("fields") or []) + (spec.get("fields") or []),
                        "keys": (base.get("keys") or []) + (spec.get("keys") or []),
                        "indexes": spec.get("indexes") or []}
    tables = []
    for tname, spec in specs.items():
        if not NAME_RE.fullmatch(tname):
            fail(f"bad table name '{tname}' — use [a-z][a-z0-9_]*")
        if len(tname) > TABLE_NAME_MAX:
            fail(f"table name '{tname}' is {len(tname)} chars, max {TABLE_NAME_MAX} (63 minus a 10-char prefix)")
        fields = {}
        for fspec in ["id"] + spec["fields"]:
            field = parse_field(fspec, tname)
            fields[field["name"]] = field
        keys = {"primary": {"name": "primary", "type": "primary", "fields": "id", "ref": ""}}
        for kspec in spec["keys"]:
            match = re.fullmatch(r"(\w+)->(\w+)\.(\w+)", str(kspec))
            if not match or match.group(1) not in fields:
                fail(f"table '{tname}': bad key '{kspec}' — use field->table.field on a listed field")
            field, reftable, reffield = match.groups()
            if field in keys or field == "id":
                fail(f"table '{tname}': second key on '{field}' — one key per field")
            keys[field] = {"name": field, "type": "foreign", "fields": field,
                           "ref": f' REFTABLE="{reftable}" REFFIELDS="{reffield}"'}
        indexes = []
        for ispec in spec.get("indexes") or []:
            unique = str(ispec).startswith("unique:")
            names = [c.strip() for c in str(ispec).removeprefix("unique:").split(",")]
            if not all(n in fields for n in names):
                fail(f"table '{tname}': bad index '{ispec}' — use [unique:]field[,field] on listed fields")
            if ", ".join(names) in {k["fields"] for k in keys.values()}:
                fail(f"table '{tname}': index '{ispec}' has the same fields as a key — "
                     f"Moodle refuses it (key collides with index); drop the index")
            indexes.append({"name": "-".join(names), "fields": ", ".join(names),
                            "unique": "true" if unique else "false"})
        tables.append({"name": tname, "comment": xml_attr(spec["comment"]),
                       "fields": list(fields.values()), "keys": list(keys.values()),
                       "indexes": indexes, "has_indexes": bool(indexes)})
    return tables


def build_block_list(ptype, spec, tables, lang_strings):
    """get_content() context from recipe `block: {table, link}`: the user's rows by userid, first char field shown."""
    if ptype != "block" or not isinstance(spec, dict) or set(spec) != {"table", "link"}:
        fail("'block:' needs a block_ component and exactly {table: <recipe table>, link: <page.php>}")
    table = next((t for t in tables if t["name"] == spec["table"]), None)
    if table is None:
        fail(f"block: table '{spec['table']}' is not in the recipe tables")
    names = [f["name"] for f in table["fields"]]
    field = next((f["name"] for f in table["fields"] if 'TYPE="char"' in f["attrs"]), None)
    if "userid" not in names or not field:
        fail(f"block: table '{spec['table']}' needs a userid field and a char field to list")
    if not PAGE_RE.fullmatch(str(spec["link"])):
        fail(f"block: bad link '{spec['link']}' — use a page.php path inside the plugin")
    if "viewall" not in {s["id"] for s in lang_strings}:
        lang_strings.append({"id": "viewall", "text": "View all"})
    return [{"table": table["name"], "field": field, "link": spec["link"]}]


def build_context(recipe):
    component = recipe.get("component") or fail("recipe needs a 'component'")
    if not re.fullmatch(r"[a-z][a-z0-9]*_[a-z][a-z0-9_]*", component):
        fail(f"'{component}' is not a valid frankenstyle component name")
    ptype, pname = component.split("_", 1)

    requires = recipe.get("requires", "4.5")
    if str(requires) in REQUIRES:
        requires = REQUIRES[str(requires)]
    elif not DIGITS_RE.fullmatch(str(requires)):
        fail(f"unknown 'requires' branch '{requires}' — use one of "
             f"{', '.join(REQUIRES)} or a raw version number")

    today = datetime.date.today()
    name = recipe.get("name", pname)
    ctx = {
        "component": component,
        "type": ptype,
        "pluginname": pname,
        "name": php_quote(recipe.get("name", pname)),
        "release": recipe.get("release", "0.1.0"),
        "version": f"{today:%Y%m%d}00",
        "xmldbversion": f"{today:%Y%m%d}",
        "requires": requires,
        "maturity": recipe.get("maturity", "MATURITY_ALPHA"),
        "copyright": recipe.get("copyright", default_copyright(today.year)),
        "features": recipe.get("features") or {},
        "privacy": (recipe.get("features") or {}).get("privacy", True),
        "lang_strings": [{"id": s["id"], "text": php_quote(s["text"])}
                         for s in recipe.get("lang_strings") or []],
        "capabilities": [], "phpunit_tests": [], "cli_scripts": [],
        "tables": build_tables(ptype, pname, recipe.get("tables")),
    }
    if ptype == "mod":
        ctx["lang_strings"][:0] = [
            {"id": "modulename", "text": php_quote(name)},
            {"id": "modulenameplural", "text": php_quote(recipe.get("name_plural", plural(name)))},
            {"id": "pluginadministration", "text": php_quote(f"{name} administration")}]
    ctx["block_list"] = (build_block_list(ptype, recipe["block"], ctx["tables"], ctx["lang_strings"])
                         if "block" in recipe else [])
    ctx["has_settings"] = bool(ctx["features"].get("settings"))
    caps = {cap["name"]: {**cap, "title": cap["title"].format(name=name)}
            for cap in TYPE_CAPABILITIES.get(ptype, [])}
    for cap in recipe.get("capabilities") or []:
        base = caps.get(cap["name"], {})
        merged = {**base, **cap}
        if base.get("archetypes") and cap.get("archetypes"):
            roles = {a["role"]: a for a in base["archetypes"]}
            roles.update({a["role"]: a for a in cap["archetypes"]})
            merged["archetypes"] = list(roles.values())
        caps[cap["name"]] = merged
    ctx["viewcap"] = f"report/{pname}:view" if "view" in caps else "moodle/site:viewreports"
    for cap in sorted(caps.values(), key=lambda c: c["name"]):
        ctx["capabilities"].append({
            "name": cap["name"],
            "title": php_quote(cap.get("title", cap["name"])),
            "captype": cap.get("captype", "read"),
            "contextlevel": cap.get("contextlevel", "CONTEXT_SYSTEM"),
            "riskbitmask": cap.get("riskbitmask", ""),
            "clonepermissionsfrom": cap.get("clonepermissionsfrom", ""),
            "archetypes": cap.get("archetypes")
                or [{"role": "manager", "permission": "CAP_ALLOW"}],
        })
    for test in recipe.get("phpunit_tests") or []:
        ctx["phpunit_tests"].append({"classname": test["classname"]})
    for script in recipe.get("cli_scripts") or []:
        ctx["cli_scripts"].append({"filename": script["filename"]})
    return ctx


def plan_files(ctx):
    features = ctx["features"]
    files = [("version.php", "version.php", "Plugin version and other metadata."),
             (f"lang/en/{ctx['pluginname'] if ctx['type'] == 'mod' else ctx['component']}.php",
              "lang.php", "Plugin strings are defined here.")]
    files += [(path.format(pluginname=ctx["pluginname"]), template, description)
              for path, template, description in TYPE_FILES.get(ctx["type"], [])]
    if ctx["tables"]:
        if ctx["type"] not in TYPE_PATHS:
            fail(f"tables need a known plugin type to place install.xml; "
                 f"'{ctx['type']}' is not in the type map")
        ctx["plugindir"] = f"{TYPE_PATHS[ctx['type']]}/{ctx['pluginname']}"
        ctx["xsdrel"] = "../" * (len(TYPE_PATHS[ctx["type"]].split("/")) + 2)
        files.append(("db/install.xml", "install.xml", ""))
    if ctx["privacy"]:
        files.append(("classes/privacy/provider.php", "privacy_provider.php",
                      "Privacy provider."))
    if ctx["capabilities"]:
        files.append(("db/access.php", "access.php", "Plugin capabilities are defined here."))
    if features.get("install"):
        files.append(("db/install.php", "install.php", "Code run after the plugin installation."))
    if features.get("upgrade"):
        files.append(("db/upgrade.php", "upgrade.php", "Plugin upgrade steps are defined here."))
    if features.get("settings"):
        ctx["settings_category"] = SETTINGS_CATEGORIES.get(ctx["type"], "")
        ctx["settings_own_page"] = bool(ctx["settings_category"])
        ctx["settings_fulltree"] = not ctx["settings_category"]
        if ctx["settings_fulltree"] and "generalsettings" not in {s["id"] for s in ctx["lang_strings"]}:
            ctx["lang_strings"].append({"id": "generalsettings", "text": "General settings"})
        files.append(("settings.php", "settings.php", "Plugin administration settings."))
    for test in ctx["phpunit_tests"]:
        files.append((f"tests/{test['classname']}_test.php", "test.php",
                      f"Tests for {ctx['component']}.", test))
    if ctx["cli_scripts"]:
        if ctx["type"] not in TYPE_PATHS:
            fail(f"cli_scripts need a known plugin type to locate config.php; "
                 f"'{ctx['type']}' is not in the type map")
        depth = len(TYPE_PATHS[ctx["type"]].split("/")) + 2
        ctx["configrel"] = "../" * depth
        for script in ctx["cli_scripts"]:
            files.append((f"cli/{script['filename']}.php", "cli.php",
                          "CLI script.", script))
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recipe", help="path to the YAML recipe")
    parser.add_argument("--target-dir", default=".",
                        help="directory to create the plugin folder in (default: cwd)")
    parser.add_argument("--list", action="store_true",
                        help="list the files that would be generated, without writing")
    args = parser.parse_args()

    try:
        recipe = yaml.safe_load(Path(args.recipe).read_text())
    except (OSError, yaml.YAMLError) as exc:
        fail(f"cannot read recipe: {exc}")
    ctx = build_context(recipe)
    files = plan_files(ctx)

    if args.list:
        for path, *_ in files:
            print(f"{ctx['pluginname']}/{path}")
        return

    root = Path(args.target_dir) / ctx["pluginname"]
    if root.exists():
        fail(f"target '{root}' already exists — never overwrites, generate elsewhere and merge")

    for path, template, description, *extra in files:
        file_ctx = {**ctx, **(extra[0] if extra else {})}
        file_ctx["header"] = header(description, ctx)
        content = render((TEMPLATES / f"{template}.tpl").read_text(), file_ctx)
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        print(target)


if __name__ == "__main__":
    main()
