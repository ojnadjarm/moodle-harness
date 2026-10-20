# Moodle Coding Style Guide (local reference)

Source: https://moodledev.io/general/development/policies/codingstyle
Mirror: ~/.moodle-devdocs/general/development/policies/codingstyle/index.md (upstream 2026-10-15, condensed 2026-10-20).
Headings mirror upstream; `~/.claude/skills/moodle-guidelines/tests/style-coverage.test.sh` lists any upstream section missing here.

## Overview

Defers to PSR-12, then PSR-1, where this guide is silent.

### Useful tools
Check code with both the Code checker (`local_codechecker`, phpcs) and the PHPdoc checker (`local_moodlecheck`);
they check different things.

---

## File Formatting

### PHP Tags
Long PHP tags only. No closing `?>` at end of files (avoids whitespace problems). SQL has its own
indentation rules (SQL coding style).

```php
<?php
require('config.php');
```

### Maximum Line Length
Aim for 132 chars when convenient; do not exceed ~180. Exception: `/lang` files keep
string values as single unbroken quoted strings (no concatenation, heredoc or nowdoc).

#### Wrapping lines
Indent wrapped lines 4 spaces by default; wrapped control-statement conditions and function/class
declarations get 4 additional spaces (8) so they stand apart from the body.

#### Wrapping control structures
```php
while ($fileinfolevel && $params['component'] === 'user'
        && $params['filearea'] === 'private') {
    $fileinfolevel = $fileinfolevel->get_parent();
}
```

#### Wrapping if-statement conditions
Same rule as control structures. With several conditions, prefer named helper variables over a long
wrapped condition.

```php
$iscourseorcategoryitem = ($element['object']->is_course_item() || $element['object']->is_category_item());
$usesscaleorvalue = in_array($element['object']->gradetype, [GRADE_TYPE_SCALE, GRADE_TYPE_VALUE]);
if ($iscourseorcategoryitem && $usesscaleorvalue) {
    // Readable condition.
}
```

### Line Termination
- Unix LF only (0x0A). No CR (0x0D), alone or with LF.
- No trailing whitespace.
- No extra blank lines at end of file; end with a single LF.

### Whitespace
No trailing whitespace anywhere, including inside multiline string literals such as SQL.

#### Assignment operator
One or more spaces allowed before `=`; exactly one after. Follow surrounding/similar code.

```php
$foo    = true;
$foobar = false;
$bafoo  = 'Hello world';
```

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
Uppercase, Frankenstyle prefix (activities: module name only), underscore separated.

```php
define('BLOCK_COURSE_OVERVIEW_SHOWCATEGORIES_NONE', '0');
define('FORUM_MODE_FLATOLDEST', 1);
```

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

## Strings

Readability is the criterion.

### Single quotes
For literals or strings with many double quotes (HTML):

```php
$a = 'Example string';
echo '<span class="'.s($class).'"></span>';
```

### Double quotes
For plain variables or many single quotes; complex SQL always in double quotes:

```php
echo "<span>$string</span>";
$sql = "SELECT e.*, ue.userid
          FROM {user_enrolments} ue
          JOIN {user} u ON u.id = ue.userid
         WHERE :now - u.lastaccess > e.customint2";
```

### Variable substitution
Both acceptable:

```php
$greeting = "Hello $name, welcome back!";
$greeting = "Hello {$name}, welcome back!";
```

### String concatenation
Use `.`; spaces around it optional. When wrapping, dot at the line end:

```php
$string = 'This is very long ' . $editorname .
    " couldn't think of better example.";
```

### Language strings

#### Capitals
Only at sentence start or proper names (`Always look like this`, not `Never Like This`).

#### Structure
Each string stands alone; never designed for concatenation into sentences.

```php
$string['overduehandling'] = 'Time expiry behaviour';
$string['overduehandlingautosubmit'] = 'Unfinished attempts will be autosubmitted immediately';
```

#### Whitespace
No leading or trailing whitespace in strings, and never rely on it (breaks AMOS translation).

---

## Objects

### Importing `stdClass`
In namespaced code, `use stdClass;` or `\stdClass` are both fine.

```php
use stdClass;
$foo = new stdClass();
```

### Dynamic properties
Cast an associative array or assign onto a new `stdClass`:

