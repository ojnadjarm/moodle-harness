#!/usr/bin/env python3
"""Add an event to a plugin: classes/event/<name>.php + lang string (+ an event test and a trigger snippet without --observe, wired into a page with --emit-in), or with --observe alone only a handler; observer test (crud, edulevel, context from core), version bump."""

import argparse
import os
import datetime
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

from external import php_lint
from generate import TEMPLATES, default_copyright, fail, header, render
from hook import class_in_core, default_core, merge_hooks
from task import add_string

TPL = TEMPLATES / "event"
EVENTNAME = re.compile(r"[a-z][a-z0-9]*(?:_[a-z0-9]+)+")
OBSERVED = re.compile(r"\\?([a-z][a-z0-9_]*)\\event\\([a-z][a-z0-9]*(?:_[a-z0-9]+)+)")
EDULEVELS = {"teaching": "LEVEL_TEACHING", "participating": "LEVEL_PARTICIPATING", "other": "LEVEL_OTHER"}
LEVELS = {"level_other": 0, "level_teaching": 1, "level_participating": 2}
CONTEXTS = {
    "system": {"contextsetup": "$context = \\context_system::instance();", "contextinstanceid": "0", "courseid": "0"},
    "user": {"contextsetup": "$context = \\context_user::instance($user->id);", "contextinstanceid": "$user->id",
             "courseid": "0"},
    "coursecat": {"contextsetup": "$category = $this->getDataGenerator()->create_category();\n"
                                  "        $context = \\context_coursecat::instance($category->id);",
                  "contextinstanceid": "$category->id", "courseid": "0"},
    "course": {"contextsetup": "$course = $this->getDataGenerator()->create_course();\n"
                               "        $context = \\context_course::instance($course->id);",
               "contextinstanceid": "$course->id", "courseid": "$course->id"},
    "module": {"contextsetup": "$course = $this->getDataGenerator()->create_course();\n"
                               "        $cm = $this->getDataGenerator()->create_module('page', ['course' => $course->id]);\n"
                               "        $context = \\context_module::instance($cm->cmid);",
               "contextinstanceid": "$cm->cmid", "courseid": "$course->id"},
}


def read_plugin(plugin):
    """version.php text, its version match and the component."""
    versionphp = plugin / "version.php"
    if not versionphp.is_file():
        fail(f"{plugin} has no version.php")
    vtext = versionphp.read_text()
    vmatch = re.search(r"^\$plugin->version\s*=\s*(\d+);", vtext, re.M)
    cmatch = re.search(r"^\$plugin->component\s*=\s*'([a-z0-9]+_[a-z0-9_]+)';", vtext, re.M)
    if not vmatch or not cmatch:
        fail("version.php needs $plugin->version and $plugin->component")
    return vtext, vmatch, cmatch.group(1)


def table_fill(plugin, table):
    """PHP array tail filling the NOT NULL, no-default fields of an install.xml table besides id and userid."""
    installxml = plugin / "db/install.xml"
    if not installxml.is_file():
        fail(f"--table {table} needs {installxml}")
    node = ET.parse(installxml).find(f".//TABLE[@NAME='{table}']")
    if node is None:
        fail(f"table {table} not found in {installxml}")
    fields = node.findall("FIELDS/FIELD")
    if not any(f.get("NAME") == "userid" for f in fields):
        fail(f"table {table} has no userid field")
    fill = ""
    for field in fields:
        if field.get("NAME") in ("id", "userid") or field.get("NOTNULL") != "true" or field.get("DEFAULT") is not None:
            continue
        fill += f", '{field.get('NAME')}' => " + ("'x'" if field.get("TYPE") in ("char", "text", "binary") else "1")
    return fill


def create_calls(core, fqn, needle):
    """(file text, call offset, argument text) of each fqn::create() call outside tests in files mentioning needle."""
    ns, _, name = fqn.rpartition("\\")
    call = re.compile(rf"(?<![\w\\])(\\?[\w\\]*?){name}::create\s*\(")
    for dirpath, dirs, files in os.walk(core):
        dirs[:] = sorted(d for d in dirs if d not in (".git", "node_modules", "vendor", "tests"))
        for file in sorted(files):
            if not file.endswith(".php"):
                continue
            text = Path(dirpath, file).read_text(errors="replace")
            if f"{name}::create" not in text or needle not in text:
                continue
            for match in call.finditer(text):
                prefix = match.group(1)
                qualified = prefix.lstrip("\\") + name
                if prefix.startswith("\\") and qualified != fqn or not fqn.endswith(qualified) \
                        or not prefix and fqn not in text and not re.search(rf"^namespace \\?{re.escape(ns)};", text, re.M):
                    continue
                depth, end = 1, match.end()
                while depth and end < len(text):
                    depth += {"(": 1, ")": -1}.get(text[end], 0)
                    end += 1
                yield text, match.start(), text[match.end():end]


