#!/usr/bin/env bash
# Drive message.py on mktemp plugins: db/messages.php create and merge, lang, notifier send method, redirectMessages test, bump, refusals, mlang, php -l, codechecker.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
D="$(cd "$(dirname "$0")/.." && pwd)"
M="$D/message.py"; G="$D/generate.py"; S="$D/../moodle-ci/scripts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
version() { sed -n 's/^\$plugin->version = \([0-9]*\);/\1/p' "$1/version.php"; }
providers() {
    php -r "define('MOODLE_INTERNAL', 1); define('MESSAGE_PERMITTED', 1); define('MESSAGE_DEFAULT_ENABLED', 2);
        include '$1'; echo json_encode(\$messageproviders);"
}

render() {
    mkdir -p "$T/$1"
    printf 'component: %s\nrequires: "%s"\ncopyright: 2026 onwards, Example Author <author@example.com>\n' "$2" "$1" > "$T/$1/recipe.yaml"
    python3 "$G" --target-dir "$T/$1" "$T/$1/recipe.yaml" >/dev/null 2>"$T/err" || bad "$2 skeleton: $(cat "$T/err")"
}

render 4.5 local_demo; P="$T/4.5/demo"
render 4.1 mod_demo; PM="$T/4.1/demo"
python3 "$D/access.py" "$P" receive --type read --context system >/dev/null 2>"$T/err" || bad "access.py: $(cat "$T/err")"
v0="$(version "$P")"
python3 "$M" "$P" grade_released --capability receive >"$T/out" 2>&1 && ok "provider renders" || bad "rc: $(cat "$T/out")"
v1="$(version "$P")"; [ "$v1" -gt "$v0" ] && ok "version bumped $v0 -> $v1" || bad "version not bumped: $v1"
! grep -q 'warning' "$T/out" && ok "defined capability: no warning" || bad "warning: $(cat "$T/out")"

mp="$P/db/messages.php"; cls="$P/classes/local/notifier.php"; tst="$P/tests/local/notifier_test.php"; lang="$P/lang/en/local_demo.php"
[ "$(providers "$mp")" = '{"grade_released":{"capability":"local\/demo:receive","defaults":{"popup":3,"email":3}}}' ] \
    && ok "db/messages.php: capability + popup,email defaults" || bad "messages.php: $(providers "$mp")"
grep -q "^\$string\['messageprovider:grade_released'\] = 'Grade released';" "$lang" && ok "lang string added" || bad "lang: $(cat "$lang")"
grep -q 'public static function send_grade_released(\\stdClass \$user, string \$subject, string \$text, \\moodle_url \$url) {' "$cls" \
    && grep -q '\$message = new \\core\\message\\message();' "$cls" && grep -q "\$message->component = 'local_demo';" "$cls" \
    && grep -q "\$message->name = 'grade_released';" "$cls" && grep -q '\$message->userfrom = \\core_user::get_noreply_user();' "$cls" \
    && grep -q '\$message->contexturl = \$url->out(false);' "$cls" && grep -q '\$message->smallmessage = \$subject;' "$cls" \
    && grep -q 'return message_send(\$message);' "$cls" && ok "notifier: core message from noreply with contexturl + smallmessage" \
    || bad "notifier: $(cat "$cls")"
grep -q '\$sink = \$this->redirectMessages();' "$tst" && grep -q '\$this->assertCount(1, \$messages);' "$tst" \
    && grep -q '\$this->assertEquals(\$user->id, \$messages\[0\]->useridto);' "$tst" \
    && grep -q "\$this->assertEquals('grade_released', \$messages\[0\]->eventtype);" "$tst" \
    && grep -q "assign_capability('local/demo:receive', CAP_ALLOW" "$tst" \
    && ok "test: redirectMessages sink, 1 message to the user, capability granted" || bad "test: $(cat "$tst")"

python3 "$M" "$P" reminder --defaults popup >"$T/out" 2>&1 || bad "second rc: $(cat "$T/out")"
[ "$(providers "$mp")" = '{"grade_released":{"capability":"local\/demo:receive","defaults":{"popup":3,"email":3}},"reminder":{"defaults":{"popup":3}}}' ] \
    && [ "$(grep -c '^\$messageproviders = ' "$mp")" = 1 ] && ok "merge keeps the first provider, --defaults popup" || bad "merge: $(providers "$mp")"
