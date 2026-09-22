#!/usr/bin/env python3
"""Render a Moodle plugin skeleton from a small YAML recipe."""

import argparse
import datetime
import re
import subprocess
import sys
from pathlib import Path

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

REQUIRES = {
    "4.0": 2022041900, "4.1": 2022112800, "4.2": 2023042400, "4.3": 2023100900,
    "4.4": 2024042200, "4.5": 2024100700, "5.0": 2025041400, "5.1": 2025100600,
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


def build_context(recipe):
    component = recipe.get("component") or fail("recipe needs a 'component'")
    if not re.fullmatch(r"[a-z][a-z0-9]*_[a-z][a-z0-9_]*", component):
        fail(f"'{component}' is not a valid frankenstyle component name")
    ptype, pname = component.split("_", 1)

    requires = recipe.get("requires", "4.5")
    if str(requires) in REQUIRES:
        requires = REQUIRES[str(requires)]
    elif not str(requires).isdigit():
        fail(f"unknown 'requires' branch '{requires}' — use one of "
             f"{', '.join(REQUIRES)} or a raw version number")

    today = datetime.date.today()
    ctx = {
        "component": component,
        "type": ptype,
        "pluginname": pname,
        "name": php_quote(recipe.get("name", pname)),
        "release": recipe.get("release", "0.1.0"),
        "version": f"{today:%Y%m%d}00",
        "requires": requires,
        "maturity": recipe.get("maturity", "MATURITY_ALPHA"),
        "copyright": recipe.get("copyright", default_copyright(today.year)),
        "features": recipe.get("features") or {},
        "privacy": (recipe.get("features") or {}).get("privacy", True),
        "lang_strings": [{"id": s["id"], "text": php_quote(s["text"])}
                         for s in recipe.get("lang_strings") or []],
        "capabilities": [], "phpunit_tests": [], "cli_scripts": [],
    }
    for cap in recipe.get("capabilities") or []:
        ctx["capabilities"].append({
            "name": cap["name"],
            "title": php_quote(cap.get("title", cap["name"])),
            "captype": cap.get("captype", "read"),
            "contextlevel": cap.get("contextlevel", "CONTEXT_SYSTEM"),
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
             (f"lang/en/{ctx['component']}.php", "lang.php", "Plugin strings are defined here.")]
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
