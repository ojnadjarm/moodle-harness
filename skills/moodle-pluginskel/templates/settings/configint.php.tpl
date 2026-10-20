$settings->add(new admin_setting_configtext(
    '{{component}}/{{name}}',
    get_string('{{name}}', '{{component}}'),
    get_string('{{name}}_desc', '{{component}}'),
    {{default}},
    PARAM_INT
));
