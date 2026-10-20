<?php
{{header}}

namespace {{component}}\event;

/**
 * Event {{name}}: {{description}}.
 *
 * @package    {{component}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class {{name}} extends \core\event\base {
    /**
     * Sets the CRUD letter, education level and object table.
     */
    protected function init() {
        $this->data['crud'] = '{{crud}}';
        $this->data['edulevel'] = self::{{edulevel}};
{{#objecttable}}
        $this->data['objecttable'] = '{{objecttable}}';
{{/objecttable}}
    }

    /**
     * Localised event name.
     *
     * @return string
     */
    public static function get_name() {
        return get_string('{{stringid}}', '{{component}}');
    }

    /**
     * Non-localised description for the logs.
     *
     * @return string
     */
    public function get_description() {
        return "{{sentence}}";
    }

    /**
     * URL of the context the event happened in.
     *
     * @return \moodle_url
     */
    public function get_url() {
        return $this->get_context()->get_url();
    }
{{#objecttable}}

    /**
     * Restore mapping of objectid when course logs are restored.
     *
     * @return array
     */
    public static function get_objectid_mapping() {
        return ['db' => '{{objecttable}}', 'restore' => \core\event\base::NOT_MAPPED];
    }
{{/objecttable}}
}
