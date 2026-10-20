<?php
{{header}}

namespace {{component}};

/**
 * Tests for the {{methodname}} observer.
 *
 * @package    {{component}}
 * @category   test
 * @covers     \{{component}}\observer
{{#emit}}
 * @covers     \{{component}}\event\{{name}}
{{/emit}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
final class {{name}}_test extends \advanced_testcase {
    /**
     * db/events.php registers the observer.
     */
    public function test_observer_registered(): void {
        $observers = \core\event\manager::get_all_observers()['\{{observed}}'] ?? [];
        $this->assertContains('\{{component}}\observer::{{methodname}}', array_column($observers, 'callable'));
    }

    /**
     * {{testdoc}}
     */
    public function test_{{testname}}(): void {
{{#table}}
        global $DB;

{{/table}}
        $this->resetAfterTest();
        $user = $this->getDataGenerator()->create_user();
        {{contextsetup}}
{{#table}}
        $other = $this->getDataGenerator()->create_user();
        foreach ([$user, $other] as $owner) {
            $DB->insert_record('{{table}}', ['userid' => $owner->id{{tablefill}}]);
        }
{{/table}}
        $observed = \{{observed}}::restore([
            'eventname' => '\{{observed}}', 'component' => '{{observedcomponent}}',
            'action' => '{{observedaction}}', 'target' => '{{observedtarget}}',
            'objecttable' => {{observedobjecttable}}, 'objectid' => {{observedobjectid}},
            'crud' => '{{observedcrud}}', 'edulevel' => {{observededulevel}},
            'contextid' => $context->id, 'contextlevel' => {{contextlevel}}, 'contextinstanceid' => {{contextinstanceid}},
            'userid' => {{observeduserid}}, 'courseid' => {{courseid}}, 'relateduserid' => {{observedrelateduserid}}, 'anonymous' => 0,
            'other' => null, 'timecreated' => time(),
        ], []);

{{#handler}}
        observer::{{methodname}}($observed);
{{#table}}
        $this->assertFalse($DB->record_exists('{{table}}', ['userid' => $user->id]));
        $this->assertTrue($DB->record_exists('{{table}}', ['userid' => $other->id]));
{{/table}}
{{#notable}}
        $this->assertDebuggingCalled('TODO: handle \{{observed}} (objectid 7, relateduserid ' . $user->id .
            ', contextid ' . $context->id . ')');
{{/notable}}
{{/handler}}
{{#emit}}
        $sink = $this->redirectEvents();
        observer::{{methodname}}($observed);
        $events = $sink->get_events();
        $sink->close();

        $this->assertCount(1, $events);
        $event = reset($events);
        $this->assertInstanceOf(event\{{name}}::class, $event);
        $this->assertEquals($context->id, $event->contextid);
        $this->assertEquals($user->id, $event->userid);
{{#objecttable}}
        $this->assertEquals(42, $event->objectid);
{{/objecttable}}
        $this->assertEquals(get_string('{{stringid}}', '{{component}}'), $event::get_name());
        $this->assertStringContainsString("'{$user->id}'", $event->get_description());
        $this->assertEquals($context->get_url(), $event->get_url());
{{/emit}}
    }
}