```php
$foo = (object) ['bar' => 1, 'baz' => 2];
```

### Empty objects
`(object) []` or `new stdClass()`, also inside arrays/objects and as return values:

```php
$boo = ['far' => (object) []];
return new stdClass();
```

---

## Arrays

### Array syntax
Short syntax for all new code; long `array()` only to match surrounding code (also in casts).

```php
$myarray = ['some', 'value'];
$myobject = (object) ['some' => 'value'];
```

### Numerically indexed arrays
Space after each comma; continuation lines indented 4; brackets and newlines balanced; trailing comma
recommended on multi-line:

```php
$myarray = [
    1, 2, 3, 'Stuff', 'Here',
    $a, $b, $c, 56.44, $d, 500,
];
```

### Associative arrays
Multiple lines when it helps readability:

```php
$myarray = [
    'firstkey' => 'firstvalue',
    'secondkey' => 'secondvalue',
];
```

---

## Classes

### Class declarations
- Moodle naming; in `component/classes/` (autoloading, namespaces).
- One class/interface/trait per file (old multi-artifact APIs excepted).
- Complete PHPDoc block; 4-space indentation.
- No side-effects in class files except requiring non-autoloaded code, which then needs the
  `MOODLE_INTERNAL` check.

```php
/**
 * Short description for class.
 *
 * @package    mod_mymodule
 * @copyright  2008 Kim Bloggs
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class sample_class {
}
```

### Class member variables
Variable naming rules; declared at top, above methods. Never `var`; always `private`/`protected`/`public`.
Public properties allowed but discouraged in favour of get/set methods.

```php
class zebra {
    /** @var int The number of white stripes */
    protected $whitestripes = 0;
}
```

---

## Functions and methods

### Function and method declaration
Moodle function naming. Methods always declare visibility. Opening brace on the same line, no space
before `(`, return value not in parentheses, one return type (multiple discouraged).

```php
public function sample_function() {
    return true;
}
```

### Function and method usage
Single space after each comma:

```php
three_arguments(1, 2, 3);
```

### Magic methods
Heavily discouraged; justification required (laziness is not one).

### Using arrays for options as arguments
List every argument explicitly with a type and default instead of a generic `array $options` (or use a
dedicated options class); a generic array needs a stated reason.

```php
function good_function(
    string $text,
    ?context $context = null,
    bool $trusted = false,
    bool $filter = true,
): string;
```

---

## Control statements

Use whitespace between lines liberally.

### If / else
Space before/after the bracketed condition, operators spaced, 4-space indent, `else if` (never
`elseif`), always braces, opening brace on the same line:

```php
if ($x == $y) {
    $a = $b;
} else if ($x == $z) {
    $a = $c;
} else {
    $a = $d;
}
```

### Switch
Cases indented 4, case content 4 more:

```php
switch ($something) {
    case 1:
        break;
    default:
        break;
}
```

### Foreach
```php
foreach ($objects as $key => $thing) {
    process($thing);
}
```

### Ternary Operator
Only for short statements understandable in one sentence, spaces around `?` and `:`; prefer `??` for
`isset()` ternaries:

```php
$users = is_array($users) ? $users : [$users];
$username = $user->username ?? '';
```

---

## Require / include

Browser-accessed files start with:

```php
require(__DIR__ . '/../../config.php');
```

Other includes use `__DIR__` or `$CFG->dirroot`/`$CFG->libdir`; never `../`-relative paths (CLI scripts
included). Library files use `require_once`; include only at file top or inside the function needing it:

```php
require_once(__DIR__ . '/locallib.php');
require_once($CFG->libdir . '/filelib.php');
```

Files with side-effects (global code other than `namespace`, `use`, namespace constants, `declare`),
except imported third-party libs, start with:

```php
defined('MOODLE_INTERNAL') || die();
```

---

## Documentation and comments

### PHPDoc
Standard phpDocumentor format for files, classes, functions, with the Moodle rules below.

#### Types
Short names (`bool`, `int`, not `boolean`/`integer`); `array`/`stdClass` (not `Array`/`object`); class
names; `true|false|null` lowercase; `static`, `self`, `$this`, `void`. Arrays of a type as `int[]`;
alternatives with a pipe (`int|false`); primitives lowercase, classes in their original case.

