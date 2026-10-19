#!/usr/bin/env bash
# Offline: argument checks against a fake docker in a no-network sandbox. Live: apply, check, idempotency and drift on
# the throwaway moodle53 env only (AISETUP_TEST_ENV may name another throwaway env; never 4.5/Vass).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cli=$here/../ai-setup
live=${AISETUP_TEST_ENV:-moodle53}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

mkdir "$out/bin"
cat > "$out/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_OUT/argv"; env > "$FAKE_OUT/env"; cat > "$FAKE_OUT/stdin"
EOF
chmod +x "$out/bin/docker"
echo "sk-fixture-not-a-real-key" > "$out/key"
sandbox=(env PATH="$out/bin:$PATH" FAKE_OUT="$out" bwrap --unshare-net --ro-bind / / --dev /dev --proc /proc --bind "$out" "$out")
spec() { grep -- '^--spec-b64=' "$out/argv" | cut -d= -f2- | base64 -d; }

check "selftest: sandbox has no network" '! "${sandbox[@]}" python3 -c "import socket; socket.create_connection((\"1.1.1.1\", 443), 3)" 2>/dev/null'
check "selftest: docker is the fake" '[ "$("${sandbox[@]}" bash -c "command -v docker")" = "$out/bin/docker" ]'
check "refuses the vass env" '! "${sandbox[@]}" "$cli" vass --provider ollama --roles student --limit 1 2>/dev/null'
check "refuses the 4.5 env" '! "${sandbox[@]}" "$cli" moodle45 --provider ollama --roles student --limit 1 2>/dev/null'
check "needs provider, roles and limit" '! "${sandbox[@]}" "$cli" moodle53 --provider ollama --limit 3 2>/dev/null'
check "limit must be a positive integer" '! "${sandbox[@]}" "$cli" moodle53 --provider ollama --roles student --limit 0 2>/dev/null'
"${sandbox[@]}" "$cli" moodle53 --provider ollama --roles editingteacher,teacher --limit 20 --apikey-file "$out/key"
check "runs in moodle53-app-1 as www-data" 'grep -qx moodle53-app-1 "$out/argv" && grep -qx www-data "$out/argv"'
check "pipes apply.php" 'cmp -s "$out/stdin" "$here/../apply.php"'
check "spec carries roles and limits" '[ "$(spec | python3 -c "import json,sys; d=json.load(sys.stdin); print(\",\".join(d[\"roles\"]), d[\"limit\"], d[\"sitelimit\"], d[\"endpoint\"])")" = "editingteacher,teacher 20 200 http://127.0.0.1:11434" ]'
check "spec carries the default policy" 'spec | grep -q "Using the AI tools on this site"'
check "api key passes by env name only" '! grep -q sk-fixture "$out/argv" && grep -qx -- -e "$out/argv" && grep -qx AISETUP_APIKEY "$out/argv"'
check "api key never in the spec" '! spec | grep -q sk-fixture'
"${sandbox[@]}" "$cli" moodle53 --check
check "--check sends no spec" '! grep -q -- --spec-b64 "$out/argv" && grep -qx -- --mode=check "$out/argv"'

if ! docker ps --format '{{.Names}}' | grep -qx "$live-app-1"; then
  echo "FAIL live: $live-app-1 is not running"; exit 1
fi
case $live in moodle45*|*vass*) echo "FAIL live env $live is a customer site"; exit 1 ;; esac
run() { "$cli" "$live" --provider ollama --roles editingteacher --limit 20 > "$out/run.txt"; }
php() { docker exec -u www-data -w /var/www/html "$live-app-1" php -r "define('CLI_SCRIPT', 1); require 'config.php'; $1"; }
run
check "live: --check is clean after setup" '"$cli" "$live" --check > "$out/check.txt"'
check "live: second run changes nothing" 'run && grep -qx "changed: 0" "$out/run.txt"'
check "live: user limit is 20, site limit 200" 'php "\$p = \$DB->get_record(\"ai_providers\", [\"name\" => \"AI setup (ollama)\"]); \$c = json_decode(\$p->config); echo \$p->enabled, \$c->userratelimit, \"/\", \$c->globalratelimit;" | grep -qx "120/200"'
check "live: student cannot summarise" 'php "echo \$DB->get_field(\"role_capabilities\", \"permission\", [\"capability\" => \"aiplacement/courseassist:summarise_text\", \"roleid\" => \$DB->get_field(\"role\", \"id\", [\"shortname\" => \"student\"]), \"contextid\" => 1]);" | grep -qx -- -1'
check "live: policy string is overridden" 'php "echo get_string(\"userpolicy\", \"core_ai\");" | grep -q "Using the AI tools on this site"'
php "\$m = \core\di::get(\core_ai\manager::class); \$p = current(\$m->get_provider_instances(['name' => 'AI setup (ollama)'])); \$m->update_provider_instance(\$p, ['userratelimit' => 5] + \$p->config); set_config('generate_text', 0, 'aiplacement_editor');"
check "live: --check exits 1 on drift" '! "$cli" "$live" --check > "$out/drift.txt"'
check "live: drift lists both values" 'grep -q "^drift provider.userratelimit want 20 have 5" "$out/drift.txt" && grep -q "^drift placement.editor.generate_text" "$out/drift.txt" && grep -qx "drift: 2" "$out/drift.txt"'
check "live: rerun repairs the drift" 'run && grep -qx "changed: 2" "$out/run.txt" && "$cli" "$live" --check > /dev/null'
exit $fail
