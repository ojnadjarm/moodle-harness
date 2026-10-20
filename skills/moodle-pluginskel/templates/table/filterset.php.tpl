<?php
{{header}}

namespace {{component}}\table;

/**
 * Filterset for the {{name}} dynamic table.
 *
 * @package    {{component}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class {{name}}_filterset extends \core_table\local\filter\filterset {
{{#course}}
    /**
     * Filters every load needs: the course.
     *
     * @return array
     */
    public function get_required_filters(): array {
        return ['courseid' => \core_table\local\filter\integer_filter::class];
    }
{{/course}}
}
