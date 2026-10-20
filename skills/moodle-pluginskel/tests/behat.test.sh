#!/usr/bin/env bash
# behat.py on rendered mod_/block_/local_/report_/tool_ plugins in a fake 5.2 tree; msteps --check against the fixture step dump.
set -uo pipefail
K="$(cd "$(dirname "$0")/.." && pwd)"
B="$K/behat.py"; G="$K/generate.py"; M="$K/../moodle-ci/scripts/msteps"; DL="$K/tests/fixtures/steps-5.2.txt"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
W="$T/env/www"
mkdir -p "$T/bin" "$W/vendor/bin" "$W/public/mod" "$W/public/blocks" "$W/public/local"
touch "$W/vendor/bin/phpunit" "$W/config.php"
echo '$version  = 2026042004.02;' > "$W/public/version.php"
cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
case "\$1" in
    ps) echo fake52-app-1 ;;
    inspect) printf '%s\t/var/www/html\n' "$W" ;;
    exec) case "\$*" in *"command -v php"*) exit 0 ;; *behat*) cat "$DL" ;; esac ;;
esac
EOF
chmod +x "$T/bin/docker"
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
steps() { PATH="$T/bin:$PATH" XDG_CACHE_HOME="$T/cache" "$M" --check "$1" 2>&1; }
undefined0() { local out; out="$(steps "$1")" && grep -q ', 0 undefined$' <<<"$out" \
    && ok "$2: $(tail -1 <<<"$out" | sed 's/^msteps: //') against the fixture" || bad "$2: $out"; }

[ "$(grep -c '^default | ' "$DL")" -ge 100 ] && ok "fixture holds $(grep -c '^default | ' "$DL") step definitions" || bad "fixture"

for type in mod block; do
    dir="$W/public/$([ "$type" = mod ] && echo mod || echo blocks)"
    printf 'component: %s_t798\nname: T798 %s\ncopyright: 2026 onwards, Example Author <author@example.com>\n' \
        "$type" "$type" > "$T/$type.yaml"
    python3 -B "$G" --target-dir "$dir" "$T/$type.yaml" >/dev/null || { bad "$type skeleton renders"; continue; }
    p="$dir/t798"; f="$p/tests/behat/basic_use.feature"
    out="$(python3 -B "$B" "$p" basic_use 2>&1)" && ok "$type behat.py rc 0" || { bad "$type behat.py: $out"; continue; }
    grep -q "msteps --check $f" <<<"$out" && ok "$type prints the msteps --check hint" || bad "$type hint"
    head -1 "$f" | grep -qx "@${type}_t798" && ok "$type feature tagged @${type}_t798" || bad "$type tag: $(head -1 "$f")"
    undefined0 "$f" "$type feature"
    if [ "$type" = mod ]; then
        grep -q 'the following "activities" exist:' "$f" && grep -q '"t798 activity" page logged in as "student1"' "$f" \
            && ok "mod Background adds the activity, scenario opens its page" || bad "mod feature body"
        g="$p/tests/generator/lib.php"
        grep -q '^class mod_t798_generator extends testing_module_generator {' "$g" \
            && php -l "$g" >/dev/null 2>&1 && ok "mod generator written, php -l clean" || bad "mod generator"
        if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
            cc="$(nice -n 19 "$MPC" codechecker "$p" 2>&1)"; rc=$?
            if grep -q '| ERROR |' <<<"$cc" || [ "$rc" -ne 0 ]; then bad "mod codechecker rc=$rc"; grep -B2 '| ERROR |' <<<"$cc" | head -20
            else ok "mod codechecker 0 errors"; fi
        else
            echo "SKIP mod codechecker: moodle-plugin-ci absent"
        fi
    else
        grep -q 'the following "blocks" exist:' "$f" && grep -q 'And I turn editing mode on' "$f" \
            && [ ! -e "$p/tests/generator" ] && ok "block Background adds the block, no generator" || bad "block feature body"
        grep -qx '    Then I should see "T798 block" in the "T798 block" "block"' "$f" \
            && ok "block scenario checks the text inside the block region" || bad "block see in region: $(grep 'should see' "$f")"
    fi
done

