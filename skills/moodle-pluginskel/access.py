#!/usr/bin/env python3
"""Add a capability to a plugin: db/access.php entry, sorted lang string, version bump."""

import argparse
import datetime
import re
import shutil
from pathlib import Path

from external import NAME, php_lint
from generate import TEMPLATES, default_copyright, fail, header, php_quote, render
from hook import merge_hooks
from task import add_string

TPL = TEMPLATES / "access"
CONTEXTS = {"system": "CONTEXT_SYSTEM", "user": "CONTEXT_USER", "coursecat": "CONTEXT_COURSECAT",
            "course": "CONTEXT_COURSE", "module": "CONTEXT_MODULE", "block": "CONTEXT_BLOCK"}
ROLES = ("manager", "coursecreator", "editingteacher", "teacher", "student", "guest", "user", "frontpage")
PERMISSIONS = {"allow": "CAP_ALLOW", "prevent": "CAP_PREVENT", "prohibit": "CAP_PROHIBIT"}
RISKS = ("managetrust", "config", "xss", "personal", "spam", "dataloss")
CAPABILITY = re.compile(r"[a-z]+/[a-z0-9_]+:[a-z0-9_]+")
COMMENT = re.compile(r"""('(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")|(//[^\n]*|#(?!\[)[^\n]*|/\*.*?\*/)""", re.S)


def strip_comments(src):
    """Blank PHP comments, keeping string literals (as mlang does)."""
    return COMMENT.sub(lambda m: m.group(1) or " ", src)


def parse_archetypes(spec):
    """'role=allow,role=prevent' -> [{role, permission}]."""
    archetypes = []
    for item in filter(None, spec.split(",")):
        role, _, perm = item.strip().partition("=")
        if role not in ROLES:
            fail(f"bad archetype role '{role}': use {', '.join(ROLES)}")
        if perm not in PERMISSIONS:
            fail(f"bad permission '{perm}' for {role}: use {', '.join(PERMISSIONS)}")
        if any(a["role"] == role for a in archetypes):
            fail(f"archetype role '{role}' given twice")
        archetypes.append({"role": role, "permission": PERMISSIONS[perm]})
    return archetypes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory with version.php")
    parser.add_argument("name", help="capability name after the colon (e.g. view)")
    parser.add_argument("--type", choices=("read", "write"), required=True, help="captype")
    parser.add_argument("--context", choices=CONTEXTS, required=True, help="contextlevel")
    parser.add_argument("--archetypes", default="manager=allow",
                        help="comma list role=allow|prevent|prohibit (default manager=allow)")
    parser.add_argument("--clone", help="clonepermissionsfrom capability (e.g. moodle/course:view)")
    parser.add_argument("--risk", help="comma list of " + ", ".join(RISKS))
    parser.add_argument("--title", help="lang string text (default: name in words)")
    args = parser.parse_args()

    plugin = Path(args.plugin).resolve()
    if not NAME.fullmatch(args.name):
        fail(f"bad capability name '{args.name}': use [a-z][a-z0-9_]*")
    if args.clone and not CAPABILITY.fullmatch(args.clone):
        fail(f"bad --clone '{args.clone}': use type/name:capability")
    if args.title and re.search(r"[\r\n]", args.title):
        parser.error("--title must be one line")
    risks = {r.strip() for r in (args.risk or "").split(",") if r.strip()}
    for risk in sorted(risks):
        if risk not in RISKS:
            fail(f"bad risk '{risk}': use {', '.join(RISKS)}")
    risks = [r for r in RISKS if r in risks]
    archetypes = parse_archetypes(args.archetypes)
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
    capability, stringid = f"{ptype}/{pname}:{args.name}", f"{pname}:{args.name}"

    accessphp = plugin / "db/access.php"
    langphp = plugin / "lang/en" / f"{pname if ptype == 'mod' else component}.php"
    if not langphp.is_file():
        fail(f"{langphp} not found")
    lang = langphp.read_text()
    access = accessphp.read_text() if accessphp.exists() else None
    if access and re.search(rf"""['"]{re.escape(capability)}['"]\s*=>""", strip_comments(access)):
        fail(f"{capability} already exists in {accessphp}")
    if re.search(rf"""^\$string\[['"]{re.escape(stringid)}['"]\]""", lang, re.M):
        fail(f"string '{stringid}' already exists in {langphp}")

    copyright = re.search(r"@copyright\s+(.+)", vtext)
    ctx = {"component": component, "capability": capability, "captype": args.type,
           "contextlevel": CONTEXTS[args.context], "archetypes": archetypes, "clone": args.clone or "",
           "riskbitmask": " | ".join(f"RISK_{r.upper()}" for r in risks),
           "copyright": copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year)}
    entry = render((TPL / "entry.php.tpl").read_text(), ctx)
    if access is None:
        access = render((TPL / "access.php.tpl").read_text(),
                        {**ctx, "entry": entry, "header": header("Plugin capabilities are defined here.", ctx)})
    else:
        access = merge_hooks(access, "capabilities", entry, accessphp)
    title = php_quote(args.title or args.name.replace("_", " ").capitalize())
    outputs = [(accessphp, access), (langphp, add_string(lang, stringid, title))]
    if shutil.which("php"):
        for path, text in outputs:
            php_lint(path.relative_to(plugin), text)
    else:
        print("warning: php not on PATH: generated PHP is not linted")

    version = max(int(datetime.date.today().strftime("%Y%m%d00")), int(vmatch.group(1)) + 1)
    for path, text in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(path)
    versionphp.write_text(vtext[:vmatch.start(1)] + str(version) + vtext[vmatch.end(1):])
    print(f"{versionphp}: {vmatch.group(1)} -> {version}")
    print(f"capability: {capability}")


if __name__ == "__main__":
    main()
