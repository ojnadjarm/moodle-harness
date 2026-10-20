#!/usr/bin/env python3
"""Turn a db/install.xml change into a db/upgrade.php step, a version bump and a savepoint."""

import argparse
import datetime
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from generate import TEMPLATES, default_copyright, fail, header, parse_field, render

FIELD_TYPES = {
    "int": "XMLDB_TYPE_INTEGER", "number": "XMLDB_TYPE_NUMBER", "float": "XMLDB_TYPE_FLOAT",
    "char": "XMLDB_TYPE_CHAR", "text": "XMLDB_TYPE_TEXT", "binary": "XMLDB_TYPE_BINARY",
    "datetime": "XMLDB_TYPE_DATETIME", "timestamp": "XMLDB_TYPE_TIMESTAMP",
}
NAME = re.compile(r"[a-z][a-z0-9_]*")
KEYNAME = re.compile(r"[a-z][a-z0-9_-]*")
KEY_TYPES = {
    "primary": "XMLDB_KEY_PRIMARY", "unique": "XMLDB_KEY_UNIQUE",
    "foreign": "XMLDB_KEY_FOREIGN", "foreign-unique": "XMLDB_KEY_FOREIGN_UNIQUE",
}


def parse_schema(text):
    """Map table name -> {'fields': [(name, attrs)], 'keys': {name: attrs}, 'indexes': {name: attrs}}."""
    if not text.strip():
        return {}
    tables = {}
    root = ET.fromstring(text)
    for node in root.iter():
        names = [node.get("NAME"), node.get("REFTABLE")] if node.tag in ("TABLE", "FIELD", "KEY", "INDEX") else []
        names += [n.strip() for a in ("FIELDS", "REFFIELDS") if node.get(a) for n in node.get(a).split(",")]
        for pos, name in enumerate(names):
            keyname = pos == 0 and node.tag in ("KEY", "INDEX")
            if name is not None and not (KEYNAME if keyname else NAME).fullmatch(name):
                fail(f"invalid {node.tag} name '{name}' in install.xml: use [a-z][a-z0-9_{'-' if keyname else ''}]*")
    for table in root.iter("TABLE"):
        tables[table.get("NAME")] = {
            "fields": [(f.get("NAME"), dict(f.attrib)) for f in table.iter("FIELD")],
            "keys": {k.get("NAME"): dict(k.attrib) for k in table.iter("KEY")},
            "indexes": {i.get("NAME"): dict(i.attrib) for i in table.iter("INDEX")},
        }
    return tables


def add_fields(text, specs):
    """Insert `table.field:type[:len]` FIELDs after each table's last field, keeping PREVIOUS/NEXT chains."""
    for spec in specs:
        table, dot, fspec = spec.partition(".")
        if not dot or not NAME.fullmatch(table):
            fail(f"bad --add-field '{spec}': use table.field[:type[:length]]")
        field = parse_field(fspec, table)
        if fspec.count(":") > 2:
            fail(f"bad --add-field '{spec}': use table.field[:type[:length]]")
        length = (fspec.split(":") + ["", ""])[2]
        if length and not re.fullmatch(r"\d+(,\d+)?", length):
            fail(f"bad --add-field '{spec}': length must be digits or digits,decimals")
        tmatch = re.search(rf'<TABLE\b[^>]*\bNAME="{table}"[^>]*>.*?</TABLE>', text, re.S)
        if not tmatch:
            fail(f"--add-field '{spec}': no table {table} in db/install.xml")
        fields = list(re.finditer(r'^([ \t]*)<FIELD\b[^>]*?\bNAME="([^"]*)"[^>]*?(\s*/>)', tmatch.group(0), re.M))
        if not fields:
            fail(f"--add-field '{spec}': table {table} has no FIELD to insert after")
        if any(f.group(2) == field["name"] for f in fields):
            fail(f"--add-field '{spec}': field {table}.{field['name']} already in db/install.xml")
        last = fields[-1]
        attrs = field["attrs"]
        tail = last.group(0)
        if any("PREVIOUS=" in f.group(0) or "NEXT=" in f.group(0) for f in fields):
            attrs += f' PREVIOUS="{last.group(2)}"'
            tail = tail[:last.start(3) - last.start()] + f' NEXT="{field["name"]}"' + last.group(3)
        new = f'{tail}\n{last.group(1)}<FIELD NAME="{field["name"]}" {attrs}/>'
        start, end = tmatch.start() + last.start(), tmatch.start() + last.end()
        text = text[:start] + new + text[end:]
    return text


