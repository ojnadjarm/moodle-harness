#!/usr/bin/env python3
"""Add a hook callback to a plugin from a hook class or a legacy lib.php callback name."""

import argparse
import datetime
import difflib
import importlib.machinery
import importlib.util
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from external import merge_array as merge_hooks, php_lint
from generate import REQUIRES, TEMPLATES, default_copyright, fail, header, render
import vphp

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "moodle-upgrade-audit"))
from codescan import hook_map  # noqa: E402

TPL = TEMPLATES / "hook"
ENVS = Path(os.environ.get("MOODLE_ENVS") or Path.home() / "moodle-envs")
MSRC = Path(__file__).resolve().parent.parent / "moodle-ci/scripts/msrc"
_loader = importlib.machinery.SourceFileLoader("msrc", str(MSRC))
msrc = importlib.util.module_from_spec(importlib.util.spec_from_loader("msrc", _loader))
_bytecode, sys.dont_write_bytecode = sys.dont_write_bytecode, True
_loader.exec_module(msrc)
sys.dont_write_bytecode = _bytecode
FQN = re.compile(r"[a-z][a-z0-9_]*(?:\\[a-z_][a-z0-9_]*)+")


def find_core(requires=None):
    """(code root, True) for the requires branch via msrc, else (newest non-Vass env in ~/moodle-envs, False), else (None, False)."""
    if requires:
        found = subprocess.run([str(MSRC), str(requires)], capture_output=True, text=True)
        if found.returncode == 0:
            return Path(found.stdout.strip()), True
    envs = sorted((d for d in ENVS.glob("[0-9]*.[0-9]*")
                   if not msrc.REFUSED.search(d.name) and re.fullmatch(r"\d+\.\d+", d.name)),
                  key=lambda d: tuple(map(int, d.name.split("."))), reverse=True)
    for env in envs:
        for root in (env / "www/public", env / "www"):
            if (root / "lib/classes").is_dir():
                if requires:
                    print(f"warning: {found.stderr.strip().removeprefix('msrc: ')}; using {root}", file=sys.stderr)
                return root, False
    return None, False


def default_core(requires=None):
    """Code root of the requires branch via msrc, else of the newest non-Vass env in ~/moodle-envs, else None."""
    return find_core(requires)[0]


def branch_of(core):
    """X.Y of the $branch in core's version.php, else '?'."""
    vphp = core / "version.php"
    m = msrc.BRANCH.search(vphp.read_text(errors="replace")) if vphp.is_file() else None
    return f"{m.group(1)[:-2]}.{int(m.group(1)[-2:])}" if m else "?"


def class_in_core(core, fqn):
    """Path of core's classes/**/<name>.php declaring the namespace of fqn, else None."""
    ns, _, name = fqn.rpartition("\\")
    for dirpath, dirs, files in os.walk(core):
        dirs[:] = [d for d in dirs if d not in (".git", "node_modules", "vendor", "tests")]
        if f"{name}.php" in files and "classes" in dirpath.split(os.sep):
            path = Path(dirpath, f"{name}.php")
            if re.search(rf"^namespace \\?{re.escape(ns)};", path.read_text(errors="replace"), re.M):
                return path
    return None


def resolve(target, core, prefixes, strict=False):
    """Hook class FQN and the legacy callbacks it replaces; a class missing from a strict core fails."""
    hooks = hook_map(str(core)) if core else {}
    name = target.removesuffix("::class").lstrip("\\")
    if "\\" not in name:
        for pre in prefixes:
            if name.startswith(pre) and name[len(pre):] in hooks:
                name = name[len(pre):]
        if not core:
            fail(f"'{target}' is a callback name and no core tree was found: pass --core <root>")
        if name not in hooks:
            near = difflib.get_close_matches(name, hooks, n=3)
            fail(f"no hook replaces the callback '{name}' in {core}"
                 + (f"; nearest: {', '.join(near)}" if near else ""))
        name = hooks[name]
    elif not FQN.fullmatch(name):
        fail(f"'{target}' is not a hook class name")
    elif not core:
        print("warning: no core tree found: hook class not checked", file=sys.stderr)
    elif not class_in_core(core, name):
        if strict:
            fail(f"{name} not found in the Moodle {branch_of(core)} tree {core}: pass --force to add it anyway")
        print(f"warning: {name} not found in {core}", file=sys.stderr)
    return name, sorted(cb for cb, fqn in hooks.items() if fqn == name)


