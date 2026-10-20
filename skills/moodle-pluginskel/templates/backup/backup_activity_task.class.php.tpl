<?php
{{header}}

defined('MOODLE_INTERNAL') || die();

require_once($CFG->dirroot . '/mod/{{pluginname}}/backup/moodle2/backup_{{pluginname}}_stepslib.php');

/**
 * Backup task that provides all the settings and steps to back up one {{pluginname}} activity.
 */
class backup_{{pluginname}}_activity_task extends backup_activity_task {
    /**
     * Defines the activity-specific settings (none).
     */
    protected function define_my_settings() {
    }

    /**
     * Defines the structure step that writes {{pluginname}}.xml.
     */
    protected function define_my_steps() {
        $this->add_step(new backup_{{pluginname}}_activity_structure_step('{{pluginname}}_structure', '{{pluginname}}.xml'));
    }

    /**
     * Encodes links to index.php and view.php so restore can rewrite them.
     *
     * @param string $content HTML that may contain links to this activity.
     * @return string The content with the links encoded.
     */
    public static function encode_content_links($content) {
        global $CFG;

        $base = preg_quote($CFG->wwwroot . '/mod/{{pluginname}}', '#');
        $content = preg_replace('#(' . $base . '/index\.php\?id=)([0-9]+)#', '$@{{rule}}INDEX*$2@$', $content);
        return preg_replace('#(' . $base . '/view\.php\?id=)([0-9]+)#', '$@{{rule}}VIEWBYID*$2@$', $content);
    }
}
