<?php
{{header}}

defined('MOODLE_INTERNAL') || die();

require_once($CFG->dirroot . '/mod/{{pluginname}}/backup/moodle2/restore_{{pluginname}}_stepslib.php');

/**
 * Restore task that provides all the settings and steps to restore one {{pluginname}} activity.
 */
class restore_{{pluginname}}_activity_task extends restore_activity_task {
    /**
     * Defines the activity-specific settings (none).
     */
    protected function define_my_settings() {
    }

    /**
     * Defines the structure step that reads {{pluginname}}.xml.
     */
    protected function define_my_steps() {
        $this->add_step(new restore_{{pluginname}}_activity_structure_step('{{pluginname}}_structure', '{{pluginname}}.xml'));
    }

    /**
     * Defines the contents whose links the decoder rewrites.
     *
     * @return restore_decode_content[]
     */
    public static function define_decode_contents() {
        $contents = [];
{{#decodes}}
        $contents[] = new restore_decode_content('{{table}}', [{{fields}}], '{{table}}');
{{/decodes}}
        return $contents;
    }

    /**
     * Defines the rules that decode links to index.php and view.php.
     *
     * @return restore_decode_rule[]
     */
    public static function define_decode_rules() {
        return [
            new restore_decode_rule('{{rule}}INDEX', '/mod/{{pluginname}}/index.php?id=$1', 'course'),
            new restore_decode_rule('{{rule}}VIEWBYID', '/mod/{{pluginname}}/view.php?id=$1', 'course_module'),
        ];
    }

    /**
     * Defines the legacy log rules for activity logs.
     *
     * @return restore_log_rule[]
     */
    public static function define_restore_log_rules() {
        return [
            new restore_log_rule('{{pluginname}}', 'add', 'view.php?id={course_module}', '{{{pluginname}}}'),
            new restore_log_rule('{{pluginname}}', 'update', 'view.php?id={course_module}', '{{{pluginname}}}'),
            new restore_log_rule('{{pluginname}}', 'view', 'view.php?id={course_module}', '{{{pluginname}}}'),
        ];
    }

    /**
     * Defines the legacy log rules for course logs.
     *
     * @return restore_log_rule[]
     */
    public static function define_restore_log_rules_for_course() {
        return [
            new restore_log_rule('{{pluginname}}', 'view all', 'index.php?id={course}', null),
        ];
    }
}
