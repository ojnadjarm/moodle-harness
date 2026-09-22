# Moodle Coding Style Guide (local reference)

Source: https://moodledev.io/general/development/policies/codingstyle
Saved so it doesn't need re-fetching each time. Refresh periodically if upstream changes.

---

## File Formatting

### PHP Tags
Long PHP tags only. No closing `?>` at end of files (avoids whitespace problems).

```php
<?php
require('config.php');
```

### Maximum Line Length
Aim for 132 chars when convenient; do not exceed ~180. Exception: `/lang` files keep
string values as single unbroken lines.

When wrapping: indent 4 spaces by default; wrapped lines in control structures or
declarations get 4 additional spaces.

### Line Termination
- Unix LF only (0x0A). No CR (0x0D).
- No trailing whitespace.
- Single LF at end of file.

### Whitespace
- No trailing whitespace anywhere (incl. SQL).
- One or more spaces allowed before `=`; one space only after.

```php
$foo    = true;
$foobar = false;
$bafoo  = 'Hello world';
```

---

## Naming Conventions

### Filenames
Whole English words, lowercase only. Extensions: `.php`, `.html`, `.js`, `.css`, `.xml`.

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

Plain objects use `stdClass`:

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
Lowercase English words separated by underscores. Legacy functions need Frankenstyle
prefix. Type hints and return types required for new code.

```php
function report_participation_get_overviews(
    string $action,
    ?int $userid
): ?array {
    // Function code
}
```

Override parent methods with the `#[\Override]` attribute:

```php
class example extends \Some\Vendor\ExampleClass {
    #[\Override]
    public function makeRequest(): void {
        // ...
    }
}
```

Parameters: lowercase, sensible defaults, prefer `null` over `false`. Nullable hints
for optional typed params.

```php
public function foo($required, $optional = null);
public function get(?string $default = null): string;
```

### Web Service Functions
`{fullcomponent}_{methodname}` where method is `{verb}_{noun}`:

```
core_block_get_dashboard_blocks
core_cohort_create_cohorts
core_cohort_delete_cohort_members
```

### Variables
Meaningful lowercase English words. Plural for object arrays. Positive names
(`allow`/`enable`, not `prevent`/`disable`).

```php
$quiz = null;
$errorstring = null;
$assignments = null; // Array of objects
$i = null;           // Only in small loops
$allowfilelocking = false;
```

Invalid:
```php
$Quiz = null;            // not all lowercase
$camelCase = null;       // no camelCase
$error_string = null;    // no underscores in variables
$preventfilelocking = true; // avoid negative
```

Core globals (uppercase, create no new ones): `$CFG`, `$SESSION`, `$USER`, `$COURSE`,
`$SITE`, `$PAGE`, `$PERF`, `$DB`, `$THEME`.

### Constants
Uppercase, Frankenstyle prefix, underscore separated.

```php
define('BLOCK_COURSE_OVERVIEW_SHOWCATEGORIES_NONE', '0');
define('FORUM_MODE_FLATOLDEST', 1);
```

### Booleans / Null
Lowercase: `true`, `false`, `null`.

### Namespaces
Required for all new classes. Live in `classes/` dir, autoloadable. One namespace per file.

```php
<?php
namespace mod_porridge\local\equipment;

class spoon {
    // Code here
}
```

Structure: `namespace xxxx\yyyy;` where `xxxx` = component, `yyyy` = API.

`use` statements: after namespace + 1 blank line; one class each; alphabetically sorted;
no whole-namespace imports; avoid aliases unless resolving conflicts; 1 blank line after.

```php
<?php
use mod_porridge\local\equipment\bowl;
use mod_porridge\local\equipment\spoon;
```

Levels: **L1** (mandatory) full component (`\mod_forum`) or `\core`. **L2** short core
API name or `\local`. **L3** plugin-specific, no restrictions.

Tests: namespace matches code under test. Test classes named after code class with
`_test.php` suffix; first-level namespace matches component.

