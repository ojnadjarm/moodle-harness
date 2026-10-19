<?php
namespace local_fx;

/**
 * Helper with look-alike calls that are not the removed APIs: user_create_user() in a docblock.
 */
class helper {
    public function get_messages() {
        return $this->get_messages() + api::get_messages(1) + \other\api::get_messages(2);
    }

    public static function local_fx_user_create_user() {
        return self::local_fx_user_create_user();
    }
}
