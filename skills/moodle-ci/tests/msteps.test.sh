#!/usr/bin/env bash
# msteps against a fixture 5.x tree with a fake docker serving canned `behat -dl` output.
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/msteps"
T="$(realpath "$(mktemp -d)")"; trap 'rm -rf "$T"' EXIT
W="$T/env/www" W2="$T/env2/www"
mkdir -p "$T/bin" "$W/vendor/bin" "$W/public/local/x/tests/behat" "$T/none" "$W2/vendor/bin" "$W2/public"
touch "$W/vendor/bin/phpunit" "$W/config.php" "$W2/vendor/bin/phpunit" "$W2/config.php"
echo '$version  = 2026042004.02;' | tee "$W/public/version.php" > "$W2/public/version.php"

cat > "$T/dl.txt" <<'EOF'
default | Given /^the following "(?P<element_string>(?:[^"]|\\")*)" exist:$/
default | Given I am logged in as :username
default | When /^I am on the "(?<identifier>[^"]*)" "(?<type>[^"]*)" page logged in as "(?<username>[^"]*)"$/
default | Then /^I should see "(?P<text_string>(?:[^"]|\\")*)"$/
default | Given the page title should contain ":title"
default | Given i select edit type :edittype
default | When /^I press "(?P<button_string>(?:[^"]|\\")*)"$/
classic | Given /^the following "(?P<element_string>(?:[^"]|\\")*)" exist:$/
classic | Given I am logged in as :username
EOF
cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
case "\$1" in
    ps) echo fake52-app-1 ;;
    inspect) printf '%s\t/var/www/html\n' "$T" ;;
    exec) case "\$*" in
        *"command -v php"*) exit 0 ;;
        *behat*) echo x >> "$T/dl.count"; [ -n "\${FAKE_NOINIT:-}" ] && exit 3
            head -3 "$T/dl.txt"; [ -n "\${FAKE_SLOW:-}" ] && sleep 0.5; tail -n +4 "$T/dl.txt" ;;
    esac ;;
esac
EOF
chmod +x "$T/bin/docker"

bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got '$1')"; bad=1; fi; }
run() { (cd "$W/public/local/x" && PATH="$T/bin:$PATH" XDG_CACHE_HOME="$T/cache" "$S" "$@" 2>&1; echo "rc=$?"); }
dumps() { wc -l < "$T/dl.count" 2>/dev/null || echo 0; }
h() { printf %s "$1" | sha1sum | cut -c1-8; }
H="$(h "$W")"
C="$T/cache/moodle-harness/steps-2026042004.02-$H.txt"

check "$(run following EXIST)" $'Given /^the following "(?P<element_string>(?:[^"]|\\\\")*)" exist:$/\nrc=0' "grep: case-insensitive, suites deduped"
check "$(dumps):$([ -s "$C" ] && echo cached)" "1:cached" "first run dumps -dl into steps-<version>-<root hash>.txt"
check "$(run page logged as)" $'When /^I am on the "(?<identifier>[^"]*)" "(?<type>[^"]*)" page logged in as "(?<username>[^"]*)"$/\nrc=0' "grep: every word must match"
check "$(dumps)" "1" "second run reuses the cache"
check "$(run nosuchstep)" "rc=1" "no match: rc 1"
touch -d '1 hour ago' "$C"; run press >/dev/null
check "$(dumps)" "2" "version.php newer than cache: dumped again"
echo '$version  = 2026042005.00;' > "$W/public/version.php"; run press >/dev/null
check "$(dumps):$(ls "$T/cache/moodle-harness" | tr '\n' ' ')" "3:steps-2026042004.02-$H.txt steps-2026042005.00-$H.txt " "new version: new cache file"

cat > "$W/public/local/x/tests/behat/ok.feature" <<'EOF'
@local_x @javascript
Feature: ok
  Background:
    Given the following "users" exist:
      | username |
      | s1       |
  Scenario Outline: outline
    When I am on the "C1" "Course" page logged in as "<user>"
    Then I should see "<text>"
    Examples:
      | user | text |
      | s1   | Hi   |
  Scenario: plain
    Given I am logged in as admin
    And the page title should contain "C1: Ants"
    And I select edit type "Expanded"
    """
    Given nothing here is a step
    """
    * I press "Save"
EOF
check "$(run --check "$W/public/local/x/tests/behat/ok.feature")" $'msteps: 7 steps, 0 undefined\nrc=0' "--check green: outline, turnip, docstring"
sed -e 's/I press "Save"/I press the shiny button/' -e 's/I should see "<text>"/I magically see "<text>"/' \
    "$W/public/local/x/tests/behat/ok.feature" > "$T/bad.feature"
check "$(run --check "$T/bad.feature" --env-path "$W")" "msteps: 7 steps, 2 undefined
$T/bad.feature:9: I magically see \"<text>\"
$T/bad.feature:20: I press the shiny button
rc=1" "--check red: lists each undefined line, rc 1"

run press --env-path "$W2" >/dev/null
check "$(dumps):$(ls "$T/cache/moodle-harness" | grep -c '^steps-2026042004.02-')" "4:2" "two env roots on one version: two caches"
check "$([ -s "$T/cache/moodle-harness/steps-2026042004.02-$(h "$W2").txt" ] && echo ok)" "ok" "second root cached under its own hash"
touch "$T/cache/moodle-harness/steps-2026042004.02.txt"; run press >/dev/null
check "$(ls "$T/cache/moodle-harness" | grep -c '^steps-[0-9.]*\.txt$'):$(ls "$T/cache/moodle-harness" | wc -l)" "0:3" "legacy unhashed cache removed, hashed caches kept"
rm -rf "$T/cache"
(FAKE_SLOW=1 run press > "$T/c1") & sleep 0.2; (FAKE_SLOW=1 run press > "$T/c2") & wait
check "$(tail -1 "$T/c1"):$(tail -1 "$T/c2"):$(ls "$T/cache/moodle-harness" | wc -l):$(cmp -s "$T/dl.txt" "$T/cache/moodle-harness/steps-2026042005.00-$H.txt" && echo valid)" "rc=0:rc=0:1:valid" "concurrent first runs: one valid cache, no temp left"
check "$(run --check "$W/public/local/x/tests/behat/ok.feature" press)" $'msteps: --check takes no search words\nrc=2' "--check plus words: usage rc 2"

rm -rf "$T/cache"
check "$(FAKE_NOINIT=1 run press | tail -1):$(ls "$T/cache/moodle-harness" 2>/dev/null | wc -l)" "rc=3:0" "behat not initialised: rc 3, no cache left"
check "$(run press --env-path "$T/none")" $'msteps: no Moodle root (vendor/) above '"$T/none"$'\nrc=3' "outside a Moodle tree: rc 3"
exit $bad