def guarded(utext, sign, label):
    """True when upgrade.php already has this add or drop step (exists-guarded except keys)."""
    kind, _, name = label.partition(" ")
    table, _, item = name.partition(".")
    neg = "!" if sign == "+" else ""
    head = rf"new xmldb_table\(\s*'{re.escape(table)}'\s*\);"
    gap = r"(?:\s|//[^\n]*)*"
    if kind == "table":
        body = r"(?:(?!xmldb_table\().)*?"
        return re.search(rf"{head}{body}if \({re.escape(neg)}\$dbman->table_exists\(", utext, re.S) is not None
    item_re = rf"{head}{gap}\${kind} = new xmldb_{kind}\(\s*'{re.escape(item)}'[^;]*\);{gap}"
    if kind in ("field", "index"):
        return re.search(rf"{item_re}if \({re.escape(neg)}\$dbman->{kind}_exists\(", utext) is not None
    if kind == "key":
        return re.search(rf"{item_re}\$dbman->{'add' if sign == '+' else 'drop'}_key\(", utext) is not None
    return False


def q(value):
    """PHP single-quoted string literal."""
    return "'" + str(value).replace("\\", "\\\\").replace("'", "\\'") + "'"


def php_list(csv):
    return "[" + ", ".join(q(p.strip()) for p in csv.split(",")) + "]"


def field_php(attrs, previous=None, with_previous=True):
    length = attrs.get("LENGTH")
    if length and attrs.get("DECIMALS"):
        length = f"{length}, {attrs['DECIMALS']}"
    sequence = attrs.get("SEQUENCE") == "true"
    default = attrs.get("DEFAULT")
    parts = [FIELD_TYPES[attrs["TYPE"]], q(length) if length else "null", "null",
             "XMLDB_NOTNULL" if attrs.get("NOTNULL") == "true" else "null",
             "XMLDB_SEQUENCE" if sequence else "null",
             q(default) if default is not None and not sequence else "null"]
    if with_previous:
        parts.append(q(previous) if previous else "null")
    return ", ".join(parts)


def key_php(attrs):
    result = f"{KEY_TYPES[attrs['TYPE']]}, {php_list(attrs['FIELDS'])}"
    if attrs["TYPE"].startswith("foreign"):
        result += f", {q(attrs['REFTABLE'])}, {php_list(attrs['REFFIELDS'])}"
    return result


def index_php(attrs):
    unique = "XMLDB_INDEX_UNIQUE" if attrs.get("UNIQUE") == "true" else "XMLDB_INDEX_NOTUNIQUE"
    result = f"{unique}, {php_list(attrs['FIELDS'])}"
    if attrs.get("HINTS"):
        result += f", {php_list(attrs['HINTS'])}"
    return result


