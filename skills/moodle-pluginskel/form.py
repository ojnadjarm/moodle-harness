#!/usr/bin/env python3
"""Add a core_form\\dynamic_form to a plugin: classes/form/<name>.php, an AMD ModalForm opener, lang strings, a test."""

import argparse
import datetime
import re
import shutil
import subprocess
from pathlib import Path

from external import NAME, php_lint
from generate import TEMPLATES, default_copyright, fail, header, render
from task import add_string

TPL = TEMPLATES / "form"
DYNAMIC_FORM = 2021051700
RESERVED = {"cmid", "courseid", "id", "sesskey"}
I8 = " " * 8
TYPES = {
    "text": ("text", "PARAM_TEXT", "'Example'", "'Example'"),
    "textarea": ("textarea", "PARAM_TEXT", "'Example text'", "'Example text'"),
    "int": ("text", "PARAM_INT", "'5'", "5"),
    "checkbox": ("advcheckbox", "PARAM_BOOL", "1", "1"),
    "date_selector": ("date_selector", None, "['day' => 4, 'month' => 5, 'year' => 2026]",
                      "make_timestamp(2026, 5, 4)"),
    "date_time_selector": ("date_time_selector", None,
                           "['day' => 4, 'month' => 5, 'year' => 2026, 'hour' => 10, 'minute' => 30]",
                           "make_timestamp(2026, 5, 4, 10, 30)"),
}
CONTEXTS = {
    "system": {
        "contextcode": f"{I8}return \\context_system::instance();",
        "setdata": "[]", "pageurl": "new moodle_url('/')", "setup": "", "contextargs": "", "login": "",
        "hidden": None, "trigger": None,
    },
    "course": {
        "contextcode": f"{I8}return \\context_course::instance($this->optional_param('courseid', 0, PARAM_INT));",
        "setdata": "['courseid' => $this->optional_param('courseid', 0, PARAM_INT)]",
        "pageurl": "new moodle_url('/course/view.php', ['id' => $this->optional_param('courseid', 0, PARAM_INT)])",
        "setup": f"{I8}$course = $this->getDataGenerator()->create_course();\n",
        "contextargs": "'courseid' => $course->id", "login": "",
        "hidden": "courseid", "trigger": "$PAGE->course->id",
    },
    "module": {
        "contextcode": f"{I8}return \\context_module::instance($this->optional_param('cmid', 0, PARAM_INT));",
        "setdata": "['cmid' => $this->optional_param('cmid', 0, PARAM_INT)]",
        "pageurl": "new moodle_url('/mod/PNAME/view.php', ['id' => $this->optional_param('cmid', 0, PARAM_INT)])",
        "setup": f"{I8}$course = $this->getDataGenerator()->create_course();\n"
                 f"{I8}$cm = $this->getDataGenerator()->create_module('PNAME', ['course' => $course->id]);\n",
        "contextargs": "'cmid' => $cm->cmid",
        "login": f"{I8}[$course, $cm] = get_course_and_cm_from_cmid("
                 f"$this->optional_param('cmid', 0, PARAM_INT), 'PNAME');\n"
                 f"{I8}require_login($course, false, $cm);\n",
        "hidden": "cmid", "trigger": "$PAGE->cm->id",
    },
}


def parse_fields(spec):
    """'title:text,due:date_time_selector' -> [(name, type)]."""
    fields = []
    for item in filter(None, (f.strip() for f in spec.split(","))):
        name, _, ftype = item.partition(":")
        if not NAME.fullmatch(name) or ftype not in TYPES:
            fail(f"bad field '{item}': use name:type, type one of {', '.join(TYPES)}")
        if name in RESERVED:
            fail(f"field '{name}' is reserved")
        if name in (n for n, _ in fields):
            fail(f"duplicate field '{name}'")
        fields.append((name, ftype))
    if not fields:
        fail("--fields needs at least one name:type")
    return fields


def capability(cap, ptype, pname, plugin):
    """Full capability name; one of this plugin's must be in db/access.php."""
    full = cap if ":" in cap else f"{ptype}/{pname}:{cap}"
    if not re.fullmatch(r"[a-z]+/[a-z0-9_]+:[a-z0-9_]+", full):
        fail(f"bad --cap '{cap}': use a name (view) or a full capability (moodle/site:config)")
    if full.startswith(f"{ptype}/{pname}:"):
        access = plugin / "db/access.php"
        if not access.is_file() or not re.search(rf"""['"]{re.escape(full)}['"]\s*=>""", access.read_text()):
            fail(f"capability '{full}' is not defined in {access}")
    return full


