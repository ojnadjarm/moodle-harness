<?php
{{header}}

namespace {{component}}\table;

{{#legacy}}
defined('MOODLE_INTERNAL') || die();

global $CFG;
require_once($CFG->libdir . '/tablelib.php');

{{/legacy}}
/**
 * {{title}} table.
 *
 * @package    {{component}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class {{name}} extends {{parent}}{{implements}} {
{{#dynamiccourse}}
    /** @var int Course whose rows the table lists, set from the filterset */
    protected int $courseid = 0;

    /**
     * Sets up the columns and headers; set_filterset() adds the course, base URL and SQL.
     *
     * @param string $uniqueid Unique id of the table
     */
    public function __construct(string $uniqueid) {
{{/dynamiccourse}}
{{#plaincourse}}
    /**
     * Sets up the columns, headers, base URL and the SQL of one course's rows.
     *
     * @param string $uniqueid Unique id of the table
     * @param int $courseid Course whose rows the table lists
     */
    public function __construct(string $uniqueid, int $courseid) {
{{/plaincourse}}
{{#system}}
    /**
     * Sets up the columns, headers, base URL and SQL.
     *
     * @param string $uniqueid Unique id of the table
     */
    public function __construct(string $uniqueid) {
{{/system}}
        parent::__construct($uniqueid);
        $this->define_columns([{{columnlist}}]);
        $this->define_headers([
{{#columns}}
            get_string('{{stringid}}', '{{component}}'),
{{/columns}}
        ]);
{{#system}}
        $this->define_baseurl(new \moodle_url('{{url}}'));
        $this->set_sql('{{fields}}', '{{{dbtable}}}', '1=1');
{{/system}}
{{#plaincourse}}
        $this->define_baseurl(new \moodle_url('{{url}}', ['{{param}}' => $courseid]));
        $this->set_sql('{{fields}}', '{{{dbtable}}}', 'courseid = :courseid', [
            'courseid' => $courseid,
        ]);
{{/plaincourse}}
    }
{{#dynamiccourse}}

    /**
     * Reads the course from the filterset and limits the SQL to its rows.
     *
     * @param \core_table\local\filter\filterset $filterset Filterset with the courseid filter
     */
    public function set_filterset(\core_table\local\filter\filterset $filterset): void {
        $this->courseid = (int) $filterset->get_filter('courseid')->current();
        $this->set_sql('{{fields}}', '{{{dbtable}}}', 'courseid = :courseid', [
            'courseid' => $this->courseid,
        ]);
        parent::set_filterset($filterset);
    }
{{/dynamiccourse}}
{{#timecols}}

    /**
     * Formats the {{col}} column as a date.
     *
     * @param \stdClass $row Table row
     * @return string
     */
    public function col_{{col}}($row): string {
        return $row->{{col}} ? userdate($row->{{col}}) : '-';
    }
{{/timecols}}

    /**
     * Escapes every column without a col_ method.
     *
     * @param string $column Column name
     * @param \stdClass $row Table row
     * @return string
     */
    public function other_cols($column, $row) {
        return s($row->$column);
    }
{{#dynamic}}

    /**
     * Context the table data belongs to.
     *
     * @return \context
     */
    public function get_context(): \context {
{{#system}}
        return \context_system::instance();
{{/system}}
{{#course}}
        return \context_course::instance($this->courseid);
{{/course}}
    }

    /**
     * Base URL used when the table reloads over AJAX.
     */
    public function guess_base_url(): void {
{{#system}}
        $this->define_baseurl(new \moodle_url('{{url}}'));
{{/system}}
{{#course}}
        $this->define_baseurl(new \moodle_url('{{url}}', ['{{param}}' => $this->courseid]));
{{/course}}
    }

    /**
     * Whether the current user may load the table.
     *
     * @return bool
     */
    public function has_capability(): bool {
        return has_capability('{{capability}}', $this->get_context());
    }
{{/dynamic}}
}
