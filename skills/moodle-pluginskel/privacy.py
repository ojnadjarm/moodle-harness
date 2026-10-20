#!/usr/bin/env python3
"""Replace a plugin's null privacy provider with a real one and its PHPUnit test, from the user fields of db/install.xml."""

import argparse
import datetime
import re
import sys
import textwrap
import xml.etree.ElementTree as ET
from collections import deque
from pathlib import Path

from backup import read_tables
from generate import TEMPLATES, default_copyright, fail, header, render
import vphp

FIELD_TEXT = {"userid": "The ID of the user", "usermodified": "The ID of the user who last changed the record",
              "timecreated": "The time the record was created", "timemodified": "The time the record was changed"}
STRING_RE = re.compile(r"""^\$string\[\s*['"]([^'"]+)['"]\s*\]""")


def user_fields(names, fks):
    """Fields holding a user ID: userid, usermodified or a foreign key to user."""
    return [n for n in names if n in ("userid", "usermodified") or fks.get(n) == "user"]


def course_field(names, fks):
    """The field holding a course ID (courseid or a foreign key to course), None when absent."""
    return next((n for n in names if n == "courseid" or fks.get(n) == "course"), None)


def join_path(tables, start, target):
    """Shortest foreign-key chain [(table, field, reftable)] from start to target, None when unreachable."""
    seen, queue = {start}, deque([(start, [])])
    while queue:
        table, path = queue.popleft()
        if table == target:
            return path
        for field, ref in tables[table][2].items():
            if ref in tables and ref not in seen:
                seen.add(ref)
                queue.append((ref, path + [(table, field, ref)]))
    return None


def module_joins(path, instance):
    """JOIN lines from course_modules (cm) along a foreign-key chain to the user table as alias t, and each table's alias."""
    if not path:
        return [f"JOIN {{{instance}}} t ON t.id = cm.instance"], {instance: "t"}
    aliases = [f"j{i}" for i in range(len(path))] + ["t"]
    joins, names = [f"JOIN {{{instance}}} j0 ON j0.id = cm.instance"], {instance: "j0"}
    for i, (table, field, _) in enumerate(reversed(path)):
        joins.append(f"JOIN {{{table}}} {aliases[i + 1]} ON {aliases[i + 1]}.{field} = {aliases[i]}.id")
        names[table] = aliases[i + 1]
    return joins, names


def php_pairs(items):
    return ", ".join(f"'{key}' => {value}" for key, value in items.items())


def unique_fields(installxml):
    """Map table name -> field lists of its unique keys and unique indexes in install.xml."""
    found = {}
    for table in ET.parse(installxml).getroot().iter("TABLE"):
        for item in [*table.iter("KEY"), *table.iter("INDEX")]:
            if item.get("TYPE") in ("unique", "foreign-unique") or item.get("UNIQUE") == "true":
                found.setdefault(table.get("NAME"), []).append([f.strip() for f in item.get("FIELDS", "").split(",")])
    return found


def cycle_edges(tables, roots, skip):
    """Foreign keys [(table, field)] not in skip that close a reference cycle among the plugin tables reachable from roots."""
    visited, path, back = set(), [], []

    def visit(table):
        visited.add(table)
        path.append(table)
        for field, ref in tables[table][2].items():
            if ref not in tables or ref == table or (table, field) in skip:
                continue
            if ref in path:
                back.append((table, field))
            elif ref not in visited:
                visit(ref)
        path.pop()

    for root in roots:
        if root not in visited:
            visit(root)
    return back


