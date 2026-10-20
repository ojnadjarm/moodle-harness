#!/usr/bin/env python3
"""Write the backup/restore API and its PHPUnit test from db/install.xml: a mod_ activity or local_ course data."""

import argparse
import datetime
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from generate import REQUIRES, TEMPLATES, default_copyright, fail, header, plural, render

FILES = [("backup_{p}_activity_task.class.php", "backup_activity_task.class.php",
          "Backup task for the {p} activity."),
         ("backup_{p}_stepslib.php", "backup_stepslib.php", "Backup steps for the {p} activity."),
         ("restore_{p}_activity_task.class.php", "restore_activity_task.class.php",
          "Restore task for the {p} activity."),
         ("restore_{p}_stepslib.php", "restore_stepslib.php", "Restore steps for the {p} activity.")]
PLUGIN_FILES = [("backup_{c}_plugin.class.php", "backup_plugin.class.php", "Backup of the {c} course data."),
                ("restore_{c}_plugin.class.php", "restore_plugin.class.php", "Restore of the {c} course data.")]
FLAG_RE = re.compile(r"(FEATURE_BACKUP_MOODLE2\s*(?::\s*return|=>)\s*)false\b")
SINGULAR_S = {"alias", "atlas", "bias", "canvas", "gas"}
INVARIANT = {"news", "series", "species"}
ROOTSET = {"id", "course", "name", "intro", "introformat", "timemodified"}


def read_tables(installxml):
    """Map table name -> (field names, field types, {field: reftable}) in install.xml order."""
    tables = {}
    for table in ET.parse(installxml).getroot().iter("TABLE"):
        fields = [(f.get("NAME"), f.get("TYPE")) for f in table.iter("FIELD")]
        fks = {}
        for key in table.iter("KEY"):
            if key.get("TYPE") in ("foreign", "foreign-unique") and "," not in key.get("FIELDS", ""):
                fks[key.get("FIELDS").strip()] = key.get("REFTABLE")
        tables[table.get("NAME")] = ([n for n, _ in fields], dict(fields), fks)
    return tables


def php_list(names):
    """Field names as quoted PHP array items, wrapped at 100 columns with 12-space indent."""
    lines, line = [], ""
    for item in (f"'{n}'," for n in names):
        if line and len(line) + 1 + len(item) > 88:
            lines.append(line)
            line = item
        else:
            line = f"{line} {item}" if line else item
    lines.append(line)
    return "\n".join(" " * 12 + text for text in lines)


def wrapper_name(elem):
    """Plural of an element name for its wrapper element (entry -> entries)."""
    return elem[:-1] + "ies" if re.search(r"[^aeiou]y$", elem) else plural(elem)


def is_user(field, fks):
    return field == "userid" or fks.get(field) == "user"


def decode_fields(names, types):
    """Text fields that have a <field>format sibling (editor content with links)."""
    return [n for n in names if types[n] == "text" and f"{n}format" in names]


def element_pair(name):
    """Element and wrapper names; a plural name is the wrapper of its singular (options -> option)."""
    last = name.rsplit("_", 1)[-1]
    if last in INVARIANT:
        return name, f"{name}items"
    if last not in SINGULAR_S and re.search(r"[^isu]s$", name):
        for single in (name[:-3] + "y", name[:-2], name[:-1]):
            if wrapper_name(single) == name:
                return single, name
    return name, wrapper_name(name)


def element_names(pluginname, table, used):
    """Element and wrapper names that are valid, unique PHP variables (fall back to the table name)."""
    elem = table[len(pluginname) + 1:] if table.startswith(pluginname + "_") else table
    if not re.fullmatch(r"[a-z_][a-z0-9_]*", elem):
        elem = table
    elem, wrapper = element_pair(elem)
    if elem in used:
        elem, wrapper = element_pair(table)
    if elem in used or wrapper in used or wrapper == elem:
        fail(f"table {table}: no free element name for {elem}/{wrapper}")
    used.update((elem, wrapper))
    return elem, wrapper


def sibling_order(tables, linked):
    """Child tables ordered so a referenced sibling comes first (install.xml order otherwise)."""
    order, pending = [], list(linked)
    while pending:
        ready = [t for t in pending if not any(r in pending and r != t for r in tables[t][2].values())]
        nxt = ready[0] if ready else pending[0]
        order.append(nxt)
        pending.remove(nxt)
    return order


