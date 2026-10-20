<?php
{{header}}

namespace {{component}}\task;

/**
 * Tests for the {{name}} scheduled task.
 *
 * @package    {{component}}
 * @category   test
 * @covers     \{{component}}\task\{{name}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
final class {{name}}_test extends \advanced_testcase {
{{#plain}}
    /**
     * The task is registered from db/tasks.php and runs.
     */
    public function test_execute(): void {
        $this->resetAfterTest();
        $task = \core\task\manager::get_scheduled_task({{name}}::class);
        $this->assertInstanceOf({{name}}::class, $task);
        $this->expectOutputRegex('/done/');
        $task->execute();
    }
{{/plain}}
{{#purge}}
    /**
     * The task deletes an old {{table}} row and keeps a new one.
     */
    public function test_execute(): void {
        global $DB;
        $this->resetAfterTest();
{{#setting}}
        set_config('{{setting}}', DAYSECS, '{{component}}');
{{/setting}}
        $DB->insert_record('{{table}}', ['{{timecol}}' => 1{{fill}}]);
        $keep = $DB->insert_record('{{table}}', ['{{timecol}}' => time(){{fill}}]);
        $task = \core\task\manager::get_scheduled_task({{name}}::class);
        $this->assertInstanceOf({{name}}::class, $task);
        $task->execute();
        $this->assertEquals(1, $DB->count_records('{{table}}'));
        $this->assertTrue($DB->record_exists('{{table}}', ['id' => $keep]));
    }
{{/purge}}
}
