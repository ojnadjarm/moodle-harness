#!/usr/bin/env bash
# Golden: upgrade.py on the 6 plugins whose core 5.2->5.3 install.xml changed gives the whole golden block per table; backup.py on mod_choice gives core's backup tree.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
S="$(cd "$(dirname "$0")/.." && pwd)"; F="$S/tests/fixtures/core"; G="$F/golden.txt"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

stub() {
    mkdir -p "$1/db"
    printf "<?php\ndefined('MOODLE_INTERNAL') || die();\n\$plugin->component = '%s';\n\$plugin->version = 2026010100;\n" \
        "$2" > "$1/version.php"
}

upgrade() {
    local component=$1 old=$2 new=$3 R="$T/$1" P="$T/$1/plugin"
    stub "$P" "$component"; cp "$F/$old" "$P/db/install.xml"
    git -C "$R" init -q && git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@example.com commit -qm base
    cp "$F/$new" "$P/db/install.xml"
    python3 "$S/upgrade.py" "$P" >/dev/null 2>"$T/err" || { bad "$component upgrade.py: $(cat "$T/err")"; return; }
    local version; version=$(sed -n 's/^\$plugin->version = \([0-9]*\);/\1/p' "$P/version.php")
    local want got
    want=$(grep "^$component|" "$G")
    got=$(steps "$component" "$version" < "$P/db/upgrade.php")
    [ "$got" = "$want" ] && ok "$component upgrade block equals golden ($(echo "$want" | wc -l) steps)" \
        || bad "$component upgrade block differs: $(diff <(echo "$want") <(echo "$got") | grep '^[<>]')"
}

# Every statement of the upgrade block as component|table|statement; savepoints get table '-'.
steps() {
    awk -v c="$1" -v v="$2" '
        /if \(\$oldversion < / { on = 1; next }
        on && /^    }$/ { exit }
        on {
            s = $0; sub(/^ +/, "", s)
            if (s == "" || s ~ /^\/\// || s == "}") next
            if (s ~ /^\$table = new xmldb_table\(/) { t = s; sub(/^[^(]*\(./, "", t); sub(/.\);$/, "", t); next }
            gsub(v, "VERSION", s)
            print c "|" (s ~ /^upgrade_/ ? "-" : t) "|" s
        }'
}

upgrade mod_quiz quiz-5.2.xml quiz-5.3.xml
upgrade assignfeedback_comments comments-5.2.xml comments-5.3.xml
upgrade mod_assign assign-5.2.xml assign-5.3.xml
upgrade assignfeedback_editpdf editpdf-5.2.xml editpdf-5.3.xml
upgrade assignfeedback_file file-5.2.xml file-5.3.xml
upgrade quizaccess_seb seb-5.2.xml seb-5.3.xml

P="$T/choice"; stub "$P" mod_choice; cp "$F/choice-install.xml" "$P/db/install.xml"
printf "<?php\nfunction choice_supports(\$f) {\n    return \$f === FEATURE_BACKUP_MOODLE2;\n}\n" > "$P/lib.php"
if python3 "$S/backup.py" "$P" >/dev/null 2>"$T/err"; then
    out=$(python3 - "$P/backup/moodle2/backup_choice_stepslib.php" "$G" <<'PY'
import re, sys
php = open(sys.argv[1]).read()
gate = php.find("if ($userinfo) {")
gated = php[gate:php.find("}", gate)] if gate >= 0 else ""
for line in open(sys.argv[2]):
    if not line.startswith("choice|"):
        continue
    _, elem, wrapper, fields, *rest = line.rstrip("\n").split("|")
    m = re.search(rf"\${elem} = new backup_nested_element\('{elem}', \['id'\], \[(.*?)\]\);", php, re.S)
    got = set(re.findall(r"'(\w+)'", m.group(1))) if m else None
    print("ok  " if got == set(fields.split()) else "FAIL", f"element {elem} field set equals core")
    if wrapper:
        w = re.search(rf"\${wrapper} = new backup_nested_element\('{wrapper}'\);", php)
        add = f"${wrapper}->add_child(${elem});" in php
        print("ok  " if w and add else "FAIL", f"element {elem} wrapped in {wrapper}")
    source = f"${elem}->set_source_table("
    isgated = source in gated
    print("ok  " if isgated == ("gated" in rest) else "FAIL", f"element {elem} userinfo gating {'on' if isgated else 'off'}")
    for ann in (r.split(":") for r in rest if ":" in r):
        print("ok  " if f"${elem}->annotate_ids('{ann[0]}', '{ann[1]}');" in php else "FAIL",
              f"element {elem} annotates {ann[0]} {ann[1]}")
PY
)
    echo "$out"; fails=$((fails + $(grep -c '^FAIL' <<<"$out")))
    for f in "$P"/backup/moodle2/*.php; do
        php -l "$f" >/dev/null 2>&1 || bad "php -l $(basename "$f")"
    done
else
    bad "backup.py on mod_choice: $(cat "$T/err")"
fi

[ "$fails" -eq 0 ] && echo "golden: all green" || echo "golden: $fails failed"
exit $((fails > 0))