def seed_value(field, ftype, ref, fks, pluginname, done):
    """PHP value for one seeded field: the instance, course, user or an earlier sibling row, else a literal."""
    if ref == pluginname:
        return "$instanceid"
    if is_user(field, fks):
        return "$user->id"
    if ref == "course":
        return "$course->id"
    if ref in done:
        return f"$ids['{ref}']"
    return "0" if ftype in ("int", "number", "float") else "'x'"


def seed_lines(values):
    return "\n".join(f"{' ' * 12}'{f}' => {v}," for f, v in values)


def test_context(pluginname, tables, children):
    """Seed values and asserts for tests/backup/backup_restore_test.php."""
    names, types, fks = tables[pluginname]
    rootusers = [f for f in names if f not in ROOTSET and is_user(f, fks)]
    root = [(f, seed_value(f, types[f], fks.get(f), fks, "", ())) for f in names if f not in ROOTSET]
    seeded, done = [], set()
    for child in children:
        cnames, ctypes, cfks = tables[child["table"]]
        values = [(f, seed_value(f, ctypes[f], cfks.get(f), cfks, pluginname, done)) for f in cnames if f != "id"]
        seeded.append({**child, "values": seed_lines(values)})
        done.add(child["table"])
    userasserts = [{"table": c["table"], "field": f, "parentfield": c["parentfield"]}
                   for c in children for f in c["users"]]
    return {"rootvalues": seed_lines(root) + "\n" if root else "", "children": seeded,
            "haschildren": bool(children),
            "rootusers": [{"field": f} for f in rootusers], "userasserts": userasserts,
            "hasusers": bool(rootusers or userasserts)}


def field_maps(tables, order, pos, gatedtables, skip, courseexpr, notes, parent=None):
    """Restore expressions for the fields of order[pos]; notes the references left to map by hand."""
    table = order[pos]
    names, _, fks = tables[table]
    maps = []
    for field in names:
        ref = fks.get(field)
        if field in skip:
            continue
        if is_user(field, fks):
            maps.append({"field": field, "expr": f"$this->get_mappingid('user', $data->{field})"})
        elif ref == "course":
            maps.append({"field": field, "expr": courseexpr})
        elif parent and ref == parent:
            maps.append({"field": field, "expr": f"$this->get_new_parentid('{parent}')"})
        elif ref in order:
            maps.append({"field": field, "expr": f"$this->get_mappingid('{ref}', $data->{field})"})
            where = f"{table}.{field} references"
            if ref == table:
                notes.append(f"{where} {table} itself: rows restored before their target get false; "
                             f"remap it in after_execute()")
            elif ref not in order[:pos]:
                notes.append(f"{where} {ref}, which is restored later (cycle): fix process_{table}()")
            if ref in gatedtables and table not in gatedtables:
                notes.append(f"{where} {ref}, which is restored only with user data: "
                             f"it is false without userinfo")
        elif ref in tables:
            notes.append(f"{table}.{field} references {ref}, which is not backed up: "
                         f"map it by hand in process_{table}()")
        elif ref:
            notes.append(f"{table}.{field} references {ref}: map it by hand in process_{table}()")
    return maps


