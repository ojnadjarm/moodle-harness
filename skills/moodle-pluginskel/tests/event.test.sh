#!/usr/bin/env bash
# Drive event.py on mktemp plugins: event class, lang, bump, emit-only event test + trigger() snippet, --emit-in page wiring, --emit observer, observer test crud/edulevel/context read from core, handler stub (spy or --table row, relateduserid checked in the class chain or core ::create() callers, --force), db/events.php merge, refusals, codechecker.
# --live: also install the plugin on the 5.2 env via mfixture, run its generated observer test once, remove it.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
D="$(cd "$(dirname "$0")/.." && pwd)"
E="$D/event.py"; G="$D/generate.py"; S="$D/../moodle-ci/scripts"
LIVE=0; [ "${1:-}" = --live ] && LIVE=1
T="$(mktemp -d)"; installed=""
trap '[ -n "$installed" ] && "$S/mfixture" rm 5.2 local_t839ev >/dev/null 2>&1; rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
version() { sed -n 's/^\$plugin->version = \([0-9]*\);/\1/p' "$1/version.php"; }
observers() { php -r "define('MOODLE_INTERNAL', 1); include '$1'; echo json_encode(\$observers);"; }

render() {
    mkdir -p "$T/$1"
    printf 'component: %s\nrequires: "5.2"\ncopyright: 2026 onwards, Example Author <author@example.com>\n' "$2" > "$T/$1/recipe.yaml"
    python3 "$G" --target-dir "$T/$1" "$T/$1/recipe.yaml" >/dev/null 2>"$T/err" || bad "$2 skeleton: $(cat "$T/err")"
}
CORE="$T/core"; mkdir -p "$CORE/lib/classes/event"
init() { printf '    protected function init() {\n%s        $this->data['"'crud'"'] = '"'%s'"';\n        $this->data['"'edulevel'"'] = self::%s;\n    }\n' "$@"; }
level() { printf '    protected function validate_data() {\n        if ($this->contextlevel != CONTEXT_%s) {\n            throw new \\coding_exception();\n        }\n    }\n' "$1"; }
printf '<?php\nnamespace core\\event;\nclass course_viewed extends base {\n%s\n%s}\n' "$(init '' r LEVEL_PARTICIPATING)" "$(level COURSE)" \
    > "$CORE/lib/classes/event/course_viewed.php"
printf '<?php\nnamespace core\\event;\nclass user_loggedin extends base {\n%s}\n' \
    "$(init $'        $this->context = \\context_system::instance();\n' r LEVEL_OTHER)" > "$CORE/lib/classes/event/user_loggedin.php"
