<?php
{{header}}

namespace {{component}}\task;

/**
 * Tests for the {{name}} adhoc task.
 *
 * @package    {{component}}
 * @category   test
 * @covers     \{{component}}\task\{{name}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
final class {{name}}_test extends \advanced_testcase {
    /**
     * A queued task runs with its custom data and leaves the queue.
     */
    public function test_queue_and_run(): void {
        $this->resetAfterTest();
        \core\task\manager::queue_adhoc_task({{name}}::instance(42));
        $this->expectOutputRegex('/42/');
        {{runadhoc}}
        $this->assertEmpty(\core\task\manager::get_adhoc_tasks({{name}}::class));
    }
}
