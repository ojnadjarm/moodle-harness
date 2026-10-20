<?php
{{header}}

namespace {{component}}\local\cache;

/**
 * Tests for the {{area}} cache definition and its accessor.
 *
 * @package    {{component}}
 * @category   test
 * @covers     \{{component}}\local\cache\{{area}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
final class {{area}}_test extends \advanced_testcase {
    /**
     * Values set through the accessor are read through cache::make, and purge empties the cache.
     */
    public function test_set_get_purge(): void {
        $this->resetAfterTest();
        $cache = \cache::make('{{component}}', '{{area}}');
        $this->assertTrue({{area}}::set('key1', 'value1'));
        $this->assertSame('value1', $cache->get('key1'));
        $this->assertTrue($cache->set('key2', ['a' => 1]));
        $this->assertSame(['a' => 1], {{area}}::get('key2'));
        $this->assertTrue({{area}}::delete('key2'));
        $this->assertNull({{area}}::get('key2'));
        $this->assertTrue({{area}}::purge());
        $this->assertFalse($cache->get('key1'));
        $this->assertNull({{area}}::get('key1'));
    }
}
