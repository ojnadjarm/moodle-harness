    '{{area}}' => [
        'mode' => cache_store::{{modeconst}},
{{#simplekeys}}
        'simplekeys' => true,
{{/simplekeys}}
{{#ttl}}
        'ttl' => {{ttl}},
{{/ttl}}
    ],
