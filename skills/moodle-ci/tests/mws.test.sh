#!/usr/bin/env bash
# mws against fixture env trees (stub config.php run by host php) with a fake docker on PATH (never real docker).
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/mws"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
E="$T/envs"; export MFIXTURE_ENVS="$E" MWS_LOG="$T/call.json"
tree() { mkdir -p "$E/$1/www/vendor/bin" "$E/$1/www/public/local/x"; touch "$E/$1/www/vendor/bin/phpunit"; }
for e in fx pub vass vass-services 4.5; do tree "$e"; done
ln -s "$E/vass" "$E/alias"
mkdir -p "$T/bin" "$T/nowhere"

# Stub Moodle: users admin (2) and guest (1); call_external_function logs its inputs to $MWS_LOG.
cat > "$E/fx/www/config.php" <<'EOF'
<?php
namespace core\session {
    class manager { public static function set_user($u) { $GLOBALS['USER'] = $u; } }
}
namespace core_external {
    class external_api {
        public static function call_external_function($fn, $params, $ajax = false) {
            global $CFG, $USER;
            file_put_contents(getenv('MWS_LOG'), json_encode(['fn' => $fn, 'params' => $params, 'ajax' => $ajax,
                'user' => $USER->username, 'ws' => WS_SERVER, 'cli' => CLI_SCRIPT, 'debug' => $CFG->debug]));
            if ($fn === 'fail') {
                return ['error' => true, 'exception' => (object)['message' => 'boom', 'debuginfo' => 'dbg']];
            }
            if ($fn === 'noisy') {
                echo "noise\n";
            }
            return ['error' => false, 'data' => ['ok' => 1, 'u' => 'é/x']];
        }
    }
}
namespace {
    define('DEBUG_DEVELOPER', 32767);
    $CFG = (object)['debug' => 0, 'libdir' => __DIR__ . '/lib'];
    $USER = null;
    class stub_db {
        public $users = [1 => 'guest', 2 => 'admin'];
        public function get_record($t, $c) {
            foreach ($this->users as $id => $n) {
                if (($c['id'] ?? null) == $id || ($c['username'] ?? null) === $n) {
                    return (object)['id' => $id, 'username' => $n];
                }
            }
            return false;
        }
        public function sql_like($f, $p, $cs) { return "$f ILIKE $p"; }
        public function sql_like_escape($s) { return str_replace('_', '\_', $s); }
        public function get_records_select($t, $w, $p) {
            file_put_contents(getenv('MWS_LOG'), json_encode([$t, $w, $p]));
            return $p['p'] === '%nope%' ? [] : [(object)['name' => 'core_a', 'component' => 'moodle',
                'classname' => 'c', 'methodname' => 'm', 'capabilities' => 'moodle/x:y']];
        }
    }
    $DB = new stub_db();
    function get_admin() { return $GLOBALS['DB']->get_record('user', ['id' => 2]); }
}
EOF
for e in pub vass 4.5 vass-services; do cp "$E/fx/www/config.php" "$E/$e/www/public/config.php"; done

# Fake docker: one app container mounting $E at /srv/envs; exec -i runs host php in the mapped dir.
cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
case "\$1" in
    ps) [ -n "\${FAKE_NOAPP:-}" ] || echo fx-app-1 ;;
    inspect) printf '%s\t/srv/envs\n' "$E" ;;
    exec) [ "\$2" = -i ] || exit 0
        printf '%s\n' "\$*" >> "$T/docker.log"
        cd "$E\${6#/srv/envs}" && exec php ;;
esac
EOF
chmod +x "$T/bin/docker"

bad=0
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (got '$1')"; bad=1; fi; }
run() { (cd "$1" && shift && PATH="$T/bin:$PATH" "$S" "$@" 2>"$T/err"; echo "rc=$?"); }
log() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(d if len(sys.argv) < 3 else d[sys.argv[2]], sort_keys=True))' "$MWS_LOG" "$@"; }
OK=$'{\n    "ok": 1,\n    "u": "é/x"\n}\nrc=0'

check "$("$S" --help | grep -c -- '--user'; echo "rc=$?")" $'1\nrc=0' "--help names --user, rc 0"
check "$(run "$T/nowhere" --env fx core_webservice_get_site_info)" "$OK" "--env from any cwd: pretty JSON, rc 0"
check "$(cat "$T/err")" "" "mphp's as-is notice filtered: stderr empty"
check "$(log | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["fn"], d["user"], d["ws"], d["cli"], d["ajax"], d["debug"], d["params"])')" \
    "core_webservice_get_site_info admin True True False 32767 []" "default user admin, WS_SERVER, debug developer, ajax off"
