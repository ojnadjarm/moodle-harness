#!/usr/bin/env bash
# The 5 Moodle version tables agree: branches, requires = branching date x 100, PHP floors, install.sh PHP >= floor.
# Usage: versions.test.sh [--refresh|--selftest]   (--refresh rebuilds fixtures/environment-php.tsv from the newest non-Vass env)
# Exit: 0 green, 1 a mismatch or bad row (file:line printed), 2 a table or the env not found.
set -uo pipefail
SKILLS="${VERSIONS_SKILLS:-$(cd "$(dirname "$0")/../.." && pwd)}"

selftest() {
    local tmp self="$0" fails=0 out rc
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    mkdir -p "$tmp/s/moodle-ci/scripts" "$tmp/s/moodle-ci/tests/fixtures" "$tmp/s/moodle-pluginskel" "$tmp/s/moodle-install"
    cp "$SKILLS/moodle-ci/scripts/mphpcompat" "$SKILLS/moodle-ci/scripts/mci-workflow" "$tmp/s/moodle-ci/scripts/"
    cp "$SKILLS/moodle-pluginskel/generate.py" "$tmp/s/moodle-pluginskel/"
    cp "$SKILLS/moodle-install/install.sh" "$tmp/s/moodle-install/"
    cp "$SKILLS/moodle-ci/tests/fixtures/environment-php.tsv" "$tmp/s/moodle-ci/tests/fixtures/"
    local fx="$tmp/s/moodle-ci/tests/fixtures/environment-php.tsv" inst="$tmp/s/moodle-install/install.sh"
    cp "$fx" "$tmp/fx.orig"; cp "$inst" "$tmp/inst.orig"
    reset() { cp "$tmp/fx.orig" "$fx"; cp "$tmp/inst.orig" "$inst"; }
    run() { out="$(VERSIONS_SKILLS="$tmp/s" MOODLE_ENVS="${ENVS:-$tmp/envs}" bash "$self" "$@" 2>&1)"; rc=$?; }
    check() {
        local name="$1" want="$2" pat="$3"
        if [ "$rc" -eq "$want" ] && grep -qE -- "$pat" <<<"$out" && ! grep -q Traceback <<<"$out"; then
            echo "ok   $name"
        else
            echo "FAIL $name: rc $rc (want $want), output: $out"; fails=$((fails + 1))
        fi
        reset
    }
    run; check "copied tables green" 0 '^PASS'
    ENVS=/nonexistent run --refresh; check "refresh, env dir missing" 2 '^MISSING /nonexistent$'
    mkdir -p "$tmp/envs/5.3/www"; run --refresh; check "refresh, no environment.xml" 2 '^MISSING .*environment.xml'
    mkdir -p "$tmp/envs/5.3/www/admin"
    printf '<MOODLE version="5.3"><PHP version="8.3"/></MOODLE>\n' >"$tmp/envs/5.3/www/admin/environment.xml"
    run --refresh; check "refresh from a fake env" 0 'refreshed .*1 rows from 5.3'
    printf '<MOODLE version="3.9"><PHP version="7.2"/></MOODLE>\n' >"$tmp/envs/5.3/www/admin/environment.xml"
    run --refresh; cmp -s "$fx" "$tmp/fx.orig" || rc=99
    check "refresh, 0 rows keeps the fixture" 1 'environment.xml: 0 rows'
    printf '<MOODLE version="5.3">\xff</MOODLE>\n' >"$tmp/envs/5.3/www/admin/environment.xml"
    run --refresh; check "refresh, non-UTF-8 xml" 1 'environment.xml: not UTF-8'
    chmod 000 "$tmp/envs"; run --refresh; chmod 755 "$tmp/envs"; check "refresh, unreadable env dir" 2 '^MISSING .*/envs$'
    local dup; dup="$(grep -v '^#' "$fx" | head -1)"; printf '%s\n' "$dup" >>"$fx"
    run; check "duplicate fixture row" 1 "environment-php.tsv:$(wc -l <"$tmp/fx.orig" | awk '{print $1 + 1}'): duplicate"
    printf '\xff\n' >>"$fx"; run; check "non-UTF-8 fixture" 1 'environment-php.tsv: not UTF-8'
    printf '5.4 8.4\n' >>"$fx"; run; check "malformed fixture row" 1 "environment-php.tsv:$(wc -l <"$tmp/fx.orig" | awk '{print $1 + 1}'): bad row"
    sed -i 's/^\(\s*5\.3)\) branch=/\1  branch=/' "$inst"; run; check "install.sh double space" 0 '^PASS'
    local n; n="$(grep -n '^\s*5\.3) branch=' "$inst" | cut -d: -f1)"
    sed -i 's/^\(\s*5\.3) branch=[^;]*\);/\1/' "$inst"; run; check "install.sh unparsed row" 1 "install.sh:$n: bad row"
    rm "$inst"; run; check "install.sh missing" 2 '^MISSING .*install.sh'
    echo "$([ "$fails" -eq 0 ] && echo PASS || echo FAIL) selftest, $fails failed"
    [ "$fails" -eq 0 ]
}
[ "${1:-}" = "--selftest" ] && { selftest; exit; }

