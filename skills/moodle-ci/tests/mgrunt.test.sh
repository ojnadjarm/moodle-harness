#!/usr/bin/env bash
# mgrunt on a throwaway 5.x-shaped root with fake nvm node/npx dirs (no real grunt): picks the highest node
# matching engines.node, rc 3 + message when none, rc 3 + the npm ci line without grunt, runs nice npx grunt amd
# --root=<rel> from the root and lists changed amd/build files, grunt rc passes through, partial ranges follow npm,
# no Moodle root is rc 2, --help names engines.
set -uo pipefail
M="$(cd "$(dirname "$0")/.." && pwd)/scripts/mgrunt"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

R="$T/www"; P="$R/public/local/foo"
mkdir -p "$P/amd/src" "$P/amd/build" "$R/node_modules/.bin"
echo "<?php \$plugin->component = 'local_foo';" > "$P/version.php"
touch "$R/Gruntfile.js" "$R/node_modules/.bin/grunt" "$P/amd/build/keep.min.js" "$P/amd/build/old.min.js"
echo '{"name":"moodle","engines":{"node":">=22.11.0 <23"}}' > "$R/package.json"
export NVM_DIR="$T/nvm"
for v in v20.18.0 v22.10.0 v22.11.0 v22.23.2 v24.20.0; do
  mkdir -p "$NVM_DIR/versions/node/$v/bin"
  printf '#!/bin/sh\necho %s\n' "$v" > "$NVM_DIR/versions/node/$v/bin/node"
  cat > "$NVM_DIR/versions/node/$v/bin/npx" <<'EOF'
#!/bin/sh
echo "npx-node=$(node) cwd=$PWD nice=$(nice) args=$*" > "$MGRUNT_LOG"
for a; do case $a in --root=*) r=${a#--root=};; esac; done
echo new > "$r/amd/build/old.min.js"; echo add > "$r/amd/build/new.min.js"
exit "${FAKE_RC:-0}"
EOF
  chmod +x "$NVM_DIR"/versions/node/$v/bin/*
done
export MGRUNT_LOG="$T/npx.log"

out=$(cd "$P/amd/src" && "$M" 2>&1); rc=$?
check "runs rc 0 from a plugin subdir" '[ $rc = 0 ]'
check "highest matching node v22.23.2 runs npx" 'grep -q "npx-node=v22.23.2" "$MGRUNT_LOG"'
check "npx runs in the root" 'grep -q "cwd=$R " "$MGRUNT_LOG"'
check "nice 19" 'grep -q "nice=19" "$MGRUNT_LOG"'
check "grunt amd --root=public/local/foo" 'grep -q "args=grunt amd --root=public/local/foo$" "$MGRUNT_LOG"'
check "lists changed build files only" 'grep -q "changed: amd/build/old.min.js" <<<"$out" && grep -q "changed: amd/build/new.min.js" <<<"$out" && ! grep -q keep <<<"$out"'

out=$(FAKE_RC=6 "$M" "$P" 2>&1); rc=$?
check "grunt rc passes through" '[ $rc = 6 ]'

echo '{"engines":{"node":"^20.11.0 || >=26"}}' > "$R/package.json"
out=$("$M" "$P" 2>&1); check "caret + || picks v20.18.0" 'grep -q "npx-node=v20.18.0" "$MGRUNT_LOG"'

echo '{"engines":{"node":"~22"}}' > "$R/package.json"
rm -f "$MGRUNT_LOG"; out=$("$M" "$P" 2>&1); check "partial ~22 is >=22 <23 (npm)" 'grep -q "npx-node=v22.23.2" "$MGRUNT_LOG"'
echo '{"engines":{"node":">20 <=22"}}' > "$R/package.json"
rm -f "$MGRUNT_LOG"; out=$("$M" "$P" 2>&1); check "partial >20 <=22 is >=21 <23 (npm)" 'grep -q "npx-node=v22.23.2" "$MGRUNT_LOG"'
echo '{"engines":{"node":">22 <24"}}' > "$R/package.json"
out=$("$M" "$P" 2>&1); rc=$?; check "partial >22 <24 matches no 22.x or 24.x" '[ $rc = 3 ]'

echo '{"engines":{"node":">=18.0.0 <19"}}' > "$R/package.json"
out=$("$M" "$P" 2>&1); rc=$?
check "no matching node rc 3 + message" '[ $rc = 3 ] && grep -q "no node in .* satisfies engines.node .>=18.0.0 <19." <<<"$out"'

echo '{"engines":{"node":">=22.11.0 <23"}}' > "$R/package.json"
rm "$R/node_modules/.bin/grunt"
out=$("$M" "$P" 2>&1); rc=$?
check "no grunt rc 3 + npm ci line" '[ $rc = 3 ] && grep -qF "run: cd $R && PATH=$NVM_DIR/versions/node/v22.23.2/bin:\$PATH nice -n 19 npm ci" <<<"$out"'

out=$("$M" "$T" 2>&1); rc=$?
check "no plugin rc 2" '[ $rc = 2 ]'
mkdir -p "$T/lone/local/bar"; echo '<?php' > "$T/lone/local/bar/version.php"
out=$("$M" "$T/lone/local/bar" 2>&1); rc=$?
check "no Moodle root rc 2 + message" '[ $rc = 2 ] && grep -q "no Moodle root" <<<"$out"'
check "--help names engines" '"$M" --help | grep -q engines'

exit $fail
