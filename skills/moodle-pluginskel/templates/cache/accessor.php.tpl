<?php
{{header}}

namespace {{component}}\local\cache;

/**
 * Typed accessor for the {{area}} cache.
 *
 * @package    {{component}}
 * @copyright  {{copyright}}
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class {{area}} {
    /**
     * The {{mode}} cache loader of this definition.
     *
     * @return \cache
     */
    public static function loader(): \cache {
        return \cache::make('{{component}}', '{{area}}');
    }

    /**
     * Reads a value.
     *
     * @param string $key Cache key
     * @return mixed The value, or null when it is not cached
     */
    public static function get(string $key) {
        $value = self::loader()->get($key);
        return $value === false ? null : $value;
    }

    /**
     * Stores a value.
     *
     * @param string $key Cache key
     * @param mixed $value Value to store, never false
     * @return bool Whether it was stored
     */
    public static function set(string $key, $value): bool {
        return self::loader()->set($key, $value);
    }

    /**
     * Deletes a value.
     *
     * @param string $key Cache key
     * @return bool Whether it was deleted
     */
    public static function delete(string $key): bool {
        return self::loader()->delete($key);
    }

    /**
     * Empties the whole cache.
     *
     * @return bool Whether it was purged
     */
    public static function purge(): bool {
        return self::loader()->purge();
    }
}