def created_with_relateduserid(core, fqn):
    """True when core code outside tests passes relateduserid to fqn::create()."""
    for text, start, args in create_calls(core, fqn, "relateduserid"):
        var = re.fullmatch(r"\s*\$(\w+)\s*\)", args)
        if "relateduserid" in args or var and re.search(
                rf"\${var[1]}\s*(?:\[\s*['\"]relateduserid|=\s*(?:\[|array\s*\()[^;]*relateduserid)",
                text[max(0, start - 3000):start]):
            return True
    return False


def class_chain(core, path):
    """Comment-free text of the event class and each parent in core up to base; None for an unreadable parent."""
    while True:
        text = re.sub(r"/\*.*?\*/|//[^\n]*", "", path.read_text(errors="replace"), flags=re.S)
        yield text
        parent = re.search(r"^[a-z ]*class\s+\w+\s+extends\s+(\\?[\w\\]+)", text, re.M)
        if not parent:
            return
        name = parent.group(1)
        if not name.startswith("\\"):
            head, _, tail = name.partition("\\")
            uses = {m[2] or m[1].rpartition("\\")[2]: m[1]
                    for m in re.finditer(r"^use\s+\\?([\w\\]+)(?:\s+as\s+(\w+))?;", text, re.M)}
            ns = re.search(r"^namespace\s+([\w\\]+);", text, re.M)
            name = uses[head] + (f"\\{tail}" if tail else "") if head in uses else f"{ns.group(1) if ns else ''}\\{name}"
        name = name.lstrip("\\")
        if name == "core\\event\\base":
            return
        path = class_in_core(core, name)
        if path is None:
            yield None
            return


def sets_relateduserid(core, path):
    """True when the event class or a parent in core sets relateduserid, None when a parent cannot be read."""
    for text in class_chain(core, path):
        if text is None:
            return None
        if "relateduserid" in text:
            return True
    return False


def core_fields(core, path, fqn):
    """crud, edulevel, objecttable and context level the core event sets in its class chain or ::create() callers."""
    found = {}
    patterns = {"crud": r"\$this->data\[\s*'crud'\s*\]\s*=\s*'([crud])'",
                "edulevel": r"\$this->data\[\s*'edulevel'\s*\]\s*=\s*(?:self|static)::(LEVEL_\w+)",
                "objecttable": r"\$this->data\[\s*'objecttable'\s*\]\s*=\s*'(\w+)'",
                "level": r"(?:\$this->context\s*=|'context'\s*=>)\s*\\?context_(\w+)::instance"
                         r"|contextlevel\s*!==?\s*CONTEXT_(\w+)"}
    for text in class_chain(core, path):
        for key, pattern in patterns.items():
            match = text and key not in found and re.search(pattern, text)
            if match:
                found[key] = next(g for g in match.groups() if g).lower()
    if "level" not in found:
        levels = Counter()
        for text, start, args in create_calls(core, fqn, "context"):
            arg = re.search(r"'context'\s*=>\s*(?:\\?context_(\w+)::instance|\$(\w+))", args)
            assigned = arg and arg[2] and re.findall(rf"\${arg[2]}\s*=\s*\\?context_(\w+)::instance", text[:start])
            if arg and (arg[1] or assigned):
                levels[arg[1] or assigned[-1]] += 1
        if levels:
            found["level"] = max(sorted(levels), key=levels.get)
        if len(levels) > 1:
            print(f"warning: {fqn} is created in several context levels in core ({', '.join(f'{k} {v}' for k, v in sorted(levels.items()))}): "
                  f"the test uses the most common, {found['level']}", file=sys.stderr)
    return found


def trigger_snippet(component, name, objectid, context="$context"):
    """One-line trigger() of the plugin event."""
    return f"\\{component}\\event\\{name}::create(['context' => {context}" + (
        ", 'objectid' => $objectid" if objectid else "") + "])->trigger();"


