<?php
{{header}}

namespace {{component}}\privacy;

use core_privacy\local\metadata\collection;
use core_privacy\local\request\approved_contextlist;
use core_privacy\local\request\approved_userlist;
use core_privacy\local\request\userlist;
use core_privacy\local\request\writer;
use core_privacy\tests\provider_testcase;

/**
 * Tests for the {{component}} privacy provider.
 *
 * @package    {{component}}
 * @category   test
 * @covers     \{{component}}\privacy\provider
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
final class provider_test extends provider_testcase {
    /** @var array Seed rows: user and plugin-table references, literal values, values made distinct per user. */
    private const ROWS = [
{{rows}}
    ];
{{#course}}

    /** @var array Course fields by table, set to the course of the seeded row. */
    private const COURSES = [{{courses}}];
{{/course}}

    /** @var \context The context holding the seeded data. */
    private \context $context;

    /** @var \stdClass The user whose data is exported and deleted. */
    private \stdClass $user1;

    /** @var \stdClass The user whose data must survive the deletion of user1's. */
    private \stdClass $user2;

    /** @var array Seeded row IDs by table and user ID. */
    private array $seeded = [];
{{#course}}

    /** @var \context The other course context, whose data must survive deletions in the first. */
    private \context $othercontext;

    /** @var \stdClass The user holding data only in the other course. */
    private \stdClass $user3;

    /** @var int The course of the rows being seeded. */
    private int $courseid;
{{/course}}
{{#module}}

    /** @var \stdClass The activity instance. */
    private \stdClass $instance;
{{/module}}

    /**
     * Seed a row in every user table for two users.
     */
    protected function setUp(): void {
        parent::setUp();
        $this->resetAfterTest();
{{#module}}
        $course = $this->getDataGenerator()->create_course();
        $this->instance = $this->getDataGenerator()->create_module('{{pluginname}}', ['course' => $course->id]);
        $this->context = \context_module::instance($this->instance->cmid);
{{/module}}
{{#system}}
        $this->context = \context_system::instance();
{{/system}}
        $this->user1 = $this->getDataGenerator()->create_user();
        $this->user2 = $this->getDataGenerator()->create_user();
{{#course}}
        $this->user3 = $this->getDataGenerator()->create_user();
        $other = $this->getDataGenerator()->create_course();
        $course = $this->getDataGenerator()->create_course();
        $this->othercontext = \context_course::instance($other->id);
        $this->context = \context_course::instance($course->id);
        $this->courseid = $other->id;
        foreach (array_keys(self::ROWS) as $table) {
            $this->seed($table, $this->user3->id);
        }
        $this->courseid = $course->id;
{{/course}}
        foreach ([$this->user2, $this->user1] as $user) {
            foreach (array_keys(self::ROWS) as $table) {
                $this->seed($table, $user->id);
            }
        }
    }

    /**
     * Every user table is declared in the metadata.
     */
    public function test_get_metadata(): void {
        $collection = provider::get_metadata(new collection('{{component}}'));
        $this->assertCount({{metadatacount}}, $collection->get_collection());
    }

    /**
     * The context of the seeded data is found for its user.
     */
    public function test_get_contexts_for_userid(): void {
        $this->assertContains((int) $this->context->id, $this->contextids($this->user1->id));
    }

    /**
     * The user of the seeded data is found in its context.
     */
    public function test_get_users_in_context(): void {
        $userlist = new userlist($this->context, '{{component}}');
        provider::get_users_in_context($userlist);
        $this->assertContains((int) $this->user1->id, array_map('intval', $userlist->get_userids()));
    }

    /**
     * The data of a user is exported in its context.
     */
    public function test_export_user_data(): void {
        $this->export_context_data_for_user($this->user1->id, $this->context, '{{component}}');
        $this->assertTrue(writer::with_context($this->context)->has_any_data());
    }

    /**
     * Deleting a context removes the data of every user.
     */
    public function test_delete_data_for_all_users_in_context(): void {
        provider::delete_data_for_all_users_in_context($this->context);
        foreach ([$this->user1, $this->user2] as $user) {
            $this->assertNotContains((int) $this->context->id, $this->contextids($user->id));
        }
{{#course}}
        $this->assertContains((int) $this->othercontext->id, $this->contextids($this->user3->id));
{{/course}}
    }

    /**
     * Deleting a user's data keeps the other user's.
     */
    public function test_delete_data_for_user(): void {
        $kept = $this->owned($this->user2->id);
        $this->assertGreaterThan(0, $kept);
        provider::delete_data_for_user(new approved_contextlist($this->user1, '{{component}}', [$this->context->id]));
        $this->assertNotContains((int) $this->context->id, $this->contextids($this->user1->id));
        $this->assertSame($kept, $this->owned($this->user2->id));
    }

    /**
     * Deleting the data of a userlist keeps the other user's.
     */
    public function test_delete_data_for_users(): void {
        $kept = $this->owned($this->user2->id);
        $this->assertGreaterThan(0, $kept);
        provider::delete_data_for_users(new approved_userlist($this->context, '{{component}}', [$this->user1->id]));
        $this->assertNotContains((int) $this->context->id, $this->contextids($this->user1->id));
        $this->assertSame($kept, $this->owned($this->user2->id));
    }
{{#coursesystem}}

    /**
     * Rows without a course are exported and deleted in the system context, apart from the course rows.
     */
    public function test_system_context(): void {
        $system = \context_system::instance();
        $this->assertContains((int) $system->id, $this->contextids($this->user1->id));
        $this->export_context_data_for_user($this->user1->id, $system, '{{component}}');
        $this->assertTrue(writer::with_context($system)->has_any_data());
        provider::delete_data_for_user(new approved_contextlist($this->user1, '{{component}}', [$system->id]));
        $this->assertNotContains((int) $system->id, $this->contextids($this->user1->id));
        $this->assertContains((int) $system->id, $this->contextids($this->user2->id));
        $this->assertContains((int) $this->context->id, $this->contextids($this->user1->id));
    }
{{/coursesystem}}

    /**
     * IDs of the contexts holding data of a user, as integers.
     *
     * @param int $userid The user ID.
     * @return int[]
     */
    private function contextids(int $userid): array {
        return array_map('intval', provider::get_contexts_for_userid($userid)->get_contextids());
    }

    /**
     * Number of seeded-table rows whose user fields hold a user ID.
     *
     * @param int $userid The user ID.
     * @return int
     */
    private function owned(int $userid): int {
        global $DB;

        $count = 0;
        foreach (self::ROWS as $table => $row) {
            foreach (array_keys($row['refs'], 'user') as $field) {
                $count += $DB->count_records($table, [$field => $userid]);
            }
        }
        return $count;
    }

    /**
     * Insert a row of a table for a user, once, with the rows it references.
     *
     * @param string $table The table name.
     * @param int $userid The user ID.
     * @return int The row ID.
     */
    private function seed(string $table, int $userid): int {
        global $DB;

        if (isset($this->seeded[$table][$userid])) {
            return $this->seeded[$table][$userid];
        }
{{#module}}
        if ($table === '{{pluginname}}') {
            foreach (array_keys(self::ROWS[$table]['refs'], 'user') as $field) {
                $DB->set_field($table, $field, $userid, ['id' => $this->instance->id]);
            }
            return $this->seeded[$table][$userid] = $this->instance->id;
        }
{{/module}}
        $row = (object) self::ROWS[$table]['values'];
        foreach (self::ROWS[$table]['unique'] as $field) {
            $row->$field = is_int($row->$field) ? $userid : (string) $userid;
        }
{{#course}}
        if (isset(self::COURSES[$table])) {
            $row->{self::COURSES[$table]} = $this->courseid;
        }
{{/course}}
        foreach (self::ROWS[$table]['refs'] as $field => $ref) {
            $row->$field = $ref === 'user' ? $userid : $this->seed($ref, $userid);
        }
        return $this->seeded[$table][$userid] = $DB->insert_record($table, $row);
    }
}