p="$W/public/mod/t798"; g="$p/tests/generator/lib.php"; sum="$(md5sum < "$g")"
cat > "$T/recipe.yaml" <<'EOF'
title: Custom view
course: {fullname: Biology 101, shortname: BIO}
users:
  - {username: manager1, role: manager}
  - {username: guest1}
instance: The "quoted" activity
scenarios:
  - name: Manager sees two texts
    user: manager1
    see: [The "quoted" activity, Biology 101]
  - name: Editing view
    user: manager1
    editing: true
EOF
out="$(python3 -B "$B" "$p" custom --recipe "$T/recipe.yaml" 2>&1)" && ok "recipe render rc 0" || bad "recipe render: $out"
f="$p/tests/behat/custom.feature"
grep -q 'And I should see "Biology 101"' "$f" && grep -q 'page logged in as "manager1"' "$f" \
    && ! grep -q 'guest1 *| BIO' "$f" && ok "recipe: users, unenrolled user, two see lines" || bad "recipe body"
undefined0 "$f" "recipe feature (quotes, editing)"
grep -q "kept $g" <<<"$out" && [ "$(md5sum < "$g")" = "$sum" ] && ok "existing generator kept unchanged" || bad "generator overwritten"

sed 's/Then I should see/Then I magically see/' "$f" > "$p/tests/behat/broken.feature"
steps "$p/tests/behat/broken.feature" >/dev/null && bad "negative control: invented step passed" \
    || ok "negative control: an invented step is reported undefined"

sum="$(md5sum < "$f")"
python3 -B "$B" "$p" custom >/dev/null 2>&1 && bad "existing feature overwritten" \
    || { [ "$(md5sum < "$f")" = "$sum" ] && ok "refuses an existing feature, file unchanged" || bad "feature changed"; }
python3 -B "$B" "$T/bin" x >/dev/null 2>&1 && bad "non-plugin dir accepted" || ok "refuses a dir without version.php"
python3 -B "$B" "$p" "Bad-Name" >/dev/null 2>&1 && bad "bad feature name accepted" || ok "refuses a bad feature name"

pb="$W/public/blocks/t798"
run() { printf '%s\n' "$2" > "$T/$1.yaml"; python3 -B "$B" "$3" "$1" --recipe "$T/$1.yaml" 2>&1; }
refused() { local out; out="$(run "$1" "$2" "$3")" && bad "$4 accepted" || { grep -q '^error: ' <<<"$out" && ! grep -q Traceback <<<"$out" \
    && [ ! -e "$3/tests/behat/$1.feature" ] && ok "refuses $4: ${out#error: }" || bad "$4: $out"; }; }
run seestr $'scenarios:\n  - {name: One text, see: Hello}' "$p" >/dev/null && f="$p/tests/behat/seestr.feature" \
    && grep -qx '    Then I should see "Hello"' "$f" && ! grep -q 'see "H"' "$f" && ok "see as one text gives one step" || bad "see string"
refused norole $'users:\n  - {username: u1}' "$pb" "a block recipe with no enrolled user"
run student $'users:\n  - {username: s1, role: student}' "$pb" >/dev/null && f="$pb/tests/behat/student.feature" \
    && grep -q 'logged in as "s1"' "$f" && ! grep -q 'editing mode' "$f" && ok "block student scenario keeps editing off" || bad "student editing"
run bsee $'scenarios:\n  - {name: Content, user: teacher1, see: [Hello there, T798 block]}' "$pb" >/dev/null \
    && f="$pb/tests/behat/bsee.feature" && grep -qx '    Then I should see "Hello there" in the "T798 block" "block"' "$f" \
    && grep -qx '    And I should see "T798 block" in the "T798 block" "block"' "$f" \
    && ok "block see: texts are asserted inside the block" && undefined0 "$f" "block see feature" || bad "block see: texts"
refused stuedit $'users:\n  - {username: s1, role: student}\nscenarios:\n  - {name: E, user: s1, editing: true}' "$pb" "editing on for a student"
run pipe $'course: {fullname: A | B, shortname: AB}\ninstance: X | Y' "$p" >/dev/null && f="$p/tests/behat/pipe.feature" \
    && grep -q '| A \\| B ' "$f" && grep -q '| X \\| Y ' "$f" && ok "| escaped in table cells" && undefined0 "$f" "pipe feature" || bad "pipe escape"
