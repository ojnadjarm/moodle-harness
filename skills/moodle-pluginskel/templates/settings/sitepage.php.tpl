if ($hassiteconfig) {
    $settings = new admin_settingpage('{{component}}', get_string('pluginname', '{{component}}'));
    $ADMIN->add('{{category}}', $settings);

    if ($ADMIN->fulltree) {
    }
}