def registered(hookstext, fqn):
    short, full = re.escape(fqn.rsplit("\\", 1)[-1]), re.escape(fqn)
    return re.search(rf"(?<![\w\\])(?:\\?{full}|{short})::class|['\"]\\?{full}['\"]",
                     hookstext.replace("\\\\", "\\"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory with version.php")
    parser.add_argument("target", help="hook class (core\\hook\\after_config) or legacy callback (before_standard_html_head)")
    parser.add_argument("--core", help="Moodle code root to resolve callbacks (default: msrc tree of $plugin->requires, else newest non-Vass ~/moodle-envs)")
    parser.add_argument("--force", action="store_true", help="add a hook class missing from the requires tree, with a warning")
    args = parser.parse_args()

    plugin = Path(args.plugin).resolve()
    info = vphp.read(plugin) or fail(f"{plugin} has no version.php")
    vtext = info["text"]
    if info["version"] is None or info["requires"] is None or not re.fullmatch(r"[a-z0-9]+_[a-z0-9_]+", info["component"] or ""):
        fail("version.php needs $plugin->version, $plugin->component and $plugin->requires")
    component, requires = info["component"], info["requires"]
    if requires < REQUIRES["4.3"]:
        print(f"warning: requires {requires} < 4.3: those sites have no hooks API", file=sys.stderr)
    core, strict = (Path(args.core).resolve(), True) if args.core else find_core(requires)
    if core and not core.is_dir():
        fail(f"core root {core} is not a directory")

    prefixes = [component + "_"] + ([component[4:] + "_"] if component.startswith("mod_") else [])
    hook, legacycbs = resolve(args.target, core, prefixes, strict and not args.force)
    method = hook.rsplit("\\", 1)[-1]
    libphp, hooksphp = plugin / "lib.php", plugin / "db/hooks.php"
    classfile = plugin / "classes/hook_callbacks.php"
    hookstext = hooksphp.read_text() if hooksphp.exists() else None
    if hookstext and registered(hookstext, hook):
        fail(f"{hook} is already registered in {hooksphp}")
    classtext = classfile.read_text() if classfile.exists() else None
    if classtext and re.search(rf"function\s+{method}\s*\(", classtext):
        fail(f"{classfile} already has a method {method}()")

    libtext = libphp.read_text() if libphp.exists() else ""
    legacy = next((f"{pre}{cb}" for cb in legacycbs for pre in prefixes
                   if re.search(rf"^\s*function\s+{pre}{cb}\s*\(", libtext, re.M)), "")
    copyright = re.search(r"@copyright\s+(.+)", vtext)
    ctx = {"component": component, "hook": hook, "method": method, "shortname": method, "legacy": legacy,
           "copyright": copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year)}
    ctx["callback"] = (f"[\\{component}\\hook_callbacks::class, '{method}']" if requires >= REQUIRES["4.4"]
                       else f"'{component}\\hook_callbacks::{method}'")
    methodtext = render((TPL / "method.php.tpl").read_text(), ctx)
    if classtext is None:
        classtext = render((TPL / "hook_callbacks.php.tpl").read_text(),
                           {**ctx, "method": methodtext, "header": header(f"Hook callbacks for {component}.", ctx)})
    else:
        end = classtext.rstrip().rfind("}")
        if end < 0:
            fail(f"{classfile}: no closing brace of class hook_callbacks")
        classtext = classtext[:end].rstrip("\n") + "\n\n" + methodtext + classtext[end:]
    entry = render((TPL / "entry.php.tpl").read_text(), ctx)
    if hookstext is None:
        hookstext = render((TPL / "hooks.php.tpl").read_text(),
                           {**ctx, "entry": entry, "header": header("Hook callbacks.", ctx)})
    else:
        hookstext = merge_hooks(hookstext, "callbacks", entry, hooksphp)
    if shutil.which("php"):
        for label, text in (("classes/hook_callbacks.php", classtext), ("db/hooks.php", hookstext)):
            php_lint(label, text)
    else:
        print("warning: php not on PATH: generated PHP is not linted", file=sys.stderr)

    version = max(int(datetime.date.today().strftime("%Y%m%d00")), info["version"] + 1)
    for path, text in ((classfile, classtext), (hooksphp, hookstext)):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(path)
    old, new = vphp.bump(plugin, version)
    print(f"{plugin / 'version.php'}: {old} -> {new}")
    print(f"hook: {hook} -> {component}\\hook_callbacks::{method}")
    if legacy and requires < REQUIRES["4.4"]:
        print(f"note: keep {legacy}() in lib.php: requires {requires} < 4.4 still calls it")
    elif legacy:
        print(f"note: {legacy}() in lib.php can be removed: requires {requires} >= 4.4 uses the hook")


if __name__ == "__main__":
    main()
