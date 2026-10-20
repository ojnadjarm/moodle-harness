$ADMIN->add('{{category}}', new admin_externalpage(
    '{{pagename}}',
    get_string('{{stringid}}', '{{component}}'),
    new moodle_url('/{{url}}'),
    '{{capability}}'
));
