<?php
{{header}}

require(__DIR__ . '/../../config.php');
require_once($CFG->libdir . '/completionlib.php');

$id = required_param('id', PARAM_INT);
[$course, $cm] = get_course_and_cm_from_cmid($id, '{{pluginname}}');
$instance = $DB->get_record('{{pluginname}}', ['id' => $cm->instance], '*', MUST_EXIST);

require_login($course, true, $cm);
$context = context_module::instance($cm->id);
require_capability('mod/{{pluginname}}:view', $context);

$completion = new completion_info($course);
$completion->set_module_viewed($cm);

$PAGE->set_url('/mod/{{pluginname}}/view.php', ['id' => $cm->id]);
$PAGE->set_title(format_string($instance->name));
$PAGE->set_heading(format_string($course->fullname));
$PAGE->set_context($context);

echo $OUTPUT->header();
echo $OUTPUT->footer();
