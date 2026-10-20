<?php
{{header}}

namespace {{component}}\output;

/**
 * {{description}}, exported to the {{component}}/{{name}} template.
 *
 * @package    {{component}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class {{name}} implements \renderable, \templatable {
{{properties}}

    /**
     * Constructor.
     *
{{paramdocs}}
     */
    public function __construct({{params}}) {
{{assigns}}
    }

    /**
     * Exports the context of the {{component}}/{{name}} template.
     *
     * @param \renderer_base $output Renderer used to export
     * @return array Template context
     */
    public function export_for_template(\renderer_base $output): array {
        return [
{{exports}}
        ];
    }
}
