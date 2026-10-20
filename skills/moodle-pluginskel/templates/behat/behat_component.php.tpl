<?php
{{header}}

// NOTE: no MOODLE_INTERNAL test here, this file may be required by behat before including /config.php.

require_once(__DIR__ . '/{{baserel}}lib/behat/behat_base.php');

/**
 * Step definitions for {{component}}.
 *
 * @package    {{component}}
 * @category   test
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class behat_{{component}} extends behat_base {
    /**
     * Convert page names to URLs for steps like 'When I am on the "[identifier]" "[page type]" page'.
     *
     * Recognised page names are:
     * | pagetype | name meaning | description |
     * | {{pagename}} | Course shortname, idnumber or fullname | {{path}} |
     *
     * @param string $page identifies which type of page this is, e.g. '{{pagename}}'.
     * @param string $identifier identifies the particular page, e.g. 'C1'.
     * @return moodle_url the corresponding URL.
     * @throws Exception with a meaningful error message if the specified page cannot be found.
     */
    protected function resolve_page_instance_url(string $page, string $identifier): moodle_url {
        switch (strtolower($page)) {
            case '{{pagekey}}':
                return new moodle_url('{{path}}', ['{{param}}' => $this->get_course_id($identifier)]);
            default:
                throw new Exception("Unrecognised {{component}} page type '{$page}'");
        }
    }
}
