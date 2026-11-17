# Moodle Coding Style Guide (local reference)

Source: https://moodledev.io/general/development/policies/codingstyle
Mirror: ~/.moodle-devdocs/general/development/policies/codingstyle/index.md (upstream 2026-10-15, condensed 2026-10-20).
Headings mirror upstream minus the sections the checkers enforce; `~/.claude/skills/moodle-guidelines/tests/style-coverage.test.sh` lists any other upstream section missing here.

## Overview

Defers to PSR-12, then PSR-1, where this guide is silent.

### Useful tools
Check code with both the Code checker (`local_codechecker`, phpcs) and the PHPdoc checker (`local_moodlecheck`);
they check different things.
Formatting, strings, objects, arrays, classes, functions, control statements, require/include and
docblocks are left to those checkers (`/moodle-ci`: codechecker, phpdoc); the upstream page has them.

---

## Naming Conventions

### Filenames
Whole English words, as short as possible, lowercase only. Extensions: `.php`, `.html`, `.js`, `.css`, `.xml`.

### Classes
Lowercase English words separated by underscores. Always use `()` when instantiating.

```php
class some_custom_class {
    function class_method() {
        echo 'foo';
    }
}
$instance = new some_custom_class();
```

Plain objects use `stdClass` (never the deprecated `object` class):

```php
$row = new stdClass();
$row->id = $id;
$row->field = 'something';
$DB->insert_record('table', $row);

$row = (object) [
    'id' => $id,
    'field' => 'something',
];
```

### Functions and Methods
Lowercase English words separated by underscores; verbose, illustrative names are encouraged. Legacy
(non-class) functions need the Frankenstyle prefix (activity modules: module name only, e.g.
`forum_set_display_mode()`). Type hints and return types required in all possible places for new code.
No space between name and `(`, between `?` and the type, or between `)` and `:`.

```php
function report_participation_get_overviews(string $action, ?int $userid): ?array {
    // Function code.
}
```

Override parent methods with the `#[\Override]` attribute (phpcs then skips doc/naming sniffs on it):

```php
class example extends \Some\Vendor\ExampleClass {
    #[\Override]
    public function makeRequest(): void {
        // ...
    }
}
```

#### Function Parameters
Simple lowercase English words (`$initialvalue`), sensible defaults. Default `null` rather than `false`
when no value is needed; `true`/`false` fine for genuine boolean options. Use nullable hints on optional
typed params.

```php
public function foo($required, $optional = null);
public function get(?string $default = null): string;
```

### Web Service Functions
`{fullcomponent}_{methodname}` where method is `{verb}_{noun}` (verb preferably `get`, `create`,
`delete`, `update`):

```
core_block_get_dashboard_blocks
core_cohort_create_cohorts
core_cohort_delete_cohort_members
```

### Variables
Meaningful, short, lowercase English words run together. Plural for object arrays. Positive names
(`allow`/`enable`, not `prevent`/`disable`).

```php
$quiz = null;
$errorstring = null;
$assignments = null; // Array of objects.
$i = null;           // Only in small loops.
$allowfilelocking = false;
```

Invalid:
```php
$Quiz = null;            // Not all lowercase.
$camelCase = null;       // No camelCase/PascalCase.
$error_string = null;    // No underscores in variables.
$preventfilelocking = true; // Avoid negatives.
```

Core globals (uppercase, create no new ones): `$CFG`, `$SESSION`, `$USER`, `$COURSE`,
`$SITE`, `$PAGE`, `$PERF`, `$DB`, `$THEME`.

### Constants
New code declares class constants; global and namespaced constants are discouraged.

#### Class constants
Uppercase, underscore separated (PSR-1); no Frankenstyle prefix, the namespace names the component:
`public const MODE_FLAT_OLDEST = 1;`.

#### Global constants
Avoid in new code. Where used: uppercase, Frankenstyle prefix (activities: module name only), underscore separated.

