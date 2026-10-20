<?php
{{header}}

namespace {{component}}\form;

/**
 * Tests for the {{name}} dynamic form.
 *
 * @package    {{component}}
 * @category   test
 * @covers     \{{component}}\form\{{name}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
final class {{name}}_test extends \advanced_testcase {
    /**
     * A user with the capability submits the form and gets the data back.
     */
    public function test_process_dynamic_submission(): void {
        $this->resetAfterTest();
{{setup}}        $this->setAdminUser();
        $data = {{name}}::mock_ajax_submit([
{{submitted}}
        ]);
        $form = new {{name}}(null, null, 'post', '', [], true, $data, true);
        $form->set_data_for_dynamic_submission();
        $this->assertTrue($form->is_validated());
        $result = $form->process_dynamic_submission();
{{asserts}}
    }

    /**
     * A user without the capability is refused.
     */
    public function test_access_denied(): void {
        $this->resetAfterTest();
{{setup}}        $this->setUser($this->getDataGenerator()->create_user());
        $data = {{name}}::mock_ajax_submit([{{contextargs}}]);
        $this->expectException(\moodle_exception::class);
        new {{name}}(null, null, 'post', '', [], true, $data, true);
    }
}
