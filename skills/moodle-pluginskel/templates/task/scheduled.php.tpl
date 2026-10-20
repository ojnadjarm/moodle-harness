<?php
{{header}}

namespace {{component}}\task;

/**
 * Scheduled task: {{description}}.
 *
 * @package    {{component}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class {{name}} extends \core\task\scheduled_task {
    /**
     * Name shown in the task admin screens.
     *
     * @return string
     */
    public function get_name(): string {
        return get_string('{{stringid}}', '{{component}}');
    }

{{#plain}}
    /**
     * Runs the task.
     */
    public function execute(): void {
        mtrace('{{description}}: done.');
    }
{{/plain}}
{{#purge}}
    /**
     * Deletes {{table}} rows whose {{timecol}} is older than the retention period.
     */
    public function execute(): void {
        global $DB;
{{#setting}}
        $retention = (int) get_config('{{component}}', '{{setting}}');
        if ($retention <= 0) {
            return;
        }
{{/setting}}
{{#nosetting}}
        $retention = 30 * DAYSECS;
{{/nosetting}}
        $DB->delete_records_select('{{table}}', '{{timecol}} < ?', [time() - $retention]);
    }
{{/purge}}
}
