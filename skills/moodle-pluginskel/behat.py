#!/usr/bin/env python3
"""Write a Behat feature (and, for mod_, the data generator) for an existing plugin, using only real core steps."""

import argparse
import datetime
import re
import sys
from pathlib import Path

import yaml

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent))
from generate import TYPE_PATHS, default_copyright, fail, header, render  # noqa: E402

TEMPLATES = Path(__file__).parent / "templates" / "behat"
DEFAULT_USERS = [{"username": "teacher1", "role": "editingteacher"},
                 {"username": "student1", "role": "student"}]
EDITORS = ("editingteacher", "manager")
AS_ROLES = {"admin": (), "teacher": ("editingteacher", "teacher"), "student": ("student",)}
KEYS = "title, course, users, instance, page, heading, as, scenarios"
PAGE_KEYS = ("path", "param", "instance", "name")


def page_resolver(page, ptype):
    """Validated course-scoped page: {path, param, instance: course, name} with defaults."""
    if set(page) - set(PAGE_KEYS):
        fail(f"recipe page: unknown keys {', '.join(sorted(map(str, set(page) - set(PAGE_KEYS))))} "
             f"(allowed: {', '.join(PAGE_KEYS)})")
    path = page.get("path")
    if not isinstance(path, str) or not re.fullmatch(r"/?[a-z0-9_]+(?:/[a-z0-9_]+)*\.php", path):
        fail("recipe page.path: must be a plugin script such as report/x/index.php")
    param = page.get("param", "id")
    if not isinstance(param, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", param):
        fail("recipe page.param: must be a URL parameter name such as id or courseid")
    if page.get("instance", "course") != "course":
        fail("recipe page.instance: must be course")
    stem = path.rsplit("/", 1)[-1][:-4].replace("_", " ").capitalize()
    name = page.get("name", stem)
    if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9 _-]*", name) or "  " in name:
        fail("recipe page.name: must be a page name such as Visits (letters, digits, spaces, _ -)")
    if ptype not in TYPE_PATHS:
        fail(f"recipe page: {ptype}_ is not in the type map, cannot locate lib/behat/behat_base.php")
    return {"path": "/" + path.lstrip("/"), "param": param, "pagename": name.strip(),
            "pagekey": name.strip().lower(), "baserel": "../" * (len(TYPE_PATHS[ptype].split("/")) + 3)}


def plugin_info(root):
    """Component, type, plugin name and display name read from version.php and the lang file."""
    try:
        version = (root / "version.php").read_text()
    except OSError:
        fail(f"no version.php in '{root}' — not a plugin directory")
    match = re.search(r"\$plugin->component\s*=\s*['\"]([a-z][a-z0-9]*_[a-z0-9_]+)['\"]", version)
    if not match:
        fail(f"no $plugin->component in {root / 'version.php'}")
    component = match.group(1)
    ptype, pname = component.split("_", 1)
    lang = root / "lang" / "en" / f"{pname if ptype == 'mod' else component}.php"
    key = "modulename" if ptype == "mod" else "pluginname"
    found = re.search(rf"\$string\['{key}'\]\s*=\s*'((?:[^'\\]|\\.)*)'",
                      lang.read_text() if lang.is_file() else "")
    name = re.sub(r"\\(.)", r"\1", found.group(1)) if found else pname
    return component, ptype, pname, name


def table(rows, indent="      "):
    """Gherkin table with aligned columns."""
    rows = [[str(c).replace("\\", "\\\\").replace("|", "\\|") for c in row] for row in rows]
    widths = [max(len(str(row[i])) for row in rows) for i in range(len(rows[0]))]
    return "\n".join(indent + "| " + " | ".join(str(c).ljust(w) for c, w in zip(row, widths)) + " |"
                     for row in rows)


def step_arg(text):
    return str(text).replace('"', '\\"')


def check_text(value, where="recipe"):
    """Fail on text the renderer would substitute again or a line break would split."""
    if isinstance(value, dict):
        for key, item in value.items():
            check_text(item, f"{where}.{key}")
    elif isinstance(value, list):
        for i, item in enumerate(value):
            check_text(item, f"{where}[{i}]")
    elif isinstance(value, str) and ("{{" in value or "\n" in value):
        fail(f"{where}: '{{{{' and line breaks are not allowed in recipe values")


