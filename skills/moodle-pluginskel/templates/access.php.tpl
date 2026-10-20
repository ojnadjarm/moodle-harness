<?php
{{header}}

defined('MOODLE_INTERNAL') || die();

$capabilities = [
{{#capabilities}}
    '{{type}}/{{pluginname}}:{{name}}' => [
{{#riskbitmask}}
        'riskbitmask' => {{riskbitmask}},
{{/riskbitmask}}
        'captype' => '{{captype}}',
        'contextlevel' => {{contextlevel}},
        'archetypes' => [
{{#archetypes}}
            '{{role}}' => {{permission}},
{{/archetypes}}
        ],
{{#clonepermissionsfrom}}
        'clonepermissionsfrom' => '{{clonepermissionsfrom}}',
{{/clonepermissionsfrom}}
    ],
{{/capabilities}}
];
