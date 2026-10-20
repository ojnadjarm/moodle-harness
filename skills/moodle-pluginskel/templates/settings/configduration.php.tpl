$settings->add(new admin_setting_configduration(
    '{{component}}/{{name}}',
    get_string('{{name}}', '{{component}}'),
    get_string('{{name}}_desc', '{{component}}'),
    {{default}}
));