for ev in user_created:c user_deleted:d; do
    printf '<?php\nnamespace core\\event;\nclass %s extends base {\n%s\n    protected function validate_data() {\n        if (!isset($this->relateduserid)) {\n            throw new \\coding_exception();\n        }\n    }\n}\n' \
        "${ev%:*}" "$(init $'        $this->data[\'objecttable\'] = \'user\';\n' "${ev#*:}" LEVEL_OTHER)" > "$CORE/lib/classes/event/${ev%:*}.php"
done
cat > "$CORE/lib/moodlelib.php" <<'PHP'
<?php
function delete_user($user) {
    $usercontext = context_user::instance($user->id);
    \core\event\user_deleted::create(['objectid' => $user->id, 'relateduserid' => $user->id, 'context' => $usercontext])->trigger();
}
PHP
mkdir -p "$CORE/mod/x/classes/event"
printf '<?php\nnamespace mod_x\\event;\nuse core\\event\\user_deleted as deleted;\n/** Mentions relateduserid only here. */\nclass member_removed extends deleted {\n}\n' > "$CORE/mod/x/classes/event/member_removed.php"
printf '<?php\nnamespace mod_x\\event;\nclass page_seen extends \\core\\event\\course_viewed {\n}\n' > "$CORE/mod/x/classes/event/page_seen.php"
for ev in attempt_deleted locks_cleared; do
    printf '<?php\nnamespace mod_x\\event;\nclass %s extends \\core\\event\\base {\n%s\n%s}\n' "$ev" "$(init '' d LEVEL_TEACHING)" "$(level MODULE)" \
        > "$CORE/mod/x/classes/event/$ev.php"
done
printf '<?php\nnamespace mod_x\\event;\nclass bare_done extends \\core\\event\\base {\n}\n' > "$CORE/mod/x/classes/event/bare_done.php"
printf '<?php\nnamespace mod_x\\event;\nclass role_given extends \\core\\event\\base {\n%s}\n' "$(init '' u LEVEL_OTHER)" > "$CORE/mod/x/classes/event/role_given.php"
for f in a:module b:course c:module; do
    printf '<?php\n\\mod_x\\event\\role_given::create([\x27context\x27 => \\context_%s::instance(1)])->trigger();\n' "${f#*:}" > "$CORE/mod/x/role_${f%%:*}.php"
done
cat > "$CORE/mod/x/locallib.php" <<'PHP'
<?php
use mod_x\event\locks_cleared;
function x_delete_attempt($userid, $context) {
    \mod_x\event\attempt_deleted::create([
        'context' => $context,
        'relateduserid' => $userid,
    ])->trigger();
    \mod_x\event\page_seen::create(['context' => $context])->trigger();
    \mod_x\event\member_removed::create(['context' => \context_module::instance(1)])->trigger();
}
function x_clear_locks($userid, $context) {
    $params = ['context' => $context, 'relateduserid' => $userid];
    locks_cleared::create($params)->trigger();
}
PHP

render l local_t839ev; P="$T/l/t839ev"
render m mod_t839m; M="$T/m/t839m"
v0="$(version "$P")"
python3 "$E" "$P" item_synced --crud u --edulevel participating --objecttable course \
    --observe '\core\event\course_viewed' --emit --core "$CORE" >"$T/out" 2>"$T/err" \
    && ok "event + --emit observer renders" || bad "rc: $(cat "$T/out" "$T/err")"
[ ! -s "$T/err" ] && ok "observed event found in core, no warning" || bad "stderr: $(cat "$T/err")"
v1="$(version "$P")"; [ "$v1" -gt "$v0" ] && ok "version bumped $v0 -> $v1" || bad "version not bumped: $v1"
ec="$P/classes/event/item_synced.php"
grep -q 'class item_synced extends \\core\\event\\base {' "$ec" && grep -q "\$this->data\['crud'\] = 'u';" "$ec" \
    && grep -q "\$this->data\['edulevel'\] = self::LEVEL_PARTICIPATING;" "$ec" \
    && grep -q "\$this->data\['objecttable'\] = 'course';" "$ec" \
    && grep -q "return get_string('eventitemsynced', 'local_t839ev');" "$ec" \
    && grep -q "synced the item with id '{\$this->objectid}'" "$ec" && grep -q 'get_context()->get_url()' "$ec" \
    && grep -q "'db' => 'course', 'restore' => \\\\core\\\\event\\\\base::NOT_MAPPED" "$ec" \
    && ok "event class: init, get_name, get_description, get_url, objectid mapping" || bad "event class: $(cat "$ec")"
grep -q "^\$string\['eventitemsynced'\] = 'Item synced';" "$P/lang/en/local_t839ev.php" \
    && ok "lang string eventitemsynced" || bad "lang: $(cat "$P/lang/en/local_t839ev.php")"
[ "$(observers "$P/db/events.php")" = '[{"eventname":"\\core\\event\\course_viewed","callback":"\\local_t839ev\\observer::course_viewed"}]' ] \
    && ok "db/events.php created: eventname + callback" || bad "events.php: $(cat "$P/db/events.php")"
oc="$P/classes/observer.php"; ot="$P/tests/observer/item_synced_test.php"
grep -q 'public static function course_viewed(\\core\\event\\course_viewed $event): void {' "$oc" \
    && grep -q 'event\\item_synced::create(\[' "$oc" && grep -q "'objectid' => \$event->objectid," "$oc" \
    && ok "observer method triggers the event with objectid" || bad "observer: $(cat "$oc")"
grep -q 'redirectEvents()' "$ot" && grep -q 'observer::course_viewed($observed);' "$ot" \
    && grep -q "get_all_observers()\['\\\\core\\\\event\\\\course_viewed'\]" "$ot" \
    && grep -q "'objectid' => 42," "$ot" \
    && ok "observer test: sink + registration" || bad "observer test: $(cat "$ot")"

python3 "$E" "$P" user_flagged --crud c --edulevel teaching --observe 'core\event\user_created' --emit --core "$CORE" \
    >"$T/out" 2>&1 || bad "second observer rc: $(cat "$T/out")"
[ "$(observers "$P/db/events.php" | grep -o '"eventname"' | wc -l)" = 2 ] && [ "$(grep -c '^\$observers = ' "$P/db/events.php")" = 1 ] \
    && [ "$(grep -c 'public static function' "$oc")" = 2 ] && [ "$(grep -c '^class observer' "$oc")" = 1 ] \
    && ok "second observer merged into db/events.php and observer.php" || bad "merge: $(cat "$P/db/events.php" "$oc")"
grep -q "self::LEVEL_TEACHING;" "$P/classes/event/user_flagged.php" && ! grep -q objecttable "$P/classes/event/user_flagged.php" \
    && grep -q "flagged the user\.\"" "$P/classes/event/user_flagged.php" \
    && grep -q "'objectid' => null," "$P/tests/observer/user_flagged_test.php" \
    && ok "no --objecttable: no objecttable, no mapping" || bad "user_flagged: $(cat "$P/classes/event/user_flagged.php")"

python3 "$E" "$P" ticket_closed --crud u --edulevel other --observe '\core\event\user_deleted' --core "$CORE" >"$T/out" 2>&1 \
    || bad "handler stub rc: $(cat "$T/out")"
body="$(sed -n '/function user_deleted(/,/^    }/p' "$oc")"; ht="$P/tests/observer/ticket_closed_test.php"
grep -q '\$objectid = \$event->objectid;' <<<"$body" && grep -q '\$relateduserid = \$event->relateduserid;' <<<"$body" \
    && grep -q '\$contextid = \$event->contextid;' <<<"$body" && ! grep -qE '::create\(|->trigger\(' <<<"$body" \
    && grep -q 'debugging("TODO: handle {\$event->eventname}' <<<"$body" \
    && ok "--observe without --emit: handler reads objectid, relateduserid, contextid, no re-emit" || bad "handler: $body"
[ ! -e "$P/classes/event/ticket_closed.php" ] && ! grep -q eventticketclosed "$P/lang/en/local_t839ev.php" \
    && ok "--observe alone: no event class, no lang string" || bad "--observe alone wrote the event: $(ls "$P/classes/event")"
grep -q 'observer::user_deleted(\$observed);' "$ht" && grep -q "assertDebuggingCalled('TODO: handle \\\\core\\\\event\\\\user_deleted (objectid 7, relateduserid '" "$ht" \
    && grep -q "'relateduserid' => \$user->id," "$ht" && ! grep -qE 'redirectEvents|ticket_closed::class' "$ht" \
    && grep -q 'public function test_observer_handles_event' "$ht" \
    && ok "handler test: sink-free debugging spy asserts the handler ran with the event ids" || bad "handler test: $(cat "$ht")"
grep -q "'objecttable' => 'user', 'objectid' => 7," "$ht" && grep -q "'crud' => 'd', 'edulevel' => 0," "$ht" \
    && grep -q "'contextlevel' => CONTEXT_USER, 'contextinstanceid' => \$user->id," "$ht" \
    && grep -q '\$context = \\context_user::instance(\$user->id);' "$ht" && grep -q "'courseid' => 0," "$ht" \
    && ! grep -q create_course "$ht" \
    && ok "observer test: crud d, edulevel 0, objecttable from core init(), user context from a core ::create() caller" \
    || bad "user_deleted fields: $(cat "$ht")"
grep -q "'crud' => 'r', 'edulevel' => 2," "$ot" && grep -q "'contextlevel' => CONTEXT_COURSE, 'contextinstanceid' => \$course->id," "$ot" \
    && grep -q "'objecttable' => null," "$ot" \
    && ok "observer test: crud r, edulevel 2 and course context (validate_data) of course_viewed" || bad "course_viewed fields: $(cat "$ot")"
[ ! -e "$P/tests/event" ] && ! grep -q '^trigger: ' "$T/out" \
    && ok "--observe alone and --emit: no event test, no trigger() snippet" || bad "observe wrote an event test: $(ls "$P/tests/event"; cat "$T/out")"

python3 "$E" "$P" mark_created --crud c --edulevel teaching --objecttable course >"$T/out" 2>&1 || bad "emit-only rc: $(cat "$T/out")"
et="$P/tests/event/mark_created_test.php"
grep -q 'namespace local_t839ev\\event;' "$et" && grep -q 'final class mark_created_test extends \\advanced_testcase {' "$et" \
    && grep -q 'redirectEvents()' "$et" \
    && grep -q "mark_created::create(\['context' => \$context, 'objectid' => 42\])->trigger();" "$et" \
    && grep -q 'assertInstanceOf(mark_created::class, \$event);' "$et" \
    && grep -q 'assertEquals(\$context->id, \$event->contextid);' "$et" && grep -q 'assertEquals(42, \$event->objectid);' "$et" \
    && grep -q 'assertEquals(\$context->get_url(), \$event->get_url());' "$et" && grep -q 'get_description());' "$et" \
    && ok "emit-only: tests/event/<name>_test.php sinks the trigger(), asserts class, context, objectid, url, description" \
    || bad "event test: $(cat "$et")"
grep -qxF "trigger: \local_t839ev\event\mark_created::create(['context' => \$context, 'objectid' => \$objectid])->trigger();" "$T/out" \
    && grep -qxF "$et" "$T/out" && ok "emit-only: stdout prints the test path and a ready trigger() snippet" || bad "snippet: $(cat "$T/out")"

page() { { sed -n '1,23p' "$P/version.php" | sed 's/Plugin version and other metadata\./Test page./'; printf "\nrequire('../../config.php');\n\n"; cat; } > "$1"; }
page "$P/visits.php" <<'PHP'
$syscontext = context_system::instance();
require_login();
require_capability(
    'moodle/site:config',
    $syscontext
);
$PAGE->set_context($syscontext);
PHP
v0="$(version "$P")"
python3 "$E" "$P" visits_viewed --crud r --edulevel other --emit-in visits.php >"$T/out" 2>&1 \
    && sed -n '/^);$/{n;p}' "$P/visits.php" | grep -qxF "\local_t839ev\event\visits_viewed::create(['context' => \$syscontext])->trigger();" \
    && grep -qxF 'wired: visits.php triggers visits_viewed after its require_capability()' "$T/out" \
    && [ -e "$P/classes/event/visits_viewed.php" ] && [ "$(version "$P")" -gt "$v0" ] \
    && ok "--emit-in: trigger after the multi-line require_capability(), with its context argument" || bad "--emit-in: $(cat "$T/out" "$P/visits.php")"
vsum="$(md5sum "$P/visits.php" "$P/version.php")"
python3 "$E" "$P" visits_viewed --emit-in visits.php >"$T/out" 2>&1 && grep -q 'already triggers visits_viewed' "$T/out" \
    && [ "$vsum" = "$(md5sum "$P/visits.php" "$P/version.php")" ] && [ "$(grep -c 'visits_viewed::create(' "$P/visits.php")" = 1 ] \
    && ok "--emit-in again: idempotent, rc 0, page and version unchanged" || bad "--emit-in rerun: $(cat "$T/out" "$P/visits.php")"
W="$T/wire"; mkdir -p "$W/lang/en"; cp "$P/version.php" "$W/"; cp "$P/lang/en/local_t839ev.php" "$W/lang/en/"
python3 "$E" "$W" spot_marked --crud c --edulevel teaching --objecttable course >/dev/null 2>&1 || bad "wire plugin event rc"
page "$W/login.php" <<'PHP'
$course = get_course(required_param('id', PARAM_INT));
$objectid = $course->id;
$context = context_course::instance($course->id);
if ($course->visible) {
    require_login($course);
}
PHP
v0="$(version "$W")"
python3 "$E" "$W" spot_marked --emit-in login.php >"$T/out" 2>&1 \
    && sed -n '/^    require_login(\$course);$/{n;p}' "$W/login.php" \
    | grep -qxF "    \local_t839ev\event\spot_marked::create(['context' => \$context, 'objectid' => \$objectid])->trigger();" \
    && [ "$(version "$W")" = "$v0" ] && grep -qxF 'wired: login.php triggers spot_marked after its require_login()' "$T/out" \
    && ok "--emit-in alone on an existing event: after require_login(), indented, objectid kept, no version bump" \
    || bad "--emit-in login: $(cat "$T/out" "$W/login.php")"
page "$W/course.php" <<'PHP'
$id = required_param('id', PARAM_INT);
require_login($id);
$context = context_course::instance($id);
$PAGE->set_context($context);
PHP
python3 "$E" "$W" course_opened --crud r --edulevel participating --emit-in course.php >"$T/out" 2>&1 \
    && sed -n '/^\$context = context_course::instance(\$id);$/{n;p}' "$W/course.php" \
    | grep -qxF "\local_t839ev\event\course_opened::create(['context' => \$context])->trigger();" \
    && ok "--emit-in: \$context set after require_login(): trigger goes after the \$context line" \
    || bad "--emit-in late \$context: $(cat "$T/out" "$W/course.php")"
for case in context:ctx_opened:'$PAGE->set_url("/x.php");' objectid:spot_marked:'$context = context_system::instance();'; do
    var="${case%%:*}"; rest="${case#*:}"; ev="${rest%%:*}"
    { echo 'require_login();'; echo "${rest#*:}"; } | page "$W/no$var.php"
    before="$(md5sum "$W/version.php" "$W/no$var.php" "$W/lang/en/local_t839ev.php")"
    python3 "$E" "$W" "$ev" --crud r --edulevel other --emit-in "no$var.php" >"$T/out" 2>&1; rc=$?
    [ "$rc" = 1 ] && grep -q "never sets \\\$$var" "$T/out" && [ ! -e "$W/classes/event/ctx_opened.php" ] \
        && [ "$before" = "$(md5sum "$W/version.php" "$W/no$var.php" "$W/lang/en/local_t839ev.php")" ] \
        && ok "--emit-in on a page that never sets \$$var: rc 1, nothing written" || bad "--emit-in no \$$var rc $rc: $(cat "$T/out")"
done
python3 "$E" "$W" spot_marked --crud r --objecttable user --emit-in login.php >"$T/out" 2>"$T/err" \
    && grep -q 'already triggers spot_marked' "$T/out" && grep -q 'warning: classes/event/spot_marked.php exists: --crud, --objecttable ignored' "$T/err" \
    && ok "--emit-in on an existing event warns that --crud/--objecttable are ignored" || bad "wire-only flags: $(cat "$T/out" "$T/err")"
page "$W/none.php" <<'PHP'
$PAGE->set_context(context_system::instance());
PHP
before="$(md5sum "$W/version.php" "$W/none.php" "$W/lang/en/local_t839ev.php")"
python3 "$E" "$W" none_viewed --crud r --edulevel other --emit-in none.php >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'has no require_capability() or require_login()' "$T/out" && [ ! -e "$W/classes/event/none_viewed.php" ] \
    && [ "$before" = "$(md5sum "$W/version.php" "$W/none.php" "$W/lang/en/local_t839ev.php")" ] \
    && ok "--emit-in on a page without require_capability/require_login: rc 1, nothing written" || bad "--emit-in none rc $rc: $(cat "$T/out")"

render tb local_t879tb; B="$T/tb/t879tb"; mkdir -p "$B/db"
cat > "$B/db/install.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8" ?>
<XMLDB PATH="local/t879tb/db" VERSION="2026102000" COMMENT="XMLDB file for local/t879tb"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="../../../lib/xmldb/xmldb.xsd">
  <TABLES>
    <TABLE NAME="local_t879tb_ticket" COMMENT="Tickets">
      <FIELDS>
        <FIELD NAME="id" TYPE="int" LENGTH="10" NOTNULL="true" SEQUENCE="true"/>
        <FIELD NAME="userid" TYPE="int" LENGTH="10" NOTNULL="true" SEQUENCE="false"/>
        <FIELD NAME="subject" TYPE="char" LENGTH="255" NOTNULL="true" SEQUENCE="false"/>
        <FIELD NAME="status" TYPE="int" LENGTH="2" NOTNULL="true" DEFAULT="0" SEQUENCE="false"/>
        <FIELD NAME="note" TYPE="text" NOTNULL="false" SEQUENCE="false"/>
        <FIELD NAME="timecreated" TYPE="int" LENGTH="10" NOTNULL="true" SEQUENCE="false"/>
      </FIELDS>
      <KEYS>
        <KEY NAME="primary" TYPE="primary" FIELDS="id"/>
      </KEYS>
    </TABLE>
    <TABLE NAME="local_t879tb_log" COMMENT="No userid">
      <FIELDS>
        <FIELD NAME="id" TYPE="int" LENGTH="10" NOTNULL="true" SEQUENCE="true"/>
      </FIELDS>
      <KEYS>
        <KEY NAME="primary" TYPE="primary" FIELDS="id"/>
      </KEYS>
    </TABLE>
  </TABLES>
</XMLDB>
XML
python3 "$E" "$B" ticket_purged --crud d --edulevel other --observe '\core\event\user_deleted' --table local_t879tb_ticket \
    --core "$CORE" >"$T/out" 2>&1 || bad "--table rc: $(cat "$T/out")"
bb="$(sed -n '/function user_deleted(/,/^    }/p' "$B/classes/observer.php")"; bt="$B/tests/observer/ticket_purged_test.php"
grep -q 'global \$DB;' <<<"$bb" && ! grep -qE '\$(objectid|relateduserid|contextid) =' <<<"$bb" \
    && grep -q "\$DB->delete_records('local_t879tb_ticket', \['userid' => \$event->relateduserid\]);" <<<"$bb" \
    && ! grep -qE 'debugging|::create\(' <<<"$bb" && ok "--table: handler deletes the related user's rows, no unused locals" || bad "--table handler: $bb"
grep -q "insert_record('local_t879tb_ticket', \['userid' => \$owner->id, 'subject' => 'x', 'timecreated' => 1\]);" "$bt" \
    && grep -q "assertFalse(\$DB->record_exists('local_t879tb_ticket', \['userid' => \$user->id\]));" "$bt" \
    && grep -q "assertTrue(\$DB->record_exists('local_t879tb_ticket', \['userid' => \$other->id\]));" "$bt" \
    && ! grep -q assertDebuggingCalled "$bt" && ok "--table test: rows filled from install.xml, DB row asserted" || bad "--table test: $(cat "$bt")"
grep -q "'userid' => \$other->id," "$bt" && grep -q "'relateduserid' => \$user->id," "$bt" \
    && ok "--table test: actor and related user differ" || bad "--table test users: $(cat "$bt")"
python3 "$E" "$B" member_purged --crud d --edulevel other --observe '\mod_x\event\member_removed' --table local_t879tb_ticket \
    --core "$CORE" >"$T/out" 2>"$T/err" && [ ! -s "$T/err" ] \
    && ok "--table: relateduserid set by the parent class (use alias) accepted" || bad "--table parent: $(cat "$T/out" "$T/err")"
grep -q "'crud' => 'd', 'edulevel' => 0," "$B/tests/observer/member_purged_test.php" \
    && grep -q "'contextlevel' => CONTEXT_MODULE," "$B/tests/observer/member_purged_test.php" \
    && ok "observer test: crud/edulevel from the parent's init(), context from an inline context_module caller" \
    || bad "member_removed fields: $(cat "$B/tests/observer/member_purged_test.php")"
for ev in attempt_deleted locks_cleared; do
    python3 "$E" "$B" "${ev}_purged" --observe "\\mod_x\\event\\$ev" --table local_t879tb_ticket \
        --core "$CORE" >"$T/out" 2>"$T/err" && [ ! -s "$T/err" ] \
        && ok "--table: relateduserid set by a $ev::create() caller in core accepted" || bad "--table caller $ev: $(cat "$T/out" "$T/err")"
done
grep -q 'function attempt_deleted(' "$B/classes/observer.php" && [ ! -e "$B/classes/event/attempt_deleted_purged.php" ] \
    && ok "--observe without --crud/--edulevel: handler only" || bad "no --crud handler: $(ls "$B/classes" "$B/classes/event" 2>&1)"
python3 "$E" "$B" ghost_purged --crud d --edulevel other --observe '\mod_x\event\ghost_gone' --table local_t879tb_ticket \
    --core "$CORE" >"$T/out" 2>"$T/err" && grep -q 'warning: mod_x\\event\\ghost_gone not found' "$T/err" \
    && ok "--table: unreadable observed class warns, handler written" || bad "--table unreadable: $(cat "$T/out" "$T/err")"

lt="$P/tests/observer/login_seen_test.php"
python3 "$E" "$P" login_seen --observe '\core\event\user_loggedin' --core "$CORE" >"$T/out" 2>"$T/err" && [ ! -s "$T/err" ] \
    && grep -q '\$context = \\context_system::instance();' "$lt" && grep -q "'contextlevel' => CONTEXT_SYSTEM, 'contextinstanceid' => 0," "$lt" \
    && ok "observer test: system context from init() \$this->context" || bad "user_loggedin: $(cat "$T/out" "$T/err" "$lt")"
at="$B/tests/observer/attempt_deleted_purged_test.php"
grep -q "create_module('page', \['course' => \$course->id\]);" "$at" && grep -q '\$context = \\context_module::instance(\$cm->cmid);' "$at" \
    && grep -q "'crud' => 'd', 'edulevel' => 1," "$at" && grep -q "'contextlevel' => CONTEXT_MODULE, 'contextinstanceid' => \$cm->cmid," "$at" \
    && ok "observer test: module context and teaching edulevel from core" || bad "attempt_deleted fields: $(cat "$at")"
bt2="$P/tests/observer/bare_seen_test.php"
python3 "$E" "$P" bare_seen --observe '\mod_x\event\bare_done' --core "$CORE" >"$T/out" 2>"$T/err" \
    && grep -q "warning: crud or edulevel of mod_x\\\\event\\\\bare_done not read" "$T/err" && grep -q 'warning: context level of .*bare_done not read' "$T/err" \
    && grep -q "'crud' => 'r', 'edulevel' => 0," "$bt2" && grep -q "'contextlevel' => CONTEXT_COURSE," "$bt2" \
    && ok "observer test: core class without init() falls back to crud r, edulevel 0, course context with warnings" \
    || bad "fallback: $(cat "$T/out" "$T/err" "$bt2")"

rt="$P/tests/observer/role_seen_test.php"
python3 "$E" "$P" role_seen --observe '\mod_x\event\role_given' --core "$CORE" >"$T/out" 2>"$T/err" \
    && grep -q 'warning: mod_x\\event\\role_given is created in several context levels in core (course 1, module 2): the test uses the most common, module' "$T/err" \
    && grep -q "'contextlevel' => CONTEXT_MODULE," "$rt" \
    && ok "observer test: several caller context levels: most common one, with a warning" || bad "role_given: $(cat "$T/out" "$T/err" "$rt")"

python3 "$E" "$M" entry_viewed --crud r --edulevel other >"$T/out" 2>&1 \
    && grep -q "^\$string\['evententryviewed'\]" "$M/lang/en/t839m.php" && [ ! -e "$M/db/events.php" ] \
    && [ ! -e "$M/classes/observer.php" ] && ok "mod_: lang/en/<name>.php, no observer without --observe" \
    || bad "mod event: $(cat "$T/out")"
grep -q 'entry_viewed::create(\[.context. => \$context\])->trigger();' "$M/tests/event/entry_viewed_test.php" \
    && grep -q 'assertNull(\$event->objectid);' "$M/tests/event/entry_viewed_test.php" \
    && grep -qxF "trigger: \mod_t839m\event\entry_viewed::create(['context' => \$context])->trigger();" "$T/out" \
    && ok "emit-only, no --objecttable: no objectid in the test or the snippet" || bad "mod event test: $(cat "$M/tests/event/entry_viewed_test.php" "$T/out")"

A="$T/arr"; mkdir -p "$A/db" "$A/lang/en"; cp "$M/version.php" "$A/"; cp "$M/lang/en/t839m.php" "$A/lang/en/"
printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\$observers = array(\n    array('eventname' => '\\\\core\\\\event\\\\user_created', 'callback' => 'x::y')\n);\n" > "$A/db/events.php"
python3 "$E" "$A" view_logged --crud r --edulevel other --observe '\core\event\course_viewed' --core "$CORE" >"$T/out" 2>&1 \
    && [ "$(observers "$A/db/events.php" | grep -o '"eventname"' | wc -l)" = 2 ] && ! grep -q '\[' "$A/db/events.php" \
    && ok "array() db/events.php: merged in array() style" || bad "array() merge: $(cat "$T/out" "$A/db/events.php")"

python3 "$E" "$P" page_opened --crud r --edulevel other --observe '\core\event\nothing_here' --core "$CORE" >"$T/out" 2>"$T/err" \
    && grep -q 'warning: core\\event\\nothing_here not found' "$T/err" && ok "unknown observed event warns on stderr" \
    || bad "unknown observed: $(cat "$T/out" "$T/err")"

before="$(md5sum "$P/version.php" "$P/db/events.php" "$oc" "$P/lang/en/local_t839ev.php")"
refuse() {
    local label="$1" want="$2"; shift 2
    python3 "$E" "$@" --core "$CORE" >"$T/out" 2>&1 && { bad "$label accepted"; return; }
    grep -q "$want" "$T/out" && [ "$before" = "$(md5sum "$P/version.php" "$P/db/events.php" "$oc" "$P/lang/en/local_t839ev.php")" ] \
        && ok "$label refused, nothing written" || bad "$label: $(cat "$T/out")"
}
refuse "existing event class" 'item_synced.php already exists' "$P" item_synced --crud u --edulevel other
refuse "name without _" 'bad event name' "$P" synced --crud u --edulevel other
refuse "bad --crud" 'invalid choice' "$P" thing_done --crud x --edulevel other
refuse "bad --edulevel" 'invalid choice' "$P" thing_done --crud c --edulevel high
refuse "bad --observe" 'bad --observe' "$P" thing_done --crud c --edulevel other --observe 'course_viewed'
refuse "observer method exists" 'already has a method course_viewed' "$P" thing_done --crud c --edulevel other \
    --observe '\core\event\course_viewed'
refuse "--objecttable with --observe, no --emit" 'objecttable with --observe needs --emit' "$P" thing_done --crud c \
    --edulevel other --objecttable course --observe '\core\event\user_loggedin'
refuse "event without --crud" 'needs --crud and --edulevel' "$P" thing_done --edulevel other
refuse "--emit without --edulevel" 'needs --crud and --edulevel' "$P" thing_done --crud c --emit \
    --observe '\core\event\user_loggedin'
refuse "--emit-in with --observe" 'drop --observe' "$P" thing_done --crud c --edulevel other --emit-in visits.php \
    --observe '\core\event\user_loggedin'
refuse "--emit-in outside the plugin" 'no such page' "$P" thing_done --crud c --edulevel other --emit-in ../visits.php
refuse "--emit without --observe" 'need --observe' "$P" thing_done --crud c --edulevel other --emit
refuse "--table with --emit" 'drop --emit' "$P" thing_done --crud c --edulevel other --emit --table local_t839ev_x \
    --observe '\core\event\user_loggedin'
refuse "--table without install.xml" 'needs .*db/install.xml' "$P" thing_done --crud c --edulevel other --table local_t839ev_x \
    --observe '\core\event\user_loggedin'
python3 "$E" "$B" thing_done --crud c --edulevel other --observe '\core\event\user_loggedin' --table local_t879tb_log \
    --core "$CORE" >"$T/out" 2>&1 && bad "--table without userid accepted" \
    || { grep -q 'has no userid field' "$T/out" && [ ! -e "$B/classes/event/thing_done.php" ] \
    && ok "--table without userid refused, nothing written" || bad "--table without userid: $(cat "$T/out")"; }
for ev in '\core\event\course_viewed' '\mod_x\event\page_seen'; do
    bsum="$(md5sum "$B/version.php" "$B/db/events.php" "$B/classes/observer.php")"
    python3 "$E" "$B" view_purged --crud d --edulevel other --observe "$ev" --table local_t879tb_ticket \
        --core "$CORE" >"$T/out" 2>&1; rc=$?
    [ "$rc" = 1 ] && grep -q 'never sets relateduserid' "$T/out" && [ "$bsum" = "$(md5sum "$B/version.php" "$B/db/events.php" "$B/classes/observer.php")" ] \
        && ok "--table on $ev (no relateduserid) refused rc 1, nothing written" || bad "--table $ev rc $rc: $(cat "$T/out")"
done
python3 "$E" "$B" seen_purged --observe '\mod_x\event\page_seen' --table local_t879tb_ticket --force \
    --core "$CORE" >"$T/out" 2>"$T/err" && grep -q 'warning: .*never sets relateduserid' "$T/err" \
    && grep -q 'function page_seen(' "$B/classes/observer.php" \
    && ok "--table --force: no relateduserid warns, handler written" || bad "--force: $(cat "$T/out" "$T/err")"
[ ! -e "$P/classes/event/thing_done.php" ] && ok "refusals left no event class" || bad "thing_done.php written"

n=0; lintfail=0
for f in $(find "$T/l" "$T/m" "$T/tb" "$A" "$W" -name '*.php'); do
    n=$((n + 1)); php -l "$f" >/dev/null 2>&1 || { lintfail=1; bad "php -l $f"; }
done
[ "$lintfail" = 0 ] && ok "php -l clean ($n files)"
for p in "$P" "$M" "$B"; do
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker --max-warnings 0 "$p" 2>&1)"; rc=$?
        if grep -qE '\| (ERROR|WARNING) \|' <<<"$out" || [ "$rc" -ne 0 ]; then bad "codechecker ${p#"$T"/} rc $rc: $out"
        else ok "codechecker 0 errors 0 warnings ${p#"$T"/}"; fi
    else
        echo "SKIP codechecker: moodle-plugin-ci absent"
    fi
