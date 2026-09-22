<?php
{{header}}

defined('MOODLE_INTERNAL') || die();

$string['pluginname'] = '{{name}}';
{{#capabilities}}
$string['{{pluginname}}:{{name}}'] = '{{title}}';
{{/capabilities}}
{{#lang_strings}}
$string['{{id}}'] = '{{text}}';
{{/lang_strings}}
{{#privacy}}
$string['privacy:metadata'] = 'The {{name}} plugin does not store any personal data.';
{{/privacy}}
