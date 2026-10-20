<?php
// Run a generated privacy provider, or with test its provider_test, against SQLite with core_privacy stubs:
// privacy-db.php <mod|sys|course|test> <plugin-dir> <component>.

namespace core_privacy\local\metadata {
    interface provider {
    }
    class collection {
        private array $items = [];
        public function __construct(string $component) {
        }
        public function add_database_table($name, array $fields, $summary) {
            $this->items[] = $name;
            return $this;
        }
        public function get_collection() {
            return $this->items;
        }
    }
}

namespace core_privacy\local\request {
    interface core_userlist_provider {
    }
    interface plugin_provider {
    }
    interface plugin {
    }
    class contextlist {
        public array $ids = [];
        public function add_from_sql($sql, $params) {
            global $DB;
            $this->ids = array_merge($this->ids, $DB->get_fieldset_sql("SELECT id FROM {context} WHERE id IN ($sql)", $params));
            $this->ids = array_values(array_unique($this->ids));
            sort($this->ids);
        }
        public function add_system_context() {
            $this->ids[] = 1;
        }
        public function get_contextids() {
            return $this->ids;
        }
    }
    class approved_contextlist {
        public function __construct(private $user, $component, private array $contextids) {
        }
        public function get_user() {
            return $this->user;
        }
        public function get_contexts() {
            return array_map(fn($id) => \context::by_id($id), $this->contextids);
        }
    }
    class userlist {
        public array $ids = [];
        public function __construct(private $context, $component = '') {
        }
        public function get_context() {
            return $this->context;
        }
        public function add_from_sql($field, $sql, $params) {
            global $DB;
            $sql = "SELECT DISTINCT u.id FROM {user} u JOIN ({$sql}) target ON u.id = target.{$field}";
            $this->ids = array_merge($this->ids, $DB->get_fieldset_sql($sql, $params));
        }
        public function get_userids() {
            return $this->ids;
        }
    }
    class approved_userlist extends userlist {
        public function __construct($context, $component, array $userids) {
            parent::__construct($context);
            $this->ids = $userids;
        }
    }
    class writer {
        public static array $data = [];
        public static function with_context($context) {
            return new class ($context) {
                public function __construct(private $context) {
                }
                public function export_data($path, $data) {
                    writer::$data[$this->context->id][implode('/', $path)] = $data;
                }
                public function has_any_data() {
                    return !empty(writer::$data[$this->context->id]);
                }
            };
        }
    }
}

namespace core_privacy\local\request\plugin {
    interface provider {
    }
}

namespace core_privacy\tests {
    abstract class provider_testcase {
        protected function setUp(): void {
        }
        public function resetAfterTest() {
        }
        public function getDataGenerator() {
            return new \fake_generator();
        }
        public function export_context_data_for_user(int $userid, \context $context, string $component) {
            $provider = "\\$component\\privacy\\provider";
            $provider::export_user_data(new \core_privacy\local\request\approved_contextlist((object) ['id' => $userid],
                $component, [$context->id]));
        }
        private function ensure($ok, $what) {
            if (!$ok) {
                throw new \Exception($what);
            }
        }
        public function assertCount($count, $items) {
            $this->ensure(count($items) === $count, 'count ' . count($items) . ", want $count");
        }
        public function assertContains($item, $items) {
            $this->ensure(in_array($item, $items, true), json_encode($items) . " lacks $item");
        }
        public function assertNotContains($item, $items) {
            $this->ensure(!in_array($item, $items, true), json_encode($items) . " holds $item");
        }
        public function assertTrue($value) {
            $this->ensure($value === true, 'not true');
        }
        public function assertSame($want, $got) {
            $this->ensure($want === $got, json_encode($got) . ', want ' . json_encode($want));
        }
        public function assertGreaterThan($limit, $value) {
            $this->ensure($value > $limit, "$value not > $limit");
        }
    }
}

namespace {
    const CONTEXT_SYSTEM = 10;
    const CONTEXT_COURSE = 50;
    const CONTEXT_MODULE = 70;
    const SQL_PARAMS_NAMED = 1;

