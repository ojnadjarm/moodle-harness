#!/usr/bin/env bash
# mexec against fixture 4.5-flat / 5.2-public layouts with a fake docker and php on PATH.
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/mexec"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/flat/www/admin/cli" "$T/flat/www/mod/forum" "$T/flat/www/vendor/bin" \
    "$T/pub/www/admin/cli" "$T/pub/www/public/admin/tool/phpunit/cli" "$T/pub/www/public/local/x" "$T/pub/www/vendor/bin" "$T/none/local/x"
touch "$T/flat/www/config.php" "$T/flat/www/vendor/bin/phpunit" "$T/pub/www/config.php" \
    "$T/pub/www/public/config.php" "$T/pub/www/vendor/bin/phpunit" "$T/flat/www/admin/cli/cfg.php" \
    "$T/pub/www/admin/cli/cfg.php" "$T/pub/www/public/admin/tool/phpunit/cli/init.php"

# Fake docker: logs argv; for `exec -i -u U -w W C cmd...` runs cmd in the host dir mounted at W.
cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
case "\$1" in
    ps) printf 'flat-app-1\npub-app-1\n' ;;
    inspect) case "\${@: -1}" in
        flat-app-1) printf '%s\t/var/www/html\n' "$T/flat/www" ;;
        pub-app-1) printf '%s\t/var/www/moodle\n' "$T/pub/www" ;;
    esac ;;
    exec)
        [ "\$2" = "-i" ] && [ "\$3" = "-u" ] || exit 0
        printf '%s\n' "\$*" >> "$T/argv.log"
        w="\$6"; c="\$7"; shift 7
        case "\$c" in flat-app-1) h="$T/flat/www\${w#/var/www/html}" ;; pub-app-1) h="$T/pub/www\${w#/var/www/moodle}" ;; esac
        cd "\$h" && "\$@" ;;
esac
EOF
printf '#!/usr/bin/env bash\necho "php cwd=${PWD#%s} $*"\nexit 7\n' "$T" > "$T/bin/php"
chmod +x "$T/bin/docker" "$T/bin/php"

bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got '$1')"; bad=1; fi; }
run() { (cd "$1" && shift && PATH="$T/bin:$PATH" "$S" "$@" 2>&1; echo "rc=$?"); }

A='sh -c [ "$1" = php ] && [ ! -e "$2" ] && [ -e "public/$2" ] && cd public; exec "$@" mexec'
check "$(run "$T/flat/www/mod/forum" admin/cli/purge_caches.php)" $'php cwd=/flat/www admin/cli/purge_caches.php\nrc=7' "4.5 flat: runs in dirroot, rc passed through"
check "$(tail -1 "$T/argv.log")" "exec -i -u www-data -w /var/www/html flat-app-1 $A php admin/cli/purge_caches.php" "argv: www-data, dirroot, php script"
check "$(run "$T/pub/www/public/local/x" admin/cli/cfg.php --name='a b' --set=1)" $'php cwd=/pub/www admin/cli/cfg.php --name=a b --set=1\nrc=7' "5.2: admin/cli at root, args kept"
check "$(tail -1 "$T/argv.log")" "exec -i -u www-data -w /var/www/moodle pub-app-1 $A php admin/cli/cfg.php --name=a b --set=1" "argv: public layout"
check "$(run "$T/pub/www/public/local/x" admin/tool/phpunit/cli/init.php)" $'php cwd=/pub/www/public admin/tool/phpunit/cli/init.php\nrc=7' "5.2: script only under public/ runs from public/"
check "$(run "$T/pub/www/public/local/x" pwd)" "$T/pub/www"$'\nrc=0' "5.2: non-php command stays in dirroot"
check "$(run "$T/none/local/x" admin/cli/purge_caches.php)" $'mexec: no running Moodle container mounts '"$T/none/local/x"$' (not inside a Moodle code tree, or its env is stopped)\nrc=2' "unknown dir: rc 2 with reason"
check "$(run "$T/flat/www")" $'usage: mexec <script.php|cmd> [args...]  (run from inside a Moodle code tree)\nrc=2' "no args: rc 2 usage"
mkdir -p "$T/nodocker"; printf '#!/bin/sh\ntouch "%s/docker-called"; exit 99\n' "$T" > "$T/nodocker/docker"; chmod +x "$T/nodocker/docker"
for h in --help -h; do
    o="$(cd /tmp && PATH="$T/nodocker:$PATH" "$S" $h 2>&1; echo "rc=$?")"
    check "$(grep -c '^usage: mexec' <<<"$o") $(grep -c '^Examples:' <<<"$o") $(grep -c '^Exit:' <<<"$o") ${o##*$'\n'}" "1 1 1 rc=0" "$h: usage, examples, exit codes, rc 0"
done
check "$([ -e "$T/docker-called" ] && echo called || echo none)" none "--help never calls docker"
nohelp=""
for f in "${S%/*}"/*; do [ -f "$f" ] && [ -x "$f" ] || continue; o="$(cd /tmp && "$f" --help 2>&1)" && grep -qi usage <<<"$o" || nohelp+=" ${f##*/}"; done
check "${nohelp:-none}" none "every script in scripts/ prints usage with rc 0 on --help"
exit $bad