def mappings(value, key, where):
    """The list at `where`, failing unless every entry is a mapping with `key`."""
    if not isinstance(value, list) or not all(isinstance(v, dict) and v.get(key) for v in value):
        fail(f"recipe {where}: must be a list of mappings, each with a '{key}'")
    return value


def build_context(root, recipe):
    component, ptype, pname, name = plugin_info(root)
    check_text(recipe)
    if not isinstance(recipe.get("course") or {}, dict):
        fail("recipe course: must be a mapping (fullname, shortname)")
    course = {"fullname": "Course 1", "shortname": "C1", **(recipe.get("course") or {})}
    users = mappings(recipe.get("users") or DEFAULT_USERS, "username", "users")
    instance = recipe.get("instance") or f"Test {name}"

    givens = [("users", [["username", "firstname", "lastname", "email"]] + [
        [u["username"], u.get("firstname", re.sub(r"\d+$", "", u["username"]).capitalize() or "User"),
         u.get("lastname", re.sub(r"^\D*", "", u["username"]) or "User"),
         u.get("email", f"{u['username']}@example.com")] for u in users])]
    givens.append(("courses", [["fullname", "shortname"], [course["fullname"], course["shortname"]]]))
    enrolled = [u for u in users if u.get("role")]
    if enrolled:
        givens.append(("course enrolments", [["user", "course", "role"]] +
                       [[u["username"], course["shortname"], u["role"]] for u in enrolled]))
    if ptype == "mod":
        givens.append(("activities", [["activity", "name", "intro", "course", "idnumber"],
                                      [pname, instance, f"{instance} description",
                                       course["shortname"], f"{pname}1"]]))
        identifier = f"{pname}1" if '"' in instance else instance
        pagetype, seen = f"{pname} activity", instance
    else:
        if ptype == "block":
            givens.append(("blocks", [["blockname", "contextlevel", "reference"],
                                      [pname, "Course", course["shortname"]]]))
        identifier, pagetype = course["shortname"], "Course"
        seen = name if ptype == "block" else course["fullname"]
    background = "\n".join(
        f"    {'Given' if i == 0 else 'And'} the following \"{entity}\" exist:\n{table(rows)}"
        for i, (entity, rows) in enumerate(givens))

    default_users = enrolled[:1] if ptype == "block" else (enrolled or users[:1])
    default_scenarios = [{"name": f"{u['username']} sees the {name}", "user": u["username"]} for u in default_users]
    page, kept = recipe.get("page"), []
    if page == "activity" and ptype != "mod":
        fail(f"recipe page: activity needs a mod_ plugin, {component} is {ptype}_")
    resolver = page_resolver(page, ptype) if isinstance(page, dict) else None
    if page is not None and page != "activity" and not resolver \
            and not (isinstance(page, str) and re.fullmatch(r"/[^\s\"]+", page)):
        fail("recipe page: must be activity (mod_), a site-relative URL such as /local/x/view.php, "
             "or a mapping {path, param, instance: course, name}")
    if page:
        if ptype == "mod" and page != "activity":
            kept = [{**d, "see": seen} for d in default_scenarios]
        seen = recipe.get("heading", instance if page == "activity" else name)
        if not isinstance(seen, (str, int, float)) or isinstance(seen, bool):
            fail("recipe heading: must be text")
        who = recipe.get("as", "admin")
        if not isinstance(who, str) or who not in AS_ROLES:
            fail(f"recipe as: must be one of {', '.join(AS_ROLES)}")
        pageuser = "admin" if who == "admin" else next(
            (u["username"] for u in users if u.get("role") in AS_ROLES[who]), None)
        if not pageuser:
            fail(f"recipe as: {who} needs a user with role {' or '.join(AS_ROLES[who])}")
        pagescenario = {"name": f"{who} sees {seen}", "user": pageuser}
        default_scenarios = kept + [pagescenario]
        if page == "activity":
            page = None
    else:
        for key in ("heading", "as"):
            if key in recipe:
                print(f"warning: {key}: is ignored without page:", file=sys.stderr)
        if ptype == "local":
            print("warning: the feature never opens a plugin page (add page: to the recipe)", file=sys.stderr)
    scenarios = mappings(recipe.get("scenarios") or default_scenarios, "name", "scenarios")
    if not scenarios:
        fail("no scenario to write: list scenarios, or give a user a role (block_ scenarios need one)")
    roles = {u["username"]: u.get("role") for u in users}
    ctx = {"component": component, "name": name,
           "title": recipe.get("title", f"Basic use of {name}"),
           "background": background, "scenarios": [], "resolver": resolver}
    for sc in scenarios:
        visit = page if not any(sc is k for k in kept) else None
        resolved = bool(visit) and resolver is not None
        see = sc.get("see")
        see = [seen] if see is None else see
        see = [see] if isinstance(see, (str, int, float)) else see
        if not isinstance(see, list) or not all(isinstance(t, (str, int, float)) and not isinstance(t, bool)
                                                for t in see):
            fail(f"scenario '{sc['name']}': see must be a text or a list of texts")
        user = sc.get("user", users[0]["username"])
        can_edit = user == "admin" or roles.get(user) in EDITORS
        editing = sc.get("editing", ptype == "block" and can_edit and not visit)
        if not isinstance(editing, bool):
            fail(f"scenario '{sc['name']}': editing must be true or false")
        if editing and visit:
            fail(f"scenario '{sc['name']}': editing is not available with page:")
        if editing and not can_edit:
            fail(f"scenario '{sc['name']}': '{user}' cannot turn editing on (needs role {' or '.join(EDITORS)})")
        where = f' in the "{step_arg(name)}" "block"' if ptype == "block" and not visit else ""
        ctx["scenarios"].append({
            "scenario": sc["name"], "user": step_arg(user),
            "identifier": step_arg(course["shortname"] if resolved else identifier),
            "pagetype": f"{component} > {resolver['pagename']}" if resolved else pagetype,
            "visit": bool(visit) and not resolved, "coursepage": not visit or resolved, "page": visit,
            "editing": editing,
            "see": [{"keyword": "Then" if i == 0 else "And", "text": step_arg(t), "where": where}
                    for i, t in enumerate(see)],
        })
    return ctx, ptype


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin_dir", help="the plugin directory (holds version.php)")
    parser.add_argument("feature", help="feature file name, e.g. basic_use (-> tests/behat/basic_use.feature)")
    parser.add_argument("--recipe", help=f"YAML: {KEYS}; page: activity, /url or {{path, param, instance: course, name}}")
    args = parser.parse_args()

    if not re.fullmatch(r"[a-z0-9_]+", args.feature):
        fail(f"feature name '{args.feature}' must match [a-z0-9_]+")
    root = Path(args.plugin_dir)
    recipe = {}
    if args.recipe:
        try:
            recipe = yaml.safe_load(Path(args.recipe).read_text()) or {}
        except (OSError, yaml.YAMLError) as exc:
            fail(f"cannot read recipe: {exc}")
        if not isinstance(recipe, dict):
            fail(f"recipe: must be a YAML mapping ({KEYS})")
    ctx, ptype = build_context(root, recipe)

    feature = root / "tests" / "behat" / f"{args.feature}.feature"
    if feature.exists():
        fail(f"'{feature}' already exists — never overwrites, pick another name")
    feature.parent.mkdir(parents=True, exist_ok=True)
    feature.write_text(render((TEMPLATES / "feature.tpl").read_text(), ctx))
    print(feature)

    if ctx["resolver"]:
        context = root / "tests" / "behat" / f"behat_{ctx['component']}.php"
        if not context.exists():
            rctx = {"component": ctx["component"], **ctx["resolver"],
                    "copyright": recipe.get("copyright", default_copyright(datetime.date.today().year))}
            rctx["header"] = header(f"Step definitions for {ctx['component']}.", rctx)
            context.write_text(render((TEMPLATES / "behat_component.php.tpl").read_text(), rctx))
            print(context)
        elif f"case '{ctx['resolver']['pagekey']}':" in context.read_text():
            print(f"kept {context}")
        else:
            print(f"warning: kept {context}; add case '{ctx['resolver']['pagekey']}' to its "
                  f"resolve_page_instance_url()", file=sys.stderr)

    generator = root / "tests" / "generator" / "lib.php"
    if ptype == "mod" and not generator.exists():
        gctx = {"component": ctx["component"],
                "copyright": recipe.get("copyright", default_copyright(datetime.date.today().year))}
        gctx["header"] = header(f"Data generator for {ctx['component']}.", gctx)
        generator.parent.mkdir(parents=True, exist_ok=True)
        generator.write_text(render((TEMPLATES / "generator.php.tpl").read_text(), gctx))
        print(generator)
    elif ptype == "mod":
        print(f"kept {generator}")
    print(f"check: ~/.claude/skills/moodle-ci/scripts/msteps --check {feature}")


if __name__ == "__main__":
    main()
