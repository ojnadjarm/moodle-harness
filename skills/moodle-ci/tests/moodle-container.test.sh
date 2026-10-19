#!/usr/bin/env bash
# moodle-container.sh against fixture 4.5 / 5.2 / 5.3 layouts and a fake docker on PATH.
set -uo pipefail
S="$(cd "$(dirname "$0")/../../.." && pwd)/hooks/moodle-container.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"

# 4.5: flat code tree, vendor installed. 5.2: public/ layout, vendor installed.
# 5.3: public/ layout, composer root not yet installed (no vendor/).
mkdir -p "$T/4.5/www/mod/forum" "$T/4.5/www/vendor/bin" \
    "$T/5.2/www/public/mod/forum" "$T/5.2/www/vendor/bin" \
    "$T/5.3/www/public/mod/forum" "$T/none/www/mod/forum"
touch "$T/4.5/www/config.php" "$T/4.5/www/composer.json" "$T/4.5/www/vendor/bin/phpunit"
for v in 5.2 5.3; do touch "$T/$v/www/config.php" "$T/$v/www/public/config.php" "$T/$v/www/composer.json"; done
touch "$T/5.2/www/vendor/bin/phpunit" "$T/none/www/mod/forum/version.php"

cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
case "\$1" in
    ps) printf 'moodle45-db-1\nmoodle45-app-1\nmoodle52-app-1\nmoodle53-app-1\n' ;;
    inspect) case "\${@: -1}" in
        moodle45-*) printf '%s\t/var/www/html\n' "$T/4.5/www" ;;
        moodle52-app-1) printf '%s\t/var/www/moodledata\n%s\t/var/www/html\n' "$T/5.2/moodledata" "$T/5.2/www" ;;
        moodle53-app-1) printf '%s\t/var/www/behatfaildumps\n%s\t/var/www/html\n' "$T/5.3/behatfaildumps" "$T/5.3/www" ;;
    esac ;;
    exec) [ "\$2" != moodle45-db-1 ] ;;
esac
EOF
chmod +x "$T/bin/docker"

bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got '$1')"; bad=1; fi; }
run() { PATH="$T/bin:$PATH" "$S" "$1"; echo "rc=$?"; }
tab=$'\t'
check "$(run "$T/4.5/www/mod/forum")" "moodle45-app-1${tab}/var/www/html"$'\nrc=0' "4.5 flat layout"
check "$(run "$T/5.2/www/public/mod/forum")" "moodle52-app-1${tab}/var/www/html"$'\nrc=0' "5.2 public layout with vendor"
check "$(run "$T/5.3/www/public/mod/forum")" "moodle53-app-1${tab}/var/www/html"$'\nrc=0' "5.3 public layout without vendor"
check "$(run "$T/none/www/mod/forum")" "rc=1" "no Moodle root"
exit $bad