```php
// Code: mod/breakfast/classes/local/utils/
// Test: mod/breakfast/tests/local/utils/
namespace mod_breakfast\local\utils;
```

---

## Strings

Single quotes for literals or strings with many double quotes:

```php
$a = 'Example string';
echo '<span class="'.s($class).'"></span>';
$html = '<a href="http://something" title="something">Link</a>';
```

Double quotes for variables or strings with many single quotes:

```php
echo "<span>$string</span>";
$statement = "You aren't serious!";
```

Complex SQL in double quotes:

```php
$sql = "SELECT e.*, ue.userid
        FROM {user_enrolments} ue
        JOIN {enrol} e ON (e.id = ue.enrolid AND e.enrol = 'self')
        JOIN {user} u ON u.id = ue.userid
        WHERE :now - u.lastaccess > e.customint2";
```

Variable substitution — both acceptable:

```php
$greeting = "Hello $name, welcome back!";
$greeting = "Hello {$name}, welcome back!";
```

Concatenation with `.`; dot at line end when wrapping:

```php
$longstring = $several . $short . 'strings';
$string = 'This is very long ' . $editorname .
    " couldn't think of better example.";
```

Language strings: capitals only at sentence start/proper names; must stand alone (no
concatenation); no leading/trailing whitespace.

```php
$string['overduehandling'] = 'Time expiry behaviour';
$string['overduehandlingautosubmit'] = 'Unfinished attempts will be autosubmitted';
```

---

## Objects

```php
use stdClass;
$foo = new stdClass();
// or
$foo = new \stdClass();

// Dynamic properties
$foo = (object) ['bar' => 1, 'baz' => 2];
$foo = new stdClass();
$foo->bar = 1;

// Empty
$foo = (object) [];
$foo = new stdClass();
```

---

## Arrays

Short syntax for all new code (long syntax only to match surrounding code).

```php
$myarray = [];
$myarray = ['some', 'value'];
$myarray = ['some' => 'value'];
$myobject = (object) ['some' => 'value'];
```

Numerically indexed — trailing space after commas, trailing comma recommended:

```php
$myarray = [1, 2, 3, 'Stuff', 'Here'];
$myarray = [
    1, 2, 3, 'Stuff', 'Here',
    $a, $b, $c, 56.44, $d, 500,
];
```

Associative — multiple lines:

```php
$myarray = [
    'firstkey' => 'firstvalue',
    'secondkey' => 'secondvalue',
];
```

---

## Classes

- One class per file (documented exceptions), in `component/classes/`.
- Complete PHPDoc. 4-space indentation.
- Member variables declared at top, above methods. Never `var`. Always declare
  visibility (`private`/`protected`/`public`). Document each property explicitly.

```php
/**
 * Short description for class.
 *
 * @package    mod_mymodule
 * @copyright  2008 Kim Bloggs
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class zebra {
    /** @var int The number of white stripes */
    protected $whitestripes = 0;

    /** @var int The number of black stripes */
    protected $blackstripes = 0;
}
```

---

## Functions and Methods

Opening brace on same line. No space between name and `()`. Return values not in
parentheses. Methods declare visibility. Type hints + return types for new code.

```php
public function sample_function() {
    return true;
}
```

Calls — single trailing space after commas:

```php
three_arguments(1, 2, 3);
```

Magic methods heavily discouraged. List all arguments explicitly with types rather than
generic `array $options` (or use a dedicated options class):

```php
function good_function(
    string $text,
    ?context $context = null,
    bool $trusted = false,
    bool $filter = true,
): string;
```

---

## Control Statements

If/else — spaces around, 4-space indent, `else if` (not `elseif`), always braces:

```php
if ($x == $y) {
    $a = $b;
} else if ($x == $z) {
    $a = $c;
} else {
    $a = $d;
}
```

Switch — cases indented 4, content 4 more:

```php
switch ($something) {
    case 1:
        break;
    case 2:
        break;
    default:
        break;
}
```

Foreach:

