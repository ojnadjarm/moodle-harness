<?php
{{header}}

{{configphp}}
require_once($CFG->libdir . '/clilib.php');
require_once($CFG->libdir . '/enrollib.php');
require_once($CFG->libdir . '/filelib.php');
require_once($CFG->libdir . '/resourcelib.php');
require_once($CFG->dirroot . '/course/lib.php');
require_once($CFG->dirroot . '/user/lib.php');

/**
 * Get or create a manual-auth user by username.
 *
 * @param string $username
 * @param string $firstname
 * @return stdClass
 */
function {{prefix}}_user(string $username, string $firstname): stdClass {
    global $CFG, $DB;
    $user = $DB->get_record('user', ['username' => $username, 'mnethostid' => $CFG->mnet_localhost_id]);
    if ($user) {
        return $user;
    }
    $id = user_create_user((object) [
        'username' => $username,
        'password' => '{{password}}',
        'firstname' => $firstname,
        'lastname' => 'Testdata',
        'email' => $username . '@example.com',
        'auth' => 'manual',
        'confirmed' => 1,
        'mnethostid' => $CFG->mnet_localhost_id,
    ]);
    return $DB->get_record('user', ['id' => $id], '*', MUST_EXIST);
}

/**
 * Get or create a course with completion enabled by shortname.
 *
 * @param string $shortname
 * @param string $fullname
 * @return stdClass
 */
function {{prefix}}_course(string $shortname, string $fullname): stdClass {
    global $DB;
    $course = $DB->get_record('course', ['shortname' => $shortname]);
    if ($course) {
        return $course;
    }
    return create_course((object) [
        'fullname' => $fullname,
        'shortname' => $shortname,
        'category' => core_course_category::get_default()->id,
        'enablecompletion' => 1,
    ]);
}

/**
 * Enrol a user with a role through the course's manual enrolment instance, once.
 *
 * @param stdClass $user
 * @param stdClass $course
 * @param string $roleshortname
 */
function {{prefix}}_enrol(stdClass $user, stdClass $course, string $roleshortname): void {
    global $DB;
    $plugin = enrol_get_plugin('manual');
    $instance = $DB->get_record('enrol', ['courseid' => $course->id, 'enrol' => 'manual'], '*', IGNORE_MULTIPLE);
    if (!$instance) {
        $instance = $DB->get_record('enrol', ['id' => $plugin->add_default_instance($course)], '*', MUST_EXIST);
    }
    if ($DB->record_exists('user_enrolments', ['enrolid' => $instance->id, 'userid' => $user->id])) {
        return;
    }
    $role = $DB->get_record('role', ['shortname' => $roleshortname], '*', MUST_EXIST);
    $plugin->enrol_user($instance, $user->id, $role->id);
}

/**
 * Get or create an activity by course and name; $fields holds the module's own required fields.
 *
 * @param stdClass $course
 * @param string $modname
 * @param string $name
 * @param array $fields
 * @return stdClass course module
 */
function {{prefix}}_module(stdClass $course, string $modname, string $name, array $fields = []): stdClass {
    global $DB;
    $instance = $DB->get_record($modname, ['course' => $course->id, 'name' => $name], 'id', IGNORE_MULTIPLE);
    if ($instance) {
        return get_coursemodule_from_instance($modname, $instance->id, $course->id, false, MUST_EXIST);
    }
    $info = create_module((object) array_merge([
        'modulename' => $modname,
        'course' => $course->id,
        'section' => 0,
        'visible' => 1,
        'name' => $name,
        'introeditor' => ['text' => '', 'format' => FORMAT_HTML, 'itemid' => file_get_unused_draft_itemid()],
    ], $fields));
    return get_coursemodule_from_id($modname, $info->coursemodule, $course->id, false, MUST_EXIST);
}

