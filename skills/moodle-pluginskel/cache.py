#!/usr/bin/env python3
"""Add a MUC cache definition to a plugin: db/caches.php entry, cachedef_ string, typed accessor, test, version bump."""

import argparse
import datetime
import re
import shutil
from pathlib import Path

from external import NAME, merge_array, php_lint
from generate import TEMPLATES, default_copyright, fail, header, render
from task import add_string

TPL = TEMPLATES / "cache"
MODES = {"application": "MODE_APPLICATION", "session": "MODE_SESSION", "request": "MODE_REQUEST"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory with version.php")
    parser.add_argument("area", help="cache area name (e.g. course_summary)")
    parser.add_argument("--mode", choices=MODES, default="application", help="default application")
    parser.add_argument("--simplekeys", action="store_true", help="keys are only a-zA-Z0-9_")
    parser.add_argument("--ttl", type=int, metavar="N", help="seconds before an entry expires")
    args = parser.parse_args()

    plugin = Path(args.plugin).resolve()
    area = args.area
    if not NAME.fullmatch(area):
        fail(f"bad area name '{area}': use [a-z][a-z0-9_]*")
    if args.ttl is not None and args.ttl <= 0:
        fail(f"bad --ttl {args.ttl}: use a positive number of seconds")
    versionphp = plugin / "version.php"
    if not versionphp.is_file():
        fail(f"{plugin} has no version.php")
    vtext = versionphp.read_text()
    vmatch = re.search(r"^\$plugin->version\s*=\s*(\d+);", vtext, re.M)
    cmatch = re.search(r"^\$plugin->component\s*=\s*'([a-z0-9]+_[a-z0-9_]+)';", vtext, re.M)
    if not vmatch or not cmatch:
        fail("version.php needs $plugin->version and $plugin->component")
    component = cmatch.group(1)
    ptype, pname = component.split("_", 1)

    classfile = plugin / "classes/local/cache" / f"{area}.php"
    testfile = plugin / "tests/local/cache" / f"{area}_test.php"
    cachesphp = plugin / "db/caches.php"
    langphp = plugin / "lang/en" / f"{pname if ptype == 'mod' else component}.php"
    stringid = f"cachedef_{area}"
    caches = cachesphp.read_text() if cachesphp.exists() else None
    if caches and re.search(rf"""^\s*['"]{area}['"]\s*=>""", caches, re.M):
        fail(f"cache area '{area}' already exists in {cachesphp}")
    for path in (classfile, testfile):
        if path.exists():
            fail(f"{path} already exists")
    if not langphp.is_file():
        fail(f"{langphp} not found")
    lang = langphp.read_text()
    if re.search(rf"""^\$string\[['"]{stringid}['"]\]""", lang, re.M):
        fail(f"string '{stringid}' already exists in {langphp}")

    copyright = re.search(r"@copyright\s+(.+)", vtext)
    description = area.replace("_", " ").capitalize()
    ctx = {
        "component": component, "area": area, "mode": args.mode, "modeconst": MODES[args.mode],
        "simplekeys": args.simplekeys, "ttl": args.ttl or "",
        "copyright": copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year),
    }
    entry = render((TPL / "entry.php.tpl").read_text(), ctx)
    if caches is None:
        caches = render((TPL / "caches.php.tpl").read_text(),
                        {**ctx, "entry": entry, "header": header("Cache definitions.", ctx)})
    else:
        caches = merge_array(caches, "definitions", entry, cachesphp)
    outputs = [
        (cachesphp, caches),
        (langphp, add_string(lang, stringid, description)),
        (classfile, render((TPL / "accessor.php.tpl").read_text(),
                           {**ctx, "header": header(f"Typed accessor for the {area} cache.", ctx)})),
        (testfile, render((TPL / "accessor_test.php.tpl").read_text(),
                          {**ctx, "header": header(f"Tests for the {area} cache.", ctx)})),
    ]
    if shutil.which("php"):
        for path, text in outputs:
            php_lint(path.relative_to(plugin), text)
    else:
        print("warning: php not on PATH: generated PHP is not linted")

    for path, text in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(path)
    version = max(int(datetime.date.today().strftime("%Y%m%d00")), int(vmatch.group(1)) + 1)
    versionphp.write_text(vtext[:vmatch.start(1)] + str(version) + vtext[vmatch.end(1):])
    print(f"{versionphp}: {vmatch.group(1)} -> {version}")


if __name__ == "__main__":
    main()