```php
/**
 * @param stdClass $obj Some object.
 * @return static The instance itself.
 */
```

#### Tags

##### `@copyright`
`@copyright 2008 Kim Bloggs` (year + original creator). Never change existing ones.

##### `@license`
`@license https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later`

##### `@param`
`@param type $name Description.`: just a space after the name, no hyphens.

##### `@return`
`@return type Description.`: mandatory if the function has a return statement; description optional
when obvious.

##### `@var`
`@var type Description.` for properties and constants (never `@const`). Inline `@var` in method
bodies only when no type can express a value; don't abuse.

##### `@uses`
`@uses exit` when a function may call `die`/`exit`.

##### `@access`
`@access private` only where the definition lacks access control; never redundant `public` on functions.

##### `@package`
Required, exactly one Frankenstyle component: plugin (`mod_quiz`), core subsystem (`core_enrol`), or
`core`. No `@subpackage` standard.

##### `@category`
Only for public items that are part of (or exemplify) a Core API; value from the API guides list
(`@category preferences`).

##### `@since`
New core classes/functions/methods: `@since Moodle 2.1`.

##### `@see`
Related code element (not URLs), also inline: `{@see get_string()}`.

##### `@link`
External URL, also inline: `{@link https://docs.moodle.org/dev/Core_APIs}`.

##### `@deprecated` (and `@todo`)
State the version and MDL; add `@todo` and `@see`. Optionally `debugging('...', DEBUG_DEVELOPER)`, or
throw `coding_exception` if unsupportable (see `lib/deprecatedlib.php`).

```php
 * @deprecated since Moodle 2.0 MDL-12345 - please do not use this function any more.
 * @todo MDL-22334 This will be deleted in Moodle 2.2.
 * @see class_name::new_function()
```

##### `@throws`
Optional; marks exceptions callers may need to handle.

##### Other specific tags
Only in context: `@Given/@When/@Then` (Behat steps); `@covers`, `@coversDefaultClass`, `@coversNothing`,
`@uses`, `@dataProvider`, `@testWith`, `@depends`, `@group`, `@requires`, `@runTestsInSeparateProcesses`,
`@runInSeparateProcess` (PHPUnit; separate processes only when strictly needed).

### Files
Every PHP file: GPL block right after `<?php` (no blank line), then a separate docblock with short
description, optional long description, `@package` (required), `@category` (only if wholly one Core
API), `@copyright` and `@license` (required). Single-artifact files may skip it if the class docblock
carries the tags.

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

### Classes
Every class has a complete docblock. In single-artifact files (all of `classes/`) the class docblock is
enough; `@package`, `@copyright`, `@license` (and optional `@category`) must appear together in one
docblock of the file.

```php
/**
 * Short description for class.
 *
 * @package    mod_mymodule
 * @copyright  2008 Kim Bloggs
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class policy_issue {
```

### Properties
Every property gets its own docblock (no DocBlock templates):

```php
/** @var string This variable does something */
protected $something;
```

### Constants
Class constants documented:

```php
/**
 * This is used when Sam is in a good mood.
 */
const MOOD_GOOD = 0;
```

### Functions
Every function/method has a complete docblock with a description, even if obvious. Unchanged overrides:
omit the docblock and use `#[\Override]`; `@inheritdoc`/`@see` as a docblock replacement is forbidden.

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

### Defines
```php
/**
 * PARAM_INT - integers only, use when expecting only numbers.
 */
define('PARAM_INT', 'int');
```

### Inline comments
`// ` (two slashes + space), aligned with the code; first char capital (or digit or `...`); end with
`.`, `?` or `!`. No `#` or `/* */`. No MDL references except in TODOs.

```php
$ratings = [];     // Initialize the empty array.
```

#### Using TODO
Every TODO carries an MDL reference (and goes on the Review TODOs epic MDL-47779):

```php
// TODO MDL-12345 This works but is a hack needing revision.
```

### CVS keywords
No CVS keywords (`$Id$`) since Moodle 2.0.

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

## Policy about coding-style only fixes

New code must conform; old code is fixed progressively (MDL-43233):

1. Related style fixes (same lines, adjacent comments) are fine inside a real issue.
2. Unrelated style fixes inside a real issue: main only, separate commit.
3. Style-only issues: main only, first 2 months of a cycle.

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
