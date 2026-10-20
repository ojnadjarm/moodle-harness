<?php
{{header}}

namespace {{component}}\form;

use context;
use moodle_url;

/**
 * {{description}} form, opened in a modal by the {{component}}/{{name}} AMD module.
 *
 * @package    {{component}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class {{name}} extends \core_form\dynamic_form {
    /**
     * Form definition.
     */
    protected function definition() {
        $mform = $this->_form;
{{elements}}
    }

    /**
     * Context the form is submitted in.
     *
     * @return context
     */
    protected function get_context_for_dynamic_submission(): context {
{{contextcode}}
    }

    /**
     * Throws unless the user may use the form.
     */
    protected function check_access_for_dynamic_submission(): void {
{{login}}        require_capability('{{capability}}', $this->get_context_for_dynamic_submission());
    }

    /**
     * Processes the submitted form.
     *
     * @return \stdClass The submitted data
     */
    public function process_dynamic_submission() {
        return $this->get_data();
    }

    /**
     * Loads the form defaults.
     */
    public function set_data_for_dynamic_submission(): void {
        $this->set_data({{setdata}});
    }

    /**
     * URL of the page the form belongs to.
     *
     * @return moodle_url
     */
    protected function get_page_url_for_dynamic_submission(): moodle_url {
        return {{pageurl}};
    }
}