done

if [ "$LIVE" = 1 ]; then
    out="$("$S/mfixture" add 5.2 "$P" 2>&1)"; rc=$?
    dir="$(sed -n 's/^mfixture: installed local_t839ev at //p' <<<"$out")"
    [ "$rc" -eq 0 ] && [ -d "$dir" ] && installed=1 && ok "live: mfixture add 5.2" || bad "live: mfixture add rc $rc: $out"
    if [ -n "$installed" ]; then
        out="$(nice -n 19 "$S/mtest" phpunit "$dir/tests/observer/item_synced_test.php" 2>&1)"; rc=$?
        [ "$rc" -eq 0 ] && ! grep -qE 'Notices:|Debugging:' <<<"$out" \
            && ok "live: item_synced_test.php passes on 5.2, no notices ($(grep -oE '^Tests: [0-9]+' <<<"$out" | tail -1))" \
            || bad "live: mtest phpunit rc $rc: $(tail -15 <<<"$out")"
        out="$(nice -n 19 "$S/mtest" phpunit "$dir/tests/observer/ticket_closed_test.php" 2>&1)"; rc=$?
        [ "$rc" -eq 0 ] && ! grep -qE 'Notices:|Debugging:' <<<"$out" \
            && ok "live: ticket_closed_test.php (user context, crud d) passes on 5.2 ($(grep -oE '^Tests: [0-9]+' <<<"$out" | tail -1))" \
            || bad "live: mtest observer phpunit rc $rc: $(tail -15 <<<"$out")"
        out="$(nice -n 19 "$S/mtest" phpunit "$dir/tests/event/mark_created_test.php" 2>&1)"; rc=$?
        [ "$rc" -eq 0 ] && ! grep -qE 'Notices:|Debugging:' <<<"$out" \
            && ok "live: mark_created_test.php passes on 5.2, no notices ($(grep -oE '^Tests: [0-9]+' <<<"$out" | tail -1))" \
            || bad "live: mtest event phpunit rc $rc: $(tail -15 <<<"$out")"
        out="$("$S/mfixture" rm 5.2 local_t839ev 2>&1)"; rc=$?
        [ "$rc" -eq 0 ] && [ ! -e "$dir" ] && { installed=""; ok "live: fixture removed"; } || bad "live: mfixture rm rc $rc: $out"
    fi
fi

[ "$fails" -eq 0 ] && echo "PASS event.test.sh" || { echo "FAIL event.test.sh ($fails)"; exit 1; }
