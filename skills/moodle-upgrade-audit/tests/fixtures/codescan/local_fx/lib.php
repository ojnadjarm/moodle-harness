<?php
defined('MOODLE_INTERNAL') || die();

use core_message\api;

function local_fx_run($event, $u, $userid) {
    // calendar_add_event_metadata() was removed in 5.0.
    calendar_add_event_metadata($event);
    $msgs = api::get_messages($userid, 0);
    $id = user_create_user($u);
    \core\user::create_user($u);
    old_45_function();
    return [$msgs, $id];
}
