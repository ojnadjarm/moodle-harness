<?php
{{header}}

/**
 * Adds the report to the course Reports menu.
 *
 * @param navigation_node $navigation The course reports node.
 * @param stdClass $course The course.
 * @param context $context The course context.
 */
function {{component}}_extend_navigation_course($navigation, $course, $context) {
    if (has_capability('{{viewcap}}', $context)) {
        $url = new moodle_url('/report/{{pluginname}}/index.php', ['id' => $course->id]);
        $name = get_string('pluginname', '{{component}}');
        $navigation->add($name, $url, navigation_node::TYPE_SETTING, null, null, new pix_icon('i/report', ''));
    }
}
