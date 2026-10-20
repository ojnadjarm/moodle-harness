#!/usr/bin/env bash
# mupgrade against a fixture 5.2-public tree with a fake docker on PATH (never real docker).
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/mupgrade"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
tree() { mkdir -p "$T/$1/www/vendor/bin" "$T/$1/www/admin/cli" "$T/$1/www/public/local/x/db"; touch "$T/$1/www/vendor/bin/phpunit"
    printf "<?php\n\$CFG->dbtype = 'pgsql';\n\$CFG->dbhost = 'db';\n\$CFG->dbname = 'moodle';\n\$CFG->dbuser = 'moodle';\n\$CFG->dbpass = 'p';\n\$CFG->prefix = 'mdl_';\n" > "$T/$1/www/config.php"
    printf "<?php\n\$plugin->component = 'local_x';\n\$plugin->version = 2026102001;\n" > "$T/$1/www/public/local/x/version.php"; }
tree app; tree none; tree moodle-envs/vass; tree moodle-envs/4.5
mkdir -p "$T/bin" "$T/app/www/public/lib"

# Fake docker: app container app-app-1 (project app, db app-db-1); psql prints $T/db.ver;
# `exec -i -u` logs the php argv, upgrade.php writes FAKE_NEW (default version.php's) to $T/db.ver.
cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
case "\$1" in
    ps) if [ "\$2" = --filter ]; then echo app-db-1; else echo app-app-1; fi ;;
    inspect) case "\$3" in
        *Mounts*) printf '%s\t/var/www/html\n' "$T/app/www" ;;
        *Labels*) echo app ;;
    esac ;;
    exec) [ "\$2" = -i ] || exit 0
        if [ "\$3" = -u ]; then
            shift 7; printf '%s\n' "\$*" >> "$T/argv.log"
            case "\$*" in *upgrade.php*)
                [ "\${FAKE_UPG_RC:-0}" = 0 ] || { echo "upgrade error line"; exit "\$FAKE_UPG_RC"; }
                echo "\${FAKE_NEW:-2026102001}" > "$T/db.ver" ;; esac
            exit 0
        fi
        cat > "$T/stdin.log"; printf 'value\n'; cat "$T/db.ver" 2>/dev/null; exit "\${FAKE_DB_RC:-0}" ;;
esac
EOF
chmod +x "$T/bin/docker"

bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got '$1')"; bad=1; fi; }
run() { (cd "$1" && shift && PATH="$T/bin:$PATH" "$S" "$@" 2>&1; echo "rc=$?"); }
reset() { rm -f "$T/argv.log" "$T/stdin.log"; if [ -n "$1" ]; then echo "$1" > "$T/db.ver"; else rm -f "$T/db.ver"; fi; }
P="$T/app/www/public/local/x"
HINT="mupgrade: phpunit init stale after a version change; run mtest init phpunit before tests"
A='sh -c f=$1; shift; [ ! -e "$f" ] && [ -e "public/$f" ] && cd public; exec nice -n 19 php "$f" "$@" mupgrade'

check "$(run "$P" --help | head -1)" "usage: mupgrade [plugin-dir]   (default: \$PWD; walks up to version.php with \$plugin->component)" "--help: usage"
check "$(run "$P" --help | tail -1)" "rc=0" "--help: rc 0"
reset 2026102000
check "$(run "$P/db")" "local_x 2026102000 -> 2026102001"$'\n'"$HINT"$'\nrc=0' "ok: old -> new, stale hint, rc 0"
check "$(cat "$T/argv.log")" "$A admin/cli/upgrade.php --non-interactive"$'\n'"$A admin/cli/purge_caches.php" "argv: niced upgrade --non-interactive then purge, no init"
check "$(cat "$T/stdin.log")" "select value from mdl_config_plugins where plugin = 'local_x' and name = 'version'" "read-back: config_plugins via mdb"
reset ""
check "$(run "$T" "$P")" "local_x none -> 2026102001"$'\n'"$HINT"$'\nrc=0' "fresh install: none -> new; plugin-dir argument"
reset 2026102001
check "$(run "$P")" $'local_x 2026102001 -> 2026102001\nrc=0' "no change: no stale hint"
reset 2026102000
check "$(FAKE_UPG_RC=3 run "$P")" $'upgrade error line\nmupgrade: admin/cli/upgrade.php failed (rc 3)\nrc=1' "upgrade fail: tail shown, rc 1"
check "$(grep -c purge_caches "$T/argv.log")" "0" "upgrade fail: no purge"
reset 2026102000
check "$(FAKE_NEW=2026102000 run "$P")" $'local_x 2026102000 -> 2026102000\nmupgrade: DB version 2026102000 != version.php 2026102001\nrc=1' "read-back mismatch: rc 1"
reset 2026102000
check "$(FAKE_DB_RC=5 run "$P" | tail -1)" "rc=2" "read-back failed: rc 2"
check "$(test -e "$T/argv.log" && echo ran || echo none)" "none" "read-back failed: upgrade never run"
reset 2026102000
check "$(run "$T/app/www/public/lib")" "mupgrade: no version.php with \$plugin->component above $T/app/www/public/lib"$'\nrc=2' "no plugin: rc 2"
check "$(run "$T/none/www/public/local/x")" "mupgrade: no running Moodle container mounts $T/none/www/public/local/x (its env is stopped?)"$'\nrc=2' "no container: rc 2"
check "$(run "$T/moodle-envs/vass/www/public/local/x")" "mupgrade: refused Vass path $T/moodle-envs/vass/www/public/local/x (never touched)"$'\nrc=2' "vass path: rc 2"
check "$(run "$T" "$T/moodle-envs/4.5/www/public/local/x" | tail -1)" "rc=2" "4.5 env path: rc 2"
check "$(test -e "$T/argv.log" && echo ran || echo none)" "none" "refusals: docker exec never called"
check "$(run "$P" a b | tail -1)" "rc=2" "two args: rc 2 usage"
reset 2026102000
check "$(cd "$(dirname "$S")/.." && PATH="$T/bin:$PATH" scripts/mupgrade "$P" 2>&1 | tail -1; echo "rc=${PIPESTATUS[0]}")" "$HINT"$'\nrc=0' "relative script path: mdb found, rc 0"
mkdir -p "$T/app/www/public/local/y" "$T/app/www/public/local/z"
printf "<?php\n\$plugin->component = 'local_y';\n\$plugin->version = 2026102000.00;\n" > "$T/app/www/public/local/y/version.php"
reset 2026102000
check "$(FAKE_NEW=2026102000 run "$T/app/www/public/local/y")" $'local_y 2026102000 -> 2026102000\nrc=0' "decimal 2026102000.00 == 2026102000: rc 0"
reset 2026102000
check "$(FAKE_NEW=2026102000.01 run "$T/app/www/public/local/y" | tail -1)" "rc=1" "decimal 2026102000.01 != 2026102000.00: rc 1"
printf "<?php\n\$plugin->component = 'local_z';\n// \$plugin->version = 2020010100;\n# \$plugin->version = 2020010101;\n/* \$plugin->version = 2020010102; */\n\$plugin->version = 2026102001;\n" > "$T/app/www/public/local/z/version.php"
reset 2026102001
check "$(run "$T/app/www/public/local/z")" $'local_z 2026102001 -> 2026102001\nrc=0' "commented version lines skipped: rc 0"
exit $bad
