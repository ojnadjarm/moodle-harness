# Moodle Upgrade notes

## 5.3

### core

#### Deprecated

- The following functions from `user/lib.php` have been deprecated and moved to the `\core\user` class as static methods. Existing calls emit a `DEBUG_DEVELOPER` notice:

   | Old function name    | New method name               |
   | ---                  | ---                           |
   | `user_create_user()` | `\core\user::create_user()`   |

  For more information see [MDL-82650](https://tracker.moodle.org/browse/MDL-82650)

## 5.2

### core_message

#### Removed

- - The following methods have been removed from `public/message/classes/api.php`:
    - `\core_message\api::get_messages()`

  For more information see [MDL-87426](https://tracker.moodle.org/browse/MDL-87426)

### core_calendar

#### Removed

- calendar_add_event_metadata() has been removed. Use `calendar_get_events()` instead.

  For more information see [MDL-87427](https://tracker.moodle.org/browse/MDL-87427)

## 5.1

### core_calendar

#### Deprecated

- The `calendar_add_event_metadata()` function has been deprecated.

  For more information see [MDL-80000](https://tracker.moodle.org/browse/MDL-80000)

## 4.5

### core

#### Removed

- `old_45_function()` has been removed.