/**
 * Insert the marked rows of a plugin table once, after the plugin rows they reference, skipping unique-key clashes.
 *
 * @param array $spec Rows by table from rows.php: references, literal values, unique fields, unique keys.
 * @param string $table
 * @param int $count Rows per table.
 * @param array $fields Values by field name: user, course and instance IDs.
 * @param array $seeded Row IDs by table, filled in.
 * @return int[] The marked row IDs of the table.
 */
function {{prefix}}_rows(array $spec, string $table, int $count, array $fields, array &$seeded): array {
    global $DB;
    if (isset($seeded[$table])) {
        return $seeded[$table];
    }
    $seeded[$table] = [];
    $marker = array_key_first(array_filter($spec[$table]['values'], 'is_string'));
    if ($marker === null) {
        return [];
    }
    $select = $DB->sql_compare_text($marker) . ' = ' . $DB->sql_compare_text(':marker');
    for ($i = 1; $i <= $count; $i++) {
        $value = 'testdata-' . $i;
        $id = $DB->get_field_select($table, 'id', $select, ['marker' => $value], IGNORE_MULTIPLE);
        if (!$id) {
            $row = [];
            foreach ($spec[$table]['values'] as $field => $default) {
                if (is_string($default)) {
                    $row[$field] = $value;
                } else if (preg_match('/^time(created|modified|updated|start|end|open|close|due|submitted|completed)$/', $field)) {
                    $row[$field] = time();
                } else if (isset($fields[$field])) {
                    $row[$field] = $fields[$field];
                } else {
                    $row[$field] = in_array($field, $spec[$table]['unique'], true) ? $i : $default;
                }
            }
            foreach ($spec[$table]['refs'] as $field => $ref) {
                $ids = $ref === 'user' ? [$fields['user']] : {{prefix}}_rows($spec, $ref, $count, $fields, $seeded);
                $row[$field] = $ids ? $ids[($i - 1) % count($ids)] : 0;
            }
            foreach ($spec[$table]['keys'] as $key) {
                if ($DB->record_exists($table, array_intersect_key($row, array_flip($key)))) {
                    continue 2;
                }
            }
            $id = $DB->insert_record($table, (object) $row);
        }
        $seeded[$table][] = (int) $id;
    }
    return $seeded[$table];
}

\core\session\manager::set_user(get_admin());

$course = {{prefix}}_course('{{shortname}}', '{{component}} test data');
$teacher = {{prefix}}_user('{{shortname}}_teacher', 'Teacher');
$student = {{prefix}}_user('{{shortname}}_student', 'Student');
{{prefix}}_enrol($teacher, $course, 'editingteacher');
{{prefix}}_enrol($student, $course, 'student');
$page = {{prefix}}_module($course, 'page', '{{component}} test page', [
    'content' => 'Test page content',
    'contentformat' => FORMAT_HTML,
    'display' => RESOURCELIB_DISPLAY_AUTO,
    'printintro' => 0,
    'printlastmodified' => 1,
]);
{{#module}}
$instance = {{prefix}}_module($course, '{{pluginname}}', '{{component}} test instance');
$seeded = ['{{pluginname}}' => [(int) $instance->instance]];
{{/module}}
{{#system}}
$seeded = [];
{{/system}}
$spec = require(__DIR__ . '/rows.php');
$fields = [{{fields}}];
foreach (array_keys($spec) as $table) {
    {{prefix}}_rows($spec, $table, {{rows}}, $fields, $seeded);
}

cli_writeln("Course {$course->id}: " . (new moodle_url('/course/view.php', ['id' => $course->id]))->out(false));
cli_writeln("Participants: " . (new moodle_url('/user/index.php', ['id' => $course->id]))->out(false));
cli_writeln("Page cm {$page->id}: " . (new moodle_url('/mod/page/view.php', ['id' => $page->id]))->out(false));
cli_writeln("Teacher {$teacher->id} {$teacher->username}, student {$student->id} {$student->username}, password {{password}}");
foreach ($seeded as $table => $ids) {
    cli_writeln("Rows {$table}: " . count($ids));
}
