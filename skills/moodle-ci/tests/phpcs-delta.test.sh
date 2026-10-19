#!/usr/bin/env bash
# phpcs-delta on a throwaway git repo: pre-existing violations are ignored, added ones reported.
set -uo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)/scripts/phpcs-delta"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q && mkdir -p local/x/classes
hdr="<?php
// This file is part of Moodle - https://moodle.org/
//
// Moodle is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Moodle is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Moodle.  If not, see <https://www.gnu.org/licenses/>.

/**
 * Fixture.
 *
 * @package    local_x
 * @copyright  2026 Test
 * @license    https://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

defined('MOODLE_INTERNAL') || die();
"
printf '%s\n$a = 1 .%s;\n' "$hdr" "'x'" > local/x/lib.php
git add -A && git -c user.email=t@t -c user.name=t commit -qm base
bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got $1)"; bad=1; fi; }
"$D" >/dev/null; check $? 0 "unchanged repo exits 0"
sed -i "s#^defined.*die();#&\n\n// Shift.#" local/x/lib.php
grep -q "^// Shift." local/x/lib.php || { echo "FAIL fixture shift"; exit 1; }
"$D" >/dev/null; check $? 0 "pre-existing violation on a moved line is not new"
printf '$b = 2 .%s;\n' "'y'" >> local/x/lib.php
out="$("$D")"; check $? 1 "added violation exits 1"
check "$(grep -c 'lib.php:' <<<"$out")" 1 "one new violation listed"
exit $bad
