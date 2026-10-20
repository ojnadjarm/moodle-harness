<?php
{{header}}

require(__DIR__ . '/../../config.php');

$id = required_param('id', PARAM_INT);
$course = get_course($id);
require_login($course);
$context = context_course::instance($course->id);
require_capability('{{viewcap}}', $context);

$PAGE->set_url('/report/{{pluginname}}/index.php', ['id' => $id]);
$PAGE->set_pagelayout('report');
$PAGE->set_title(get_string('pluginname', '{{component}}'));
$PAGE->set_heading(format_string($course->fullname, true, ['context' => $context]));

echo $OUTPUT->header();
echo $OUTPUT->heading(get_string('pluginname', '{{component}}'));
echo $OUTPUT->footer();
