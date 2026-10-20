<?php
{{header}}

namespace {{component}}\backup;
{{#attributes}}

use PHPUnit\Framework\Attributes\CoversClass;
{{/attributes}}

/**
 * Backup and restore tests for {{component}}.
 *
 * @package    {{component}}
 * @category   test
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
{{#attributes}}
#[CoversClass(\backup_{{component}}_plugin::class)]
#[CoversClass(\restore_{{component}}_plugin::class)]
{{/attributes}}
final class backup_restore_test extends \advanced_testcase {
    /**
     * A course with one row per course table restores into a new course with every row.
{{#docblock}}
     *
     * @covers \backup_{{component}}_plugin
     * @covers \restore_{{component}}_plugin
{{/docblock}}
     */
    public function test_backup_and_restore_into_new_course(): void {
        global $CFG, $DB, $USER;
        require_once($CFG->dirroot . '/backup/util/includes/backup_includes.php');
        require_once($CFG->dirroot . '/backup/util/includes/restore_includes.php');

        $this->resetAfterTest();
        $this->setAdminUser();
        $generator = $this->getDataGenerator();
        $course = $generator->create_course();
{{#hasusers}}
        $user = $generator->create_user();
        $generator->enrol_user($user->id, $course->id);
{{/hasusers}}
        $ids = [];
{{#children}}
        $ids['{{table}}'] = $DB->insert_record('{{table}}', [
{{values}}
        ]);
{{/children}}

        $bc = new \backup_controller(
            \backup::TYPE_1COURSE,
            $course->id,
            \backup::FORMAT_MOODLE,
            \backup::INTERACTIVE_NO,
            \backup::MODE_SAMESITE,
            $USER->id
        );
        $backupid = $bc->get_backupid();
        $basepath = $bc->get_plan()->get_basepath();
        $bc->execute_plan();
        $file = $bc->get_results()['backup_destination'];
        $bc->destroy();
        if (!file_exists($basepath . '/moodle_backup.xml')) {
            $file->extract_to_pathname(get_file_packer('application/vnd.moodle.backup'), $basepath);
        }
        $newcourseid = \restore_dbops::create_new_course($course->fullname . ' 2', $course->shortname . '_2', $course->category);
        $rc = new \restore_controller(
            $backupid,
            $newcourseid,
            \backup::INTERACTIVE_NO,
            \backup::MODE_SAMESITE,
            $USER->id,
            \backup::TARGET_NEW_COURSE
        );
        $this->assertTrue($rc->execute_precheck());
        $rc->execute_plan();
        $rc->destroy();

{{#children}}
        $this->assertEquals(1, $DB->count_records('{{table}}', ['{{coursefield}}' => $newcourseid]));
{{/children}}
{{#userasserts}}
        $this->assertEquals($user->id, $DB->get_field('{{table}}', '{{field}}', ['{{coursefield}}' => $newcourseid]));
{{/userasserts}}
    }
}
