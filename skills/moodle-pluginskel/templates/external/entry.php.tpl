    '{{component}}_{{name}}' => [
        'classname' => '{{component}}\external\{{name}}',
        'description' => '{{description}}.',
        'type' => '{{type}}',
        'ajax' => {{ajax}},
{{#capability}}
        'capabilities' => '{{capability}}',
{{/capability}}
{{#mobile}}
        'services' => [MOODLE_OFFICIAL_MOBILE_SERVICE],
{{/mobile}}
    ],
