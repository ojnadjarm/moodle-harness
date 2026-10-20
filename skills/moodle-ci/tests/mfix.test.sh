#!/usr/bin/env bash
# mfix on a throwaway git plugin: changed files fixed, unchanged and vendor/ files untouched, rc per spec.
set -uo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)/scripts/mfix"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
P="$T/repo/local/x"; mkdir -p "$P/vendor" && cd "$T/repo" && git init -q
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
fixable="\$a = 1 .'x';"
printf '%s\n$plugin->component = %s;\n' "$hdr" "'local_x'" > "$P/version.php"
printf '%s\n%s\n' "$hdr" "$fixable" > "$P/lib.php"
git add -A && git -c user.email=t@t -c user.name=t commit -qm base
printf '%s\n%s\n' "$hdr" "$fixable" > "$P/new.php"
printf '%s\n%s\n' "$hdr" "$fixable" > "$P/vendor/v.php"
printf '%s\n%s\n' "$hdr" "$fixable" > "$T/repo/out.php"
cp "$P/lib.php" "$T/lib.orig"; cp "$P/vendor/v.php" "$T/v.orig"
bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got $1)"; bad=1; fi; }

MPC_HOME="$T/none" "$M" "$P" >/dev/null 2>&1; check $? 3 "no moodle-plugin-ci is SKIP rc 3"
"$M" "$P" --bogus >/dev/null 2>&1; check $? 2 "unknown option rc 2"
"$M" "$T" >/dev/null 2>&1; check $? 2 "dir without version.php rc 2"

mkdir -p "$T/crash/vendor/bin"; printf '#!/bin/sh\necho "PHP Fatal error: Allowed memory size exhausted"; exit 255\n' > "$T/crash/vendor/bin/phpcs"
chmod +x "$T/crash/vendor/bin/phpcs"; cp "$T/crash/vendor/bin/phpcs" "$T/crash/vendor/bin/phpcbf"
err="$(MPC_HOME="$T/crash" "$M" "$P" 2>&1 >/dev/null)"; check $? 4 "crashing phpcs is rc 4, not a false green"
grep -q 'phpcs failed (rc 255): PHP Fatal error' <<<"$err"; check $? 0 "crash message names phpcs and its output"
printf '#!/bin/sh\nexit 0\n' > "$T/crash/vendor/bin/phpcs"
err="$(MPC_HOME="$T/crash" "$M" "$P" 2>&1 >/dev/null)"; check $? 4 "crashing phpcbf is rc 4"
grep -q 'phpcbf failed (rc 255)' <<<"$err"; check $? 0 "crash message names phpcbf"

[ -x "$HOME/.moodle-plugin-ci/vendor/bin/phpcs" ] || { echo "SKIP real phpcs cases: no moodle-plugin-ci"; exit $bad; }

out="$("$M" "$P")"; check $? 0 "fixable violation fixed, rc 0"
grep -q "^\$a = 1 \. 'x';" "$P/new.php"; check $? 0 "new.php rewritten"
grep -q 'fixed 1 files' <<<"$out"; check $? 0 "prints fixed 1 files ($out)"
grep -q 'errors 1 -> 0' <<<"$out"; check $? 0 "prints errors 1 -> 0"
cmp -s "$P/lib.php" "$T/lib.orig"; check $? 0 "unchanged committed file byte-equal"
cmp -s "$P/vendor/v.php" "$T/v.orig"; check $? 0 "vendor/ file byte-equal"
cmp -s "$T/repo/out.php" "$T/v.orig"; check $? 0 "changed file outside the plugin byte-equal"

printf '$camelCase = 2;\n' >> "$P/new.php"
out="$("$M" "$P")"; check $? 1 "unfixable error rc 1"
grep -q 'new.php:.*camelCase' <<<"$out"; check $? 0 "left error listed"

git add "$P/new.php" && git -c user.email=t@t -c user.name=t commit -qm more; sed -i '$d' "$P/new.php"
out="$("$M" "$P" --base HEAD~1)"; check $? 0 "--base HEAD~1 includes committed new.php, rc 0"
grep -q 'of 1 php' <<<"$out"; check $? 0 "--base lists new.php only"
cmp -s "$P/lib.php" "$T/lib.orig"; check $? 0 "lib.php still byte-equal with --base"

printf '%s\n%s\n' "$hdr" "$fixable" > "$P/ñ.php"
out="$("$M" "$P" --base HEAD~1)"; check $? 0 "non-ASCII name run rc 0"
grep -q "^\$a = 1 \. 'x';" "$P/ñ.php"; check $? 0 "untracked ñ.php fixed"
grep -q 'of 2 php' <<<"$out"; check $? 0 "ñ.php listed ($out)"

out="$("$M" "$P" --all)"; check $? 0 "--all rc 0"
grep -q "^\$a = 1 \. 'x';" "$P/lib.php"; check $? 0 "--all fixes unchanged lib.php"
cmp -s "$P/vendor/v.php" "$T/v.orig"; check $? 0 "--all never touches vendor/"

cp -r "$P" "$T/nogit"; cp "$T/lib.orig" "$T/nogit/lib.php"
"$M" "$T/nogit" >/dev/null; check $? 0 "outside git rc 0"
grep -q "^\$a = 1 \. 'x';" "$T/nogit/lib.php"; check $? 0 "outside git fixes the whole plugin"

mkdir -p "$T/repo/local/ign"; cp "$T/nogit/version.php" "$T/repo/local/ign/"; cp "$T/lib.orig" "$T/repo/local/ign/lib.php"
echo 'local/ign/' > "$T/repo/.gitignore"
out="$("$M" "$T/repo/local/ign")"; check $? 0 "gitignored plugin rc 0"
grep -q 'of 2 php' <<<"$out"; check $? 0 "gitignored plugin checks the whole plugin ($out)"
exit $bad