def build_context(pluginname, component, tables, copyright):
    names, types, fks = tables[pluginname]
    root = [n for n in names if n not in ("id", "course")]
    notes = [f"{pluginname}.{f} references {ref}: map it by hand in process_{pluginname}()"
             for f, ref in fks.items() if f in root and not is_user(f, fks)]
    linked = [t for t, (_, _, cfks) in tables.items() if t != pluginname and pluginname in cfks.values()]
    skipped = [t for t in tables if t != pluginname and t not in linked]
    order = sibling_order(tables, linked)
    gatedtables = {t for t in linked if any(is_user(f, tables[t][2]) for f in tables[t][0])}
    children, used = [], {pluginname, "this", "userinfo"}
    for pos, table in enumerate(order):
        cnames, ctypes, cfks = tables[table]
        parentfield = next(f for f, ref in cfks.items() if ref == pluginname)
        elem, wrapper = element_names(pluginname, table, used)
        maps = field_maps(tables, order, pos, gatedtables, ("id", parentfield), "$this->get_courseid()", notes,
                          pluginname)
        users = [f for f in cnames if is_user(f, cfks)]
        children.append({"table": table, "elem": elem, "wrapper": wrapper, "parentfield": parentfield,
                         "fields": php_list([f for f in cnames if f not in ("id", parentfield)]),
                         "users": users, "maps": maps, "decode": decode_fields(cnames, ctypes)})
    rootusers = [f for f in root if is_user(f, fks)]
    gated = [c for c in children if c["users"]]
    annotations = [{"elem": pluginname, "field": f} for f in rootusers]
    annotations += [{"elem": c["elem"], "field": f} for c in children for f in c["users"]]
    decodes = [{"table": t, "fields": ", ".join(f"'{f}'" for f in fs)}
               for t, fs in [(pluginname, decode_fields(names, types))] + [(c["table"], c["decode"]) for c in children]
               if fs]
    ctx = {"component": component, "pluginname": pluginname, "rule": pluginname.upper(), "copyright": copyright,
           "rootfields": php_list(root), "children": children, "gated": gated,
           "ungated": [c for c in children if not c["users"]], "hasgated": bool(gated),
           "annotations": annotations, "hasannotations": bool(annotations), "hasintro": "intro" in names,
           "decodes": decodes,
           "rootmaps": [{"field": f, "expr": f"$this->get_mappingid('user', $data->{f}, 0)"} for f in rootusers]}
    return ctx, skipped, notes


def course_field(names, fks):
    """The field holding the course id: a foreign key to course, else courseid."""
    return next((f for f in names if fks.get(f) == "course"), "courseid" if "courseid" in names else None)


def plugin_context(component, tables, copyright):
    """Template context for a local_ plugin that backs up every table with a course field at course level."""
    linked = [t for t, (names, _, fks) in tables.items() if course_field(names, fks)]
    skipped = [t for t in tables if t not in linked]
    order = sibling_order(tables, linked)
    gatedtables = {t for t in linked if any(is_user(f, tables[t][2]) for f in tables[t][0])}
    children, notes, used = [], [], {"plugin", "wrapper", "userinfo", "this"}
    for pos, table in enumerate(order):
        names, types, fks = tables[table]
        coursefield = course_field(names, fks)
        elem, wrapper = element_names(component, table, used)
        maps = field_maps(tables, order, pos, gatedtables, ("id", coursefield), "$this->task->get_courseid()", notes)
        done = order[:pos]
        values = [(f, "$course->id" if f == coursefield else seed_value(f, types[f], fks.get(f), fks, "", done))
                  for f in names if f != "id"]
        children.append({"table": table, "elem": elem, "wrapper": wrapper, "coursefield": coursefield,
                         "fields": php_list([f for f in names if f not in ("id", coursefield)]),
                         "users": [f for f in names if is_user(f, fks)], "maps": maps,
                         "values": seed_lines(values)})
    gated = [c for c in children if c["users"]]
    ctx = {"component": component, "copyright": copyright, "children": children, "gated": gated,
           "ungated": [c for c in children if not c["users"]], "hasgated": bool(gated),
           "annotations": [{"elem": c["elem"], "field": f} for c in children for f in c["users"]],
           "hasusers": bool(gated),
           "userasserts": [{"table": c["table"], "field": f, "coursefield": c["coursefield"]}
                           for c in children for f in c["users"]]}
    return ctx, skipped, notes


def mod_outputs(plugin, component, tables, copyright, attributes, dry_run):
    """The 4 activity files and the test of a mod_; flips FEATURE_BACKUP_MOODLE2 in lib.php."""
    pluginname = component[4:]
    if pluginname not in tables:
        fail(f"{plugin / 'db/install.xml'} has no instance table '{pluginname}'")
    libphp = plugin / "lib.php"
    ctx, skipped, notes = build_context(pluginname, component, tables, copyright)
    libtext = libphp.read_text()
    newlib, flipped = FLAG_RE.subn(r"\1true", libtext)

    outputs = []
    for name, tpl, description in FILES:
        text = render((TEMPLATES / f"backup/{tpl}.tpl").read_text(),
                      {**ctx, "header": header(description.format(p=pluginname), ctx)})
        outputs.append((plugin / "backup/moodle2" / name.format(p=pluginname), text))
    tctx = {**ctx, **test_context(pluginname, tables, ctx["children"]), "attributes": attributes,
            "docblock": not attributes}
    text = render((TEMPLATES / "backup/backup_restore_test.php.tpl").read_text(),
                  {**tctx, "header": header(f"Backup and restore tests for {component}.", ctx)})
    outputs.append((plugin / "tests/backup/backup_restore_test.php", text))
    messages, first = [], []
    if flipped:
        if not dry_run:
            libphp.write_text(newlib)
        messages.append(f"{libphp}: FEATURE_BACKUP_MOODLE2 -> true")
    elif "FEATURE_BACKUP_MOODLE2" not in libtext:
        first.append(f"{libphp} has no FEATURE_BACKUP_MOODLE2 case: return true for it in {pluginname}_supports()")
    skipped = [f"table {t} has no foreign key to {pluginname}: not backed up" for t in skipped]
    return outputs, messages, first + skipped + notes


