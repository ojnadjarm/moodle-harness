$settings->add(new admin_setting_configselect(
    '{{component}}/{{name}}',
    get_string('{{name}}', '{{component}}'),
    get_string('{{name}}_desc', '{{component}}'),
    '{{default}}',
    [
{{#choices}}
        '{{key}}' => get_string('{{name}}_{{key}}', '{{component}}'),
{{/choices}}
    ]
));
