#!/usr/bin/env python3
"""Add Moodle App support to a plugin: db/mobile.php handler, output class, templates/mobileapp page, test, lang."""

import argparse
import datetime
import difflib
import json
import re
import shutil
from pathlib import Path

from access import strip_comments
from external import NAME, XMLDB, php_lint, table_context, user_table
from generate import TEMPLATES, default_copyright, fail, header, render
from task import add_string

TPL = TEMPLATES / "mobile"
DELEGATES = Path(__file__).parent.parent / "moodle-ci/reference/mobile-delegates.json"
TYPE_DELEGATES = {
    "AddonMessageOutputDelegate": "message",
    "AddonModAssignFeedbackDelegate": "assignfeedback",
    "AddonModAssignSubmissionDelegate": "assignsubmission",
    "AddonModQuizAccessRuleDelegate": "quizaccess",
    "AddonWorkshopAssessmentStrategyDelegate": "workshopform",
    "CoreBlockDelegate": "block",
    "CoreCourseFormatDelegate": "format",
    "CoreCourseModuleDelegate": "mod",
    "CoreCourseModulePrefetchDelegate": "mod",
    "CoreEnrolDelegate": "enrol",
    "CoreFilterDelegate": "filter",
    "CoreQuestionBehaviourDelegate": "qbehaviour",
    "CoreQuestionDelegate": "qtype",
    "CoreUserProfileFieldDelegate": "profilefield",
}
MOD_ICONS = ("pix/monologo.svg", "pix/icon.svg", "pix/icon.png")
COURSE_DELEGATES = ("CoreCourseFormatDelegate", "CoreCourseOptionsDelegate", "CoreUserDelegate")
LEVELS = ("system", "user", "coursecat", "course", "module", "block")
I8 = " " * 8
ENROL = (f"{I8}$roleid = $DB->get_field('role', 'id', ['shortname' => 'student'], MUST_EXIST);\n"
         f"{I8}$this->getDataGenerator()->enrol_user($user->id, $course->id, $roleid);\n"
         f"{I8}$contextid = \\context_course::instance($course->id)->id;\n")
COURSE_SETUP = f"{I8}$course = $this->getDataGenerator()->create_course();\n"
KINDS = {
    "system": {"capcontext": "\\context_system::instance()", "login": "", "setup": "", "args": "[]",
               "testglobal": "$CFG", "grant": f"{I8}$roleid = $CFG->defaultuserroleid;\n"
                                              f"{I8}$contextid = \\context_system::instance()->id;\n"},
    "course": {"capcontext": "\\context_course::instance($args['courseid'])",
               "login": f"{I8}require_login($args['courseid'], false, null, true, true);\n",
               "setup": COURSE_SETUP, "args": "['courseid' => $course->id]", "testglobal": "$DB", "grant": ENROL},
    "module": {"capcontext": "\\context_module::instance($cm->id)",
               "login": f"{I8}[$course, $cm] = get_course_and_cm_from_cmid($args['cmid'], 'PNAME');\n"
                        f"{I8}require_login($course, false, $cm, true, true);\n",
               "setup": COURSE_SETUP
                        + f"{I8}$cm = $this->getDataGenerator()->create_module('PNAME', ['course' => $course->id]);\n",
               "args": "['cmid' => $cm->cmid, 'courseid' => $course->id]", "testglobal": "$DB", "grant": ENROL},
    "block": {"capcontext": "\\context_block::instance($args['blockid'])", "login": "",
              "setup": COURSE_SETUP + f"{I8}$block = $this->getDataGenerator()->create_block('PNAME', "
                                      "['parentcontextid' => \\context_course::instance($course->id)->id]);\n",
              "args": "['contextlevel' => 'course', 'instanceid' => $course->id, 'blockid' => $block->id]",
              "testglobal": "$DB", "grant": ENROL},
}


def display_data(delegate, pname, plugin, stringid):
    """displaydata entries (key, PHP expression) for the delegate; [] when it takes none."""
    if delegate == "CoreCourseModuleDelegate":
        icon = next((p for p in MOD_ICONS if (plugin / p).is_file()), None)
        return ([("icon", f"$CFG->wwwroot . '/mod/{pname}/{icon}'")] if icon else []) + [("class", "''")]
    if delegate == "CoreBlockDelegate":
        return [("title", f"'{stringid}'"), ("class", f"'block_{pname}'")]
    return [("title", f"'{stringid}'"), ("icon", "'earth'")]