refused tplvar 'instance: A {{name}}' "$p" "a {{var}} in a recipe value"
refused seebool $'scenarios:\n  - {name: B, see: true}' "$p" "a bool see"
refused seefalse $'scenarios:\n  - {name: B, see: false}' "$p" "a false see"
refused seelistbool $'scenarios:\n  - {name: B, see: [Hello, false]}' "$p" "a bool in a see list"
refused editstr $'users:\n  - {username: m1, role: manager}\nscenarios:\n  - {name: E, user: m1, editing: "no"}' "$p" "a text editing"
refused nouser $'users:\n  - {role: student}' "$p" "a user without username"
refused noname $'scenarios:\n  - {user: student1}' "$p" "a scenario without name"

printf 'component: local_t880\nname: T880 desk\ncopyright: 2026 onwards, Example Author <author@example.com>\n' > "$T/local.yaml"
python3 -B "$G" --target-dir "$W/public/local" "$T/local.yaml" >/dev/null || bad "local skeleton renders"
pl="$W/public/local/t880"
out="$(run lpage $'page: /local/t880/view.php\nheading: Ticket desk\nas: student' "$pl")" && f="$pl/tests/behat/lpage.feature" \
    && grep -qx '    Given I log in as "student1"' "$f" && grep -qx '    And I visit "/local/t880/view.php"' "$f" \
    && grep -qx '    Then I should see "Ticket desk"' "$f" && ! grep -q ' page logged in as ' "$f" && ! grep -q warning <<<"$out" \
    && ok "page: as student logs in, visits the page, sees the heading" && undefined0 "$f" "page feature" || bad "page feature: $out"
run ladmin $'page: /local/t880/view.php' "$pl" >/dev/null && f="$pl/tests/behat/ladmin.feature" \
    && grep -qx '    Given I log in as "admin"' "$f" && grep -qx '    Then I should see "T880 desk"' "$f" \
    && ok "page: defaults to admin and the plugin name as heading" && undefined0 "$f" "page admin feature" || bad "page defaults"
run lteach $'page: /local/t880/view.php\nas: teacher' "$pl" >/dev/null && f="$pl/tests/behat/lteach.feature" \
    && grep -qx '    Given I log in as "teacher1"' "$f" && ok "page: as teacher picks the editing teacher" || bad "page teacher"
run lblock $'page: /blocks/t798/manage.php' "$pb" >/dev/null && f="$pb/tests/behat/lblock.feature" \
    && grep -q 'I visit "/blocks/t798/manage.php"' "$f" && ! grep -q 'editing mode' "$f" \
    && grep -qx '    Then I should see "T798 block"' "$f" && ok "page: on a block keeps editing off, plain see" && undefined0 "$f" "block page feature" || bad "block page"
out="$(run lnopage $'title: No page' "$pl")" && grep -q '^warning: the feature never opens a plugin page' <<<"$out" \
    && ok "local_ without page: warns" || bad "local no-page warning: $out"
out="$(run mnopage $'title: No page' "$p")" && ! grep -q warning <<<"$out" && ok "mod_ without page: no warning" || bad "mod warning: $out"
refused lrel 'page: local/t880/view.php' "$pl" "a page: not starting with /"
refused lquote $'page: \'/local/t880/a"b.php\'' "$pl" "a page: with a quote"
refused las $'page: /local/t880/view.php\nas: guest' "$pl" "an unknown as:"
refused lnostu $'users:\n  - {username: t1, role: editingteacher}\npage: /local/t880/view.php\nas: student' "$pl" "as: student with no student"
refused ledit $'page: /local/t880/view.php\nscenarios:\n  - {name: E, user: admin, editing: true}' "$pl" "editing with page:"

out="$(run mact $'page: activity\nheading: Act heading\nas: teacher' "$p")" && f="$p/tests/behat/mact.feature" \
    && grep -qx '    When I am on the "Test T798 mod" "t798 activity" page logged in as "teacher1"' "$f" \
    && grep -qx '    Then I should see "Act heading"' "$f" && ! grep -q 'I visit' "$f" && ! grep -q warning <<<"$out" \
    && ok "page: activity opens the activity page as the teacher" && undefined0 "$f" "page: activity feature" || bad "page: activity: $out"
