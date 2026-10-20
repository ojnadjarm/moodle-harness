<?php
{{header}}

defined('MOODLE_INTERNAL') || die();

$addons = [
    '{{component}}' => [
        'handlers' => [
            '{{handler}}' => [
                'delegate' => '{{delegate}}',
                'method' => '{{method}}',
                {{#hasdisplaydata}}
                'displaydata' => [
                    {{#displaydata}}
                    '{{key}}' => {{value}},
                    {{/displaydata}}
                ],
                {{/hasdisplaydata}}
            ],
        ],
        'lang' => [
            ['pluginname', '{{component}}'],
            ['{{stringid}}', '{{component}}'],
        ],
    ],
];