    class context {
        public function __construct(public $id, public $instanceid) {
        }
        public static function by_id($id) {
            global $DB;
            $row = $DB->get_record('context', ['id' => $id]);
            return match ((int) ($row['contextlevel'] ?? 0)) {
                CONTEXT_MODULE => new context_module($id, $row['instanceid']),
                CONTEXT_COURSE => new context_course($id, $row['instanceid']),
                default => new context_system($id, 0),
            };
        }
    }
    class context_course extends context {
        public static function instance($courseid) {
            global $DB;
            return new context_course($DB->get_record('context', ['instanceid' => $courseid, 'contextlevel' => CONTEXT_COURSE])['id'], $courseid);
        }
    }
    class context_module extends context {
        public static function instance($cmid) {
            global $DB;
            return new context_module($DB->get_record('context', ['instanceid' => $cmid, 'contextlevel' => CONTEXT_MODULE])['id'], $cmid);
        }
    }
    class context_system extends context {
        public static function instance() {
            return new context_system(1, 0);
        }
    }

    class fake_generator {
        private static int $courses = 0;
        public function create_course() {
            global $DB;
            $id = 7 + self::$courses++;
            $DB->insert('context', ['id' => 43 + $id, 'contextlevel' => CONTEXT_COURSE, 'instanceid' => $id]);
            return (object) ['id' => $id];
        }
        public function create_module($modname, $record) {
            global $DB;
            $module = $DB->insert_record('modules', ['name' => $modname]);
            $instance = $DB->insert_record($modname, $record);
            $cmid = $DB->insert_record('course_modules', ['module' => $module, 'instance' => $instance]);
            $DB->insert_record('context', ['contextlevel' => CONTEXT_MODULE, 'instanceid' => $cmid]);
            return (object) ['id' => $instance, 'cmid' => $cmid];
        }
        public function create_user() {
            global $DB;
            $id = 20 + count($DB->rows('user'));
            $DB->insert('user', ['id' => $id]);
            return (object) ['id' => $id];
        }
    }

    class fake_db {
        public PDO $pdo;
        private int $n = 0;
        public function __construct(array $tables, array $uniques = []) {
            $this->pdo = new PDO('sqlite::memory:', null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
            $tables += ['user' => [], 'modules' => ['name' => 'char'], 'course_modules' => ['module' => 'int', 'instance' => 'int'],
                'context' => ['contextlevel' => 'int', 'instanceid' => 'int']];
            foreach ($tables as $name => $fields) {
                $cols = ['id INTEGER PRIMARY KEY'];
                foreach ($fields as $field => $type) {
                    $cols[] = "$field " . ($type === 'int' ? 'INTEGER NOT NULL DEFAULT 0' : "TEXT NOT NULL DEFAULT ''");
                }
                $this->pdo->exec("CREATE TABLE \"$name\" (" . implode(', ', $cols) . ')');
            }
            foreach ($uniques as $i => [$table, $fields]) {
                $this->pdo->exec("CREATE UNIQUE INDEX u$i ON \"$table\" ($fields)");
            }
        }
        private function q($sql, $params = []) {
            $st = $this->pdo->prepare(preg_replace('/\{(\w+)\}/', '"$1"', $sql));
            $st->execute($params ?? []);
            return $st;
        }
        public function insert($table, array $row) {
            $this->q("INSERT INTO {{$table}} (" . implode(', ', array_keys($row)) . ') VALUES (' .
                implode(', ', array_map(fn($k) => ":$k", array_keys($row))) . ')', $row);
        }
        public function insert_record($table, $row) {
            $row = array_diff_key((array) $row, ['id' => 0]) ?: ['id' => null];
            $this->insert($table, $row);
            return (int) $this->pdo->lastInsertId();
        }
        private function where(array $conditions) {
            return implode(' AND ', array_map(fn($k) => "$k = :$k", array_keys($conditions))) ?: '1 = 1';
        }
        public function get_record($table, array $conditions) {
            return $this->q("SELECT * FROM {{$table}} WHERE " . $this->where($conditions), $conditions)->fetch(PDO::FETCH_ASSOC);
        }
        public function count_records($table, array $conditions) {
            return (int) $this->q("SELECT COUNT(1) FROM {{$table}} WHERE " . $this->where($conditions), $conditions)->fetchColumn();
        }
        public function set_field($table, $field, $value, array $conditions) {
            $this->q("UPDATE {{$table}} SET $field = :newvalue WHERE " . $this->where($conditions), $conditions + ['newvalue' => $value]);
        }
        public function rows($table) {
            return $this->q("SELECT * FROM {{$table}} ORDER BY id")->fetchAll(PDO::FETCH_ASSOC);
        }
        public function get_in_or_equal($items, $type, $prefix = 'param') {
            if (!$items) {
                throw new Exception('get_in_or_equal() does not accept empty arrays');
            }
            $params = [];
            foreach ((array) $items as $item) {
                $params[$prefix . $this->n++] = $item;
            }
            $names = array_map(fn($k) => ":$k", array_keys($params));
            return [count($names) === 1 ? "= {$names[0]}" : 'IN (' . implode(', ', $names) . ')', $params];
        }
        public function get_fieldset_sql($sql, $params = []) {
            return $this->q($sql, $params)->fetchAll(PDO::FETCH_COLUMN);
        }
        public function record_exists_sql($sql, $params = []) {
            return (bool) $this->q($sql, $params)->fetch();
        }
        public function get_records_list($table, $field, array $values, $sort = '', $fields = '*') {
            [$in, $params] = $this->get_in_or_equal($values, SQL_PARAMS_NAMED);
            $out = [];
            foreach ($this->q("SELECT $fields FROM {{$table}} WHERE $field $in ORDER BY $sort", $params)->fetchAll(PDO::FETCH_ASSOC) as $row) {
                $out[$row['id']] = (object) $row;
            }
            return $out;
        }
        public function delete_records_list($table, $field, array $values) {
            [$in, $params] = $this->get_in_or_equal($values, SQL_PARAMS_NAMED);
            $this->q("DELETE FROM {{$table}} WHERE $field $in", $params);
        }
        public function set_field_select($table, $field, $value, $select, $params = []) {
            $this->q("UPDATE {{$table}} SET $field = :newvalue WHERE $select", $params + ['newvalue' => $value]);
        }
    }

