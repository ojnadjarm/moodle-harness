# Writing Behat features for a Moodle plugin

Never invent step text: every line must match a definition of the target env.
- `$S/msteps <words…>`: definitions containing every word, from the env that mounts the cwd.
- `$S/msteps --check tests/behat/x.feature`: lists undefined step lines (rc 1); run it before `mtest behat`.
- Cache: `~/.cache/moodle-harness/steps-<version>-<root hash>.txt` (one per env root); `--refresh` after adding a `behat_<component>.php` step.

## File and tags
- Path: `<plugin>/tests/behat/<what>.feature`; one feature per user story.
- First line: `@<plugintype> @<component>` (e.g. `@mod @mod_forum`); `mtest behat --tags @<component>` selects it.
- `@javascript`: only on scenarios that need JS (modals, autocomplete, drag and drop, inline edit); non-JS runs are much faster.
- `@_file_upload`: needed for every "I upload … file to …" step (and `@javascript`).
- Other runner tags: `@_switch_window`, `@_switch_iframe`, `@_alert`.

## Data: generators, not UI clicks
- `Given the following "<entity>" exist:` + a table; the 5.2 core features use, most often:
  `users` (username), `courses` (fullname, shortname), `course enrolments` (user, course, role),
  `activities` (activity, name, course, idnumber), `groups`, `group members`, `categories`,
  `blocks`, `permission overrides`, `question categories`, `questions`.
- Plugin entities: `the following "<component> > <entity>" exist:` (e.g. `"mod_forum > discussions"`),
  defined in `tests/generator/behat_<component>_generator.php` `get_creatable_entities()` and backed by
  `tests/generator/lib.php`.
- Settings: `the following config values are set as admin:` with `| name | value |` rows, or a
  `| config | value | plugin |` header for plugin settings.

## Navigation: jump, do not click through menus
- `I am on the "<identifier>" "<type>" page logged in as "<user>"` (also without `logged in as`).
- Core types: `"C1" "Course"` (shortname), `"<idnumber>" "Activity"`, `"<idnumber>" "Activity editing"`,
  `"C1" "Course editing"`, `"<idnumber>" "Category"`.
- Plugin types: `"<identifier>" "<component> > <Page>"` (e.g. `"Quiz 1" "mod_quiz > View"`), resolved by
  `resolve_page_instance_url(string $type, string $identifier)` in `tests/behat/behat_<component>.php`.
- Pages without an instance: `I am on the "<component> > <Page>" page` → `resolve_page_url(string $page)`.

## Asserting and acting
- Prefer user-visible text: `I should see "X" in the "Y" "Z"` with Z a selector (`table_row`, `region`,
  `css_element`, `button`, `link`, `field`…).
- Forms: `I set the following fields to these values:` (field labels), `I press "Save changes"`.
- Custom steps: `behat_<component>.php` in `tests/behat/`, class extends `behat_base`, a docblock
  `@Given ...` / `@When ...` / `@Then ...`; prefer reusing core steps.

## Minimal feature
```gherkin
@mod @mod_forum
Feature: Students reply to a discussion
  In order to discuss a topic
  As a student
  I need to reply to a forum discussion

  Background:
    Given the following "users" exist:
      | username | firstname | lastname |
      | student1 | Student   | One      |
    And the following "courses" exist:
      | fullname | shortname |
      | Course 1 | C1        |
    And the following "course enrolments" exist:
      | user     | course | role    |
      | student1 | C1     | student |
    And the following "activities" exist:
      | activity | name    | course | idnumber |
      | forum    | Forum 1 | C1     | forum1   |

  Scenario: A student sees the forum
    When I am on the "forum1" "Activity" page logged in as "student1"
    Then I should see "Forum 1"
```

## Run
- `msteps --check` first, then `mtest behat <feature> [--tags @<component>]`; init happens only when stale.
- "not initialised" / "behat not enabled": `mtest init behat <plugin>`; never a full core Behat run.
