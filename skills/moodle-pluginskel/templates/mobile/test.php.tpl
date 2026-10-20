<?php
{{header}}

namespace {{component}}\output;

/**
 * Tests for the Moodle App page of the {{handler}} handler.
 *
 * @package    {{component}}
 * @category   test
 * @covers     \{{component}}\output\mobile
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
final class mobile_test extends \advanced_testcase {
    /**
     * The page renders its template as 'main' and sends the otherdata the app reads.
     */
    public function test_{{method}}(): void {
{{#hastable}}
        global $DB, $USER;

{{/hastable}}
        $this->resetAfterTest();
        $this->setAdminUser();
{{setup}}{{#hastable}}
        $other = $this->getDataGenerator()->create_user();
        $DB->insert_record('{{table}}', [
{{ownrow}}        ]);
        $DB->insert_record('{{table}}', [
{{otherrow}}        ]);
{{/hastable}}

        $result = mobile::{{method}}({{args}});

        $this->assertCount(1, $result['templates']);
        $this->assertEquals('main', $result['templates'][0]['id']);
        $this->assertStringContainsString('plugin.{{component}}.{{stringid}}', $result['templates'][0]['html']);
{{#notable}}
        $this->assertSame([], $result['otherdata']);
{{/notable}}
{{#hastable}}
        $rows = json_decode($result['otherdata']['rows'], true);
        $this->assertCount(1, $rows);
{{asserts}}{{/hastable}}
    }
{{#hascapability}}

    /**
     * A user whose role grants {{capability}} where real users get it opens the page.
     */
    public function test_{{method}}_with_capability(): void {
        global {{testglobal}};

        $this->resetAfterTest();
{{setup}}        $user = $this->getDataGenerator()->create_user();
{{grant}}        assign_capability('{{capability}}', CAP_ALLOW, $roleid, $contextid, true);
        $this->setUser($user);

        $result = mobile::{{method}}({{args}});

        $this->assertEquals('main', $result['templates'][0]['id']);
    }

    /**
     * A user whose role prohibits {{capability}} there cannot open the page.
     */
    public function test_{{method}}_requires_capability(): void {
        global {{testglobal}};

        $this->resetAfterTest();
{{setup}}        $user = $this->getDataGenerator()->create_user();
{{grant}}        assign_capability('{{capability}}', CAP_PROHIBIT, $roleid, $contextid, true);
        $this->setUser($user);

        $this->expectException(\{{denied}}::class);
        mobile::{{method}}({{args}});
    }
{{/hascapability}}
}
