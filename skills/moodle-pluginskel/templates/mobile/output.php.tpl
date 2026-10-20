<?php
{{header}}

namespace {{component}}\output;

/**
 * Content served to the Moodle App through tool_mobile_get_content.
 *
 * @package    {{component}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class mobile {
    /**
     * Page of the {{handler}} handler ({{delegate}}).
     *
     * @param array $args Arguments sent by the app
     * @return array Templates, javascript and otherdata for the app
     */
    public static function {{method}}(array $args): array {
        {{#notable}}
        global $OUTPUT;
        {{/notable}}
        {{#hastable}}
        global $DB, $OUTPUT, $USER;
        {{/hastable}}
{{checks}}        {{#hastable}}

        $context = \context_user::instance($USER->id);
        $rows = [];
        foreach ($DB->get_records('{{table}}', ['userid' => $USER->id], 'id') as $record) {
            $rows[] = [
                {{#cols}}
                '{{col}}' => format_string($record->{{col}}, true, ['context' => $context]),
                {{/cols}}
            ];
        }
        {{/hastable}}

        return [
            'templates' => [
                [
                    'id' => 'main',
                    'html' => $OUTPUT->render_from_template('{{component}}/{{template}}', []),
                ],
            ],
            'javascript' => '',
            'otherdata' => {{otherdata}},
        ];
    }
}