run mpage $'page: /mod/t798/report.php\nheading: Report' "$p" >/dev/null && f="$p/tests/behat/mpage.feature" \
    && grep -q '"t798 activity" page logged in as "student1"' "$f" && grep -qx '    Then I should see "Test T798 mod"' "$f" \
    && grep -qx '    And I visit "/mod/t798/report.php"' "$f" && grep -qx '    Then I should see "Report"' "$f" \
    && [ "$(grep -c '^  Scenario:' "$f")" -eq 3 ] && ok "mod_ page: keeps the activity scenario next to the page scenario" \
    && undefined0 "$f" "mod page feature" || bad "mod page: keeps activity"
out="$(run hnull $'page: /local/t880/view.php\nheading: null' "$pl")"; [ $? -eq 1 ] && grep -qx 'error: recipe heading: must be text' <<<"$out" \
    && ok "heading: null gives rc 1, heading: must be text" || bad "heading: null: $out"
refused htilde $'page: /local/t880/view.php\nheading: ~' "$pl" "heading: ~"
refused hlist $'page: /local/t880/view.php\nheading: [a, b]' "$pl" "a list heading:"
refused lact 'page: activity' "$pl" "page: activity on a local_ plugin"
refused aslist $'page: /local/t880/view.php\nas: [admin]' "$pl" "a list as: [admin] (was a TypeError)"
refused asdict $'page: /local/t880/view.php\nas: {a: b}' "$pl" "a mapping as:"
out="$(run lhead $'heading: Lost\nas: student' "$pl")" && grep -q '^warning: heading: is ignored without page:' <<<"$out" \
    && grep -q '^warning: as: is ignored without page:' <<<"$out" && ok "heading/as without page: warn" || bad "heading/as warning: $out"
out="$(run lmap '[a, b]' "$pl")"; grep -q 'page, heading, as, scenarios' <<<"$out" && ok "mapping error lists all keys" || bad "mapping keys: $out"

printf 'component: report_t1021\nname: T1021 visits\ncopyright: 2026 onwards, Example Author <author@example.com>\n' > "$T/report.yaml"
python3 -B "$G" --target-dir "$W/public/report" "$T/report.yaml" >/dev/null || bad "report skeleton renders"
pr="$W/public/report/t1021"; c="$pr/tests/behat/behat_report_t1021.php"
cr=$'copyright: 2026 onwards, Example Author <author@example.com>\n'
out="$(run rvisits "${cr}page: {path: report/t1021/visits.php, param: id, instance: course, name: Visits}"$'\nas: teacher' "$pr")" \
    && f="$pr/tests/behat/rvisits.feature" && grep -qx "$c" <<<"$out" \
    && grep -qx '    When I am on the "C1" "report_t1021 > Visits" page logged in as "teacher1"' "$f" \
    && grep -qx '    Then I should see "T1021 visits"' "$f" && ! grep -q 'I visit' "$f" \
    && ok "page: {path, param, instance: course} opens the C1 page through the component resolver" \
    && undefined0 "$f" "resolver page feature" || bad "resolver page: $out"
grep -q 'protected function resolve_page_instance_url(string $page, string $identifier): moodle_url {' "$c" \
    && grep -qx "            case 'visits':" "$c" && grep -q "^class behat_report_t1021 extends behat_base {" "$c" \
    && grep -qF "new moodle_url('/report/t1021/visits.php', ['id' => \$this->get_course_id(\$identifier)]);" "$c" \
    && grep -qF "require_once(__DIR__ . '/../../../../lib/behat/behat_base.php');" "$c" && php -l "$c" >/dev/null 2>&1 \
    && ok "behat_report_t1021.php: resolve_page_instance_url maps the course to visits.php?id=, php -l clean" || bad "resolver context: $(cat "$c")"
if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
    cc="$(nice -n 19 "$MPC" codechecker "$pr" 2>&1)"; rc=$?
    if grep -q '| ERROR |\|| WARNING |' <<<"$cc" || [ "$rc" -ne 0 ]; then bad "report resolver codechecker rc=$rc"; grep -B2 '| ERROR |\|| WARNING |' <<<"$cc" | head -20
    else ok "report resolver codechecker 0 errors, 0 warnings"; fi