check "$(tail -1 "$T/docker.log")" "exec -i -u www-data -w /srv/envs/fx/www fx-app-1 php" "runs through mphp in the env dirroot"
run "$T" --env fx f a=1 'v[]=x' 'v[]=y&z=2' 'o[k]=a b' 'e=' >/dev/null
check "$(log params)" '{"a": "1", "e": "", "o": {"k": "a b"}, "v": ["x", "y&z=2"]}' "key=value, key[]=v, key[sub]=v parsed like a query string"
run "$T" --env fx f a=1 'o[k]=x' 'o[j]=y' --json '{"o":{"k":[1,2]},"b":true}' >/dev/null
check "$(log params)" '{"a": "1", "b": true, "o": {"j": "y", "k": [1, 2]}}' "--json merged over key=value"
run "$T" --env fx --user guest f >/dev/null; check "$(log user)" '"guest"' "--user by username"
run "$T" --env fx --user 1 f >/dev/null; check "$(log user)" '"guest"' "--user by id"
check "$(run "$T" --env fx --user ghost f)" "rc=1" "unknown user: rc 1"
check "$(cat "$T/err")" "mws: no user 'ghost'" "unknown user: named on stderr"
run "$T" --env fx --ajax f >/dev/null; check "$(log ajax)" "true" "--ajax passes ajaxonly=true"
check "$(run "$T" --env fx fail)" $'{\n    "message": "boom",\n    "debuginfo": "dbg"\n}\nrc=1' "exception with debuginfo, rc 1"
check "$(run "$T" --env fx noisy)" "$OK" "echoed output kept off stdout"
check "$(cat "$T/err")" "noise" "echoed output goes to stderr"
check "$(run "$T" --env fx --list site_info)" $'name\tcomponent\tclassname\tmethodname\tcapabilities\ncore_a\tmoodle\tc\tm\tmoodle/x:y\nrc=0' "--list: TSV rows, rc 0"
check "$(log)" '["external_functions", "name ILIKE :p", {"p": "%site\\_info%"}]' "--list: case-insensitive LIKE, pattern escaped"
check "$(run "$T" --env fx --list nope | tail -1)" "rc=1" "--list: no match rc 1"
check "$(run "$E/fx/www/public/local/x" f)" "$OK" "no --env: the code tree holding the cwd"
check "$(run "$T" --env pub f)" "$OK" "5.1+ layout: public/config.php only"
: > "$T/docker.log"
check "$(run "$T" --env vass f)" "rc=64" "--env vass refused rc 64"
check "$(cat "$T/err")" "mws: env 'vass' is refused (Vass and 4.5 are never touched)" "vass refusal message"
check "$(run "$T" --env 4.5 f)" "rc=64" "--env 4.5 refused rc 64"
check "$(run "$T" --env vass-services --list)" "rc=64" "--env vass-services refused rc 64"
check "$(run "$T" --env alias f)" "rc=64" "env symlinked into vass refused rc 64"
check "$(run "$E/vass/www/public/local/x" f)" "rc=64" "cwd inside a vass tree refused rc 64"
check "$(run "$E/4.5/www" --list)" "rc=64" "cwd inside a 4.5 tree refused rc 64"
check "$(wc -c < "$T/docker.log")" "0" "refusals never reach docker"
check "$(run "$T" --env ../fx f)" "rc=64" "--env with a path refused rc 64"
check "$(run "$T" --env nope f)" "rc=64" "unknown env rc 64"
check "$(run "$T/nowhere" f)" "rc=64" "outside a code tree rc 64"
check "$(cat "$T/err")" "mws: no Moodle code tree (vendor/bin/phpunit) above $T/nowhere; pass --env <name>" "outside a code tree: says why"
check "$(run "$T" --env fx)" "rc=64" "no function: usage rc 64"
check "$(run "$T" --env fx a=1 f)" "rc=64" "key=value before the function: usage rc 64"
check "$(run "$T" --env fx f g)" "rc=64" "two functions: usage rc 64"
check "$(run "$T" --env fx --list x a=1)" "rc=64" "--list with key=value: usage rc 64"
check "$(run "$T" --env fx f --json '[1')" "rc=64" "bad --json rc 64"
check "$(cat "$T/err")" "mws: --json is not a JSON object" "bad --json: says why"
check "$(run "$T" --env fx "f');")" "rc=64" "function name with quotes refused rc 64"
check "$(FAKE_NOAPP=1 run "$T" --env fx f)" "rc=2" "no running container: mphp rc 2"
exit $bad
