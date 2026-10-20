<?php
{{header}}

namespace {{component}}\output;

/**
 * Tests for the {{name}} output class.
 *
 * @package    {{component}}
 * @category   test
 * @covers     \{{component}}\output\{{name}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
final class {{name}}_test extends \advanced_testcase {
    /**
     * The export has one formatted key per field, in field order.
     */
    public function test_export_for_template(): void {
        global $PAGE;
        $widget = new {{name}}({{args}});
        $data = $widget->export_for_template($PAGE->get_renderer('core'));
        $this->assertSame([{{keys}}], array_keys($data));
        $this->assertSame([
{{expected}}
        ], $data);
    }
}
