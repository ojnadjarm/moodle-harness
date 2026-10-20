#!/usr/bin/env python3
"""Add a renderable, templatable output class to a plugin: class, mustache template with Example context, test, optional renderer method."""

import argparse
import datetime
import json
import re
import shutil
from pathlib import Path

from external import NAME, php_lint
from generate import GPL, TEMPLATES, default_copyright, fail, header, render

TPL = TEMPLATES / "output"
# Field type: PHP type, export expression, mustache tag, example value, PHP example.
TYPES = {
    "text": ("string", "format_string($this->{f})", "{{{{{{{f}}}}}}}", "{label} example", "'{label} example'"),
    "string": ("string", "s($this->{f})", "{{{{{{{f}}}}}}}", "{label} example", "'{label} example'"),
    "int": ("int", "$this->{f}", "{{{{{f}}}}}", 1, "1"),
    "url": ("\\moodle_url", "$this->{f}->out(false)", '<a href="{{{{{f}}}}}">{{{{{f}}}}}</a>',
            "https://example.com/view.php", "new \\moodle_url('https://example.com/view.php')"),
}


def parse_fields(spec):
    fields = []
    for item in spec.split(","):
        name, _, ftype = item.strip().partition(":")
        ftype = ftype or "text"
        if not NAME.fullmatch(name):
            fail(f"bad field name '{name}': use [a-z][a-z0-9_]*")
        if ftype not in TYPES:
            fail(f"bad field type '{ftype}' for '{name}': use one of {', '.join(TYPES)}")
        if any(name == f["name"] for f in fields):
            fail(f"duplicate field '{name}'")
        phptype, export, tag, example, phpexample = TYPES[ftype]
        label = name.replace("_", " ").capitalize()
        fields.append({
            "name": name, "type": ftype, "label": label, "phptype": phptype,
            "export": export.format(f=name), "tag": tag.format(f=name),
            "example": example.format(label=label) if isinstance(example, str) else example,
            "phpexample": phpexample.format(label=label),
        })
    return fields


def mustache_gpl():
    lines = [line[3:] for line in GPL.splitlines()]
    return "{{!\n" + "\n".join(f"    {line}" if line else "" for line in lines) + "\n}}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", help="plugin directory with version.php")
    parser.add_argument("name", help="output class and template name (e.g. summary)")
    parser.add_argument("--fields", required=True, help="comma list name:type, types: " + ", ".join(TYPES))
    parser.add_argument("--renderer", action="store_true", help="add render_<name>() to classes/output/renderer.php")
    args = parser.parse_args()

    plugin = Path(args.plugin).resolve()
    name = args.name
    if not NAME.fullmatch(name):
        fail(f"bad name '{name}': use [a-z][a-z0-9_]*")
    if name == "renderer":
        fail("name 'renderer' clashes with the plugin renderer class")
    fields = parse_fields(args.fields)
    versionphp = plugin / "version.php"
    if not versionphp.is_file():
        fail(f"{plugin} has no version.php")
    vtext = versionphp.read_text()
    cmatch = re.search(r"^\$plugin->component\s*=\s*'([a-z0-9]+_[a-z0-9_]+)';", vtext, re.M)
    if not cmatch:
        fail("version.php needs $plugin->component")
    component = cmatch.group(1)

    classfile = plugin / "classes/output" / f"{name}.php"
    templatefile = plugin / "templates" / f"{name}.mustache"
    testfile = plugin / "tests/output" / f"{name}_test.php"
    rendererfile = plugin / "classes/output/renderer.php"
    for path in (classfile, templatefile, testfile):
        if path.exists():
            fail(f"{path} already exists")
    renderer = None
    if args.renderer:
        if (plugin / "renderer.php").exists():
            fail(f"{plugin / 'renderer.php'} is a legacy renderer: add render_{name}() there by hand")
        if rendererfile.exists():
            renderer = rendererfile.read_text()
            if re.search(rf"function\s+render_{name}\s*\(", renderer):
                fail(f"render_{name}() already exists in {rendererfile}")

    copyright = re.search(r"@copyright\s+(.+)", vtext)
    description = name.replace("_", " ").capitalize()
    ctx = {
        "component": component, "name": name, "description": description,
        "copyright": copyright.group(1).strip() if copyright else default_copyright(datetime.date.today().year),
    }
    classctx = {
        **ctx, "header": header(f"{description} output class.", ctx),
        "properties": "\n\n".join(f"    /** @var {f['phptype']} {f['label']} */\n    protected {f['phptype']} ${f['name']};"
                                    for f in fields),
        "paramdocs": "\n".join(f"     * @param {f['phptype']} ${f['name']} {f['label']}" for f in fields),
        "params": ", ".join(f"{f['phptype']} ${f['name']}" for f in fields),
        "assigns": "\n".join(f"        $this->{f['name']} = ${f['name']};" for f in fields),
        "exports": "\n".join(f"            '{f['name']}' => {f['export']}," for f in fields),
    }
    example = json.dumps({f["name"]: f["example"] for f in fields}, indent=4)
    templatectx = {
        **ctx, "gpl": mustache_gpl(),
        "vardocs": "\n".join(f"    * {f['name']} - {f['label']} ({f['type']})" for f in fields),
        "example": "\n".join(f"    {line}" for line in example.splitlines()),
        "body": "\n".join(f"    <div>{f['tag']}</div>" for f in fields),
    }
    testctx = {
        **ctx, "header": header(f"Tests for the {name} output class.", ctx),
        "args": ", ".join(f["phpexample"] for f in fields),
        "keys": ", ".join(f"'{f['name']}'" for f in fields),
        "expected": "\n".join(f"            '{f['name']}' => {json.dumps(f['example']).replace(chr(34), chr(39))},"
                              for f in fields),
    }
    outputs = [
        (classfile, render((TPL / "class.php.tpl").read_text(), classctx)),
        (templatefile, render((TPL / "template.mustache.tpl").read_text(), templatectx)),
        (testfile, render((TPL / "class_test.php.tpl").read_text(), testctx)),
    ]
    if args.renderer:
        method = render((TPL / "method.php.tpl").read_text(), ctx)
        if renderer is None:
            renderer = render((TPL / "renderer.php.tpl").read_text(),
                              {**ctx, "method": method, "header": header(f"Renderer of {component}.", ctx)})
        else:
            end = renderer.rstrip().rfind("}")
            renderer = renderer[:end].rstrip("\n") + "\n\n" + method + renderer[end:]
        outputs.append((rendererfile, renderer))

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


if __name__ == "__main__":
    main()
