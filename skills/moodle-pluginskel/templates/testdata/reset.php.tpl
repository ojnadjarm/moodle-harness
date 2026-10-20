<?php
{{header}}

{{configphp}}
require_once($CFG->libdir . '/clilib.php');

/**
 * Return the fixture course's {{component}} data to the scenario's start state.
 *
 * @param stdClass $course
 * @param array $spec Rows by table from rows.php.
 * @return int[] Deleted marked rows by table.
 */
function {{prefix}}_reset(stdClass $course, array $spec): array {
    global $DB;
    $deleted = [];
    foreach ($spec as $table => $rows) {
        $marker = array_key_first(array_filter($rows['values'], 'is_string'));
        if ($marker !== null) {
            $select = $DB->sql_like($DB->sql_compare_text($marker), ':marker');
            $params = ['marker' => $DB->sql_like_escape('testdata-') . '%'];
            $deleted[$table] = $DB->count_records_select($table, $select, $params);
            $DB->delete_records_select($table, $select, $params);
        }
    }
    // Restore any other rows this scenario mutates, scoped to $course->id.
    return $deleted;
}

$course = $DB->get_record('course', ['shortname' => '{{shortname}}']);
if (!$course) {
    cli_error('No fixture course {{shortname}}: run setup.php first.');
}
\core\session\manager::set_user(get_admin());
foreach ({{prefix}}_reset($course, require(__DIR__ . '/rows.php')) as $table => $count) {
    cli_writeln("Deleted {$table}: {$count}");
}
cli_writeln("Reset course {$course->id}: " . (new moodle_url('/course/view.php', ['id' => $course->id]))->out(false));