```php
define('FORUM_MODE_FLATOLDEST', 1);
```

#### Namespaced constants
Avoid: autoloading does not load them; use a class constant.

### Booleans and the null value
Lowercase: `true`, `false`, `null`.

### Namespaces
Required for all new classes (no need to move old ones; Frankenstyle class-name prefix only where a
loader cannot handle namespaces). Classes live in `classes/` (`mod/forum/classes`, `lib/classes`,
`<subsystem>/classes`), follow autoloading rules. At most one namespace per file.

```php
<?php

namespace mod_porridge\local\equipment;

class spoon {
    // Code here.
}
```

#### Further notes
- Namespace line is the first non-comment line (a docblock may precede it), then 1 blank line, then `use`
  lines, one class each, alphabetically sorted, 1 blank line after the last.
- Class naming rules apply to every namespace level. Use maximum detail: `namespace xxxx\yyyy;`
  (component, API).
- Never import a whole namespace; no aliases (`use X as Y`) unless resolving a conflict.
- Never `__NAMESPACE__`, `namespace\Foo`, or bracketed `namespace { }` blocks.
- Namespaces only for classes in a subfolder of `classes/`.
- No leading `\` in `namespace`/`use` lines or on global functions; other-scope classes take a leading
  `\` or a `use`.

```php
<?php
namespace mod_breakfast\local;

use moodle_url;

echo get_string('goodmorning', 'mod_breakfast');
$url = new moodle_url('/mod/breakfast/view.php');
$tasks = \core\task\manager::get_all_scheduled_tasks();
$a = new \stdClass();
```

#### Parts of a namespace
`\<level1>\<level2>\<level3>\...\<classname>`; only level1 is mandatory.

#### Rules for level1
Full component name (`\mod_forum`; all a plugin's namespaced classes sit under it) or `\core` for core APIs.

#### Rules for level2
Short name of a core API the class implements or uses (`\mod_forum\external`), or `\local` for other
classes the maintainer wants to organise.

#### Rules for level3
No restrictions.

#### Namespaces within `**/tests` directories
Namespace strongly recommended and matching the code under test; test class named after the class
under test with `_test.php` suffix; level1 must be the component; sub-directories mirror the namespace
under `tests/`. Tests are not autoloaded.

```php
// Code: mod/breakfast/classes/local/utils/  Test: mod/breakfast/tests/local/utils/
namespace mod_breakfast\local\utils;
// Invalid: namespace mod_forum\test; (no "test" API under test)
```

---

## Exceptions

Use exceptions to report errors (esp. in library code). `print_error()` deprecated since
2021: throw `moodle_exception` instead. Only for erroneous situations, not normal flow.

### Exception classes
Base: `moodle_exception`; create subclasses where useful. Notable: `coding_exception` (developer mistake;
helpful message), `dml_exception` (DB failure), `file_exception` (File API). Since 4.5 custom exceptions
may live in `classes/exception/` with namespace `<plugin>\exception`.

```php
throw new \coding_exception('Invalid $mode: ' . $mode);
```

---

## Dangerous functions and constructs

Highly discouraged (security):

1. `eval()` (language packs excepted)
2. `preg_replace()` with `/e` modifier (use callbacks)
3. Backticks for shell execution
4. `goto` / labels
5. `unserialize()` on user-supplied data

---

## Git commits

```
MDL-xxxx CODE AREA: short summary (72 chars soft limit)

Blank line, then detailed explanation. Include motivation and
contrast with previous behavior.
```

Tell a clean history; include MDL issue number + CODE AREA; don't split atomic changes, don't include
pre-integration bug fixes or repeated revisions of the same lines.

---

## Related Standards

- Defers to PSR-12 and PSR-1 where unspecified.
- Separate guides: SQL coding style, JavaScript Coding Style, CSS Coding Style,
  Frankenstyle naming, PHP CodeSniffer, accessibility coding guidelines.
