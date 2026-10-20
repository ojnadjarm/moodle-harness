<?php
{{header}}

/**
 * Adds the {{component}} rows of a course to the course backup.
 */
class backup_{{component}}_plugin extends backup_local_plugin {
    /**
     * Defines the {{component}} rows attached to the course element.
     *
     * @return backup_plugin_element
     */
    protected function define_course_plugin_structure() {
{{#hasgated}}
        $userinfo = $this->get_setting_value('users');

{{/hasgated}}
        $plugin = $this->get_plugin_element();
        $wrapper = new backup_nested_element($this->get_recommended_name());
        $plugin->add_child($wrapper);
{{#children}}

        ${{wrapper}} = new backup_nested_element('{{wrapper}}');
        ${{elem}} = new backup_nested_element('{{elem}}', ['id'], [
{{fields}}
        ]);
        $wrapper->add_child(${{wrapper}});
        ${{wrapper}}->add_child(${{elem}});
{{/children}}

{{#ungated}}
        ${{elem}}->set_source_table('{{table}}', ['{{coursefield}}' => backup::VAR_COURSEID], 'id ASC');
{{/ungated}}
{{#hasgated}}
        if ($userinfo) {
{{#gated}}
            ${{elem}}->set_source_table('{{table}}', ['{{coursefield}}' => backup::VAR_COURSEID], 'id ASC');
{{/gated}}
        }
{{#annotations}}
        ${{elem}}->annotate_ids('user', '{{field}}');
{{/annotations}}
{{/hasgated}}

        return $plugin;
    }
}