else
    echo "SKIP report resolver codechecker: moodle-plugin-ci absent"
fi
sum="$(md5sum < "$c")"
out="$(run rkeep "page: {path: /report/t1021/visits.php, name: Visits}"$'\ncourse: {fullname: Biology, shortname: BIO}' "$pr")" \
    && grep -qx "kept $c" <<<"$out" && [ "$(md5sum < "$c")" = "$sum" ] \
    && grep -q '"BIO" "report_t1021 > Visits" page logged in as "admin"' "$pr/tests/behat/rkeep.feature" \
    && ok "existing resolver with the page kept unchanged; course shortname BIO is the identifier" || bad "resolver keep: $out"
out="$(run rindex 'page: {path: report/t1021/index.php, instance: course}' "$pr")" && f="$pr/tests/behat/rindex.feature" \
    && grep -q "^warning: kept $c; add case 'index' to its resolve_page_instance_url()" <<<"$out" && [ "$(md5sum < "$c")" = "$sum" ] \
    && grep -q '"C1" "report_t1021 > Index" page' "$f" && ok "page name defaults to the script stem; a missing case warns, file unchanged" \
    || bad "resolver default name: $out"
out="$(run mres "${cr}page: {path: mod/t798/report.php, param: courseid, name: Course report}" "$p")" && f="$p/tests/behat/mres.feature" \
    && grep -q '"Test T798 mod" "t798 activity" page logged in as "student1"' "$f" \
    && grep -qx '    When I am on the "C1" "mod_t798 > Course report" page logged in as "admin"' "$f" \
    && grep -qx "            case 'course report':" "$p/tests/behat/behat_mod_t798.php" \
    && grep -qF "['courseid' => " "$p/tests/behat/behat_mod_t798.php" && grep -q "kept $g" <<<"$out" \
    && ok "mod_ resolver page: activity scenario kept, courseid param, generator kept" && undefined0 "$f" "mod resolver feature" || bad "mod resolver: $out"
printf 'component: tool_t1021\nname: T1021 tool\ncopyright: 2026 onwards, Example Author <author@example.com>\n' > "$T/tool.yaml"
mkdir -p "$W/public/admin/tool" && python3 -B "$G" --target-dir "$W/public/admin/tool" "$T/tool.yaml" >/dev/null || bad "tool skeleton renders"
pt="$W/public/admin/tool/t1021"
run tres "${cr}page: {path: admin/tool/t1021/index.php}" "$pt" >/dev/null \
    && grep -qF "require_once(__DIR__ . '/../../../../../lib/behat/behat_base.php');" "$pt/tests/behat/behat_tool_t1021.php" \
    && php -l "$pt/tests/behat/behat_tool_t1021.php" >/dev/null 2>&1 && ok "tool_ resolver reaches lib/ five levels up" || bad "tool resolver depth"
run bres 'page: {path: blocks/t798/manage.php}' "$pb" >/dev/null && f="$pb/tests/behat/bres.feature" \
    && ! grep -q 'editing mode' "$f" && grep -qx '    Then I should see "T798 block"' "$f" \
    && ok "block resolver page keeps editing off, plain see" && undefined0 "$f" "block resolver feature" || bad "block resolver"
refused rinst 'page: {path: report/t1021/index.php, instance: activity}' "$pr" "page.instance: activity"
refused rkey 'page: {path: report/t1021/index.php, url: x}' "$pr" "an unknown page: key"
refused rdots 'page: {path: report/../x.php}' "$pr" "a page.path with .."
refused rnopath 'page: {name: Visits}' "$pr" "a page: mapping without path"
refused rname $'page: {path: report/t1021/index.php, name: \'A > B\'}' "$pr" "a page.name with >"
refused rparam 'page: {path: report/t1021/index.php, param: 1d}' "$pr" "a bad page.param"
refused redit $'page: {path: report/t1021/index.php}\nscenarios:\n  - {name: E, user: admin, editing: true}' "$pr" "editing with a resolver page:"

[ "$fails" -eq 0 ] && echo "PASS behat.test.sh" || echo "FAIL behat.test.sh ($fails)"
exit $((fails > 0))