def capability_of(plugin, component, given):
    """Full capability name from --capability (short names are the plugin's), else the only one in db/access.php."""
    access = plugin / "db/access.php"
    caps = re.findall(r"""['"]([a-z0-9_]+/[a-z0-9_]+:[a-z0-9_]+)['"]\s*=>""",
                      strip_comments(access.read_text())) if access.is_file() else []
    if not given:
        if len(caps) != 1:
            print(f"warning: no --capability and {len(caps)} capabilities in db/access.php: add require_capability() by hand")
        return caps[0] if len(caps) == 1 else ""
    capability = given if "/" in given else "{}/{}:{}".format(*component.split("_", 1), given)
    if capability.startswith(component.replace("_", "/", 1) + ":") and capability not in caps:
        print(f"warning: {capability} is not defined in db/access.php")
    return capability


def kind_of(delegate):
    """Context the page runs in, from the args the app sends: cmid, blockid, courseid or none."""
    if TYPE_DELEGATES.get(delegate) == "mod":
        return "module"
    if delegate == "CoreBlockDelegate":
        return "block"
    return "course" if delegate in COURSE_DELEGATES else "system"


def check_level(plugin, capability, delegate, kind):
    """Warn when db/access.php defines the capability below the context the page checks it in."""
    access = plugin / "db/access.php"
    found = re.search(rf"""['"]{re.escape(capability)}['"]\s*=>.*?['"]contextlevel['"]\s*=>\s*CONTEXT_([A-Z]+)""",
                      strip_comments(access.read_text()), re.S) if access.is_file() else None
    caplevel = found.group(1).lower() if found else ""
    if caplevel in LEVELS and LEVELS.index(caplevel) > LEVELS.index(kind):
        print(f"warning: {capability} is a CONTEXT_{caplevel.upper()} capability but {delegate} pages check it in the "
              f"{kind} context: users who hold it only in a {caplevel} are refused")


def test_context(component, kind, table, cols, names, types):
    """Fixture lines, method arguments and row asserts for tests/output/mobile_test.php."""
    pname = component.split("_", 1)[1]
    spec = KINDS[kind]
    ctx = {"setup": spec["setup"].replace("PNAME", pname), "args": spec["args"], "grant": spec["grant"],
           "testglobal": spec["testglobal"], "ownrow": "", "otherrow": "", "asserts": ""}
    if table:
        ctx.update({k: v for k, v in table_context(table, cols, names, types).items() if k in ("ownrow", "otherrow")})
        own = {c: "$USER->id" if c == "userid" else XMLDB.get(types[c], ("", "'a'"))[1] for c in cols}
        ctx["asserts"] = "".join(f"        $this->assertEquals({own[c]}, $rows[0]['{c}']);\n" for c in cols)
    return ctx