def seed_rows(tables, roots, uniques, instance):
    """PHP ROWS entries seeding the root tables and the plugin tables they reference, and notes on broken cycles."""
    fixed = {(instance, f) for f, ref in tables[instance][2].items() if ref in tables} if instance else set()
    cycles = cycle_edges(tables, roots, fixed)
    notes = [f"foreign-key cycle at {t}.{f}: provider_test leaves it as the generator sets it"
             for t, f in sorted(fixed) if join_path(tables, tables[t][2][f], t)]
    notes += [f"foreign-key cycle at {t}.{f}: provider_test seeds it as a plain value" for t, f in cycles]
    cut = fixed | set(cycles)
    order, todo = [], list(roots)
    while todo:
        table = todo.pop(0)
        if table not in order:
            order.append(table)
            todo += [ref for f, ref in tables[table][2].items()
                     if ref in tables and ref != table and (table, f) not in cut]
    entries = []
    for table in order:
        names, types, fks = tables[table]
        users = user_fields(names, fks)
        refs = {n: "'user'" if n in users else f"'{fks[n]}'" for n in names
                if n in users or (fks.get(n) in tables and fks[n] != table and (table, n) not in cut)}
        values = {n: "'x'" if types[n] in ("char", "text") else "0" for n in names
                  if n != "id" and n not in refs and table != instance}
        unique = [f"'{n}'" for n in values if any(n in key for key in uniques.get(table, ()))]
        notes += [f"unique key {table}({', '.join(key)}) holds only the instance: provider_test setUp inserts one row "
                  f"per user for the one instance and collides, seed it by hand"
                  for key in uniques.get(table, ()) if instance and all(fks.get(n) == instance for n in key)]
        entries.append(f"        '{table}' => [\n            'refs' => [{php_pairs(refs)}],\n"
                       f"            'values' => [{php_pairs(values)}],\n"
                       f"            'unique' => [{', '.join(unique)}],\n        ],")
    return "\n".join(entries), notes


def php_strings(items, indent):
    return "\n".join(f"{' ' * indent}'{item}'," for item in items)


def build(component, tables, copyright, uniques):
    """Template context, lang strings and notes for the user tables of a plugin."""
    ptype, pname = component.split("_", 1)
    module = ptype == "mod"
    usertables = {t: user_fields(names, fks) for t, (names, _, fks) in tables.items() if user_fields(names, fks)}
    owners = {t: [f for f in fields if f != "usermodified"] for t, fields in usertables.items()
              if not (module and t == pname)}
    courses = {} if module else {t: course_field(names, fks) for t, (names, _, fks) in tables.items()
                                 if course_field(names, fks)}
    course = any(t in courses for t in usertables)
    strings, metadata, entries, notes, cascaded, seeded = {}, [], [], [], {}, []
    for table, fields in usertables.items():
        names = [n for n in tables[table][0] if n != "id"]
        strings[f"privacy:metadata:{table}"] = f"Records of the {table} table linked to users"
        for name in names:
            strings[f"privacy:metadata:{table}:{name}"] = FIELD_TEXT.get(name, f"The {name} field")
        items = "\n".join(f"            '{n}' => 'privacy:metadata:{table}:{n}'," for n in names)
        metadata.append(f"        $collection->add_database_table('{table}', [\n{items}\n"
                        f"        ], 'privacy:metadata:{table}');")
        columns = [f"t.{f}" for f in owners.get(table, [])]
        modifiers = [f for f in fields if f not in owners.get(table, [])]
        entry = [f"        '{table}' => ["]
        depth = 0
        if module:
            path = join_path(tables, table, pname) if pname in tables else None
            if path is None:
                notes.append(f"table {table} has no foreign-key path to {pname}: declared in get_metadata only, "
                             f"export and delete it by hand")
                continue
            depth = len(path)
            joins, aliases = module_joins(path, pname)
            parents = [p for p in aliases if p != table and owners.get(p)]
            cascaded[table] = set(parents)
            columns += [f"{aliases[p]}.{f}" for p in parents for f in owners[p]]
            entry += ["            'joins' => [", php_strings(joins, 16), "            ],"]
        if course:
            entry.append(f"            'course' => {repr(courses[table]) if table in courses else 'null'},")
        entry += [f"            'fields' => [{', '.join(repr(f) for f in fields)}],",
                  f"            'owners' => [{', '.join(repr(c) for c in columns)}],",
                  f"            'modifiers' => [{', '.join(repr(f) for f in modifiers)}],", "        ],"]
        entries.append((-depth, len(entries), "\n".join(entry)))
        seeded.append(table)
    for table, (_, _, fks) in tables.items():
        for field, ref in fks.items():
            if owners.get(ref) and ref not in cascaded.get(table, ()):
                notes.append(f"{table}.{field} references user table {ref}: its rows are orphaned when {ref} rows "
                             f"are deleted")
    rows, cyclenotes = seed_rows(tables, seeded, uniques, pname if module and pname in tables else None)
    notes += cyclenotes
    if module and seeded and all(t == pname for t in seeded):
        notes.append(f"only {pname} holds user fields: user2 owns no row, provider_test fails until a user table "
                     f"is added")
    notes += [f"{t} rows with {courses[t]} 0 or a deleted course match no context: never reported, exported or deleted"
              for t in seeded if t in courses]
    ctx = {"component": component, "pluginname": pname, "copyright": copyright, "module": module,
           "system": not module and not course, "course": course,
           "coursesystem": course and any(t not in courses for t in seeded),
           "metadata": "\n".join(metadata),
           "tables": textwrap.indent("\n".join(e for *_, e in sorted(entries)), "    "),
           "tablesdoc": ("joins from course_modules to alias t, " if module else "")
           + ("course field (null: system), " if course else "")
           + "user fields, owners (rows deleted), modifiers (set to 0)",
           "contextclass": "\\context_module" if module else "\\context" if course else "\\context_system",
           "instancearg": "$context->instanceid" if module else "$context" if course else "",
           "ctxarg": "$context->instanceid, " if module else "$context, " if course else "",
           "cmparam": "int $cmid, " if module else "\\context $context, " if course else "",
           "cmarg": "$cmid, " if module else "$context, " if course else "",
           "scopedoc": " in one course module" if module else " in one context" if course else "",
           "metadatacount": len(metadata), "rows": rows, "courses": php_pairs({t: repr(f) for t, f in courses.items()})}
    return ctx, strings, notes


