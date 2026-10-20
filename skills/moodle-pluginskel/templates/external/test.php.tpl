<?php
{{header}}

namespace {{component}}\external;

{{#legacy}}
defined('MOODLE_INTERNAL') || die();

global $CFG;
require_once($CFG->libdir . '/externallib.php');

{{/legacy}}
/**
 * Tests for the {{component}}_{{name}} external function.
 *
 * @package    {{component}}
 * @category   test
 * @covers     \{{component}}\external\{{name}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
final class {{name}}_test extends \advanced_testcase {
    /**
     * Calls execute as admin and cleans the result like the web service server does.
     */
    public function test_execute(): void {
{{#table}}
        global $DB, $USER;

{{/table}}
        $this->resetAfterTest();
        $this->setAdminUser();
{{setup}}{{#table}}
        $other = $this->getDataGenerator()->create_user();
        $ownid = $DB->insert_record('{{table}}', [
{{ownrow}}        ]);
        $DB->insert_record('{{table}}', [
{{otherrow}}        ]);
{{/table}}

        $result = {{name}}::execute({{args}});
        $result = {{apiclass}}::clean_returnvalue({{name}}::execute_returns(), $result);
{{#notable}}
        $this->assertIsArray($result);
{{/notable}}
{{#table}}
        $this->assertCount(1, $result);
{{asserts}}{{/table}}
    }
}
