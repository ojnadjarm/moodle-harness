#!/usr/bin/env python3
"""Add a message provider to a plugin: db/messages.php entry, lang string, notifier send method, sink test, version bump."""

import argparse
import datetime
import re
import shutil
from pathlib import Path

from external import NAME, merge_array, php_lint
from generate import TEMPLATES, default_copyright, fail, header, render
from task import add_string
import vphp

TPL = TEMPLATES / "message"
PROCESSORS = ("popup", "email", "airnotifier")
CAPABILITY = re.compile(r"[a-z]+/[a-z][a-z0-9_]*:[a-z][a-z0-9_]*")


def add_method(text, method, path):
    """Insert method before the closing brace of the file's class."""
    end = text.rstrip().rfind("}")
    if end < 0 or not re.search(r"^(?:final\s+)?class\s+\w+", text, re.M):
        fail(f"{path}: no class to add the method to")
    return text[:end].rstrip("\n") + "\n\n" + method + text[end:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory with version.php")
    parser.add_argument("name", help="message provider name (e.g. grade_released)")
    parser.add_argument("--capability", help="capability a recipient needs: full name or the plugin's own short name "
                                             "(receive -> mod/x:receive)")
    parser.add_argument("--defaults", default="popup,email",
                        help=f"processors enabled by default, from {', '.join(PROCESSORS)} (default popup,email)")
    args = parser.parse_args()

    plugin = Path(args.plugin).resolve()
    name = args.name
    if not NAME.fullmatch(name):
        fail(f"bad provider name '{name}': use [a-z][a-z0-9_]*")
    defaults = [p.strip() for p in args.defaults.split(",") if p.strip()]
    if not defaults or any(p not in PROCESSORS for p in defaults):
        fail(f"bad --defaults '{args.defaults}': use a comma list from {', '.join(PROCESSORS)}")
    info = vphp.read(plugin) or fail(f"{plugin} has no version.php")
    if info["version"] is None or not re.fullmatch(r"[a-z0-9]+_[a-z0-9_]+", info["component"] or ""):
        fail("version.php needs $plugin->version and $plugin->component")
    component = info["component"]
    ptype, pname = component.split("_", 1)
    capability = args.capability
    if capability and "/" not in capability:
        capability = f"{ptype}/{pname}:{capability}"
    if capability and not CAPABILITY.fullmatch(capability):
        fail(f"bad --capability '{args.capability}': use type/name:cap or a short name")
    if capability and capability.startswith(f"{ptype}/{pname}:"):
        access = plugin / "db/access.php"
        if not access.exists() or f"'{capability}'" not in access.read_text():
            print(f"warning: {capability} is not defined in db/access.php")

    messagesphp = plugin / "db/messages.php"
    classfile = plugin / "classes/local/notifier.php"
    testfile = plugin / "tests/local/notifier_test.php"
    langphp = plugin / "lang/en" / f"{pname if ptype == 'mod' else component}.php"
    stringid = f"messageprovider:{name}"
    if not langphp.is_file():
        fail(f"{langphp} not found")
    lang = langphp.read_text()
    messages = messagesphp.read_text() if messagesphp.exists() else None
    if messages and re.search(rf"""['"]{name}['"]\s*=>""", messages):
        fail(f"provider '{name}' already exists in {messagesphp}")
    if re.search(rf"""^\$string\[['"]{stringid}['"]\]""", lang, re.M):
        fail(f"string '{stringid}' already exists in {langphp}")
    notifier = classfile.read_text() if classfile.exists() else None
    if notifier and re.search(rf"function\s+send_{name}\s*\(", notifier):
        fail(f"send_{name}() already exists in {classfile}")
    tests = testfile.read_text() if testfile.exists() else None
    if tests and re.search(rf"function\s+test_send_{name}\s*\(", tests):
        fail(f"test_send_{name}() already exists in {testfile}")

    copyright = re.search(r"@copyright\s+(.+)", info["text"])
    ctx = {
        "component": component, "name": name, "capability": capability or "",
        "copyright": copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year),
        "defaults": "".join(f"            '{p}' => MESSAGE_PERMITTED + MESSAGE_DEFAULT_ENABLED,\n" for p in defaults),
    }
    entry = render((TPL / "entry.php.tpl").read_text(), ctx)
    if messages is None:
        messages = render((TPL / "messages.php.tpl").read_text(),
                          {**ctx, "entry": entry, "header": header("Message providers.", ctx)})
    else:
        messages = merge_array(messages, "messageproviders", entry, messagesphp)
    method = render((TPL / "method.php.tpl").read_text(), ctx)
    if notifier is None:
        notifier = render((TPL / "notifier.php.tpl").read_text(),
                          {**ctx, "method": method, "header": header("Notification sender.", ctx)})
    else:
        notifier = add_method(notifier, method, classfile)
    testmethod = render((TPL / "test_method.php.tpl").read_text(), ctx)
    if tests is None:
        tests = render((TPL / "notifier_test.php.tpl").read_text(),
                       {**ctx, "method": testmethod, "header": header("Tests for the notifier.", ctx)})
    else:
        tests = add_method(tests, testmethod, testfile)
    description = name.replace("_", " ").capitalize()
    outputs = [(messagesphp, messages), (classfile, notifier), (testfile, tests),
               (langphp, add_string(lang, stringid, description))]
    if shutil.which("php"):
        for path, text in outputs:
            php_lint(path.relative_to(plugin), text)
    else:
        print("warning: php not on PATH: generated PHP is not linted")

    for path, text in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(path)
    old, new = vphp.bump(plugin, max(int(datetime.date.today().strftime("%Y%m%d00")), info["version"] + 1))
    print(f"{plugin / 'version.php'}: {old} -> {new}")


if __name__ == "__main__":
    main()