exec python3 - "$SKILLS" "${MOODLE_ENVS:-$HOME/moodle-envs}" "$@" <<'PY'
import os, re, sys

skills, envs, args = sys.argv[1], sys.argv[2], sys.argv[3:]
fixture = f"{skills}/moodle-ci/tests/fixtures/environment-php.tsv"
files = {
    "mphpcompat": f"{skills}/moodle-ci/scripts/mphpcompat",
    "mci-workflow": f"{skills}/moodle-ci/scripts/mci-workflow",
    "generate.py": f"{skills}/moodle-pluginskel/generate.py",
    "install.sh": f"{skills}/moodle-install/install.sh",
}
bad = []

def vkey(v):
    return tuple(int(p) for p in v.split("."))

def missing(msg):
    print(f"MISSING {msg}")
    sys.exit(2)

def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except UnicodeDecodeError:
        print(f"FAIL {path}: not UTF-8")
        sys.exit(1)
    except OSError:
        missing(path)

def refresh():
    if not os.path.isdir(envs):
        missing(envs)
    try:
        names = os.listdir(envs)
    except OSError:
        missing(envs)
    vers = [d for d in names if re.fullmatch(r"\d+\.\d+", d) and d != "4.5" and "vass" not in d]
    for d in sorted(vers, key=vkey, reverse=True):
        for sub in ("www/public/admin", "www/admin"):
            xml = f"{envs}/{d}/{sub}/environment.xml"
            if os.path.isfile(xml):
                text = read(xml)
                rows = re.findall(r'<MOODLE version="(\d+\.\d+)"[^>]*>.*?<PHP version="(\d+\.\d+)', text, re.S)
                rows = [(m, p) for m, p in rows if vkey(m) >= (4, 0)]
                if not rows:
                    print(f"FAIL {xml}: 0 rows, {fixture} kept")
                    sys.exit(1)
                with open(fixture, "w") as f:
                    f.write(f"# moodle\tphp_min  (from ~/moodle-envs/{d}/{sub}/environment.xml; versions.test.sh --refresh)\n")
                    f.writelines(f"{m}\t{p}\n" for m, p in rows)
                print(f"refreshed {fixture}: {len(rows)} rows from {d}")
                sys.exit(0)
    missing(f"environment.xml in a non-Vass env under {envs}")

if args == ["--refresh"]:
    refresh()
elif args:
    sys.exit("usage: versions.test.sh [--refresh]")

def line(text, pos):
    return text.count("\n", 0, pos) + 1

def pydict(name, key):
    text = read(files[name])
    m = re.search(rf"^{key}\s*=\s*\{{(.*?)\}}", text, re.S | re.M)
    if not m:
        print(f"MISSING {files[name]}: no {key} table")
        sys.exit(2)
    return {k: (v.strip('"'), f"{files[name]}:{line(text, m.start(1) + e.start())}")
            for e in re.finditer(r'"(\d+\.\d+)":\s*("?[\d.]+"?)', m.group(1)) for k, v in [e.groups()]}