def rows_markup(cols):
    """Ionic list over CONTENT_OTHERDATA.rows: row values never enter the compiled template."""
    labels = "".join(f'            <p><core-format-text [text]="row.{c}"></core-format-text></p>\n' for c in cols)
    return ('    <ion-item *ngFor="let row of CONTENT_OTHERDATA.rows">\n        <ion-label>\n'
            f"{labels}        </ion-label>\n    </ion-item>\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory with version.php")
    parser.add_argument("--delegate", required=True,
                        help="app delegate from moodle-ci/reference/mobile-delegates.json "
                             "(e.g. CoreMainMenuDelegate, CoreCourseModuleDelegate, CoreBlockDelegate)")
    parser.add_argument("--handler", help="handler name (default: the plugin name)")
    parser.add_argument("--table", help="install.xml table with a userid field: the page lists the current user's rows")
    parser.add_argument("--cols", help="comma-separated fields of --table shown per row (format_string)")
    parser.add_argument("--capability", help="required to open the page: full name or the plugin's short name "
                                             "(default: the only capability in db/access.php)")
    args = parser.parse_args()

    delegates = json.loads(DELEGATES.read_text())
    delegate = args.delegate
    if delegate not in delegates:
        near = difflib.get_close_matches(delegate, delegates, 1, 0)
        fail(f"'{delegate}' is not an app delegate in {DELEGATES.name} (nearest: {near[0] if near else '-'})")
    plugin = Path(args.plugin).resolve()
    versionphp = plugin / "version.php"
    if not versionphp.is_file():
        fail(f"{plugin} has no version.php")
    vtext = versionphp.read_text()
    vmatch = re.search(r"^\$plugin->version\s*=\s*(\d+(?:\.\d+)?);", vtext, re.M)
    cmatch = re.search(r"^\$plugin->component\s*=\s*'([a-z0-9]+_[a-z0-9_]+)';", vtext, re.M)
    if not vmatch or not cmatch:
        fail("version.php needs $plugin->version and $plugin->component")
    component = cmatch.group(1)
    ptype, pname = component.split("_", 1)
    if TYPE_DELEGATES.get(delegate, ptype) != ptype:
        allowed = sorted(d for d in delegates if TYPE_DELEGATES.get(d, ptype) == ptype)
        fail(f"{delegate} needs a {TYPE_DELEGATES[delegate]}_ plugin, got {component}; "
             f"{component} can take: {', '.join(allowed)}")
    handler = args.handler or pname
    if not NAME.fullmatch(handler):
        fail(f"bad handler name '{handler}': use [a-z][a-z0-9_]*")

    if bool(args.table) != bool(args.cols):
        fail("--table and --cols go together")
    cols = args.cols.split(",") if args.cols else []
    names, types = user_table(plugin, args.table, cols) if args.table else ([], {})

    template = f"mobileapp/{handler}"
    stringid = f"mobile_{handler}"
    mobilephp = plugin / "db/mobile.php"
    classfile = plugin / "classes/output/mobile.php"
    mustache = plugin / "templates" / f"{template}.mustache"
    testfile = plugin / "tests/output/mobile_test.php"
    langphp = plugin / "lang/en" / f"{pname if ptype == 'mod' else component}.php"
    for path in (mobilephp, classfile, mustache, testfile):
        if path.exists():
            fail(f"{path} already exists")
    if not langphp.is_file():
        fail(f"{langphp} not found")
    lang = langphp.read_text()
    if re.search(rf"""^\$string\[['"]{stringid}['"]\]""", lang, re.M):
        fail(f"string '{stringid}' already exists in {langphp}")

    capability = capability_of(plugin, component, args.capability)
    kind = kind_of(delegate)
    checks = KINDS[kind]["login"].replace("PNAME", pname)
    if capability:
        check_level(plugin, capability, delegate, kind)
        checks += f"        require_capability('{capability}', {KINDS[kind]['capcontext']});\n"
    checks = "\n" + checks if checks else ""
    generator = plugin / "tests/generator/lib.php"
    copyright = re.search(r"@copyright\s+(.+)", vtext)
    displaydata = display_data(delegate, pname, plugin, stringid) if "displaydata" in delegates[delegate] else []
    ctx = {
        "component": component, "handler": handler, "delegate": delegate, "method": f"mobile_{handler}_view",
        "template": template, "stringid": stringid,
        "copyright": copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year),
        "hasdisplaydata": bool(displaydata), "displaydata": [{"key": k, "value": v} for k, v in displaydata],
        "hastable": bool(args.table), "notable": not args.table, "table": args.table or "",
        "cols": [{"col": c} for c in cols],
        "otherdata": "['rows' => json_encode($rows)]" if args.table else "[]",
        "rowsmarkup": rows_markup(cols) if args.table else "",
        "hascapability": bool(capability), "capability": capability, "checks": checks,
        "denied": "require_login_exception" if kind == "module" and capability == f"mod/{pname}:view"
                  else "required_capability_exception",
        **test_context(component, kind, args.table, cols, names, types),
    }
    outputs = [
        (mobilephp, render((TPL / "mobile.php.tpl").read_text(), {**ctx, "header": header("Moodle App handlers.", ctx)})),
        (classfile, render((TPL / "output.php.tpl").read_text(),
                           {**ctx, "header": header("Moodle App content callbacks.", ctx)})),
        (mustache, render((TPL / "view.mustache.tpl").read_text(), ctx)),
        (testfile, render((TPL / "test.php.tpl").read_text(),
                          {**ctx, "header": header(f"Tests for the {handler} Moodle App page.", ctx)})),
        (langphp, add_string(lang, stringid, handler.replace("_", " ").capitalize())),
    ]
    if kind == "module" and not generator.exists():
        outputs.append((generator, render((TEMPLATES / "behat/generator.php.tpl").read_text(),
                                          {**ctx, "header": header(f"Data generator for {component}.", ctx)})))
    if shutil.which("php"):
        for path, text in outputs:
            if path.suffix == ".php":
                php_lint(path.relative_to(plugin), text)
    else:
        print("warning: php not on PATH: generated PHP is not linted")

    for path, text in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(path)
    version = max(int(datetime.date.today().strftime("%Y%m%d00")), int(vmatch.group(1).split(".")[0]) + 1)
    versionphp.write_text(vtext[:vmatch.start(1)] + str(version) + vtext[vmatch.end(1):])
    print(f"{versionphp}: {vmatch.group(1)} -> {version}")


if __name__ == "__main__":
    main()
