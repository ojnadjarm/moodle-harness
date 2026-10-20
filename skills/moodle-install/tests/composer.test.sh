#!/usr/bin/env bash
# Composer selftest: fixture HOME, fake docker/git/curl/php, no network; asserts composer install runs whenever vendor/bin/phpunit is missing and only a working composer.phar is kept.
set -u
S="$(cd "$(dirname "$0")/.." && pwd)/install.sh"
FX="$(mktemp -d)"; trap 'rm -rf "$FX"' EXIT
mkdir -p "$FX/bin" "$FX/moodle-envs/"{4.5,vass/www} "$FX/src/vendor/bin" "$FX/app"
touch "$FX/src/version.php" "$FX/src/vendor/bin/phpunit"
cat > "$FX/bin/docker" <<'F'
#!/usr/bin/env bash
a="$*"; echo "${a//$'\n'/ }" >> "$FAKE_OUT/docker.log"
case "$*" in *psql*) echo 0 ;; *"exec -T app sh -c"*) cd "$FAKE_OUT/app" && exec sh -c "${@: -1}" ;; esac
F
cat > "$FX/bin/curl" <<'F'
#!/usr/bin/env bash
out="${@: -2:1}"; echo "$*" >> "$FAKE_OUT/curl.log"
case "$(cat "$FAKE_OUT/curl.mode")" in good) echo GOODPHAR > "$out" ;; fail) echo partial > "$out"; exit 18 ;; esac
F
cat > "$FX/bin/php" <<'F'
#!/usr/bin/env bash
case "$2" in --version) grep -qx GOODPHAR "$1" 2>/dev/null ;; install) echo "install $1" >> "$FAKE_OUT/php.log" ;; esac
F
cat > "$FX/bin/git" <<'F'
#!/usr/bin/env bash
mkdir -p "${@: -1}" && touch "${@: -1}/version.php"
F
chmod +x "$FX/bin/"*
box=(env PATH="$FX/bin:$PATH" FAKE_OUT="$FX" HOME="$FX" MOODLE_ENVS="$FX/moodle-envs" HARNESS_CONFIG="$FX/none"
    MOODLE_DB_PASSWORD=fixture MOODLE_ADMIN_PASSWORD=fixture
    bwrap --unshare-net --ro-bind / / --dev /dev --proc /proc --tmpfs /run --bind "$FX" "$FX")
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
run() { : > "$FX/docker.log"; : > "$FX/curl.log"; : > "$FX/php.log"; "${box[@]}" "$S" "$@" > "$FX/out" 2>&1; rc=$?; }
phar() { rm -f "$FX/app/"*; echo good > "$FX/curl.mode"; [ -z "$1" ] || echo "$1" > "$FX/app/composer.phar"; }
composed() { grep -q "exec -T app .*composer.phar install --no-interaction" "$FX/docker.log"; }

check "selftest: docker is the fake" '[ "$("${box[@]}" bash -c "command -v docker")" = "$FX/bin/docker" ]'
check "selftest: sandbox has no network" '! "${box[@]}" python3 -c "import socket; socket.create_connection((\"1.1.1.1\", 443), 3)" 2>/dev/null'

phar ""
run 5.3 --new-name t755a
check "fresh env without --phpunit runs composer install" '[ "$rc" = 0 ] && composed'
check "no phpunit init without --phpunit" '! grep -q "phpunit/cli/init.php" "$FX/docker.log"'
run 5.0 --new-name t755b --phpunit
check "fresh env with --phpunit runs composer install first" '[ "$rc" = 0 ] && composed &&
    [ "$(grep -n "composer.phar install" "$FX/docker.log" | cut -d: -f1)" -lt "$(grep -n "phpunit/cli/init.php" "$FX/docker.log" | cut -d: -f1)" ]'
phar truncated
run 5.3 --new-name t801a
check "truncated composer.phar is re-downloaded" '[ "$rc" = 0 ] && grep -qx GOODPHAR "$FX/app/composer.phar" &&
    [ ! -e "$FX/app/composer.phar.tmp" ] && grep -q "install composer.phar" "$FX/php.log"'
phar GOODPHAR
run 5.3 --new-name t801b
check "working composer.phar is kept, no download" '[ "$rc" = 0 ] && [ ! -s "$FX/curl.log" ] && grep -q "install composer.phar" "$FX/php.log"'
phar ""; echo fail > "$FX/curl.mode"
run 5.3 --new-name t801c
check "failed download leaves no composer.phar" '[ "$rc" != 0 ] && [ ! -e "$FX/app/composer.phar" ] &&
    [ ! -e "$FX/app/composer.phar.tmp" ] && [ ! -s "$FX/php.log" ]'
phar GOODPHAR
run 5.2 --new-name t755c --src "$FX/src"
check "existing vendor/bin/phpunit skips composer" '[ "$rc" = 0 ] && ! grep -q composer "$FX/docker.log"'
run 4.5
check "4.5 stays refused, no composer" '[ "$rc" = 3 ] && ! grep -q composer "$FX/docker.log"'
run 5.3 --new-name vass
check "vass stays refused, no composer" '[ "$rc" = 3 ] && ! grep -q composer "$FX/docker.log"'
[ "$fail" = 0 ] && echo "composer.test: ok"
exit "$fail"
