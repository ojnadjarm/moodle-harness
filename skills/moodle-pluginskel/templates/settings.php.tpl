<?php
{{header}}

defined('MOODLE_INTERNAL') || die();

{{#settings_own_page}}
if ($hassiteconfig) {
    $settings = new admin_settingpage('{{component}}', get_string('pluginname', '{{component}}'));
    $ADMIN->add('{{settings_category}}', $settings);
}
{{/settings_own_page}}
{{#settings_fulltree}}
if ($ADMIN->fulltree) {
    $settings->add(new admin_setting_heading(
        '{{component}}/generalsettings',
        get_string('generalsettings', '{{component}}'),
        ''
    ));
}
{{/settings_fulltree}}
