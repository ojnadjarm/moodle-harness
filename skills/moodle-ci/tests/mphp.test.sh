#!/usr/bin/env bash
# mphp against fixture flat / public-only layouts with a fake docker that runs the host php.
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/mphp"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v php >/dev/null || { echo "SKIP mphp.test.sh: no host php"; exit 0; }
mkdir -p "$T/bin" "$T/flat/www/local/x" "$T/flat/www/vendor/bin" "$T/pub/www/public/local/x" "$T/pub/www/vendor/bin" "$T/none/local/x"
touch "$T/flat/www/vendor/bin/phpunit" "$T/pub/www/vendor/bin/phpunit"
cfg='<?php
namespace core\session { class manager { static function set_user($u) { global $USER; $USER = $u; } } }
namespace {
echo "cfg=%s\n";
$USER = (object)["id" => 0];
$DB = new class { function count_records($t) { return 3; } };
function get_admin() { return (object)["id" => 2]; }
}'
printf "$cfg" flat > "$T/flat/www/config.php"
printf "$cfg" public > "$T/pub/www/public/config.php"

# Fake docker: identity mounts; logs argv and stdin of `exec -i -u U -w W C php`, runs it with the host php in W.
cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
case "\$1" in
    ps) printf 'flat-app-1\npub-app-1\n' ;;
    inspect) case "\${@: -1}" in
        flat-app-1) printf '%s\t%s\n' "$T/flat/www" "$T/flat/www" ;;
        pub-app-1) printf '%s\t%s\n' "$T/pub/www" "$T/pub/www" ;;
    esac ;;
    exec)
        [ "\$2" = "-i" ] && [ "\$3" = "-u" ] || exit 0
        printf '%s\n' "\$*" >> "$T/argv.log"
        cat > "$T/stdin.php"
        cd "\$6" && php -n < "$T/stdin.php" ;;
esac
EOF
chmod +x "$T/bin/docker"

bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got '$1')"; bad=1; fi; }
run() { (cd "$1" && shift && PATH="$T/bin:$PATH" "$S" "$@" 2>&1; echo "rc=$?"); }

check "$(run "$T/flat/www/local/x" 'echo $DB->count_records("user"), "\n"; exit(4);')" $'cfg=flat\n3\nrc=4' "snippet: config loaded, \$DB global, rc passed through"
check "$(tail -1 "$T/argv.log")" "exec -i -u www-data -w $T/flat/www flat-app-1 php" "argv: www-data in dirroot"
printf '#!/usr/bin/env php\n<?php\necho "file ", CLI_SCRIPT ? "cli" : "web", "\\n";\n' > "$T/flat/www/local/x/r.php"
check "$(run "$T/flat/www/local/x" r.php)" $'cfg=flat\nfile cli\nrc=0' "file: shebang and <?php dropped, CLI_SCRIPT set"
check "$(grep -o '<?php' "$T/stdin.php" | wc -l)" "1" "file: one <?php in the composed script"
check "$( (cd "$T/flat/www/local/x" && printf '  <?php echo "in\\n";' | PATH="$T/bin:$PATH" "$S" - 2>&1; echo "rc=$?") )" $'cfg=flat\nin\nrc=0' "stdin: - reads the script"
check "$(run "$T/pub/www/public/local/x" 'echo $DB->count_records("user"), "\n";')" $'cfg=public\n3\nrc=0' "public/ layout: public/config.php when dirroot has none"
check "$(run "$T/flat/www" --admin 'echo $USER->id, "\n";')" $'cfg=flat\n2\nrc=0' "--admin: \$USER is the admin"
check "$(run "$T/flat/www" 'echo $USER->id, "\n";')" $'cfg=flat\n0\nrc=0' "no --admin: \$USER untouched"
check "$(run "$T/none/local/x" 'echo 1;')" $'mphp: no running Moodle container mounts '"$T/none/local/x"$' (not inside a Moodle code tree, or its env is stopped)\nrc=2' "no container: rc 2 with reason"
check "$(run "$T/flat/www" | tail -1)" "rc=2" "no args: rc 2 usage"
check "$("$S" --help | grep -c -- '--admin')" "1" "--help names --admin"
printf '<?php\n// GPL.\ndeclare(strict_types=1);\necho strlen("ab"), " ", CLI_SCRIPT ? "cli" : "web", "\\n";\n' > "$T/flat/www/local/x/s.php"
check "$(run "$T/flat/www/local/x" s.php)" $'cfg=flat\n2 cli\nrc=0' "strict_types: header goes after declare()"
printf '<?php\n/* GPL. */\ndeclare(strict_types=1);\n\nnamespace local_x;\necho __NAMESPACE__, " ", $DB->count_records("user"), " ", __LINE__, "\\n";\n' > "$T/flat/www/local/x/n.php"
check "$(run "$T/flat/www/local/x" --admin n.php)" $'cfg=flat\nlocal_x 3 6\nrc=0' "namespace: header goes after namespace;, line numbers kept"
printf '#!/usr/bin/env php\n<?php\ndefine('"'"'CLI_SCRIPT'"'"', true);\nrequire(__DIR__ . '"'"'/../../config.php'"'"');\necho "self\\n";\n' > "$T/flat/www/local/x/b.php"
check "$(run "$T/flat/www/local/x" b.php)" $'mphp: b.php requires config.php itself; running it as is, without the header\ncfg=flat\nself\nrc=0' "self-bootstrapping file: config runs once, noted on stderr"
check "$(tail -1 "$T/argv.log")" "exec -i -u www-data -w $T/flat/www/local/x flat-app-1 php" "self-bootstrapping file: runs in its own dir for __DIR__"
check "$(run "$T/flat/www" --admin 'define("CLI_SCRIPT", true); require("config.php"); echo $DB->count_records("u"), "\n";')" $'mphp: the code requires config.php itself; running it as is, without the header (--admin ignored)\ncfg=flat\n3\nrc=0' "self-bootstrapping snippet: <?php added, --admin ignored noted"
check "$( (cd "$T/flat/www/local/x" && printf 'define("CLI_SCRIPT", 1);\nrequire_once(__DIR__ . "/../../config.php");\necho "stdin\\n";' | PATH="$T/bin:$PATH" "$S" - 2>/dev/null; echo "rc=$?") )" $'cfg=flat\nstdin\nrc=0' "self-bootstrapping stdin: runs in the cwd for __DIR__"
printf '<?php\n// This script requires config.php to be loaded first.\n/* include config.php */\necho CLI_SCRIPT ? "cli" : "web", "\\n";\n' > "$T/flat/www/local/x/c.php"
check "$(run "$T/flat/www/local/x" c.php)" $'cfg=flat\ncli\nrc=0' "detection: config.php in comments gets the header"
check "$(run "$T/flat/www" 'echo "see include config.php", "\n";')" $'cfg=flat\nsee include config.php\nrc=0' "detection: config.php in a string gets the header"
printf '<?php\ndeclare(strict_types=1);\nnamespace local_x {\necho __NAMESPACE__, " ", $DB->count_records("user"), "\\n";\n}\n' > "$T/flat/www/local/x/k.php"
check "$(run "$T/flat/www/local/x" k.php)" $'cfg=flat\nlocal_x 3\nrc=0' "bracketed namespace: header goes inside the first block"
exit $bad
