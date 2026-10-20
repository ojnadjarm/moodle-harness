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
#[CoversClass(\backup_{{pluginname}}_activity_structure_step::class)]
#[CoversClass(\restore_{{pluginname}}_activity_structure_step::class)]
{{/attributes}}
final class backup_restore_test extends \advanced_testcase {
    /**
     * A course with one instance and one row per child table restores into a new course with every row.
{{#docblock}}
     *
     * @covers \backup_{{pluginname}}_activity_structure_step
     * @covers \restore_{{pluginname}}_activity_structure_step
{{/docblock}}
     */
    public function test_backup_and_restore_into_new_course(): void {
        global $CFG, $DB, $USER;
        require_once($CFG->dirroot . '/backup/util/includes/backup_includes.php');
        require_once($CFG->dirroot . '/backup/util/includes/restore_includes.php');
        require_once($CFG->dirroot . '/course/lib.php');

        $this->resetAfterTest();
        $this->setAdminUser();
        $generator = $this->getDataGenerator();
        $course = $generator->create_course();
{{#hasusers}}
        $user = $generator->create_user();
        $generator->enrol_user($user->id, $course->id);
{{/hasusers}}
        $instanceid = create_module((object) [
            'modulename' => '{{pluginname}}',
            'course' => $course->id,
            'section' => 0,
            'visible' => 1,
            'name' => 'Backup test',
            'introeditor' => ['text' => '', 'format' => FORMAT_HTML, 'itemid' => file_get_unused_draft_itemid()],
{{rootvalues}}        ])->instance;
{{#haschildren}}
        $ids = [];
{{/haschildren}}
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

        $restored = $DB->get_records('{{pluginname}}', ['course' => $newcourseid]);
        $this->assertCount(1, $restored);
        $newinstance = reset($restored);
{{#rootusers}}
        $this->assertEquals($user->id, $newinstance->{{field}});
{{/rootusers}}
{{#children}}
        $this->assertEquals(1, $DB->count_records('{{table}}', ['{{parentfield}}' => $newinstance->id]));
{{/children}}
{{#userasserts}}
        $this->assertEquals($user->id, $DB->get_field('{{table}}', '{{field}}', ['{{parentfield}}' => $newinstance->id]));
{{/userasserts}}
    }
}