[ "$(grep -c 'public static function send_' "$cls")" = 2 ] && [ "$(grep -c '^class notifier' "$cls")" = 1 ] \
    && [ "$(grep -c 'public function test_send_' "$tst")" = 2 ] && ! grep -A6 'test_send_reminder' "$tst" | grep -q assign_capability \
    && ok "second provider adds a method to notifier and its test" || bad "second methods: $(cat "$cls" "$tst")"
ids="$(sed -n "s/^\$string\['\([^']*\)'\].*/\1/p" "$lang")"
[ "$ids" = "$(LC_ALL=C sort <<<"$ids")" ] && ok "lang strings in sorted order" || bad "lang order: $ids"

before="$(md5sum "$mp" "$cls" "$tst" "$lang" "$P/version.php")"
python3 "$M" "$P" reminder >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "already exists" "$T/out" && [ "$before" = "$(md5sum "$mp" "$cls" "$tst" "$lang" "$P/version.php")" ] \
    && ok "rerun refused rc 1 'exists', nothing written" || bad "rerun rc=$rc: $(cat "$T/out")"
for c in "Bad-Name|x|bad provider name" "fine|--defaults=popup,sms|bad --defaults" "fine|--defaults=|bad --defaults" \
    "fine|--capability=Bad:Cap|bad --capability"; do
    IFS='|' read -r n opt msg <<<"$c"
    python3 "$M" "$P" "$n" $([ "$opt" = x ] || echo "$opt") >"$T/out" 2>&1; rc=$?
    [ "$rc" = 1 ] && grep -q "$msg" "$T/out" && [ "$before" = "$(md5sum "$mp" "$cls" "$tst" "$lang" "$P/version.php")" ] \
        && ok "$n $opt refused rc 1" || bad "$n $opt rc=$rc: $(cat "$T/out")"
done

python3 "$M" "$PM" submitted --capability receive >"$T/out" 2>&1 && grep -q 'warning: mod/demo:receive is not defined' "$T/out" \
    && grep -q "^\$string\['messageprovider:submitted'\]" "$PM/lang/en/demo.php" \
    && grep -q "'capability' => 'mod/demo:receive'," "$PM/db/messages.php" \
    && ok "mod_: lang/en/demo.php, mod/demo:receive, undefined capability warned" || bad "mod_: $(cat "$T/out")"
mkdir -p "$T/arr/db" "$T/arr/lang/en"; cp "$PM/version.php" "$T/arr/"; cp "$PM/lang/en/demo.php" "$T/arr/lang/en/"
printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\$messageproviders = array(\n    'old' => array('defaults' => array('popup' => MESSAGE_PERMITTED)),\n);\n" > "$T/arr/db/messages.php"
python3 "$M" "$T/arr" fresh >/dev/null 2>"$T/err" && php -l "$T/arr/db/messages.php" >/dev/null \
    && [ "$(providers "$T/arr/db/messages.php")" = '{"old":{"defaults":{"popup":1}},"fresh":{"defaults":{"popup":3,"email":3}}}' ] \
    && ok "merge into array() keeps old provider" || bad "array() merge: $(cat "$T/err" "$T/arr/db/messages.php")"

lintfail=0; n=0
for f in "$mp" "$cls" "$tst" "$lang" "$PM"/db/messages.php "$PM"/classes/local/*.php "$PM"/tests/local/*.php; do
    n=$((n + 1)); php -l "$f" >/dev/null 2>&1 || { lintfail=1; bad "php -l $f: $(php -l "$f" 2>&1)"; }
done
[ "$lintfail" = 0 ] && ok "php -l clean ($n files)"
for p in "$P" "$PM"; do
    out="$("$S/mlang" "$p" 2>&1)"; rc=$?
    [ "$rc" = 0 ] && grep -q ' 0 missing' <<<"$out" && ok "mlang ${p#"$T"/}: 0 missing" || bad "mlang rc=$rc: $out"
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker --max-warnings 0 "$p" 2>&1)"; rc=$?
        [ "$rc" = 0 ] && ! grep -q '| \(ERROR\|WARNING\) |' <<<"$out" && ok "codechecker 0/0 ${p#"$T"/}" || bad "$p codechecker rc=$rc"
    else
        echo "SKIP codechecker: moodle-plugin-ci absent"
    fi
done

[ "$fails" -eq 0 ] && echo "PASS message.test.sh" || { echo "FAIL message.test.sh ($fails)"; exit 1; }