def build(fields, context, strid, component):
    """Element, submitted-data and assert lines for the class and test templates."""
    elements = []
    hidden = CONTEXTS[context]["hidden"]
    if hidden:
        elements += [f"{I8}$mform->addElement('hidden', '{hidden}');", f"{I8}$mform->setType('{hidden}', PARAM_INT);"]
    submitted = [f"{I8}    {CONTEXTS[context]['contextargs']},"] if hidden else []
    asserts = []
    for name, ftype in fields:
        element, param, value, expected = TYPES[ftype]
        elements.append(f"{I8}$mform->addElement('{element}', '{name}', get_string('{strid}_{name}', '{component}'));")
        if param:
            elements.append(f"{I8}$mform->setType('{name}', {param});")
        submitted.append(f"{I8}    '{name}' => {value},")
        asserts.append(f"{I8}$this->assertEquals({expected}, $result->{name});")
    return "\n".join(elements), "\n".join(submitted), "\n".join(asserts)


def wire_page(plugin, page, component, name, titleid, context):
    """Page path and its text with a trigger button and the js_call_amd opener before the footer; None if wired."""
    path = (plugin / page).resolve()
    if path.suffix != ".php" or plugin not in path.parents or not path.is_file():
        fail(f"--page {page}: not a .php file inside {plugin}")
    text = path.read_text()
    code = re.sub(r"/\*.*?\*/|(//|#)[^\n]*", "", text, flags=re.S)
    if context == "module" and not re.search(r"require_(course_)?login\([^;]*\$cm\b|\$PAGE->set_cm\(", code):
        fail(f"--page {page}: --context module needs a page with a course module (an uncommented require_login or "
             f"require_course_login with $cm, or $PAGE->set_cm; a text match, not a PHP parse), else $PAGE->cm is null")
    if f"js_call_amd('{component}/{name}'" in text:
        return path, None
    footer = re.findall(r"^([ \t]*)echo \$OUTPUT->footer\(\);$", text, re.M)
    if len(footer) != 1:
        fail(f"--page {page}: needs exactly one 'echo $OUTPUT->footer();' line")
    action = f"{component}-{name}"
    attrs = ["'type' => 'button'", "'class' => 'btn btn-primary'", f"'data-action' => '{action}'"]
    trigger = CONTEXTS[context]["trigger"]
    if trigger:
        attrs.append(f"'data-{CONTEXTS[context]['hidden']}' => {trigger}")
    indent = footer[0]
    block = [f"$PAGE->requires->js_call_amd('{component}/{name}', 'init', ['[data-action=\"{action}\"]']);",
             f"echo html_writer::tag('button', get_string('{titleid}', '{component}'), ["]
    block += [f"    {attr}," for attr in attrs] + ["]);"]
    insert = "".join(f"{indent}{line}\n" for line in block)
    return path, re.sub(r"^[ \t]*echo \$OUTPUT->footer\(\);$", lambda m: insert + m.group(0), text, flags=re.M)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory with version.php")
    parser.add_argument("name", help="form class name (e.g. edit_entry)")
    parser.add_argument("--fields", required=True, help=f"name:type,... type one of {', '.join(TYPES)}")
    parser.add_argument("--cap", required=True, help="capability checked on submit: a name of this plugin or a full one")
    parser.add_argument("--context", choices=CONTEXTS, default="system",
                        help="context of the form (default system); module needs a mod_ plugin and passes cmid")
    parser.add_argument("--page", help="plugin page (e.g. view.php) that gets a trigger button and the js_call_amd opener")
    args = parser.parse_args()

    plugin = Path(args.plugin).resolve()
    name = args.name
    if not NAME.fullmatch(name):
        fail(f"bad form name '{name}': use [a-z][a-z0-9_]*")
    fields = parse_fields(args.fields)
    versionphp = plugin / "version.php"
    if not versionphp.is_file():
        fail(f"{plugin} has no version.php")
    vtext = versionphp.read_text()
    cmatch = re.search(r"""^\$plugin->component\s*=\s*(['"])([a-z0-9]+_[a-z0-9_]+)\1;""", vtext, re.M)
    rmatch = re.search(r"^\$plugin->requires\s*=\s*(\d+)(?:\.\d+)?;", vtext, re.M)
    if not cmatch or not rmatch:
        fail("version.php needs $plugin->component and $plugin->requires")
    if int(rmatch.group(1)) < DYNAMIC_FORM:
        fail(f"core_form\\dynamic_form needs Moodle 3.11 ($plugin->requires >= {DYNAMIC_FORM}), "
             f"this plugin requires {rmatch.group(1)}")
    component = cmatch.group(2)
    ptype, pname = component.split("_", 1)
    if args.context == "module" and ptype != "mod":
        fail(f"--context module needs a mod_ plugin, {component} is not one")
    cap = capability(args.cap, ptype, pname, plugin)

    classfile = plugin / "classes/form" / f"{name}.php"
    jsfile = plugin / "amd/src" / f"{name}.js"
    testfile = plugin / "tests/form" / f"{name}_test.php"
    langphp = plugin / "lang/en" / f"{pname if ptype == 'mod' else component}.php"
    for path in (classfile, jsfile, testfile):
        if path.exists():
            fail(f"{path} already exists")
    if not langphp.is_file():
        fail(f"{langphp} not found")
    titleid = f"form_{name}"
    description = name.replace("_", " ").capitalize()
    strings = [(titleid, description)] + [(f"{titleid}_{f}", f.replace("_", " ").capitalize()) for f, _ in fields]
    lang = langphp.read_text()
    for stringid, text in strings:
        if re.search(rf"""^\$string\[['"]{stringid}['"]\]""", lang, re.M):
            fail(f"string '{stringid}' already exists in {langphp}")
        lang = add_string(lang, stringid, text)

    copyright = re.search(r"@copyright\s+(.+)", vtext)
    elements, submitted, asserts = build(fields, args.context, titleid, component)
    contextvars = {k: v.replace("PNAME", pname) for k, v in CONTEXTS[args.context].items() if isinstance(v, str)}
    ctx = {
        "component": component, "name": name, "description": description, "capability": cap, "titleid": titleid,
        "copyright": copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year),
        "elements": elements, "submitted": submitted, "asserts": asserts, **contextvars,
    }
    classtext = render((TPL / "class.php.tpl").read_text(), {**ctx, "header": header(f"{description} dynamic form.", ctx)})
    testtext = render((TPL / "test.php.tpl").read_text(),
                      {**ctx, "header": header(f"Tests for the {name} dynamic form.", ctx)})
    jstext = render((TPL / "modal.js.tpl").read_text(), ctx)
    outputs = [(classfile, classtext), (testfile, testtext), (langphp, lang)]
    generator = plugin / "tests/generator/lib.php"
    if args.context == "module" and not generator.exists():
        outputs.append((generator, render((TEMPLATES / "behat/generator.php.tpl").read_text(),
                                          {**ctx, "header": header(f"Data generator for {component}.", ctx)})))
    page = wire_page(plugin, args.page, component, name, titleid, args.context) if args.page else None
    if page and page[1] is not None:
        outputs.append(page)
    if shutil.which("php"):
        for path, text in outputs:
            php_lint(path.relative_to(plugin), text)
    else:
        print("warning: php not on PATH: generated PHP is not linted")
    if shutil.which("node"):
        check = subprocess.run(["node", "--check", "--input-type=module"], input=jstext, capture_output=True, text=True)
        if check.returncode:
            fail(f"generated amd/src/{name}.js does not parse, nothing written: {check.stderr.strip()}")

    for path, text in outputs + [(jsfile, jstext)]:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(path)
    if page:
        if page[1] is None:
            print(f"{page[0]} already has the {component}/{name} opener")
        print(f"next: mgrunt to build amd/build; the button on {args.page} opens the form")
        return
    hidden = CONTEXTS[args.context]["hidden"]
    print(f"next: mgrunt to build amd/build; open it with $PAGE->requires->js_call_amd('{component}/{name}', 'init', "
          f"['[data-action=\"{component}-{name}\"]'])" + (f" and data-{hidden} on the trigger" if hidden else ""))


if __name__ == "__main__":
    main()
