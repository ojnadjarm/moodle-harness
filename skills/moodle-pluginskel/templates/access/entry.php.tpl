    '{{capability}}' => [
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
{{#clone}}
        'clonepermissionsfrom' => '{{clone}}',
{{/clone}}
    ],