    [, $mode, $plugin, $component] = $argv;
    $tables = $uniques = $fks = [];
    foreach (simplexml_load_file("$plugin/db/install.xml")->TABLES->TABLE as $table) {
        $name = (string) $table['NAME'];
        foreach ($table->FIELDS->FIELD as $field) {
            if ((string) $field['NAME'] !== 'id') {
                $tables[$name][(string) $field['NAME']] = (string) $field['TYPE'];
            }
        }
        foreach ($table->xpath('KEYS/KEY|INDEXES/INDEX') as $key) {
            if (in_array((string) $key['TYPE'], ['unique', 'foreign-unique']) || (string) $key['UNIQUE'] === 'true') {
                $uniques[] = [$name, (string) $key['FIELDS']];
            }
            if (in_array((string) $key['TYPE'], ['foreign', 'foreign-unique'])) {
                $fks[] = [$name, (string) $key['FIELDS'], (string) $key['REFTABLE']];
            }
        }
    }
    require("$plugin/classes/privacy/provider.php");
    $provider = "\\$component\\privacy\\provider";
    $fails = 0;
    function check($label, $got, $want) {
        global $mode, $fails;
        $ok = $got === $want;
        $fails += $ok ? 0 : 1;
        echo ($ok ? 'ok   ' : 'FAIL ') . "db $mode: $label" . ($ok ? '' : ': got ' . json_encode($got) . ', want ' . json_encode($want)) . "\n";
    }
    function col($table, $field) {
        global $DB;
        return array_column($DB->rows($table), $field, 'id');
    }
    function exported($ctxid, $path, $key) {
        $data = \core_privacy\local\request\writer::$data[$ctxid][$path] ?? null;
        return isset($data->$key) ? array_map(fn($r) => (array) $r, $data->$key) : null;
    }

