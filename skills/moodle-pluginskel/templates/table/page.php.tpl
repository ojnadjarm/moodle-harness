<?php
{{header}}

require(__DIR__ . '{{configpath}}');

{{#system}}
require_login();
$context = context_system::instance();
require_capability('{{capability}}', $context);

$url = new moodle_url('{{url}}');
$PAGE->set_url($url);
$PAGE->set_context($context);
{{/system}}
{{#course}}
$courseid = required_param('{{param}}', PARAM_INT);
$course = get_course($courseid);
require_login($course);
$context = context_course::instance($course->id);
require_capability('{{capability}}', $context);

$url = new moodle_url('{{url}}', ['{{param}}' => $course->id]);
$PAGE->set_url($url);
{{/course}}
$PAGE->set_pagelayout('report');
$PAGE->set_title(get_string('{{name}}', '{{component}}'));
$PAGE->set_heading(get_string('{{name}}', '{{component}}'));

{{block}}
echo $OUTPUT->header();
$table->out(30, false);
echo $OUTPUT->footer();
