<?php
{{header}}

/**
 * Restores the {{component}} rows of a course backup into the target course.
 */
class restore_{{component}}_plugin extends restore_local_plugin {
    /**
     * Defines the paths of the {{component}} rows under the course element.
     *
     * @return restore_path_element[]
     */
    protected function define_course_plugin_structure() {
        $paths = [];
{{#ungated}}
        $paths[] = new restore_path_element('{{table}}', $this->get_pathfor('/{{wrapper}}/{{elem}}'));
{{/ungated}}
{{#hasgated}}
        if ($this->get_setting_value('users')) {
{{#gated}}
            $paths[] = new restore_path_element('{{table}}', $this->get_pathfor('/{{wrapper}}/{{elem}}'));
{{/gated}}
        }
{{/hasgated}}
        return $paths;
    }
{{#children}}

    /**
     * Restores one {{table}} record.
     *
     * @param array $data The record from the backup file.
     */
    public function process_{{table}}($data) {
        global $DB;

        $data = (object) $data;
        $oldid = $data->id;
        $data->{{coursefield}} = $this->task->get_courseid();
{{#maps}}
        $data->{{field}} = {{expr}};
{{/maps}}

        $newitemid = $DB->insert_record('{{table}}', $data);
        $this->set_mapping('{{table}}', $oldid, $newitemid);
    }
{{/children}}
}
