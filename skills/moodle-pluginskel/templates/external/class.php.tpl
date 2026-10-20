<?php
{{header}}

namespace {{component}}\external;

{{uses}}
{{#legacy}}
defined('MOODLE_INTERNAL') || die();

global $CFG;
require_once($CFG->libdir . '/externallib.php');

{{/legacy}}
/**
 * External function {{component}}_{{name}}.
 *
 * @package    {{component}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class {{name}} extends external_api {
    /**
     * Describes the parameters.
     *
     * @return external_function_parameters
     */
    public static function execute_parameters(): external_function_parameters {
        return new external_function_parameters([
{{paramsdesc}}        ]);
    }

    /**
     * {{description}}.
     *
{{docparams}}     * @return array
     */
    public static function execute({{signature}}): array {
{{#table}}
        global $DB, $USER;

{{/table}}
        $params = self::validate_parameters(self::execute_parameters(), [
{{validate}}        ]);

        $context = {{context}};
        self::validate_context($context);
{{#capability}}
        require_capability('{{capability}}', $context);
{{/capability}}
{{#table}}

        $records = $DB->get_records('{{table}}', ['userid' => $USER->id], 'id', '{{fields}}');
{{/table}}

        return {{result}};
    }

    /**
     * Describes the return value.
     *
     * @return {{returnclass}}
     */
    public static function execute_returns(): {{returnclass}} {
{{returnsdesc}}
    }
}