def diff(old, new):
    """Ordered ops (kind, label, php lines) plus hand-work warnings."""
    ops, warnings = [], []
    shared = [t for t in new if t in old]
    for t in shared:
        for name, attrs in old[t]["indexes"].items():
            if name not in new[t]["indexes"]:
                ops.append(("-", f"index {t}.{name}", [
                    f"// Define index {name} to be dropped from {t}.",
                    f"$table = new xmldb_table('{t}');",
                    f"$index = new xmldb_index('{name}', {index_php(attrs)});",
                    "if ($dbman->index_exists($table, $index)) {",
                    "    $dbman->drop_index($table, $index);", "}"]))
        for name, attrs in old[t]["keys"].items():
            if name not in new[t]["keys"]:
                ops.append(("-", f"key {t}.{name}", [
                    f"// Define key {name} to be dropped from {t}.",
                    f"$table = new xmldb_table('{t}');",
                    f"$key = new xmldb_key('{name}', {key_php(attrs)});",
                    "$dbman->drop_key($table, $key);"]))
    for t in shared:
        newfields = dict(new[t]["fields"])
        for name, attrs in old[t]["fields"]:
            if name not in newfields:
                ops.append(("-", f"field {t}.{name}", [
                    f"// Define field {name} to be dropped from {t}.",
                    f"$table = new xmldb_table('{t}');",
                    f"$field = new xmldb_field('{name}');",
                    "if ($dbman->field_exists($table, $field)) {",
                    "    $dbman->drop_field($table, $field);", "}"]))
    for t in old:
        if t not in new:
            ops.append(("-", f"table {t}", [
                f"// Define table {t} to be dropped.",
                f"$table = new xmldb_table('{t}');",
                "if ($dbman->table_exists($table)) {",
                "    $dbman->drop_table($table);", "}"]))
    for t, spec in new.items():
        if t in old:
            continue
        lines = [f"// Define table {t} to be created.", f"$table = new xmldb_table('{t}');"]
        lines += [f"$table->add_field('{n}', {field_php(a, with_previous=False)});" for n, a in spec["fields"]]
        lines += [f"$table->add_key('{n}', {key_php(a)});" for n, a in spec["keys"].items()]
        lines += [f"$table->add_index('{n}', {index_php(a)});" for n, a in spec["indexes"].items()]
        lines += ["if (!$dbman->table_exists($table)) {", "    $dbman->create_table($table);", "}"]
        ops.append(("+", f"table {t}", lines))
    for t in shared:
        oldfields = dict(old[t]["fields"])
        previous = None
        for name, attrs in new[t]["fields"]:
            if name not in oldfields:
                ops.append(("+", f"field {t}.{name}", [
                    f"// Define field {name} to be added to {t}.",
                    f"$table = new xmldb_table('{t}');",
                    f"$field = new xmldb_field('{name}', {field_php(attrs, previous)});",
                    "if (!$dbman->field_exists($table, $field)) {",
                    "    $dbman->add_field($table, $field);", "}"]))
            elif field_php(attrs, with_previous=False) != field_php(oldfields[name], with_previous=False):
                warnings.append(f"field {t}.{name} changed: write the change_field_* step by hand")
            previous = name
        for name, attrs in new[t]["keys"].items():
            if name not in old[t]["keys"]:
                ops.append(("+", f"key {t}.{name}", [
                    f"// Define key {name} to be added to {t}.",
                    f"$table = new xmldb_table('{t}');",
                    f"$key = new xmldb_key('{name}', {key_php(attrs)});",
                    "$dbman->add_key($table, $key);"]))
            elif key_php(attrs) != key_php(old[t]["keys"][name]):
                warnings.append(f"key {t}.{name} changed: write the drop/add step by hand")
        for name, attrs in new[t]["indexes"].items():
            if name not in old[t]["indexes"]:
                ops.append(("+", f"index {t}.{name}", [
                    f"// Define index {name} to be added to {t}.",
                    f"$table = new xmldb_table('{t}');",
                    f"$index = new xmldb_index('{name}', {index_php(attrs)});",
                    "if (!$dbman->index_exists($table, $index)) {",
                    "    $dbman->add_index($table, $index);", "}"]))
            elif index_php(attrs) != index_php(old[t]["indexes"][name]):
                warnings.append(f"index {t}.{name} changed: write the drop/add step by hand")
    return ops, warnings


def savepoint(component, version):
    ptype, pname = component.split("_", 1)
    if ptype in ("mod", "block"):
        return f"upgrade_{ptype}_savepoint(true, {version}, '{pname}');"
    return f"upgrade_plugin_savepoint(true, {version}, '{ptype}', '{pname}');"


def upgrade_block(ops, component, version):
    lines = [f"if ($oldversion < {version}) {{"]
    for _, _, php in ops:
        lines += [f"    {line}" for line in php] + [""]
    lines += [f"    // {component.split('_', 1)[1].capitalize()} savepoint reached.", f"    {savepoint(component, version)}", "}"]
    return "".join(f"    {line}\n" if line else "\n" for line in lines)


