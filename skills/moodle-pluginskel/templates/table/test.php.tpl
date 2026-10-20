<?php
{{header}}

namespace {{component}}\table;

/**
 * Tests for the {{name}} table.
 *
 * @package    {{component}}
 * @category   test
 * @covers     \{{component}}\table\{{name}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
final class {{name}}_test extends \advanced_testcase {
{{#system}}
    /**
     * The table SQL runs and returns one page of rows.
     */
    public function test_query_db(): void {
        global $DB;
        $this->resetAfterTest();
{{/system}}
{{#course}}
    /**
     * The table lists only its course's rows.
     */
    public function test_query_db(): void {
        global $DB;
        $this->resetAfterTest();
{{/course}}
{{#system}}
        $table = new {{name}}('{{uniqueid}}');
        $table->setup();
        $table->query_db(5, false);
        $this->assertCount(min(5, $DB->count_records('{{dbtable}}')), $table->rawdata);
    }
{{/system}}
{{#course}}
        $course = $this->getDataGenerator()->create_course();
        $other = $this->getDataGenerator()->create_course();
        foreach ([$course->id, $course->id, $other->id] as $i => $courseid) {
            $DB->insert_record('{{dbtable}}', [
                'courseid' => $courseid,
{{#seed}}
                '{{field}}' => {{value}},
{{/seed}}
            ]);
        }
{{#plaincourse}}
        $table = new {{name}}('{{uniqueid}}', $course->id);
{{/plaincourse}}
{{#dynamiccourse}}
        $table = new {{name}}('{{uniqueid}}');
        $table->set_filterset(self::filterset($course->id));
{{/dynamiccourse}}
        $table->setup();
        $table->query_db(5, false);
        $this->assertCount(2, $table->rawdata);
    }
{{/course}}

    /**
     * Text cells are escaped and time cells are dates.
     */
    public function test_format_row(): void {
        $table = new {{name}}('{{uniqueid}}'{{formatargs}});
        $row = $table->format_row([
{{#columns}}
            '{{col}}' => {{sample}},
{{/columns}}
        ]);
{{#columns}}
        $this->assertSame({{expected}}, $row['{{col}}']);
{{/columns}}
    }
{{#dynamic}}

    /**
     * Admins load the table; a prohibited user does not.
     */
    public function test_has_capability(): void {
        global $CFG;
        $this->resetAfterTest();
        $table = new {{name}}('{{uniqueid}}');
{{#course}}
        $table->set_filterset(self::filterset($this->getDataGenerator()->create_course()->id));
{{/course}}
        $this->setAdminUser();
        $this->assertTrue($table->has_capability());
        $context = \context_system::instance();
        assign_capability('{{capability}}', CAP_PROHIBIT, $CFG->defaultuserroleid, $context, true);
        $this->setUser($this->getDataGenerator()->create_user());
        $this->assertFalse($table->has_capability());
    }

    /**
     * The core dynamic table web service renders this table.
     */
    public function test_dynamic_get(): void {
        $this->resetAfterTest();
        $this->setAdminUser();
{{#course}}
        $course = $this->getDataGenerator()->create_course();
        $filters = [[
            'name' => 'courseid',
            'jointype' => \core_table\local\filter\filter::JOINTYPE_DEFAULT,
            'values' => [(int) $course->id],
        ]];
{{/course}}
{{#namedargs}}
        $result = \core_table\external\dynamic\get::execute(
            component: '{{component}}',
            handler: '{{name}}',
            uniqueid: '{{uniqueid}}',
            sortdata: [],
            filters: {{filters}},
            jointype: \core_table\local\filter\filter::JOINTYPE_ALL,
            hiddencolumns: [],
        );
{{/namedargs}}
{{#positional}}
        $result = \core_table\external\dynamic\get::execute(
            '{{component}}',
            '{{name}}',
            '{{uniqueid}}',
            [],
            {{filters}},
            \core_table\local\filter\filter::JOINTYPE_ALL,
            null,
            null,
            null,
            null,
            [],
            null
        );
{{/positional}}
        $this->assertStringContainsString('data-table-uniqueid="{{uniqueid}}"', $result['html']);
    }
{{/dynamic}}
{{#dynamiccourse}}

    /**
     * Filterset of one course, as the page builds it.
     *
     * @param int $courseid Course id
     * @return {{name}}_filterset
     */
    private static function filterset(int $courseid): {{name}}_filterset {
        $filterset = new {{name}}_filterset();
        $filterset->add_filter(new \core_table\local\filter\integer_filter('courseid', null, [$courseid]));
        return $filterset;
    }
{{/dynamiccourse}}
}