branching = {k: (int(v), w) for k, (v, w) in pydict("mci-workflow", "BRANCHING").items()}
phpmin = pydict("mci-workflow", "PHP_MIN")
requires = {k: (int(v), w) for k, (v, w) in pydict("generate.py", "REQUIRES").items()}

text = read(files["install.sh"])
install = {}
for m in re.finditer(r"^[ \t]*(\d+\.\d+)\)(.*)$", text, re.M):
    where = f"{files['install.sh']}:{line(text, m.start())}"
    e = re.match(r"\s*branch=(\S+?);\s*phpdef=([\d.]+);", m.group(2))
    if e and m.group(1) in install:
        bad.append(f"{where}: duplicate {m.group(1)} (first {install[m.group(1)][2]})")
    elif e:
        install[m.group(1)] = (e.group(1), e.group(2), where)
    else:
        bad.append(f"{where}: bad row")

text = read(files["mphpcompat"])
m = re.search(r"for row in ((?:\d+:[\d.]+\s*)+);", text)
if not m:
    print(f"MISSING {files['mphpcompat']}: no floor table")
    sys.exit(2)
where = f"{files['mphpcompat']}:{line(text, m.start())}"
compat = [(int(r), p) for r, p in (x.split(":") for x in m.group(1).split())]

text = read(fixture)
env = {}
for n, row in enumerate(text.splitlines(), 1):
    if row and not row.startswith("#"):
        cols = row.split("\t")
        if len(cols) != 2 or not all(re.fullmatch(r"\d+\.\d+", c) for c in cols):
            bad.append(f"{fixture}:{n}: bad row")
            continue
        if cols[0] in env:
            bad.append(f"{fixture}:{n}: duplicate {cols[0]} (first {env[cols[0]][1]})")
            continue
        env[cols[0]] = (cols[1], f"{fixture}:{n}")

tables = {"BRANCHING": branching, "PHP_MIN": phpmin, "REQUIRES": requires, "install.sh": install, "fixture": env}
optional = {"4.0": ("BRANCHING", "PHP_MIN", "install.sh")}
allv = set().union(*tables.values())
for v in sorted(allv, key=vkey):
    for name, t in tables.items():
        if v not in t and name not in optional.get(v, ()):
            src = next(t2[v][-1] for t2 in tables.values() if v in t2)
            bad.append(f"{src}: {v} missing from {name}")

for v, (date, w) in branching.items():
    if v in requires and requires[v][0] != date * 100:
        bad.append(f"{requires[v][1]}: requires {requires[v][0]} != BRANCHING {date} x 100 ({w})")
    if install.get(v) and install[v][0] != "MOODLE_%d%02d_STABLE" % vkey(v):
        bad.append(f"{install[v][2]}: {v} branch {install[v][0]}")

reqvals = {r for r, _ in requires.values()}
for r, _ in compat:
    if r not in reqvals:
        bad.append(f"{where}: threshold {r} is no REQUIRES value")

def floor(req):
    out = None
    for r, p in compat:
        if req >= r:
            out = p
    return out

for v in sorted(requires, key=vkey):
    req, w = requires[v]
    floors = {"mphpcompat": (floor(req), where)}
    if v in phpmin:
        floors["PHP_MIN"] = phpmin[v]
    if v in env:
        floors["fixture"] = env[v]
    if len({p for p, _ in floors.values()}) > 1:
        bad.append(f"{v} PHP floor differs: " + ", ".join(f"{k} {p} ({src})" for k, (p, src) in floors.items()))
    if v in install and v in env and vkey(install[v][1]) < vkey(env[v][0]):
        bad.append(f"{install[v][2]}: {v} phpdef {install[v][1]} < floor {env[v][0]}")

for b in bad:
    print(f"FAIL {b}")
print(f"{'FAIL' if bad else 'PASS'} {len(allv)} versions, {len(bad)} mismatches across 5 tables + fixture")
sys.exit(1 if bad else 0)
PY
