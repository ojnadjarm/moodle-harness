#!/usr/bin/env bash
# Guard selftest: fixture HOME, fake docker/git, no network, no docker socket; real env paths are never passed.
set -u
S="$(cd "$(dirname "$0")/.." && pwd)/install.sh"
FX="$(mktemp -d)"; trap 'rm -rf "$FX"' EXIT
mkdir -p "$FX/bin" "$FX/moodle-envs/"{4.5,vass/www,vass-services,5.2}
ln -s "$FX/moodle-envs" "$FX/alias"
cat > "$FX/bin/docker" <<'F'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_OUT/docker.log"
case "$*" in "compose ls -a -q") printf '%s\n' ${FAKE_PROJECTS:-} ;; *psql*) echo 0 ;; esac
F
cat > "$FX/bin/git" <<'F'
#!/usr/bin/env bash
mkdir -p "${@: -1}" && touch "${@: -1}/version.php"
F
cat > "$FX/bin/ss" <<'F'
#!/usr/bin/env bash
printf 'LISTEN 0 4096 0.0.0.0:%s 0.0.0.0:*\n' 8045 8046 8445 8446
F
chmod +x "$FX/bin/"*
box=(env PATH="$FX/bin:$PATH" FAKE_OUT="$FX" HOME="$FX" MOODLE_ENVS="$FX/moodle-envs" HARNESS_CONFIG="$FX/none"
    MOODLE_DB_PASSWORD=fixture MOODLE_ADMIN_PASSWORD=fixture
    bwrap --unshare-net --ro-bind / / --dev /dev --proc /proc --tmpfs /run --bind "$FX" "$FX")
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
# refused <label> <args...>: exit 3, a "refused" message, and no docker call but the read-only project list.
refused() {
    local label="$1"; shift; : > "$FX/docker.log"
    "${box[@]}" "$S" "$@" > "$FX/out" 2>&1; local rc=$?
    check "refuses $label" '[ "$rc" = 3 ] && grep -q "^refused" "$FX/out" && ! grep -vqx "compose ls -a -q" "$FX/docker.log"'
}

check "selftest: sandbox has no network" '! "${box[@]}" python3 -c "import socket; socket.create_connection((\"1.1.1.1\", 443), 3)" 2>/dev/null'
check "selftest: docker is the fake" '[ "$("${box[@]}" bash -c "command -v docker")" = "$FX/bin/docker" ]'
check "selftest: no docker socket" '"${box[@]}" bash -c "[ ! -e /run/docker.sock ] && [ ! -e /var/run/docker.sock ]"'
check "selftest: HOME is the fixture" '[ "$("${box[@]}" bash -c "echo \$HOME")" = "$FX" ]'

refused "4.5 (project moodle45)" 4.5
refused "4.5 with flags" 4.5 mysql --php 8.2
refused "--new-name moodle45" 5.3 --new-name moodle45
refused "--new-name vass" 4.5 --new-name vass
refused "--new-name vass-services" 5.3 --new-name vass-services
refused "--new-name 4.5 (the 4.5 dir)" 5.3 --new-name 4.5
refused "--new-name with a path" 5.3 --new-name ../vass
refused "--src inside vass" 5.3 --new-name fresh1 --src "$FX/moodle-envs/vass/www"
refused "existing env dir" 5.2
FAKE_PROJECTS="moodle51 other" refused "existing compose project" 5.1
FAKE_PROJECTS="fresh2" refused "--new-name of an existing project" 5.3 --new-name fresh2
mkdir -p "$FX/moodle-envs/fresh3"
refused "--new-name of an existing dir" 5.3 --new-name fresh3
box[4]="MOODLE_ENVS=$FX/alias/4.5"
refused "a root inside 4.5 through a symlink" 5.3 --new-name fresh4
box[4]="MOODLE_ENVS=$FX/moodle-envs/vass"
refused "a root inside vass" 5.3 --new-name fresh5
box[4]="MOODLE_ENVS=$FX/moodle-envs"
refused "--name 4.5 (the 4.5 dir)" 4.5 --name 4.5
refused "--name vass2" 4.5 --name vass2
refused "--name 45 (project moodle45)" 4.5 --name 45

: > "$FX/docker.log"
"${box[@]}" "$S" 5.3 --new-name t430fresh > "$FX/out" 2>&1; rc=$?
check "--new-name fresh env installs" '[ "$rc" = 0 ] && grep -qx "name: t430fresh" "$FX/moodle-envs/t430fresh/docker-compose.yml"'
check "fresh env never names moodle45 or vass" '! grep -Eq "moodle45|vass" "$FX/docker.log"'
"${box[@]}" "$S" 5.0 > "$FX/out" 2>&1; rc=$?
check "fresh default env installs" '[ "$rc" = 0 ] && grep -qx "name: moodle50" "$FX/moodle-envs/5.0/docker-compose.yml"'
: > "$FX/docker.log"
"${box[@]}" "$S" 4.5 --name lts45 > "$FX/out" 2>&1; rc=$?
y="$FX/moodle-envs/lts45/docker-compose.yml"
check "--name lts45 installs as project moodlelts45" '[ "$rc" = 0 ] && grep -qx "name: moodlelts45" "$y"'
check "--name lts45 skips the Vass and busy ports" 'grep -q "\"8047:80\"" "$y" && grep -q "\"5446:5432\"" "$y"'
check "--name lts45 never names moodle45 or vass" '! grep -Eq "moodle45|vass" "$FX/docker.log" "$y"'
check "--name lts45 site is its own port" 'grep -q "wwwroot   = '"'"'http://localhost:8047'"'"';" "$FX/moodle-envs/lts45/www/config.php" && grep -q "^Site: *http://localhost:8047 " "$FX/out"'
"${box[@]}" "$S" 4.5 --name lts45b > "$FX/out" 2>&1; rc=$?
y="$FX/moodle-envs/lts45b/docker-compose.yml"
check "a second --name env skips a stopped env's ports" '[ "$rc" = 0 ] && grep -q "\"8048:80\"" "$y" && grep -q "\"5447:5432\"" "$y"'
[ "$fail" = 0 ] && echo "guard.test: ok"
exit "$fail"
