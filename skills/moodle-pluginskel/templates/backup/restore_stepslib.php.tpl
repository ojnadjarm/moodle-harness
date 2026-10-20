<?php
{{header}}

/**
 * Restore structure step for {{component}}: the instance and its child tables.
 */
class restore_{{pluginname}}_activity_structure_step extends restore_activity_structure_step {
    /**
     * Defines the paths of the backup file to process.
     *
     * @return restore_path_element[]
     */
    protected function define_structure() {
{{#hasgated}}
        $userinfo = $this->get_setting_value('userinfo');

{{/hasgated}}
        $paths = [];
        $paths[] = new restore_path_element('{{pluginname}}', '/activity/{{pluginname}}');
{{#ungated}}
        $paths[] = new restore_path_element('{{table}}', '/activity/{{pluginname}}/{{wrapper}}/{{elem}}');
{{/ungated}}
{{#hasgated}}
        if ($userinfo) {
{{#gated}}
            $paths[] = new restore_path_element('{{table}}', '/activity/{{pluginname}}/{{wrapper}}/{{elem}}');
{{/gated}}
        }
{{/hasgated}}

        return $this->prepare_activity_structure($paths);
    }

    /**
     * Restores the activity instance record.
     *
     * @param array $data The record from the backup file.
     */
    protected function process_{{pluginname}}($data) {
        global $DB;

        $data = (object) $data;
        $data->course = $this->get_courseid();
{{#rootmaps}}
        $data->{{field}} = {{expr}};
{{/rootmaps}}

        $newitemid = $DB->insert_record('{{pluginname}}', $data);
        $this->apply_activity_instance($newitemid);
    }
{{#children}}

    /**
     * Restores one {{table}} record.
     *
     * @param array $data The record from the backup file.
     */
    protected function process_{{table}}($data) {
        global $DB;

        $data = (object) $data;
        $oldid = $data->id;
        $data->{{parentfield}} = $this->get_new_parentid('{{pluginname}}');
{{#maps}}
        $data->{{field}} = {{expr}};
{{/maps}}

        $newitemid = $DB->insert_record('{{table}}', $data);
        $this->set_mapping('{{table}}', $oldid, $newitemid);
    }
{{/children}}
{{#hasintro}}

    /**
     * Restores the files of the intro area.
     */
    protected function after_execute() {
        $this->add_related_files('{{component}}', 'intro', null);
    }
{{/hasintro}}
}