def wire_page(page, component, name, objectid):
    """Page text with the trigger after its require_capability(), else require_login(), and the $context/$objectid it uses."""
    text = page.read_text()
    for function in ("require_capability", "require_login"):
        match = re.search(rf"^([ \t]*){function}\s*\(", text, re.M)
        if match:
            break
    else:
        fail(f"{page} has no require_capability() or require_login(): nothing to put the trigger after")
    args, depth, end = [""], 1, match.end()
    while depth and end < len(text):
        char = text[end]
        depth += {"(": 1, "[": 1, ")": -1, "]": -1}.get(char, 0)
        if char == "," and depth == 1:
            args.append("")
        elif depth:
            args[-1] += char
        end += 1
    semicolon = re.match(r"\s*;", text[end:])
    if not semicolon:
        fail(f"{page}: {function}() is not a statement ending in ;")
    end += semicolon.end()
    indent = match.group(1)
    context = args[1].strip() if function == "require_capability" and len(args) > 1 else "$context"
    needed = (["context"] if context == "$context" and function == "require_login" else []) + (["objectid"] if objectid else [])
    for var in needed:
        assign = re.search(rf"^([ \t]*)\${var}\s*=(?![=>])", text, re.M)
        if not assign:
            fail(f"{page} never sets ${var}: the trigger needs it; set ${var} before {function}() and rerun")
        if assign.start() > match.start():
            depth, stop = 0, assign.end()
            while stop < len(text) and not (text[stop] == ";" and depth == 0):
                depth += {"(": 1, "[": 1, ")": -1, "]": -1}.get(text[stop], 0)
                stop += 1
            if stop + 1 > end:
                end, indent = stop + 1, assign.group(1)
    return text[:end] + "\n" + indent + trigger_snippet(component, name, objectid, context) + text[end:], function