```php
foreach ($objects as $key => $thing) {
    process($thing);
}
```

Ternary — only short/simple, spaces around operators, prefer `??`:

```php
$username = isset($user->username) ? $user->username : '';
$username = $user->username ?? '';
```

---

## Require / Include

Browser-accessed files start with:

```php
require(__DIR__ . '/../../config.php');
```

Use `__DIR__` or absolute paths from `$CFG->dirroot`/`$CFG->libdir`. Avoid `../` relative
includes. Library files use `require_once`:

```php
require_once(__DIR__ . '/locallib.php');
require_once($CFG->libdir . '/filelib.php');
```

Single-artifact files / non-imported third-party libs add at top:

```php
defined('MOODLE_INTERNAL') || die();
```

---

## Documentation and Comments (PHPDoc)

Types: short names (`bool` not `boolean`); arrays as `type[]`; multiple via pipe
(`int|false`); primitives/keywords lowercase.

Key tags:
- `@package` (required) — Frankenstyle component (`mod_quiz`, `core_enrol`, `core`).
- `@copyright` (required) — `2008 Kim Bloggs`. Don't change existing.
- `@license` (required) — `https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later`.
- `@param [[type]] $name Description.` — space after name, no hyphens.
- `@return [[type]] Description.` — mandatory if function returns.
- `@var [[type]] Description.` — properties/constants.
- `@category` — Core APIs only.
- `@since Moodle 2.1`, `@see other_function()`, `@link https://...`, `@throws`,
  `@deprecated since Moodle 2.0 MDL-12345`, `@todo MDL-xxxx`, `@uses exit`.
- Never use `@inheritdoc` as a complete docblock replacement; use `#[\Override]` instead.

File header (GPL block + docblock):

```php
<?php
// This file is part of Moodle - https://moodle.org/
//
// Moodle is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Moodle is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Moodle. If not, see <https://www.gnu.org/licenses/>.

/**
 * This is a one-line short description of the file.
 *
 * @package    mod_mymodule
 * @category   backup
 * @copyright  2008 Kim Bloggs
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
```

Inline comments: `// ` (two slashes + space), first line capitalised, end with
punctuation. No `#` or `/* */` for single-line. Reference MDL issues where relevant.

```php
$ratings = [];     // Initialize the empty array.
// TODO MDL-12345 This works but is a hack needing revision.
```

Function docblock example:

```php
/**
 * Description first, with asterisks laid out exactly like this.
 *
 * @see clean_param()
 * @param int   $postid The PHP type followed by variable name
 * @param array $scale The PHP type followed by variable name
 * @return bool A status indicating success or failure
 */
```

Constants/defines documented:

```php
/**
 * PARAM_INT - integers only, use when expecting only numbers.
 */
define('PARAM_INT', 'int');
```

No CVS keywords (`$Id$`) since Moodle 2.0.

---

## Exceptions

Use exceptions to report errors (esp. in library code). `print_error()` deprecated since
2021 — throw `moodle_exception()` instead. Only for erroneous situations, not normal flow.

Base: `moodle_exception`. Notable: `coding_exception` (developer mistake), `dml_exception`
(DB failure), `file_exception`. Since Moodle 4.5, custom exceptions may live in
`classes/exception/` with namespace `<plugin>\exception`.

---

## Dangerous Constructs (highly discouraged)

1. `eval()`
2. `preg_replace()` with `/e` modifier (use callbacks)
3. Backticks for shell execution
4. `goto` / labels
5. `unserialize()` on user-supplied data

---

## Git Commits

```
MDL-xxxx CODE AREA: short summary (72 chars soft limit)

Blank line, then detailed explanation. Include motivation and
contrast with previous behavior.
```

Tell a clean history; include MDL issue number + CODE AREA; don't split atomic changes.

---

## Related Standards

- Defers to PSR-12 and PSR-1 where unspecified.
- Separate guides: SQL coding style, JavaScript Coding Style, CSS Coding Style,
  Frankenstyle naming.