def merge_lang(text, strings):
    """Drop the null provider's privacy:metadata string; add new ids before the first larger existing id."""
    lines = [ln for ln in text.splitlines(keepends=True) if not re.match(r"""\$string\[\s*['"]privacy:metadata['"]""", ln)]
    existing = {m.group(1) for ln in lines if (m := STRING_RE.match(ln))}
    for sid, value in sorted(strings.items()):
        if sid in existing:
            continue
        new = f"$string['{sid}'] = '{value}';\n"
        pos = next((i for i, ln in enumerate(lines) if (m := STRING_RE.match(ln)) and m.group(1) > sid), None)
        if pos is None:
            if lines and not lines[-1].endswith("\n"):
                lines[-1] += "\n"
            lines.append(new)
        else:
            lines.insert(pos, new)
    return "".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory (holds version.php, lang/en, db/install.xml)")
    parser.add_argument("--dry-run", action="store_true", help="print what would be written, write nothing")
    args = parser.parse_args()

    plugin = Path(args.plugin).resolve()
    info = vphp.read(plugin) or fail(f"{plugin} has no version.php")
    vtext = info["text"]
    if not re.fullmatch(r"[a-z0-9]+_[a-z0-9_]+", info["component"] or ""):
        fail("version.php needs $plugin->component")
    component = info["component"]
    provider = plugin / "classes/privacy/provider.php"
    if provider.is_file() and "null_provider" not in provider.read_text():
        fail(f"{provider} is not a null provider: refusing to overwrite")
    installxml = plugin / "db/install.xml"
    try:
        tables = read_tables(installxml) if installxml.is_file() else {}
        uniques = unique_fields(installxml) if installxml.is_file() else {}
    except ET.ParseError as error:
        fail(f"{installxml}: {error}")
    if not any(user_fields(names, fks) for names, _, fks in tables.values()):
        print(f"no user tables in {installxml.relative_to(plugin)}: null provider kept")
        return
    pname = component.split("_", 1)[1]
    langphp = plugin / "lang/en" / f"{pname if component.startswith('mod_') else component}.php"
    if not langphp.is_file():
        fail(f"{plugin} has no {langphp.relative_to(plugin)}")

    copyright = re.search(r"@copyright\s+(.+)", vtext)
    copyright = copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year)
    ctx, strings, notes = build(component, tables, copyright, uniques)
    text = render((TEMPLATES / "privacy/provider.php.tpl").read_text(),
                  {**ctx, "header": header("Privacy provider.", ctx)})
    lang = merge_lang(langphp.read_text(), strings)
    outputs = [(provider, text), (langphp, lang)]
    test = plugin / "tests/privacy/provider_test.php"
    if test.exists():
        print(f"kept {test}")
    else:
        outputs.append((test, render((TEMPLATES / "privacy/provider_test.php.tpl").read_text(),
                                     {**ctx, "header": header("Tests for the privacy provider.", ctx)})))
    generator = plugin / "tests/generator/lib.php"
    if ctx["module"] and not generator.exists():
        outputs.append((generator, render((TEMPLATES / "behat/generator.php.tpl").read_text(),
                                          {**ctx, "header": header(f"Data generator for {component}.", ctx)})))
    for path, content in outputs:
        if not args.dry_run:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        print(path)
    for note in notes:
        print(f"note: {note}", file=sys.stderr)


if __name__ == "__main__":
    main()
