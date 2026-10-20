#!/usr/bin/env python3
"""Add admin settings and admin_externalpage links to a plugin's settings.php, plus their lang strings."""

import argparse
import datetime
import re
import shutil
from pathlib import Path

from access import CAPABILITY
from external import NAME, php_lint
from generate import (SETTINGS_CATEGORIES, TEMPLATES, TYPE_PATHS, default_copyright, fail, header,
                      php_quote, render)
from task import add_string

TPL = TEMPLATES / "settings"
TYPES = ("configtext", "configint", "configcheckbox", "configselect", "configduration")
PAGE_CATEGORIES = {**SETTINGS_CATEGORIES, "mod": "modsettings", "block": "blocksettings", "auth": "authsettings",
                   "enrol": "enrolments", "filter": "filtersettings", "format": "formatsettings",
                   "qtype": "qtypesettings", "theme": "themes"}
PRESET = {"mod", "block", "auth", "enrol", "filter", "format", "qtype", "report", "theme"}
ADMIN_ONLY = {"mod": (151, 158), "block": (119, 119), "auth": (115, 113), "enrol": (105, 101), "filter": (125, 124),
              "format": (131, 131)}
PAGE = re.compile(r"(?:[a-z0-9_]+/)*([a-z][a-z0-9_]*)\.php")
BRACES = re.compile(r"""'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|(?://|#)[^\n]*|/\*.*?\*/|[{}]""", re.S)
SITECONFIG = re.compile(r"^([ \t]*)if\s*\(\s*\$hassiteconfig\s*\)\s*\{", re.M)
FULLTREE = re.compile(r"^([ \t]*)if\s*\(\s*\$ADMIN->fulltree\s*\)\s*\{", re.M)
SETTINGPAGE = re.compile(r"""'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|(?://|#)[^\n]*|/\*.*?\*/"""
                         r"|(new\s+\\?admin_settingpage\s*\()", re.S | re.I)
ASSIGNED = re.compile(r"\$settings\s*=\s*\Z")
NULLED = re.compile(r"^\$settings\s*=\s*null;[ \t]*\n", re.M)
HASCONFIG = re.compile(r"function\s+has_config\s*\(\s*\)\s*(?::\s*bool\s*)?\{", re.I)
HASCONFIG_CODE = """/**
 * The block has a settings.php file.
 *
 * @return bool
 */
public function has_config() {
    return true;
}
"""


def words(name):
    return name.replace("_", " ").capitalize()


def block_end(text, pos, where):
    """Index of the brace closing the one opened at pos, skipping PHP strings and comments."""
    depth = 0
    for m in BRACES.finditer(text, pos):
        if m.group() == "{":
            depth += 1
        elif m.group() == "}":
            depth -= 1
            if not depth:
                return m.start()
    fail(f"{where}: unbalanced braces")


def settingpages(text, start=0, end=None):
    """Offsets of admin_settingpage constructions outside PHP strings and comments."""
    return [m.start() for m in SETTINGPAGE.finditer(text, start, len(text) if end is None else end) if m.group(1)]


def indent(code, prefix):
    return "".join(prefix + line if line.strip() else line for line in code.splitlines(keepends=True))


def insert_in_block(text, match, code, where):
    """Insert code before the closing brace of the block opened by match, one level deeper."""
    close = block_end(text, match.end() - 1, where)
    linestart = text.rfind("\n", 0, close) + 1
    if text[linestart:close].strip():
        text, close = text[:close] + "\n" + match.group(1) + text[close:], close + 1
        linestart = close
    body = text[:linestart]
    sep = "" if body.rstrip().endswith("{") else "\n"
    return body + sep + indent(code, match.group(1) + "    ") + text[linestart:]


def append(text, code):
    return text.rstrip("\n") + "\n\n" + code


def block_config(path, component):
    """Text of block_<name>.php with has_config() returning true; refuses when the class is not found."""
    text = path.read_text() if path.is_file() else ""
    cls = re.search(rf"^([ \t]*)(?:(?:final|abstract)\s+)?class\s+{component}\s+extends\s+\\?\w+\s*\{{", text, re.M)
    if not cls:
        fail(f"{path}: class {component} not found: add has_config() returning true by hand")
    method = HASCONFIG.search(text, cls.end(), block_end(text, cls.end() - 1, path))
    if not method:
        return insert_in_block(text, cls, HASCONFIG_CODE, path)
    close = block_end(text, method.end() - 1, path)
    body = re.fullmatch(r"(\s*return\s+)(true|false)(\s*;\s*)", text[method.end():close], re.I)
    if not body:
        fail(f"{path}: has_config() is not a plain return true/false: make it return true by hand")
    return text[:method.end()] + body.group(1) + "true" + body.group(3) + text[close:]