def observer_outputs(plugin, ctx, core, force):
    """(path, text) for classes/observer.php, db/events.php and the observer test."""
    observed, method = ctx["observed"], ctx["methodname"]
    fields = {}
    if not core:
        print("warning: no core tree found: observed event not checked", file=sys.stderr)
    elif (path := class_in_core(core, observed)) is None:
        print(f"warning: {observed} not found in {core}", file=sys.stderr)
    else:
        fields = core_fields(core, path, observed)
        if "crud" not in fields or "edulevel" not in fields:
            print(f"warning: crud or edulevel of {observed} not read from {core}: the test restores crud 'r', edulevel 0",
                  file=sys.stderr)
        if fields.get("level") not in CONTEXTS:
            print(f"warning: context level of {observed} not read from {core}: the test restores it in a course context",
                  file=sys.stderr)
    if core and path and ctx["table"]:
        sets = sets_relateduserid(core, path)
        if not sets and created_with_relateduserid(core, observed):
            sets = True
        never = f"{observed} never sets relateduserid, in its class or a ::create() caller in core"
        if sets is False and not force:
            fail(f"--table: {never}: the handler would delete nothing (--force if it is set elsewhere)")
        if sets is False:
            print(f"warning: {never}", file=sys.stderr)
        if sets is None:
            print(f"warning: a parent class of {observed} not found: relateduserid not checked", file=sys.stderr)
    classfile, eventsphp = plugin / "classes/observer.php", plugin / "db/events.php"
    testfile = plugin / "tests/observer" / f"{ctx['name']}_test.php"
    if testfile.exists():
        fail(f"{testfile} already exists")
    classtext = classfile.read_text() if classfile.exists() else None
    if classtext and re.search(rf"function\s+{method}\s*\(", classtext):
        fail(f"{classfile} already has a method {method}()")
    eventstext = eventsphp.read_text() if eventsphp.exists() else None
    callback = rf"\\?{re.escape(ctx['component'])}\\+observer::{method}"
    if eventstext and re.search(rf"['\"]{callback}['\"]", eventstext):
        fail(f"{ctx['component']}\\observer::{method} is already registered in {eventsphp}")

    methodtext = render((TPL / "method.php.tpl").read_text(), ctx)
    if classtext is None:
        classtext = render((TPL / "observer.php.tpl").read_text(),
                           {**ctx, "method": methodtext, "header": header(f"Event observers for {ctx['component']}.", ctx)})
    else:
        end = classtext.rstrip().rfind("}")
        if end < 0:
            fail(f"{classfile}: no closing brace of class observer")
        classtext = classtext[:end].rstrip("\n") + "\n\n" + methodtext + classtext[end:]
    entry = render((TPL / "entry.php.tpl").read_text(), ctx)
    if eventstext is None:
        eventstext = render((TPL / "events.php.tpl").read_text(),
                            {**ctx, "entry": entry, "header": header("Event observers.", ctx)})
    else:
        eventstext = merge_hooks(eventstext, "observers", entry, eventsphp)
    level = fields.get("level") if fields.get("level") in CONTEXTS else "course"
    testtext = render((TPL / "observer_test.php.tpl").read_text(),
                      {**ctx, **CONTEXTS[level], "contextlevel": f"CONTEXT_{level.upper()}",
                       "observedcrud": fields.get("crud", "r"),
                       "observededulevel": LEVELS[fields["edulevel"]] if fields.get("edulevel") in LEVELS else 0,
                       "observedobjecttable": f"'{fields['objecttable']}'" if "objecttable" in fields else "null",
                       "header": header(f"Tests for the {method} observer.", ctx)})
    return [(classfile, classtext), (eventsphp, eventstext), (testfile, testtext)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory with version.php")
    parser.add_argument("name", help="event class <target>_<action> (e.g. item_synced)")
    parser.add_argument("--crud", choices=list("crud"), help="needed unless --observe without --emit")
    parser.add_argument("--edulevel", choices=EDULEVELS, help="needed unless --observe without --emit")
    parser.add_argument("--objecttable", help="table the event objectid points to")
    parser.add_argument("--observe", metavar="EVENT", help="observed event class; writes a handler stub for it")
    parser.add_argument("--emit", action="store_true", help="with --observe: the handler triggers this event instead")
    parser.add_argument("--table", help="with --observe: the handler deletes the related user's rows of this table")
    parser.add_argument("--force", action="store_true", help="with --table: warn instead of refusing an observed event that never sets relateduserid")
    parser.add_argument("--emit-in", metavar="PAGE", help="plugin page (e.g. index.php) to trigger the event in, after its "
                        "require_capability() or else require_login() and after the $context/$objectid the trigger uses "
                        "(refused when the page never sets them); alone it wires an existing event class")
    parser.add_argument("--core", help="Moodle code root to check --observe and read its crud, edulevel and context "
                        "(default: msrc tree of $plugin->requires, else newest non-Vass ~/moodle-envs)")
    args = parser.parse_args()

    plugin = Path(args.plugin).resolve()
    name = args.name
    if not EVENTNAME.fullmatch(name):
        fail(f"bad event name '{name}': use <target>_<action>, e.g. item_synced")
    if args.objecttable and not re.fullmatch(r"[a-z][a-z0-9_]*", args.objecttable):
        fail(f"bad --objecttable '{args.objecttable}'")
    if args.table and not re.fullmatch(r"[a-z][a-z0-9_]*", args.table):
        fail(f"bad --table '{args.table}'")
    if (args.emit or args.table) and not args.observe:
        fail("--emit and --table need --observe")
    if args.emit and args.table:
        fail("--table writes a handler stub: drop --emit")
    if args.observe and args.objecttable and not args.emit:
        fail("--objecttable with --observe needs --emit: a handler stub triggers no event")
    if args.emit_in and args.observe:
        fail("--emit-in wires the trigger() of an event, not an observer: drop --observe")
    observed = OBSERVED.fullmatch(args.observe) if args.observe else None
    if args.observe and not observed:
        fail(f"bad --observe '{args.observe}': use \\<component>\\event\\<target>_<action>")
    vtext, vmatch, component = read_plugin(plugin)
    ptype, pname = component.split("_", 1)
    classfile = plugin / "classes/event" / f"{name}.php"
    langphp = plugin / "lang/en" / f"{pname if ptype == 'mod' else component}.php"
    stringid = "event" + name.replace("_", "")
    wireonly = bool(args.emit_in) and classfile.exists()
    writeevent = (args.emit or not args.observe) and not wireonly
    ignored = [f"--{flag}" for flag in ("crud", "edulevel", "objecttable") if wireonly and getattr(args, flag)]
    if ignored:
        print(f"warning: {classfile.relative_to(plugin)} exists: {', '.join(ignored)} ignored, only the trigger is wired",
              file=sys.stderr)
    if writeevent and not (args.crud and args.edulevel):
        fail("an event class needs --crud and --edulevel")
    if writeevent and classfile.exists():
        fail(f"{classfile} already exists")
    eventtest = plugin / "tests/event" / f"{name}_test.php"
    if not args.observe and not wireonly and eventtest.exists():
        fail(f"{eventtest} already exists")
    if writeevent and not langphp.is_file():
        fail(f"{langphp} not found")
    lang = langphp.read_text() if writeevent else ""
    if re.search(rf"""^\$string\[['"]{stringid}['"]\]""", lang, re.M):
        fail(f"string '{stringid}' already exists in {langphp}")

    target, action = name.rsplit("_", 1)
    target = target.replace("_", " ")
    sentence = f"The user with id '{{$this->userid}}' {action} the {target}" + (
        " with id '{$this->objectid}'." if args.objecttable else ".")
    copyright = re.search(r"@copyright\s+(.+)", vtext)
    description = f"{target} {action}".capitalize()
    ctx = {"component": component, "name": name, "description": description, "stringid": stringid,
           "crud": args.crud, "edulevel": EDULEVELS.get(args.edulevel), "objecttable": args.objecttable or "",
           "sentence": sentence,
           "copyright": copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year)}
    outputs = [(classfile, render((TPL / "event.php.tpl").read_text(),
                                  {**ctx, "header": header(f"Event {name}.", ctx)})),
               (langphp, add_string(lang, stringid, description))] if writeevent else []
    objectid = bool(args.objecttable) or wireonly and "data['objecttable']" in classfile.read_text()
    snippet = trigger_snippet(component, name, objectid)
    if not args.observe and not wireonly:
        createparams = "['context' => $context" + (", 'objectid' => 42" if args.objecttable else "") + "]"
        outputs.append((eventtest, render((TPL / "event_test.php.tpl").read_text(),
                                          {**ctx, "createparams": createparams, "noobjecttable": not args.objecttable,
                                           "header": header(f"Tests for the {name} event.", ctx)})))
    wired = None
    if args.emit_in:
        page = (plugin / args.emit_in).resolve()
        if not page.is_file() or plugin not in page.parents:
            fail(f"--emit-in {args.emit_in}: no such page in {plugin}")
        if f"{name}::create(" in page.read_text():
            print(f"{page}: already triggers {name}")
        else:
            pagetext, wired = wire_page(page, component, name, objectid)
            outputs.append((page, pagetext))
    if observed:
        ocomp, oname = observed.groups()
        otarget, oaction = oname.rsplit("_", 1)
        ctx.update(observed=f"{ocomp}\\event\\{oname}", observedcomponent=ocomp, observedtarget=otarget,
                   observedaction=oaction, methodname=oname, emit=args.emit, handler=not args.emit,
                   table=args.table or "", notable=not args.table,
                   tablefill=table_fill(plugin, args.table) if args.table else "",
                   testname="observer_triggers_event" if args.emit else "observer_handles_event",
                   testdoc=f"The observer triggers {name} in the context of the observed event." if args.emit
                   else f"The handler runs on {oname} and reads its ids.",
                   observedobjectid=(42 if args.objecttable else "null") if args.emit else 7,
                   observedrelateduserid="null" if args.emit else "$user->id",
                   observeduserid="$other->id" if args.table else "$user->id")
        requires = re.search(r"^\$plugin->requires\s*=\s*(\d+);", vtext, re.M)
        core = Path(args.core).resolve() if args.core else default_core(requires and requires.group(1))
        if core and not core.is_dir():
            fail(f"core root {core} is not a directory")
        outputs += observer_outputs(plugin, ctx, core, args.force)
    if shutil.which("php"):
        for path, text in outputs:
            php_lint(path.relative_to(plugin), text)
    else:
        print("warning: php not on PATH: generated PHP is not linted", file=sys.stderr)

    for path, text in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(path)
    if not wireonly:
        version = max(int(datetime.date.today().strftime("%Y%m%d00")), int(vmatch.group(1)) + 1)
        versionphp = plugin / "version.php"
        versionphp.write_text(vtext[:vmatch.start(1)] + str(version) + vtext[vmatch.end(1):])
        print(f"{versionphp}: {vmatch.group(1)} -> {version}")
    if wired:
        print(f"wired: {args.emit_in} triggers {name} after its {wired}()")
    elif not args.observe:
        print(f"trigger: {snippet}")
    if observed:
        print(f"observer: \\{ctx['observed']} -> \\{component}\\observer::{ctx['methodname']}")
        if args.objecttable:
            print(f"note: the observer passes the observed event's objectid: set the {args.objecttable} row id")


if __name__ == "__main__":
    main()