def local_outputs(plugin, component, tables, copyright, attributes):
    """The backup and restore plugin classes and the test of a local_ that keeps course rows."""
    ctx, skipped, notes = plugin_context(component, tables, copyright)
    if not ctx["children"]:
        fail(f"{plugin / 'db/install.xml'} has no table with a courseid field or a foreign key to course: "
             f"a local_ backup saves course data only")
    outputs = []
    for name, tpl, description in PLUGIN_FILES:
        text = render((TEMPLATES / f"backup/{tpl}.tpl").read_text(),
                      {**ctx, "header": header(description.format(c=component), ctx)})
        outputs.append((plugin / "backup/moodle2" / name.format(c=component), text))
    text = render((TEMPLATES / "backup/plugin_restore_test.php.tpl").read_text(),
                  {**ctx, "attributes": attributes, "docblock": not attributes,
                   "header": header(f"Backup and restore tests for {component}.", ctx)})
    outputs.append((plugin / "tests/backup/backup_restore_test.php", text))
    return outputs, [], [f"table {t} has no course field: not backed up" for t in skipped] + notes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="mod_ (version.php, lib.php, db/install.xml) or local_ plugin directory")
    parser.add_argument("--dry-run", action="store_true", help="print what would be written, write nothing")
    args = parser.parse_args()

    plugin = Path(args.plugin).resolve()
    versionphp = plugin / "version.php"
    if not versionphp.is_file():
        fail(f"{plugin} has no version.php")
    vtext = versionphp.read_text()
    cmatch = re.search(r"^\$plugin->component\s*=\s*['\"]([a-z0-9_]+)['\"];", vtext, re.M)
    if not cmatch:
        fail("version.php needs $plugin->component")
    component = cmatch.group(1)
    if component.startswith("block_"):
        fail(f"{component}: core never loads block_ plugin-level backup classes (no add_plugin_structure('block')); "
             f"backup.py writes mod_ and local_ backups only")
    ismod = component.startswith("mod_")
    if not ismod and not component.startswith("local_"):
        fail(f"{component} is not a mod_ or local_ plugin: backup.py writes activity and local_ course backups only")
    for path in (plugin / "backup", plugin / "tests/backup/backup_restore_test.php"):
        if path.exists():
            fail(f"{path} already exists: refusing to overwrite")
    installxml = plugin / "db/install.xml"
    for path in ((plugin / "lib.php", installxml) if ismod else (installxml,)):
        if not path.is_file():
            fail(f"{plugin} has no {path.relative_to(plugin)}")
    try:
        tables = read_tables(installxml)
    except ET.ParseError as error:
        fail(f"{installxml}: {error}")

    copyright = re.search(r"@copyright\s+(.+)", vtext)
    copyright = copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year)
    rmatch = re.search(r"^\$plugin->requires\s*=\s*(\d+);", vtext, re.M)
    attributes = bool(rmatch) and int(rmatch.group(1)) >= REQUIRES["5.0"]
    if ismod:
        outputs, messages, notes = mod_outputs(plugin, component, tables, copyright, attributes, args.dry_run)
    else:
        outputs, messages, notes = local_outputs(plugin, component, tables, copyright, attributes)
    for path, text in outputs:
        if not args.dry_run:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        print(path)
    for message in messages:
        print(message)
    for note in notes:
        print(f"note: {note}", file=sys.stderr)


if __name__ == "__main__":
    main()