    // Users 2 and 3 are students, 5 a teacher who last changed their rows.
    if ($mode === 'mod') {
        $fresh = function () use ($tables, $uniques) {
            global $DB;
            $DB = new fake_db($tables, $uniques);
            foreach ([2, 3, 5, 6] as $id) {
                $DB->insert('user', ['id' => $id]);
            }
            $DB->insert('modules', ['id' => 1, 'name' => 't814']);
            foreach ([[10, 100, 1], [11, 101, 2]] as [$cm, $ctx, $instance]) {
                $DB->insert('course_modules', ['id' => $cm, 'module' => 1, 'instance' => $instance]);
                $DB->insert('context', ['id' => $ctx, 'contextlevel' => CONTEXT_MODULE, 'instanceid' => $cm]);
                $DB->insert('t814', ['id' => $instance, 'usermodified' => 5]);
            }
            foreach ([[1, 1, 2], [2, 1, 3], [3, 2, 2]] as [$id, $instance, $user]) {
                $DB->insert('t814_entry', ['id' => $id, 't814id' => $instance, 'userid' => $user, 'usermodified' => 5]);
                $DB->insert('t814_log', ['id' => $id, 'entryid' => $id, 'graderid' => 5]);
            }
        };
        $ctx = new context_module(100, 10);
        $approved = fn($userid) => new \core_privacy\local\request\approved_contextlist((object) ['id' => $userid], $component, [100]);

        $fresh();
        check('contexts of the teacher', $provider::get_contexts_for_userid(5)->ids, [100, 101]);
        check('contexts of a user without data', $provider::get_contexts_for_userid(6)->ids, []);
        $list = new \core_privacy\local\request\userlist($ctx);
        $provider::get_users_in_context($list);
        sort($list->ids);
        check('users in the context', array_values(array_unique($list->ids)), [2, 3, 5]);

        $provider::export_user_data($approved(5));
        check('teacher export: no student entry rows', exported(100, 't814_entry', 'records'), null);
        check('teacher export: modified entries as id + usermodified', exported(100, 't814_entry', 'modified'),
            [['id' => 1, 'usermodified' => 5], ['id' => 2, 'usermodified' => 5]]);
        check('teacher export: graded logs', array_column(exported(100, 't814_log', 'records') ?? [], 'id'), [1, 2]);
        $provider::export_user_data($approved(2));
        check('student export: own entry in full', exported(100, 't814_entry', 'records'),
            [['id' => 1, 't814id' => 1, 'userid' => 2, 'usermodified' => 5]]);
        check('student export: logs of the own entry', array_column(exported(100, 't814_log', 'records') ?? [], 'id'), [1]);

        $provider::delete_data_for_user($approved(5));
        check('teacher delete: student entries kept', col('t814_entry', 'userid'), [1 => 2, 2 => 3, 3 => 2]);
        check('teacher delete: usermodified set to 0 in the context only', col('t814_entry', 'usermodified'),
            [1 => 0, 2 => 0, 3 => 5]);
        check('teacher delete: graded logs deleted in the context only', array_keys(col('t814_log', 'id')), [3]);
        check('teacher delete: instance kept, usermodified 0', col('t814', 'usermodified'), [1 => 0, 2 => 5]);

        $fresh();
        $provider::delete_data_for_user($approved(2));
        check('student delete: own entry gone', array_keys(col('t814_entry', 'id')), [2, 3]);
        check('student delete: logs of the own entry gone, no orphans', array_keys(col('t814_log', 'id')), [2, 3]);

        $fresh();
        $provider::delete_data_for_users(new \core_privacy\local\request\approved_userlist($ctx, $component, [2, 5]));
        check('users delete: entries', col('t814_entry', 'usermodified'), [2 => 0, 3 => 5]);
        check('users delete: logs', array_keys(col('t814_log', 'id')), [3]);

        $fresh();
        $provider::delete_data_for_all_users_in_context($ctx);
        check('context delete: other module untouched', [array_keys(col('t814_entry', 'id')), array_keys(col('t814_log', 'id'))],
            [[3], [3]]);
        check('context delete: instance kept, usermodified 0', col('t814', 'usermodified'), [1 => 0, 2 => 5]);
    } elseif ($mode === 'test') {
        require("$plugin/tests/privacy/provider_test.php");
        $class = "\\$component\\privacy\\provider_test";
        foreach (get_class_methods($class) as $method) {
            if (str_starts_with($method, 'test_')) {
                $DB = new fake_db($tables, $uniques);
                \core_privacy\local\request\writer::$data = [];
                try {
                    $test = new $class();
                    (new ReflectionMethod($test, 'setUp'))->invoke($test);
                    $test->$method();
                    check("provider_test $method", null, null);
                } catch (Throwable $e) {
                    check("provider_test $method", $e->getMessage(), null);
                }
            }
        }
        $instance = substr($component, strpos($component, '_') + 1);
        foreach ($fks as [$table, $field, $ref]) {
            if ($ref === $instance && $table !== $instance && ($values = array_values(array_unique(col($table, $field))))) {
                check("seed: $table.$field points at the instance", $values, array_column($DB->rows($instance), 'id'));
            }
        }
    } elseif ($mode === 'course') {
        // Courses 7 and 8 (contexts 50, 51) hold items of users 2 and 5; local_t814_pref lives in the system context.
        $fresh = function () use ($tables, $uniques) {
            global $DB;
            $DB = new fake_db($tables, $uniques);
            foreach ([2, 5] as $id) {
                $DB->insert('user', ['id' => $id]);
            }
            $DB->insert('context', ['id' => 1, 'contextlevel' => CONTEXT_SYSTEM, 'instanceid' => 0]);
            foreach ([[50, 7], [51, 8]] as [$ctx, $course]) {
                $DB->insert('context', ['id' => $ctx, 'contextlevel' => CONTEXT_COURSE, 'instanceid' => $course]);
            }
            foreach ([[1, 7, 2], [2, 7, 5], [3, 8, 2]] as [$id, $course, $user]) {
                $DB->insert('local_t814_item', ['id' => $id, 'courseid' => $course, 'ownerid' => $user, 'usermodified' => 5]);
            }
            $DB->insert('local_t814_pref', ['id' => 1, 'userid' => 2]);
        };
        $ctx = new context_course(50, 7);
        $approved = fn($userid, $ids) => new \core_privacy\local\request\approved_contextlist((object) ['id' => $userid], $component, $ids);

        $fresh();
        $ids = $provider::get_contexts_for_userid(2)->ids;
        sort($ids);
        check('contexts of a student: both courses and the system', $ids, [1, 50, 51]);
        check('contexts of the teacher', $provider::get_contexts_for_userid(5)->ids, [50, 51]);
        $list = new \core_privacy\local\request\userlist(new context_course(51, 8));
        $provider::get_users_in_context($list);
        check('users in the second course', array_values(array_unique($list->ids)), [2, 5]);
        $list = new \core_privacy\local\request\userlist(new context_system(1, 0));
        $provider::get_users_in_context($list);
        check('users in the system context', $list->ids, [2]);

        $provider::export_user_data($approved(2, [50]));
        check('student export: only the first course item', [exported(50, 'local_t814_item', 'records'), exported(51, 'local_t814_item', 'records')],
            [[['id' => 1, 'courseid' => 7, 'ownerid' => 2, 'usermodified' => 5]], null]);
        check('student export: no system pref in a course context', exported(50, 'local_t814_pref', 'records'), null);

        $provider::delete_data_for_user($approved(2, [50]));
        check('student delete in course 7: course 8 item and system pref kept', [array_keys(col('local_t814_item', 'id')),
            array_keys(col('local_t814_pref', 'id'))], [[2, 3], [1]]);

        $fresh();
        $provider::delete_data_for_users(new \core_privacy\local\request\approved_userlist($ctx, $component, [5]));
        check('users delete in course 7: teacher item gone, usermodified 0 in course 7 only', col('local_t814_item', 'usermodified'),
            [1 => 0, 3 => 5]);

        $fresh();
        $provider::delete_data_for_all_users_in_context($ctx);
        check('context delete: course 8 rows and system pref kept', [array_keys(col('local_t814_item', 'id')),
            array_keys(col('local_t814_pref', 'id'))], [[3], [1]]);
        $provider::delete_data_for_all_users_in_context(new context_system(1, 0));
        check('system context delete: only the pref', [array_keys(col('local_t814_item', 'id')),
            array_keys(col('local_t814_pref', 'id'))], [[3], []]);
    } else {
        $DB = new fake_db($tables, $uniques);
        foreach ([2, 5] as $id) {
            $DB->insert('user', ['id' => $id]);
        }
        $DB->insert('local_t814_item', ['id' => 1, 'ownerid' => 2, 'usermodified' => 5]);
        $DB->insert('local_t814_item', ['id' => 2, 'ownerid' => 5, 'usermodified' => 5]);
        $ctx = new context_system(1, 0);
        $approved = new \core_privacy\local\request\approved_contextlist((object) ['id' => 5], $component, [1]);
        check('contexts of the teacher', $provider::get_contexts_for_userid(5)->ids, [1]);
        $provider::export_user_data($approved);
        check('teacher export: own item in full, modified item as id + usermodified',
            [exported(1, 'local_t814_item', 'records'), exported(1, 'local_t814_item', 'modified')],
            [[['id' => 2, 'usermodified' => 5, 'ownerid' => 5, 'timemodified' => 0]], [['id' => 1, 'usermodified' => 5]]]);
        $provider::delete_data_for_user($approved);
        check('teacher delete: own item gone, student item kept with usermodified 0', col('local_t814_item', 'usermodified'),
            [1 => 0]);
    }
    exit($fails ? 1 : 0);
}
