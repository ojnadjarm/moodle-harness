<?php
{{header}}

defined('MOODLE_INTERNAL') || die();

$capabilities = [
{{#capabilities}}
    '{{type}}/{{pluginname}}:{{name}}' => [
        'captype' => '{{captype}}',
        'contextlevel' => {{contextlevel}},
        'archetypes' => [
{{#archetypes}}
            '{{role}}' => {{permission}},
{{/archetypes}}
        ],
    ],
{{/capabilities}}
];
