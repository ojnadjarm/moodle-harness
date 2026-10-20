<?php
{{header}}

namespace {{component}}\privacy;

use core_privacy\local\metadata\collection;
use core_privacy\local\request\approved_contextlist;
use core_privacy\local\request\approved_userlist;
use core_privacy\local\request\contextlist;
use core_privacy\local\request\userlist;
use core_privacy\local\request\writer;

/**
 * Privacy provider for the personal data stored in the {{component}} tables.
 *
 * @package    {{component}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class provider implements
    \core_privacy\local\metadata\provider,
    \core_privacy\local\request\core_userlist_provider,
    \core_privacy\local\request\plugin\provider {
    /**
     * User data tables by name.
     *
     * @return array Per table: {{tablesdoc}}.
     */
    private static function tables(): array {
        return [
{{tables}}
        ];
    }

    /**
     * Describe the personal data stored by the plugin.
     *
     * @param collection $collection The collection to add the metadata to.
     * @return collection
     */
    public static function get_metadata(collection $collection): collection {
{{metadata}}
        return $collection;
    }

    /**
     * Get the contexts holding data of a user.
     *
     * @param int $userid The user ID.
     * @return contextlist
     */
    public static function get_contexts_for_userid(int $userid): contextlist {
{{#module}}
        $contextlist = new contextlist();
        foreach (self::tables() as $info) {
            foreach ($info['fields'] as $field) {
                $sql = "SELECT ctx.id
                          FROM {context} ctx
                          JOIN {course_modules} cm ON cm.id = ctx.instanceid AND ctx.contextlevel = :contextlevel
                          JOIN {modules} m ON m.id = cm.module AND m.name = :modname
                          " . implode(' ', $info['joins']) . "
                         WHERE t.{$field} = :userid";
                $params = ['contextlevel' => CONTEXT_MODULE, 'modname' => '{{pluginname}}', 'userid' => $userid];
                $contextlist->add_from_sql($sql, $params);
            }
        }
        return $contextlist;
{{/module}}
{{#system}}
        global $DB;

        $contextlist = new contextlist();
        foreach (self::tables() as $table => $info) {
            [$where, $params] = self::user_where(preg_filter('/^/', 't.', $info['fields']), [$userid]);
            if ($DB->record_exists_sql("SELECT 1 FROM {" . $table . "} t WHERE {$where}", $params)) {
                $contextlist->add_system_context();
                break;
            }
        }
        return $contextlist;
{{/system}}
{{#course}}
        global $DB;

        $contextlist = new contextlist();
        foreach (self::tables() as $table => $info) {
            [$where, $params] = self::user_where(preg_filter('/^/', 't.', $info['fields']), [$userid]);
            if ($info['course']) {
                $sql = "SELECT ctx.id
                          FROM {context} ctx
                          JOIN {" . $table . "} t ON t.{$info['course']} = ctx.instanceid AND ctx.contextlevel = :contextlevel
                         WHERE {$where}";
                $contextlist->add_from_sql($sql, $params + ['contextlevel' => CONTEXT_COURSE]);
            } else if ($DB->record_exists_sql("SELECT 1 FROM {" . $table . "} t WHERE {$where}", $params)) {
                $contextlist->add_system_context();
            }
        }
        return $contextlist;
{{/course}}
    }

    /**
     * Get the users holding data in a context.
     *
     * @param userlist $userlist The userlist to add the users to.
     */
    public static function get_users_in_context(userlist $userlist) {
        $context = $userlist->get_context();
{{#module}}
        if (!$context instanceof \context_module) {
            return;
        }
        foreach (self::tables() as $info) {
            foreach ($info['fields'] as $field) {
                $sql = "SELECT t.{$field}
                          FROM {course_modules} cm
                          JOIN {modules} m ON m.id = cm.module AND m.name = :modname
                          " . implode(' ', $info['joins']) . "
                         WHERE cm.id = :cmid";
                $userlist->add_from_sql($field, $sql, ['modname' => '{{pluginname}}', 'cmid' => $context->instanceid]);
            }
        }
{{/module}}
{{#system}}
        if (!$context instanceof \context_system) {
            return;
        }
        foreach (self::tables() as $table => $info) {
            foreach ($info['fields'] as $field) {
                $userlist->add_from_sql($field, "SELECT t.{$field} FROM {" . $table . "} t", []);
            }
        }
{{/system}}
{{#course}}
        foreach (self::tables() as $table => $info) {
            $scope = self::context_where($table, $context);
            if ($scope === null) {
                continue;
            }
            [$where, $params] = $scope;
            foreach ($info['fields'] as $field) {
                $userlist->add_from_sql($field, "SELECT t.{$field} FROM {" . $table . "} t WHERE {$where}", $params);
            }
        }
{{/course}}
    }

    /**
     * Export the data of a user in the approved contexts.
     *
     * @param approved_contextlist $contextlist The approved contexts and user.
     */
    public static function export_user_data(approved_contextlist $contextlist) {
        global $DB;

        $userid = $contextlist->get_user()->id;
        foreach ($contextlist->get_contexts() as $context) {
            if (!$context instanceof {{contextclass}}) {
                continue;
            }
            foreach (self::tables() as $table => $info) {
                $data = [];
                $owned = $info['owners'] ? self::record_ids($table, {{ctxarg}}[$userid], $info['owners']) : [];
                if ($owned) {
                    $data['records'] = array_values($DB->get_records_list($table, 'id', $owned, 'id'));
                }
                $modified = $info['modifiers'] ? array_diff(
                    self::record_ids($table, {{ctxarg}}[$userid], preg_filter('/^/', 't.', $info['modifiers'])),
                    $owned
                ) : [];
                if ($modified) {
                    $fields = 'id, ' . implode(', ', $info['modifiers']);
                    $data['modified'] = array_values($DB->get_records_list($table, 'id', $modified, 'id', $fields));
                }
                if ($data) {
                    writer::with_context($context)->export_data([$table], (object) $data);
                }
            }
        }
    }

    /**
     * Delete the data of all users in a context.
     *
     * @param \context $context The context to delete in.
     */
    public static function delete_data_for_all_users_in_context(\context $context) {
        if ($context instanceof {{contextclass}}) {
            self::delete_rows({{instancearg}});
        }
    }

    /**
     * Delete the data of a user in the approved contexts.
     *
     * @param approved_contextlist $contextlist The approved contexts and user.
     */
    public static function delete_data_for_user(approved_contextlist $contextlist) {
        $userid = $contextlist->get_user()->id;
        foreach ($contextlist->get_contexts() as $context) {
            if ($context instanceof {{contextclass}}) {
                self::delete_rows({{ctxarg}}[$userid]);
            }
        }
    }

    /**
     * Delete the data of several users in one context.
     *
     * @param approved_userlist $userlist The approved context and users.
     */
    public static function delete_data_for_users(approved_userlist $userlist) {
        $context = $userlist->get_context();
        if ($context instanceof {{contextclass}} && $userlist->get_userids()) {
            self::delete_rows({{ctxarg}}$userlist->get_userids());
        }
    }

    /**
     * Ids of the rows of a table{{scopedoc}}, optionally only those whose columns hold one of some users.
     *
     * @param string $table The table name.
{{#module}}
     * @param int $cmid The course module ID.
{{/module}}
{{#course}}
     * @param \context $context The context; a table of another context level has no rows in it.
{{/course}}
     * @param array|null $userids The user IDs, null for all rows.
     * @param array $columns The user columns (aliased) to match the users in.
     * @return array
     */
    private static function record_ids(string $table, {{cmparam}}?array $userids = null, array $columns = []): array {
        global $DB;

{{#module}}
        $sql = "SELECT t.id
                  FROM {course_modules} cm
                  JOIN {modules} m ON m.id = cm.module AND m.name = :modname
                  " . implode(' ', self::tables()[$table]['joins']) . "
                 WHERE cm.id = :cmid";
        $params = ['modname' => '{{pluginname}}', 'cmid' => $cmid];
{{/module}}
{{#system}}
        $sql = "SELECT t.id FROM {" . $table . "} t WHERE 1 = 1";
        $params = [];
{{/system}}
{{#course}}
        $scope = self::context_where($table, $context);
        if ($scope === null) {
            return [];
        }
        [$where, $params] = $scope;
        $sql = "SELECT t.id FROM {" . $table . "} t WHERE {$where}";
{{/course}}
        if ($userids !== null) {
            [$where, $userparams] = self::user_where($columns, $userids);
            $sql .= " AND {$where}";
            $params += $userparams;
        }
        return $DB->get_fieldset_sql($sql, $params);
    }
{{#course}}

    /**
     * SQL condition matching the rows of a table in a context, null when the table has no rows at its level.
     *
     * @param string $table The table name.
     * @param \context $context The context.
     * @return array|null The SQL and its parameters.
     */
    private static function context_where(string $table, \context $context): ?array {
        $course = self::tables()[$table]['course'];
        if ($course) {
            return $context instanceof \context_course ? ["t.{$course} = :courseid", ['courseid' => $context->instanceid]] : null;
        }
        return $context instanceof \context_system ? ['1 = 1', []] : null;
    }
{{/course}}

    /**
     * SQL condition matching the rows whose user columns hold one of the users.
     *
     * @param array $columns The user columns, with their table alias.
     * @param array $userids The user IDs.
     * @return array The SQL and its parameters.
     */
    private static function user_where(array $columns, array $userids): array {
        global $DB;

        $where = [];
        $params = [];
        foreach ($columns as $column) {
            [$insql, $inparams] = $DB->get_in_or_equal($userids, SQL_PARAMS_NAMED, 'user');
            $where[] = "{$column} {$insql}";
            $params += $inparams;
        }
        return ['(' . implode(' OR ', $where) . ')', $params];
    }

    /**
     * Delete the rows owned by some users{{scopedoc}} and set their modifier fields to 0 elsewhere.
     *
{{#module}}
     * @param int $cmid The course module ID.
{{/module}}
{{#course}}
     * @param \context $context The context.
{{/course}}
     * @param array|null $userids The user IDs, null for all users.
     */
    private static function delete_rows({{cmparam}}?array $userids = null): void {
        global $DB;

        foreach (self::tables() as $table => $info) {
            $ids = $info['owners'] ? self::record_ids($table, {{cmarg}}$userids, $info['owners']) : [];
            if ($ids) {
                $DB->delete_records_list($table, 'id', $ids);
            }
            foreach ($info['modifiers'] as $field) {
                $ids = self::record_ids($table, {{cmarg}}$userids, ["t.{$field}"]);
                if ($ids) {
                    [$idsql, $params] = $DB->get_in_or_equal($ids, SQL_PARAMS_NAMED, 'id');
                    $DB->set_field_select($table, $field, 0, "id {$idsql}", $params);
                }
            }
        }
    }
}
