<?php
{{header}}

namespace {{component}}\event;

/**
 * Tests for the {{name}} event.
 *
 * @package    {{component}}
 * @category   test
 * @covers     \{{component}}\event\{{name}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
final class {{name}}_test extends \advanced_testcase {
    /**
     * Triggering the event logs its class, context, objectid, url and description.
     */
    public function test_{{name}}_triggered(): void {
        $this->resetAfterTest();
        $course = $this->getDataGenerator()->create_course();
        $user = $this->getDataGenerator()->create_user();
        $this->setUser($user);
        $context = \context_course::instance($course->id);

        $sink = $this->redirectEvents();
        {{name}}::create({{createparams}})->trigger();
        $events = $sink->get_events();
        $sink->close();

        $this->assertCount(1, $events);
        $event = reset($events);
        $this->assertInstanceOf({{name}}::class, $event);
        $this->assertEquals($context->id, $event->contextid);
        $this->assertEquals($user->id, $event->userid);
{{#objecttable}}
        $this->assertEquals(42, $event->objectid);
{{/objecttable}}
{{#noobjecttable}}
        $this->assertNull($event->objectid);
{{/noobjecttable}}
        $this->assertEquals(get_string('{{stringid}}', '{{component}}'), $event::get_name());
        $this->assertStringContainsString("'{$user->id}'", $event->get_description());
        $this->assertEquals($context->get_url(), $event->get_url());
    }
}
