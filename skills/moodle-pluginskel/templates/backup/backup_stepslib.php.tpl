<?php
{{header}}

/**
 * Backup structure step for {{component}}: the instance and its child tables.
 */
class backup_{{pluginname}}_activity_structure_step extends backup_activity_structure_step {
    /**
     * Defines the backup structure of one activity instance.
     *
     * @return backup_nested_element
     */
    protected function define_structure() {
{{#hasgated}}
        $userinfo = $this->get_setting_value('userinfo');

{{/hasgated}}
        ${{pluginname}} = new backup_nested_element('{{pluginname}}', ['id'], [
{{rootfields}}
        ]);
{{#children}}

        ${{wrapper}} = new backup_nested_element('{{wrapper}}');
        ${{elem}} = new backup_nested_element('{{elem}}', ['id'], [
{{fields}}
        ]);
        ${{pluginname}}->add_child(${{wrapper}});
        ${{wrapper}}->add_child(${{elem}});
{{/children}}

        ${{pluginname}}->set_source_table('{{pluginname}}', ['id' => backup::VAR_ACTIVITYID]);
{{#ungated}}
        ${{elem}}->set_source_table('{{table}}', ['{{parentfield}}' => backup::VAR_PARENTID], 'id ASC');
{{/ungated}}
{{#hasgated}}
        if ($userinfo) {
{{#gated}}
            ${{elem}}->set_source_table('{{table}}', ['{{parentfield}}' => backup::VAR_PARENTID], 'id ASC');
{{/gated}}
        }
{{/hasgated}}
{{#hasannotations}}

{{#annotations}}
        ${{elem}}->annotate_ids('user', '{{field}}');
{{/annotations}}
{{/hasannotations}}
{{#hasintro}}

        ${{pluginname}}->annotate_files('{{component}}', 'intro', null);
{{/hasintro}}

        return $this->prepare_activity_structure(${{pluginname}});
    }
}
