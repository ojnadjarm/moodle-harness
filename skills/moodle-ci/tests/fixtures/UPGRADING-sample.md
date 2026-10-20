# Moodle Upgrade notes

Trimmed from core 5.3 UPGRADING.md for the mapicompat test.

## 5.3

### core

#### Added

- Boost now has a dark colour mode, so a plugin's styles.css can no longer assume the page is light. Styles work in both modes if they take their colours from the Bootstrap custom properties (--bs-body-bg, --bs-body-color).

  For more information see [MDL-68037](https://tracker.moodle.org/browse/MDL-68037)
- `email_to_user()` now emits a hook `before_email_to_user`. This hook allows any subscriber to modify the email contents.

  For more information see [MDL-69724](https://tracker.moodle.org/browse/MDL-69724)
- A new Behat step `I set the focus on the "<element>" "<selector>"` has been added to move keyboard focus onto an element without activating it.

  For more information see [MDL-84065](https://tracker.moodle.org/browse/MDL-84065)
- New methods have been added to `\core\session\manager` to replace the `NO_MOODLE_COOKIES` constant.

  Instead of checking the value of `NO_MOODLE_COOKIES`, you can check whether cookies are currently supported using:

  ```php
  \core\session\manager::supports_cookies();
  ```

  To update the value and start a new session you can use:

  ```php
  \core\session\manager::set_cookies_supported(true);
  \core\session\manager::start();
  ```

  For more information see [MDL-87174](https://tracker.moodle.org/browse/MDL-87174)
- The `moodle_page` class now includes `set_has_sticky_footer()` and `has_sticky_footer()` to track sticky footer presence and prevent redundant renders.

  For more information see [MDL-87302](https://tracker.moodle.org/browse/MDL-87302)
- Added `moodle_page::set_show_navigation_footer(bool $show)` to control whether the sticky navigation footer is rendered. Use $PAGE->set_show_navigation_footer(false); to suppress the footer on pages where it is not required.

  For more information see [MDL-87575](https://tracker.moodle.org/browse/MDL-87575)
- A new `\core\api\token_manager` class mints personal access tokens for the REST API.

  For more information see [MDL-87706](https://tracker.moodle.org/browse/MDL-87706)
- Added new 'url' optional parameter to `core\output\action_menu\subpanel` so subpanel menu elements can have their own link.

  For more information see [MDL-88312](https://tracker.moodle.org/browse/MDL-88312)
- A new `swizzle` command has been added to launch an interactive CLI wizard for ejecting or wrapping a React component into your theme:

  ```bash
  ./scripts/swizzle.mjs
  ```

  For more information see [MDL-88509](https://tracker.moodle.org/browse/MDL-88509)
- The internal password management functions and authentication plugin registry functions now delegate to new DI-resolvable classes `\core\authentication\password` and `\core\authentication` respectively. The global functions remain available as backward-compatible wrappers.

  | Global function | New method |
  |---|---|
  | `validate_internal_user_password()` | `\core\authentication\password::validate()` |
  | `exists_auth_plugin()` | `\core\authentication::plugin_exists()` |
  | `get_auth_plugin()` | `\core\authentication::get_plugin()` |

  For more information see [MDL-88580](https://tracker.moodle.org/browse/MDL-88580)

#### Changed

- Added `fake_changed_function()` to a changed section: never a symbol.

  For more information see [MDL-99999](https://tracker.moodle.org/browse/MDL-99999)

#### Deprecated

- The `\core\task\manager::task_is_scheduled()` method has been deprecated. Use `\core\task\manager::get_queued_adhoc_task_record()` directly instead.

  For more information see [MDL-88845](https://tracker.moodle.org/browse/MDL-88845)
- The `FEATURE_GROUPMEMBERSONLY` constant has been deprecated and is no longer supported. It should be removed from any plugin code.

  For more information see [MDL-83231](https://tracker.moodle.org/browse/MDL-83231)
- The following legacy classes and functions have been deprecated and replaced with correctly namespaced alternatives:

   | Old name                   | New name                                |
   | ---                        | ---                                     |
   | `\external_api`            | `\core_external\external_api`            |
   | `external_format_string()` | `\core_external\util::format_string()`   |

  For more information see [MDL-81225](https://tracker.moodle.org/browse/MDL-81225)
- The class core_badges_assertion has been deprecated and replaced by \core_badges\achievement_credential. The method badges_get_default_issuer() has also been deprecated because it is no longer needed.

  For more information see [MDL-85621](https://tracker.moodle.org/browse/MDL-85621)
- Deprecated the Behat step `behat_mod_workshop::i_set_portfolio_instance_to`, please use `behat_portfolio::i_set_the_portfolio_instance_to` instead.

  For more information see [MDL-89069](https://tracker.moodle.org/browse/MDL-89069)

## 5.2

### core_customfield

#### Added

- Added new `\core_customfield\api::is_shortname_unique(...)` method to determine whether a shortname is available for use inside a given handler

  For more information see [MDL-87059](https://tracker.moodle.org/browse/MDL-87059)

### core

#### Added

- The Checks API now supports multiple results being returned for a single instance of `\core\check\check`.

  To support this a new `get_results(): array;` method has been created which returns an array of `\core\check\result` objects.

  For more information see [MDL-87648](https://tracker.moodle.org/browse/MDL-87648)

### mod_subsection

#### Added

- The `manager::clear_description()` method has been added to remove legacy data.

  For more information see [MDL-87621](https://tracker.moodle.org/browse/MDL-87621)

#### Removed

- The following functions have been removed from `public/lib/deprecatedlib.php`:
  - `cron_run()`
  - `get_context_instance()`

  For more information see [MDL-87425](https://tracker.moodle.org/browse/MDL-87425)
- The following functions have been removed from `public/lib/javascript-static.js`:
  - `checkall()`

  For more information see [MDL-87426](https://tracker.moodle.org/browse/MDL-87426)
- The following methods have been removed from `public/backup/controller/base_controller.class.php`:
  - `get_copy()`

  For more information see [MDL-83479](https://tracker.moodle.org/browse/MDL-83479)
- The following methods have been removed:
  - `\grade_report_grader::get_icons()`

  For more information see [MDL-87425](https://tracker.moodle.org/browse/MDL-87425)

## 5.1

### core_courseformat

#### Added

- New needs_filtering_by_groups() and get_groups_for_filtering() had been created in activityoverviewbase class for a better management of groups filtering.

  For more information see [MDL-85852](https://tracker.moodle.org/browse/MDL-85852)

## 5.0

### core_backup

#### Added

- Added several hooks to the restore process to

   1. Hook to allow extra settings to be defined for the course restore process.

  Other changes include
   1. `base_task::add_setting()` is now public to allow hook callbacks to add settings.
   2. Settings are now added to the data sent to the course_restored event.

  For more information see [MDL-83479](https://tracker.moodle.org/browse/MDL-83479)

#### Deprecated

- The `cron_run()` function has been deprecated. Please use `\core\cron::run_main_process()` instead.

  For more information see [MDL-81070](https://tracker.moodle.org/browse/MDL-81070)
- The following methods have been deprecated:
  - grade_report_grader::get_icons
  - `\grade_report_user::get_icons()`

  For more information see [MDL-77307](https://tracker.moodle.org/browse/MDL-77307)

## 4.5

### core

#### Added

- A new hook called `\core\hook\output\after_http_headers` has been created. This hook allow plugins to modify the content after headers are sent.

  For more information see [MDL-82130](https://tracker.moodle.org/browse/MDL-82130)
