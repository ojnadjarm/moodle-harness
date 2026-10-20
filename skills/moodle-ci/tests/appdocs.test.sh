#!/usr/bin/env bash
# moodleapp-instructions.md vs the offline docs: mirror paths, moodledev.io URLs, delegates, handler keys, Node major, mobile.py flags, delegate count, plugin loop; mutants must fail.
set -uo pipefail
F="${APPDOC_FILE:-$HOME/.claude/moodleapp-instructions.md}"
D="${APPDOC_DOCS:-$HOME/.moodle-devdocs}"
MP="$HOME/.claude/skills/moodle-pluginskel/mobile.py"
DJ="$HOME/.claude/skills/moodle-ci/reference/mobile-delegates.json"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# Prints one line per problem in $1 against docs root $2; exit 1 if any.
appcheck() {
    local f=$1 d=$2 p u k n api errs=0 flat note major
    api="$d/general/app/development/plugins-development-guide/api-reference.md"
    [ -f "$api" ] || { echo "no api-reference.md under $d"; return 1; }
    for p in $(grep -oE '~/\.moodle-devdocs/[^ )`]*' "$f"); do
        [ -e "$d/${p#'~/.moodle-devdocs/'}" ] || { echo "no mirror: $p"; errs=1; }
    done
    for u in $(grep -oE 'https://moodledev\.io/[^ )`]*' "$f"); do
        p="$d/${u#https://moodledev.io/}"; p="${p%/}"
        [ -f "$p.md" ] || [ -f "$p/index.md" ] || { echo "no mirror: $u"; errs=1; }
    done
    for k in $(grep -oE '`(Core|Addon)[A-Za-z]*Delegate`' "$f" | tr -d '`' | sort -u); do
        grep -qE "^#+ $k\b" "$api" || { echo "delegate not in api-reference: $k"; errs=1; }
    done
    for k in $(awk '/^- `db\/mobile.php`/{on=1;print;next} on&&/^- /{exit} on' "$f" | grep -oE '`[a-z]+`' | tr -d '`' | sort -u); do
        grep -qE "\`([A-Za-z]+\.)*$k\`" "$api" || { echo "handler key not in api-reference: $k"; errs=1; }
    done
    flat="$(tr '\n' ' ' < "$f" | tr -s ' ')"
    note="$(grep -oE 'Verified [^;]*`\.nvmrc` `lts/[a-z]+` = Node [0-9]+' <<<"$flat")"
    major="${note##*Node }"
    case "$note" in
        *lts/iron*) n=20 ;; *lts/jod*) n=22 ;; *lts/krypton*) n=24 ;; *) n="" ;;
    esac
    if [ -z "$note" ]; then echo "no .nvmrc note in the Verified line"; errs=1
    elif [ "$n" != "$major" ]; then echo ".nvmrc note: codename is Node $n, note says $major"; errs=1
    else
        n="$(sed "s/${note//\//\\/}//" <<<"$flat" | grep -oE 'Node [0-9]+|\b[0-9]+\.x\b' | grep -oE '[0-9]+' | sort -u)"
        [ -n "$n" ] || { echo "no stated Node major"; errs=1; }
        for k in $n; do [ "$k" = "$major" ] || { echo "stated Node $k, .nvmrc note $major"; errs=1; }; done
    fi
    return $errs
}

out="$(appcheck "$F" "$D")" && ok "live file matches the offline docs" || bad "live file: $out"

# Prints each --flag on a mobile.py line of $1 that mobile.py --help lacks; exit 1 if any.
flagcheck() {
    local k h errs=0
    h="$(python3 "$MP" --help)"
    for k in $(sed -n '/mobile\.py/,/^\$S\/mmobile/p' "$1" | grep -oE -- '--[a-z-]+' | sort -u); do
        grep -qE -- "$k\b" <<<"$h" || { echo "mobile.py flag not in --help: $k"; errs=1; }
    done
    return $errs
}
out="$(flagcheck "$F")" && ok "mobile.py flags exist in --help" || bad "$out"

n=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$DJ")
grep -q "The $n delegates: \`moodle-ci/reference/mobile-delegates.json\`" "$F" \
    && ok "delegate count $n matches mobile-delegates.json" || bad "delegate count is not $n"

loop="$(awk '/^## Plugin side/{on=1} on&&/^## Tests/{exit} on' "$F" | grep -oE 'mobile\.py|--delegate|\$S/mmobile|npm run serve:test|site URL' | uniq | tr '\n' ' ')"
[ "$loop" = "mobile.py --delegate \$S/mmobile npm run serve:test site URL " ] \
    && ok "plugin side: mobile.py --delegate, \$S/mmobile, serve:test + site URL in order" || bad "plugin loop: $loop"

mutant() {
    local name=$1 expr=$2 want=$3
    sed "$expr" "$F" > "$T/m.md"
    cmp -s "$F" "$T/m.md" && { bad "$name: mutation did not apply"; return; }
    out="$(appcheck "$T/m.md" "$D")" && { bad "$name: passed"; return; }
    grep -q "$want" <<<"$out" && ok "$name" || bad "$name: wrong error: $out"
}
mutant "dead mirror path" 's#plugins-development-guide/`#plugins-dev-guide/`#' "no mirror: ~/.moodle-devdocs"
mutant "dead moodledev.io URL" 's#development/setup#development/set-up#' "no mirror: https://moodledev.io"
mutant "unknown delegate" 's#`CoreMainMenuDelegate`#`CoreMainMenusDelegate`#' "delegate not in api-reference"
mutant "unknown handler key" 's#`restricttocurrentuser`#`restricttouser`#' "handler key not in api-reference: restricttouser"
mutant "Node major drift" 's#Node 24:#Node 22:#' "stated Node 22"
mutant "wrong .nvmrc note" 's#= Node 24)#= Node 22)#' "codename is Node 24"
mutant "missing .nvmrc note" 's#`lts/krypton` = Node 24##' "no .nvmrc note"
sed 's#--handler <h>#--handlr <h>#' "$F" > "$T/m.md"
out="$(flagcheck "$T/m.md")" || true
grep -q "not in --help: --handlr" <<<"$out" && ok "wrong mobile.py flag" || bad "wrong mobile.py flag: $out"

size=$(wc -c < "$F")
[ "$size" -lt 5500 ] && ok "size $size < 5500" || bad "size $size >= 5500"
[ $fail -eq 0 ] && echo "PASS" || echo "FAILED"
exit $fail