def parse_setting(spec, choices):
    """'name:type[:default]' -> template context for one setting."""
    name, _, rest = spec.partition(":")
    kind, _, default = rest.partition(":")
    if not NAME.fullmatch(name):
        fail(f"bad setting name '{name}': use [a-z][a-z0-9_]*")
    if kind not in TYPES:
        fail(f"bad setting type '{kind}' for {name}: use {', '.join(TYPES)}")
    if kind == "configcheckbox":
        default = default or "0"
        if default not in ("0", "1"):
            fail(f"configcheckbox {name} default must be 0 or 1")
    elif kind == "configint":
        default = default or "0"
        if not re.fullmatch(r"-?[0-9]+", default):
            fail(f"configint {name} default must be an integer")
        default = str(int(default))
    elif kind == "configduration":
        default = default or "3600"
        if not default.isdigit():
            fail(f"configduration {name} default must be seconds")
    elif kind == "configselect":
        if not choices:
            fail(f"configselect {name} needs --choices a,b,c")
        default = default or choices[0]
        if default not in choices:
            fail(f"configselect {name} default '{default}' is not one of {','.join(choices)}")
    return {"name": name, "kind": kind, "default": php_quote(default),
            "choices": [{"key": c} for c in choices] if kind == "configselect" else []}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory with version.php")
    parser.add_argument("--setting", action="append", default=[], metavar="NAME:TYPE[:DEFAULT]",
                        help=f"repeatable; TYPE is one of {', '.join(TYPES)}")
    parser.add_argument("--choices", help="comma list of option keys for the configselect setting")
    parser.add_argument("--page", help="plugin page to link as an admin_externalpage (e.g. tickets.php)")
    parser.add_argument("--cap", default="moodle/site:config", help="capability for --page (default moodle/site:config)")
    args = parser.parse_args()

    if not args.setting and not args.page:
        fail("give --setting and/or --page")
    choices = [c.strip() for c in (args.choices or "").split(",") if c.strip()]
    for choice in choices:
        if not re.fullmatch(r"[a-z0-9_]+", choice):
            fail(f"bad choice '{choice}': use [a-z0-9_]+")
    if len(set(choices)) != len(choices):
        fail("--choices has a duplicate")
    settings = [parse_setting(spec, choices) for spec in args.setting]
    if sum(s["kind"] == "configselect" for s in settings) > 1:
        fail("one configselect per run (--choices is shared)")
    if choices and not any(s["kind"] == "configselect" for s in settings):
        fail("--choices needs a configselect setting")
    if len({s["name"] for s in settings}) != len(settings):
        fail("a setting name is given twice")

    plugin = Path(args.plugin).resolve()
    versionphp = plugin / "version.php"
    if not versionphp.is_file():
        fail(f"{plugin} has no version.php")
    vtext = versionphp.read_text()
    cmatch = re.search(r"^\$plugin->component\s*=\s*'([a-z0-9]+_[a-z0-9_]+)';", vtext, re.M)
    if not cmatch:
        fail("version.php needs $plugin->component")
    component = cmatch.group(1)
    ptype, pname = component.split("_", 1)
    langphp = plugin / "lang/en" / f"{pname if ptype == 'mod' else component}.php"
    if not langphp.is_file():
        fail(f"{langphp} not found")
    lang = langphp.read_text()
    settingsphp = plugin / "settings.php"
    copyright = re.search(r"@copyright\s+(.+)", vtext)
    ctx = {"component": component,
           "copyright": copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year)}
    if settingsphp.exists():
        text = settingsphp.read_text()
    else:
        text = render((TPL / "settings.php.tpl").read_text(),
                      {**ctx, "header": header("Plugin administration settings.", ctx)})

    def has_string(stringid):
        return re.search(rf"""^\$string\[['"]{re.escape(stringid)}['"]\]""", lang, re.M)

    def refuse_page(pos, why):
        fail(f"{settingsphp}:{text.count(chr(10), 0, pos) + 1}: {why}: a second page would be a duplicate admin page "
             "name: add the setting by hand")

    if settings and ptype in SETTINGS_CATEGORIES:
        site = SITECONFIG.search(text)
        span = (site.start(), block_end(text, site.end() - 1, settingsphp)) if site else (0, -1)
        for pos in settingpages(text):
            if not span[0] <= pos <= span[1]:
                refuse_page(pos, "admin_settingpage outside if ($hassiteconfig)")
        if site:
            inside = settingpages(text, *span)
            if len(inside) != 1 or not ASSIGNED.search(text, 0, inside[0]):
                fail(f"{settingsphp}:{text.count(chr(10), 0, site.start()) + 1}: if ($hassiteconfig) needs exactly one "
                     "$settings = new admin_settingpage(...): add the setting by hand")
    elif settings and settingpages(text):
        refuse_page(settingpages(text)[0], f"admin_settingpage in a {ptype}_ settings.php (core makes $settings)")

    strings = []
    for s in settings:
        if f"'{component}/{s['name']}'" in text:
            fail(f"setting {component}/{s['name']} exists in {settingsphp}")
        ids = [(s["name"], words(s["name"])), (f"{s['name']}_desc", f"{words(s['name'])} description.")]
        ids += [(f"{s['name']}_{c['key']}", words(c["key"])) for c in s["choices"]]
        for stringid, _ in ids:
            if has_string(stringid):
                fail(f"string '{stringid}' exists in {langphp}")
        strings += ids
        code = render((TPL / f"{s['kind']}.php.tpl").read_text(), {**ctx, **s})
        if ptype in SETTINGS_CATEGORIES:
            site = SITECONFIG.search(text)
            if not site:
                text = append(text, render((TPL / "sitepage.php.tpl").read_text(),
                                           {**ctx, "category": SETTINGS_CATEGORIES[ptype]}))
                site = SITECONFIG.search(text)
            close = block_end(text, site.end() - 1, settingsphp)
            tree = FULLTREE.search(text, site.end(), close)
            if not tree:
                text = insert_in_block(text, site, (TPL / "fulltree.php.tpl").read_text(), settingsphp)
                tree = FULLTREE.search(text, site.end())
        else:
            text = NULLED.sub("", text)
            tree = FULLTREE.search(text)
            if not tree:
                text = append(text, (TPL / "fulltree.php.tpl").read_text())
                tree = FULLTREE.search(text)
        text = insert_in_block(text, tree, code, settingsphp)

    if args.page:
        page = PAGE.fullmatch(args.page)
        if not page:
            fail(f"bad --page '{args.page}': use a relative path like tickets.php")
        if not CAPABILITY.fullmatch(args.cap):
            fail(f"bad --cap '{args.cap}': use type/name:capability")
        if args.cap.startswith(f"{ptype}/{pname}:"):
            accessphp = plugin / "db/access.php"
            if not accessphp.is_file() or f"'{args.cap}'" not in accessphp.read_text():
                fail(f"{args.cap} is not in db/access.php: add it with access.py first")
        if ptype not in PAGE_CATEGORIES or ptype not in TYPE_PATHS:
            fail(f"no admin category known for {ptype}_ plugins: add the page by hand")
        stringid = page.group(1)
        pagename = f"{component}_{stringid}"
        if re.search(rf"admin_externalpage\(\s*'{re.escape(pagename)}'", text):
            fail(f"admin_externalpage {pagename} exists in {settingsphp}")
        if not has_string(stringid) and stringid not in {i for i, _ in strings}:
            strings.append((stringid, words(stringid)))
        text = append(text, render((TPL / "externalpage.php.tpl").read_text(),
                                   {**ctx, "category": PAGE_CATEGORIES[ptype], "pagename": pagename,
                                    "stringid": stringid, "capability": args.cap,
                                    "url": f"{TYPE_PATHS[ptype]}/{pname}/{args.page}"}))
        if ptype in PRESET and not re.search(r"\$settings\b", text):
            text += "\n$settings = null;\n"
            print(f"note: no fulltree block: $settings = null keeps an empty {ptype}_ settings page out of the tree; "
                  "a later --setting adds the block")
        if args.cap != "moodle/site:config" and ptype in ADMIN_ONLY:
            v52, v53 = ADMIN_ONLY[ptype]
            print(f"warning: core includes {ptype}_ settings.php only for site admins "
                  f"(lib/classes/plugininfo/{ptype}.php load_settings() returns when !$hassiteconfig: "
                  f"5.2 line {v52}, 5.3 line {v53}): --cap {args.cap} adds no viewers")

    for stringid, value in strings:
        lang = add_string(lang, stringid, php_quote(value))
    outputs = [(settingsphp, text), (langphp, lang)]
    if ptype == "block":
        blockphp = plugin / f"{component}.php"
        blocktext = block_config(blockphp, component)
        if blocktext != blockphp.read_text():
            outputs.append((blockphp, blocktext))
    if shutil.which("php"):
        for path, out in outputs:
            php_lint(path.relative_to(plugin), out)
    else:
        print("warning: php not on PATH: generated PHP is not linted")
    for path, out in outputs:
        path.write_text(out)
        print(path)


if __name__ == "__main__":
    main()