def git(plugin, *args):
    return subprocess.run(["git", "-C", str(plugin), *args], capture_output=True, text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory")
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--base", help="git ref to diff db/install.xml against (default HEAD)")
    source.add_argument("--base-file", type=Path, help="old install.xml to diff against (no git needed)")
    parser.add_argument("--add-field", action="append", default=[], metavar="T.F:TYPE[:LEN]",
                        help="add FIELD F to table T in install.xml first (repeatable; generate.py field grammar);"
                             " without --base/--base-file the step diffs against install.xml before the edit")
    parser.add_argument("--dry-run", action="store_true", help="print the schema diff only, write nothing")
    args = parser.parse_args()

    plugin = Path(args.plugin).resolve()
    installxml, versionphp, upgradephp = (plugin / "db/install.xml", plugin / "version.php",
                                          plugin / "db/upgrade.php")
    if not installxml.is_file() or not versionphp.is_file():
        fail(f"{plugin} needs db/install.xml and version.php")
    prefix = git(plugin, "rev-parse", "--show-prefix")
    current = installxml.read_text()
    if args.add_field and not args.base and not args.base_file:
        label, basetext = "db/install.xml before --add-field", current
    elif args.base_file:
        if not args.base_file.is_file():
            fail(f"--base-file {args.base_file} is not a file")
        label, basetext = str(args.base_file), args.base_file.read_text()
    elif prefix.returncode:
        print(f"error: {plugin} is not in a git repo: pass --base-file old-install.xml, or git init and commit"
              " to diff against --base (default HEAD)", file=sys.stderr)
        sys.exit(2)
    else:
        label = args.base or "HEAD"
        base = git(plugin, "show", f"{label}:{prefix.stdout.strip()}db/install.xml")
        if base.returncode and git(plugin, "rev-parse", "--verify", "-q", f"{label}^{{commit}}").returncode:
            fail(f"unknown git ref '{label}'")
        basetext = base.stdout if base.returncode == 0 else ""

    if args.add_field:
        current = add_fields(current, args.add_field)
    if basetext and basetext == current:
        fail(f"db/install.xml is unchanged against {label}: nothing to upgrade")
    try:
        ops, warnings = diff(parse_schema(basetext), parse_schema(current))
    except (ET.ParseError, KeyError) as exc:
        fail(f"cannot parse install.xml: {exc!r}")
    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    if not ops:
        fail(f"db/install.xml differs from {label} but has no table/field/key/index add or drop")
    if args.base_file and upgradephp.exists():
        utext = upgradephp.read_text()
        dupes = [f"{sign} {label}" for sign, label, _ in ops if guarded(utext, sign, label)]
        if dupes:
            fail(f"db/upgrade.php already has a guarded step for {', '.join(dupes)}: refresh --base-file")
    for sign, label, _ in ops:
        print(f"{sign} {label}")
    if args.dry_run:
        return

    vtext = versionphp.read_text()
    vmatch = re.search(r"^\$plugin->version\s*=\s*(\d+);", vtext, re.M)
    cmatch = re.search(r"^\$plugin->component\s*=\s*'([a-z0-9_]+)';", vtext, re.M)
    if not vmatch or not cmatch:
        fail("version.php needs $plugin->version and $plugin->component")
    headv = git(plugin, "show", f"HEAD:{prefix.stdout.strip()}version.php") if not prefix.returncode else None
    headvmatch = headv and re.search(r"^\$plugin->version\s*=\s*(\d+);", headv.stdout, re.M)
    if headvmatch and headvmatch.group(1) != vmatch.group(1):
        fail("version.php already bumped since HEAD (step generated?): commit first")
    component = cmatch.group(1)
    version = max(int(datetime.date.today().strftime("%Y%m%d00")), int(vmatch.group(1)) + 1)

    if upgradephp.exists():
        utext = upgradephp.read_text()
    else:
        copyright = re.search(r"@copyright\s+(.+)", vtext)
        ctx = {"component": component,
               "copyright": copyright.group(1).strip() if copyright else
               default_copyright(datetime.date.today().year)}
        utext = render((TEMPLATES / "upgrade.php.tpl").read_text(),
                       {**ctx, "header": header("Upgrade steps.", ctx)})
    func = re.search(rf"function xmldb_{component}_upgrade\([^)]*\)[^{{]*\{{\n", utext)
    close = re.compile(r"^\}", re.M).search(utext, func.end()) if func else None
    end = utext.rfind("\n    return true;\n", func.end() - 1, close.start()) if close else -1
    if end < 0:
        fail(f"db/upgrade.php has no xmldb_{component}_upgrade() ending in 'return true;'")
    block = upgrade_block(ops, component, version)
    utext = utext[:end + 1] + block + "\n" + utext[end + 1:]
    if "$dbman = $DB->get_manager();" not in utext:
        setup = ("" if "global $DB;" in utext else "    global $DB;\n") + "    $dbman = $DB->get_manager();\n\n"
        utext = utext[:func.end()] + setup + utext[func.end():]
    if shutil.which("php"):
        lint = subprocess.run(["php", "-l"], input=utext, capture_output=True, text=True)
        if lint.returncode:
            fail(f"generated db/upgrade.php does not parse, nothing written: {lint.stdout.strip()}")
    current, stamped = re.subn(r'(<XMLDB\b[^>]*?\bVERSION=")(\d+)(")',
                               lambda m: m.group(1) + str(version)[:max(8, len(m.group(2)))] + m.group(3),
                               current, count=1)
    if not stamped:
        print("warning: db/install.xml <XMLDB> has no numeric VERSION attribute: not stamped", file=sys.stderr)
    upgradephp.write_text(utext)
    versionphp.write_text(vtext[:vmatch.start(1)] + str(version) + vtext[vmatch.end(1):])
    installxml.write_text(current)
    print(f"{upgradephp}: step {version}\n{versionphp}: {vmatch.group(1)} -> {version}")


if __name__ == "__main__":
    main()
