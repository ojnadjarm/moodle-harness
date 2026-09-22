<?php
{{header}}

define('CLI_SCRIPT', true);

require(__DIR__ . '/{{configrel}}config.php');
require_once($CFG->libdir . '/clilib.php');

cli_writeln('{{component}}: {{filename}} placeholder.');
