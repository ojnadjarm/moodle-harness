<?php
{{header}}

require(__DIR__ . '/../../config.php');

$id = required_param('id', PARAM_INT);
$course = $DB->get_record('course', ['id' => $id], '*', MUST_EXIST);
require_course_login($course);

$PAGE->set_url('/mod/{{pluginname}}/index.php', ['id' => $id]);
$PAGE->set_title(format_string($course->shortname) . ': ' . get_string('modulenameplural', '{{pluginname}}'));
$PAGE->set_heading(format_string($course->fullname));
$PAGE->set_pagelayout('incourse');

echo $OUTPUT->header();
echo $OUTPUT->heading(get_string('modulenameplural', '{{pluginname}}'));

$instances = get_all_instances_in_course('{{pluginname}}', $course);
if (!$instances) {
    $courseurl = new moodle_url('/course/view.php', ['id' => $course->id]);
    notice(get_string('thereareno', 'moodle', get_string('modulenameplural', '{{pluginname}}')), $courseurl);
}

$table = new html_table();
$table->head = [get_string('name')];
foreach ($instances as $instance) {
    $url = new moodle_url('/mod/{{pluginname}}/view.php', ['id' => $instance->coursemodule]);
    $table->data[] = [html_writer::link($url, format_string($instance->name))];
}
echo html_writer::table($table);

echo $OUTPUT->footer();
