<?php
{{header}}

namespace {{component}}\task;

/**
 * Adhoc task: {{description}}.
 *
 * @package    {{component}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class {{name}} extends \core\task\adhoc_task {
    /**
     * Creates the task with its custom data, ready to queue.
     *
     * @param int $id Id of the record to process
     * @return self
     */
    public static function instance(int $id): self {
        $task = new self();
        $task->set_custom_data((object) ['id' => $id]);
        return $task;
    }

    /**
     * Name shown in the task admin screens.
     *
     * @return string
     */
    public function get_name(): string {
        return get_string('{{stringid}}', '{{component}}');
    }

    /**
     * Runs the task with the custom data it was queued with.
     */
    public function execute(): void {
        $data = $this->get_custom_data();
        mtrace('{{description}}: ' . $data->id);
    }
}
