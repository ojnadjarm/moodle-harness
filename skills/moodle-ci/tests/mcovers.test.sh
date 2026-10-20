#!/usr/bin/env bash
# mcovers on throwaway plugins: check per requires, fix both ways, merge-up, idempotence, round trip, helper class, skips.
set -uo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)/scripts/mcovers"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got '$1')"; bad=1; fi; }
mk() { rm -rf "$T/p"; mkdir -p "$T/p/tests"; printf '<?php\n$plugin->component = '"'"'local_x'"'"';\n$plugin->requires = %s;\n' "$1" > "$T/p/version.php"; }
run() { "$M" "$@" "$T/p" > "$T/out" 2>&1; echo $?; }
lint() { php -l "$1" >/dev/null 2>&1 && echo ok || echo bad; }

cat > "$T/old.php" <<'EOF'
<?php
namespace local_x;

/**
 * Tests for foo.
 *
 * @package    local_x
 * @license    http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 * @covers \local_x\foo
 */
final class foo_test extends \advanced_testcase {
    /**
     * Test bar.
     */
    public function test_bar(): void {
        $this->assertTrue(true);
    }
}
EOF

mk 2024100700; cp "$T/old.php" "$T/p/tests/foo_test.php"
check "$(run --check)" 0 "below 5.0: class @covers is clean"

mk 2025041400; cp "$T/old.php" "$T/p/tests/foo_test.php"
rc="$(run --check)"
check "$rc $(grep -c '^tests/foo_test.php:9 FAIL @covers' "$T/out")" "1 1" "5.0: @covers prints file:line FAIL, rc 1"

rc="$(run --fix)"; f="$T/p/tests/foo_test.php"
check "$rc $(grep -c '^use PHPUnit\\Framework\\Attributes\\CoversClass;$' "$f") $(grep -c '^#\[CoversClass(\\local_x\\foo::class)\]$' "$f") $(grep -c '@covers' "$f")" \
    "0 1 1 0" "5.0 fix: use + #[CoversClass(\\x::class)], no @covers left"
check "$(grep -A1 'CoversClass(' "$f" | tail -1 | cut -c1-17)" "final class foo_t" "5.0 fix: attribute sits right above the class"
check "$(lint "$f") $(run --check)" "ok 0" "5.0 fix: php -l clean and check clean"
sum="$(md5sum < "$f")"; run --fix >/dev/null
check "$(md5sum < "$f")" "$sum" "5.0 fix twice: idempotent"

sed -i 's/= 2025041400/= 2024100700/' "$T/p/version.php"
rc="$(run --check)"
check "$rc $(grep -c 'FAIL #\[CoversClass' "$T/out") $(grep -c 'FAIL use PHPUnit' "$T/out")" "1 1 1" "below 5.0: attribute and its use are FAIL"
run --fix >/dev/null
check "$(diff "$T/old.php" "$f" >/dev/null && echo same || echo differs)" same "round trip old -> 5.0 -> below 5.0 is byte-identical"
sum="$(md5sum < "$f")"; run --fix >/dev/null
check "$(md5sum < "$f") $(lint "$f")" "$sum ok" "below 5.0 fix twice: idempotent, php -l clean"

mk 2025041400
cat > "$T/p/tests/merge_test.php" <<'EOF'
<?php
namespace local_x;

use core\context;

/**
 * Merge tests.
 *
 * @package    local_x
 * @coversDefaultClass \local_x\api
 */
final class merge_test extends \advanced_testcase {
    /**
     * Test one.
     *
     * @covers ::run
     * @covers \local_x\helper::go
     */
    public function test_one(): void {
        $this->assertTrue(true);
    }

    /**
     * @covers \local_x\helper
     */
    public function test_two(): void {
        $this->assertTrue(true);
    }
}
EOF
f="$T/p/tests/merge_test.php"; run --fix >/dev/null
check "$(grep -c '^#\[CoversClass(\\local_x\\api::class)\]$' "$f") $(grep -c '^#\[CoversClass(\\local_x\\helper::class)\]$' "$f") $(grep -c '@covers' "$f")" \
    "1 1 0" "5.0 fix: method @covers and @coversDefaultClass merge into deduped class attributes"
check "$(grep -n '^use ' "$f" | cut -d: -f1 | tr '\n' ' ')$(grep -c '^     \* Test one\.$' "$f") $(grep -c '^    /\*\*$' "$f")" "4 5 1 1" \
    "5.0 fix: use after the last import; a tag-only docblock goes, a described one stays"
check "$(lint "$f") $(run --check)" "ok 0" "merge fix: php -l clean, check clean"

mk 2025041400
cat > "$T/p/tests/helper_test.php" <<'EOF'
<?php
defined('MOODLE_INTERNAL') || die();

/**
 * Helper used by the test.
 */
