#!/usr/bin/env bash
# Drive output.py on mktemp plugins: renderable/templatable class, export_for_template, mustache Example context, test, renderer, refusals.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
S="$(cd "$(dirname "$0")/.." && pwd)"
O="$S/output.py"; G="$S/generate.py"; CI="$S/../moodle-ci/scripts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MPC="$HOME/.moodle-plugin-ci/bin/moodle-plugin-ci"; command -v moodle-plugin-ci >/dev/null && MPC=moodle-plugin-ci
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

skel() {
    mkdir -p "$T/$1"
    printf 'component: %s\nrequires: "%s"\ncopyright: 2026 onwards, Example Author <author@example.com>\n' "$2" "$1" > "$T/$1/recipe.yaml"
    python3 "$G" --target-dir "$T/$1" "$T/$1/recipe.yaml" >/dev/null 2>"$T/err" || bad "$1 skeleton: $(cat "$T/err")"
}
example() { python3 -c "import json, re, sys
m = re.search(r'Example context \(json\):\n(.*?)\n\}\}', open(sys.argv[1]).read(), re.S)
print(json.dumps(json.loads(m.group(1))))" "$1"; }

skel 4.5 mod_demo; P="$T/4.5/demo"
skel 4.1 local_demo; L="$T/4.1/demo"
cls="$P/classes/output/summary.php"; mus="$P/templates/summary.mustache"; tst="$P/tests/output/summary_test.php"
ren="$P/classes/output/renderer.php"
python3 "$O" "$P" summary --fields a:text,b:int,c:url >"$T/out" 2>&1 && [ -f "$cls" ] && [ -f "$mus" ] && [ -f "$tst" ] \
    && ok "class, template and test written" || bad "rc: $(cat "$T/out")"
grep -q '^class summary implements \\renderable, \\templatable {' "$cls" \
    && grep -qF 'public function __construct(string $a, int $b, \moodle_url $c) {' "$cls" \
    && grep -qF 'protected \moodle_url $c;' "$cls" && ok "renderable, templatable, typed constructor" || bad "class: $(cat "$cls")"
grep -qF 'public function export_for_template(\renderer_base $output): array {' "$cls" \
    && grep -qF "'a' => format_string(\$this->a)," "$cls" && grep -qF "'b' => \$this->b," "$cls" \
    && grep -qF "'c' => \$this->c->out(false)," "$cls" && ok "export_for_template: format_string / int / out(false)" \
    || bad "export: $(cat "$cls")"
[ ! -e "$ren" ] && ok "no renderer without --renderer" || bad "renderer written without --renderer"

head -2 "$mus" | grep -q '^    This file is part of Moodle' && grep -q '^    @template mod_demo/summary$' "$mus" \
    && grep -q 'GNU General Public License' "$mus" && ok "mustache: GPL header + @template" || bad "mustache head: $(head -20 "$mus")"
ctx="$(example "$mus" 2>"$T/err")"
[ "$ctx" = '{"a": "A example", "b": 1, "c": "https://example.com/view.php"}' ] \
    && ok "Example context is JSON matching the fields" || bad "Example context: $ctx $(cat "$T/err")"
grep -qF '{{{a}}}' "$mus" && grep -qF '{{b}}' "$mus" && grep -qF '<a href="{{c}}">{{c}}</a>' "$mus" \
    && ok "mustache tags: text raw, int and url escaped" || bad "mustache body: $(cat "$mus")"
src="$("$CI/msrc" 5.2 2>/dev/null || "$CI/msrc" 5.3 2>/dev/null)"
auto="$(dirname "$src")/vendor/autoload.php"; [ -f "$auto" ] || auto="$src/vendor/autoload.php"
if [ -f "$auto" ]; then
    html="$(php -r 'require $argv[1]; $m = new Mustache\Engine();
        echo $m->render(file_get_contents($argv[2]), json_decode($argv[3], true));' "$auto" "$mus" "$ctx" 2>&1)"
    grep -q '<div>A example</div>' <<<"$html" && grep -q '<div>1</div>' <<<"$html" \
        && grep -qF '<a href="https://example.com/view.php">' <<<"$html" && ! grep -q '@template' <<<"$html" \
        && ok "template renders its Example context (Mustache engine)" || bad "mustache render: $html"
else
    echo "SKIP mustache render: no Moodle vendor/ tree (msrc 5.2)"
fi
grep -qF "\$widget = new summary('A example', 1, new \\moodle_url('https://example.com/view.php'));" "$tst" \
    && grep -qF "\$this->assertSame(['a', 'b', 'c'], array_keys(\$data));" "$tst" \
    && grep -qF "\$data = \$widget->export_for_template(\$PAGE->get_renderer('core'));" "$tst" \
    && grep -q '@covers     \\mod_demo\\output\\summary' "$tst" && ok "test asserts export_for_template keys" || bad "test: $(cat "$tst")"

python3 "$O" "$P" card --fields title:text,note:string --renderer >"$T/out" 2>&1 \
    && grep -q '^class renderer extends \\plugin_renderer_base {' "$ren" \
    && grep -qF "return \$this->render_from_template('mod_demo/card', \$widget->export_for_template(\$this));" "$ren" \
    && grep -qF "'note' => s(\$this->note)," "$P/classes/output/card.php" \
    && ok "--renderer creates renderer.php with render_card(); string uses s()" || bad "renderer: $(cat "$T/out" "$ren")"
python3 "$O" "$P" banner --fields text --renderer >"$T/out" 2>&1 \
    && grep -q 'public function render_card(card $widget): string {' "$ren" \
    && grep -q 'public function render_banner(banner $widget): string {' "$ren" \
    && [ "$(grep -c '^class renderer' "$ren")" = 1 ] && [ "$(tail -c 2 "$ren")" = "}" ] \
    && ok "--renderer merges a second method, field type defaults to text" || bad "renderer merge: $(cat "$T/out" "$ren")"
python3 "$O" "$L" status --fields label:text,total:int >"$T/out" 2>&1 \
    && grep -q '^namespace local_demo\\output;' "$L/classes/output/status.php" \
    && grep -q '@template local_demo/status' "$L/templates/status.mustache" && ok "local_ plugin output class" \
    || bad "local_: $(cat "$T/out")"

lintfail=0; n=0
for f in "$P"/classes/output/*.php "$P"/tests/output/*.php "$L"/classes/output/*.php "$L"/tests/output/*.php; do
    n=$((n + 1)); php -l "$f" >/dev/null 2>&1 || { lintfail=1; bad "php -l $f: $(php -l "$f" 2>&1)"; }
done
[ "$lintfail" = 0 ] && ok "php -l clean ($n files)"
for p in "$P" "$L"; do
    out="$("$CI/mrules" "$p" 2>&1)"; rc=$?
    [ "$rc" = 0 ] && grep -q 'mrules: 0 FAIL, 0 WARN' <<<"$out" && ok "mrules 0 FAIL ${p#"$T"/}" || bad "mrules rc=$rc: $out"
    if [ -x "$MPC" ] || command -v "$MPC" >/dev/null; then
        out="$(nice -n 19 "$MPC" codechecker --max-warnings 0 "$p" 2>&1)"; rc=$?
        [ "$rc" = 0 ] && ok "codechecker 0/0 ${p#"$T"/}" || bad "$p codechecker rc=$rc: $(grep -E '\| (ERROR|WARNING) \|' <<<"$out" | head -3)"
    else
        echo "SKIP codechecker: moodle-plugin-ci absent"
    fi
done

snap() { find "$P" -type f -exec md5sum {} + | sort; }
before="$(snap)"
refuse() {
    local label="$1" want="$2"; shift 2
    python3 "$O" "$@" >"$T/out" 2>&1; local rc=$?
    [ "$rc" = 1 ] && grep -q "$want" "$T/out" && [ "$before" = "$(snap)" ] \
        && ok "$label refused rc 1, nothing written" || bad "$label rc=$rc: $(cat "$T/out")"
}
refuse "name 'Bad'" "bad name 'Bad'" "$P" Bad --fields a
refuse "name 'renderer'" "clashes with the plugin renderer" "$P" renderer --fields a
refuse "field '1x'" "bad field name '1x'" "$P" other --fields 1x:int
refuse "type 'date'" "bad field type 'date'" "$P" other --fields a:date
refuse "duplicate field" "duplicate field 'a'" "$P" other --fields a,a:int
refuse "existing summary" "summary.php already exists" "$P" summary --fields a
cards="$P/classes/output/card.php $P/templates/card.mustache $P/tests/output/card_test.php"
mkdir "$T/cards"; mv $cards "$T/cards/"; before="$(snap)"
refuse "existing render_card()" "render_card() already exists" "$P" card --fields a --renderer
mv "$T/cards/card.php" "$P/classes/output/"; mv "$T/cards/card.mustache" "$P/templates/"
mv "$T/cards/card_test.php" "$P/tests/output/"; before="$(snap)"
refuse "PHP keyword 'list'" "does not parse, nothing written" "$P" list --fields a
touch "$P/renderer.php"; before="$(snap)"
refuse "legacy renderer.php" "legacy renderer" "$P" other --fields a --renderer
python3 "$O" "$P" other >"$T/out" 2>&1 && bad "missing --fields accepted" || ok "missing --fields refused"
python3 "$O" "$T/none" other --fields a >"$T/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'has no version.php' "$T/out" && ok "no version.php refused rc 1" || bad "no version rc=$rc: $(cat "$T/out")"

[ "$fails" -eq 0 ] && echo "PASS output.test.sh" || { echo "FAIL output.test.sh ($fails)"; exit 1; }