class local_x_helper_stub {
    /**
     * @covers \nothing_here
     */
    public function x(): void {
    }
}

/**
 * Global tests.
 *
 * @covers ::local_x_function
 */
final class local_x_helper_test extends advanced_testcase {
    /**
     * @coversNothing
     */
    public function test_a(): void {
        $this->assertTrue(true);
    }
}
EOF
f="$T/p/tests/helper_test.php"; run --fix >/dev/null
check "$(grep -n '^use PHPUnit\\Framework\\Attributes\\CoversFunction;$\|^/\*\*$' "$f" | head -2 | cut -d: -f1 | tr '\n' ' ')" "4 6 " \
    "helper class first: use goes above the first class docblock"
check "$(grep -B0 -A1 "^#\[CoversFunction('local_x_function')\]$" "$f" | tail -1 | cut -c1-11) $(grep -c '@covers \\nothing_here' "$f") $(grep -c 'CoversNothing' "$f")" \
    "final class 1 0" "helper class first: attribute on the test class only, helper untouched, coversNothing merged away"
check "$(lint "$f")" ok "helper fix: php -l clean"

mk 2024100700
cat > "$T/p/tests/core_test.php" <<'EOF'
<?php
namespace local_x;

use local_x\local\thing;
use PHPUnit\Framework\Attributes\CoversClass;

/**
 * Core style.
 *
 * @package    local_x
 */
#[\PHPUnit\Framework\Attributes\CoversClass(\local_x\api::class)]
#[CoversClass(thing::class)]
#[CoversClass(other::class)]
final class core_test extends \advanced_testcase {
    /**
     * @covers \local_x\api::run
     */
    public function test_a(): void {
        $this->assertTrue(true);
    }
}
EOF
f="$T/p/tests/core_test.php"; run --fix >/dev/null
check "$(grep -c '^ \* @covers \\local_x\\api$' "$f") $(grep -c '^ \* @covers \\local_x\\local\\thing$' "$f") $(grep -c '^ \* @covers \\local_x\\other$' "$f")" \
    "1 1 1" "below 5.0 fix: FQ, imported and namespace-relative names resolve to @covers"
check "$(grep -c 'Covers\(Class\|Nothing\)' "$f") $(grep -c '^     \* @covers \\local_x\\api::run$' "$f") $(lint "$f") $(run --check)" "0 1 ok 0" \
    "below 5.0 fix: attributes and use gone, method @covers kept, php -l clean"

mk 2024100700
cat > "$T/p/tests/bare_test.php" <<'EOF2'
<?php
namespace local_x;

use PHPUnit\Framework\Attributes\CoversClass;

#[CoversClass(foo::class)]
final class bare_test extends \advanced_testcase {
}
EOF2
f="$T/p/tests/bare_test.php"; rc="$(run --check)"
check "$rc $(grep -c '^tests/bare_test.php:6 FAIL #\[CoversClass(foo::class)\]' "$T/out")" "1 1" \
    "below 5.0: attribute on a class without a docblock is FAIL"
run --fix >/dev/null
check "$(grep -c '^ \* @covers \\local_x\\foo$' "$f") $(grep -c 'CoversClass' "$f") $(lint "$f") $(run --check)" "1 0 ok 0" \
    "below 5.0 fix: class without a docblock gets a @covers docblock"

mk 2025041400
cat > "$T/p/tests/dup_test.php" <<'EOF2'
<?php
namespace local_x;

use local_x\local\thing;
use PHPUnit\Framework\Attributes\CoversClass;

/**
 * Dedup tests.
 *
 * @covers \local_x\foo
 * @covers \local_x\local\thing
 */
#[CoversClass(foo::class)]
#[CoversClass(thing::class)]
final class dup_test extends \advanced_testcase {
}
EOF2
f="$T/p/tests/dup_test.php"; run --fix >/dev/null
check "$(grep -c 'CoversClass(.*foo::class)' "$f") $(grep -c '@covers' "$f")" "1 0" \
    "5.0 fix: namespace-relative attribute and FQ @covers of one class give one CoversClass"
check "$(grep -c 'CoversClass(.*thing::class)' "$f") $(lint "$f") $(run --check)" "1 ok 0" \
    "5.0 fix: imported attribute and FQ @covers of one class give one CoversClass"

mk 2025041400; rmdir "$T/p/tests"
rc="$(run --check)"
check "$rc $(grep -c 'SKIP: no tests/ dir' "$T/out")" "3 1" "no tests/ dir: rc 3 named SKIP"
mk 2025041400; sed -i '/requires/d' "$T/p/version.php"
rc="$(run --check)"
check "$rc $(grep -c 'SKIP: no \$plugin->requires' "$T/out")" "3 1" "no requires: rc 3 named SKIP"
check "$("$M" --bogus "$T/p" >/dev/null 2>&1; echo $?)" 2 "unknown option: rc 2"
exit $bad
