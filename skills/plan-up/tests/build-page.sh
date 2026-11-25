# build-page.sh: Markdown in, the built page's DATA out.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

build() { run python3 "$here/../scripts/build-page.py" "$@"; }
page_data() { sed -n 's/^const DATA = \(.*\);$/\1/p' "$1" | jq -S .; }

# render [--fake-layout <js>] <html>: the built page run in node on a fake
# page, with text 7 px wide per character. Prints what the Review panel
# draws: one line per element of each Change map, then one line per Files
# row. --fake-layout runs <js> in place of the page's layout.js.
render() {
  run node - "$@" <<'EOF'
const fs = require('node:fs'), vm = require('node:vm');
const args = process.argv.slice(2);
const fake = args[0] === '--fake-layout' ? fs.readFileSync(args.splice(0, 2)[1], 'utf8') : null;
const html = fs.readFileSync(args[0], 'utf8');
class Fake {
  constructor(tag) { this.tag = tag; this.attrs = {}; this.children = []; this.listeners = {}; this.dataset = {}; this.text = '';
    this.classList = { toggle() {}, add() {}, remove() {} }; }
  get nodeType() { return 1; }
  append(...kids) { this.children.push(...kids); }
  setAttribute(k, v) {
    this.attrs[k] = String(v);
    if (k.startsWith('data-')) this.dataset[k.slice(5).replace(/-(\w)/g, (_, c) => c.toUpperCase())] = String(v);
  }
  addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); }
  set className(v) { this.attrs.class = v; }
  get className() { return this.attrs.class || ''; }
  set innerHTML(v) { this.children = []; }
  set textContent(v) { this.text = String(v); }
  get textContent() { return this.text + this.children.map((k) => k.nodeType === 3 ? k.data : k.textContent).join(''); }
  elements() { return this.children.filter((k) => k.nodeType === 1); }
  querySelectorAll(sel) {
    const tag = sel.match(/^\w+/)[0], got = [];
    const walk = (n) => { for (const k of n.elements()) { if (k.tag === tag) got.push(k); walk(k); } };
    walk(this);
    return got;
  }
  scrollIntoView() {}
  getContext() { return { measureText: (s) => ({ width: s.length * 7 }) }; }
}
const byId = {};
const document = {
  createElement: (tag) => new Fake(tag), createElementNS: (_, tag) => new Fake(tag),
  createTextNode: (data) => ({ nodeType: 3, data }), querySelector: (sel) => byId[sel] ||= new Fake(sel),
  addEventListener() {}, body: {}, title: '',
};
const page = { document, window: { scrollTo() {} }, history: { replaceState() {} }, location: { hash: '' },
  navigator: {}, getComputedStyle: () => ({ fontFamily: '' }) };
vm.createContext(page);
for (const [, code] of html.matchAll(/<script>([\s\S]*?)<\/script>/g))
  vm.runInContext(fake !== null && /^const PlanLayout\b/m.test(code) ? fake : code, page);
const review = byId['#panels'].elements().find((s) => s.dataset.id === 'review');
const find = (n, test, got = []) => { for (const k of n.elements()) { if (test(k)) got.push(k); find(k, test, got); } return got; };
const maps = find(review, (k) => k.tag === 'svg' && k.attrs['aria-label'] === 'Change map');
const rows = find(review, (k) => /\bft-row\b/.test(k.className));
for (const svg of maps) {
  const each = (n) => { for (const k of n.elements()) {
    const attrs = Object.keys(k.attrs).sort().map((a) => `${a}=${k.attrs[a]}`).join(' ');
    console.log(`${k.tag} ${attrs}${k.text ? ' | ' + k.text.replace(/\n/g, '\\n') : ''}`);
    each(k);
  } };
  console.log(`svg ${svg.attrs.viewBox}`);
  each(svg);
}
for (const row of rows) console.log([row.className, ...row.elements().map((k) => k.textContent)].join(' | '));
EOF
}

t_build_ticket() {
  T="$(mktemp -d)"
  cp "$here/build-page/ticket.md" "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq stdout "page: $T/plan-acme-shop-42.html" "$out"
  eq DATA "$(jq -S . "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_run() {
  T="$(mktemp -d)"
  cp "$here/build-page/run.md" "$T/plan-acme-shop-71-run.md"
  build "$T/plan-acme-shop-71-run.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S . "$here/build-page/run.json")" "$(page_data "$T/plan-acme-shop-71-run.html")"
}

t_build_run_one() {
  T="$(mktemp -d)"
  cp "$here/build-page/run-one.md" "$T/plan-acme-shop-75-run.md"
  build "$T/plan-acme-shop-75-run.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S . "$here/build-page/run-one.json")" "$(page_data "$T/plan-acme-shop-75-run.html")"
}

t_build_none_map() {
  T="$(mktemp -d)"
  cp "$here/build-page/none-map.md" "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S . "$here/build-page/none-map.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

# chat_plan <file> [<brief>]: ticket.md with no issue number, and <brief>
# (default: a Task and two Done-when lines) as its last block.
chat_plan() {
  sed 's/^# Plan: #42 /# Plan: /' "$here/build-page/ticket.md" > "$1"
  printf '\n%s\n' "${2-$'## Brief\nTask: staff download the orders list as CSV\nDone when:\n- the Export menu offers CSV\n- a note with a newline stays in one field'}" >> "$1"
}

t_build_plan_check_last() {
  # Given: one chat plan, and the same plan with a Plan check block after its Brief
  T="$(mktemp -d)"
  chat_plan "$T/plan-acme-shop-chat-orders-csv.md"
  chat_plan "$T/plan-acme-shop-chat-orders-csv-2.md"
  printf '\n## Plan check\nBy: plan-correctness-checker · 1 round\n- Correctness F1 the export misses the old screen. Done: fixed (S2)\n' >> "$T/plan-acme-shop-chat-orders-csv-2.md"
  # When
  build "$T/plan-acme-shop-chat-orders-csv.md"
  eq "plain exit" 0 "$code"
  build "$T/plan-acme-shop-chat-orders-csv-2.md"
  # Then
  eq "checked exit" 0 "$code"
  eq DATA "$(page_data "$T/plan-acme-shop-chat-orders-csv.html")" "$(page_data "$T/plan-acme-shop-chat-orders-csv-2.html")"
}

t_build_chat() {
  T="$(mktemp -d)"
  chat_plan "$T/plan-acme-shop-chat-orders-csv.md"
  build "$T/plan-acme-shop-chat-orders-csv.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S 'del(.issue.number, .issue.url, .layers[0].issue.number, .layers[0].issue.url)' "$here/build-page/ticket.json")" \
    "$(page_data "$T/plan-acme-shop-chat-orders-csv.html")"
}

bad_chat() {
  T="$(mktemp -d)"
  chat_plan "$T/plan-acme-shop-chat-orders-csv.md" "$1"
  build "$T/plan-acme-shop-chat-orders-csv.md"
  eq exit 1 "$code"
  eq stdout "$2" "$out"
  [ ! -e "$T/plan-acme-shop-chat-orders-csv.html" ]
}

t_build_chat_no_brief() {
  bad_chat '' 'brief: a chat plan needs a `## Brief` block'
}

t_build_chat_brief_gaps() {
  bad_chat $'## Brief\nTask:\nDone when:\n- ' "$(printf 'brief: no `Task:` line\nbrief: no `Done when:` list')"
}

bad_ticket() {
  T="$(mktemp -d)"
  sed "$1" "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 1 "$code"
  eq stdout "$2" "$out"
  eq stderr "" "$err"
  [ ! -e "$T/plan-acme-shop-42.html" ]
  [ ! -e "$T/plan-acme-shop-42.html.tmp" ]
}

t_build_perf() {
  T="$(mktemp -d)"
  cp "$here/build-page/perf.md" "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq perf '{"before":"1200 ms, median of 5, spread 1150 to 1260 ms","command":"pnpm bench orders","metric":"p95 of GET /orders, ms","pass rule":"median of 5 runs in turns, base and head; head under 300 ms"}' \
    "$(page_data "$T/plan-acme-shop-42.html" | jq -c .layers[0].perf)"
}

t_build_files() {
  T="$(mktemp -d)"
  cp "$here/build-page/files.md" "$T/plan-acme-shop-44.md"
  build "$T/plan-acme-shop-44.md"
  eq exit 0 "$code"
  eq files '[{"change":"new","from":null,"generated":false,"note":"writes one order as a CSV row","path":"src/orders/csv.ts","slices":[1]},{"change":"edited","from":null,"generated":false,"note":"streams CSV beside JSON","path":"src/orders/export.ts","slices":[1,2]},{"change":"deleted","from":null,"generated":false,"note":"the old JSON-only path","path":"src/orders/json-only.ts","slices":[1]},{"change":"moved","from":"src/orders/format.ts","generated":false,"note":"","path":"src/orders/formats/json.ts","slices":[2]},{"change":"edited","from":null,"generated":false,"note":"+ csv and empty cases","path":"src/orders/export.test.ts","slices":[1,2]},{"change":"edited","from":null,"generated":true,"note":"","path":"src/orders/__snapshots__/export.test.ts.snap","slices":[2]},{"change":"edited","from":null,"generated":false,"note":"CSV next to JSON","path":"src/README.md","slices":[1]}]' \
    "$(page_data "$T/plan-acme-shop-44.html" | jq -c .layers[0].files)"
}

bad_perf() {
  T="$(mktemp -d)"
  sed "$1" "$here/build-page/perf.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 1 "$code"
  eq stdout "$2" "$out"
  eq stderr "" "$err"
  [ ! -e "$T/plan-acme-shop-42.html" ]
  [ ! -e "$T/plan-acme-shop-42.html.tmp" ]
}

t_build_perf_no_pass() {
  bad_perf '/^Pass rule:/d' 'perf: layer 1 has no `Pass rule:` line'
}

t_build_perf_no_block() {
  bad_ticket 's/^# Plan: #42 \[feat\]/# Plan: #42 [perf]/' 'perf: layer 1 is a `[perf]` ticket with no `## Perf` block'
}

t_build_run_perf_no_block() {
  bad_run 's/#73 Add a member/#73 [perf] Add a member/' 'perf: layer 2 is a `[perf]` ticket with no `## Perf` block'
}

t_build_no_review() {
  bad_ticket '/^## Review$/d' 'not a plan-up .md: plan-acme-shop-42.md'
}

t_build_no_schema() {
  bad_ticket '/^  Schema:/d' 'review: `Blast radius` has no `Schema` line'
}

t_build_name_limit() {
  bad_ticket 's/| Orders page |/| Orders page for staff |/' 'change map: M1 part name is 21 characters, the limit is 20'
}

t_build_no_summary() {
  bad_ticket '/^## Summary$/ { N; d; }' 'summary: layer 1 has no `## Summary` block'
}

t_build_blank_before() {
  bad_ticket 's/  Before:   none/  Before:/' 'walk 1: the .md `Before` line is blank'
}

t_build_no_proved_date() {
  bad_ticket 's/, 2026-10-04. Used by S1././' 'proved: P1 needs `, <YYYY-MM-DD>. Used by <refs>.` at its end'
}

t_build_odd_tick() {
  bad_ticket 's/- O1 orders export as PDF/&`/' 'layers[0].out[0]: odd number of backticks, one shows raw: orders export as PDF`'
}

t_build_no_date() {
  bad_ticket 's/Size: size\/M    Date: 2026-10-04/Size: size\/M/' 'head: no `Date: YYYY-MM-DD` line under `# Plan:`'
}

t_build_no_head() {
  bad_ticket '/^# Plan:/d' 'head: no `# Plan:` line'
}

t_build_no_size() {
  bad_ticket 's/Size: size\/M    //' 'head: a ticket needs `Size: size/<x>`'
}

t_build_summary_limit() {
  bad_ticket '/^## Summary$/a\
one\
two\
three' 'summary: layer 1 has 4 lines, the limit is 3'
}

t_build_no_before() {
  bad_ticket '/^  Before:/d' 'walk 1: the .md has no `Before` line'
}

t_build_later_before() {
  bad_ticket 's/Before:   none/Before:   as walk 2/' 'walk 1: `as walk 2` must name an earlier walk of its layer whose `Before` names steps'
}

t_build_no_at() {
  bad_ticket 's/`src\/web\/orders.tsx:12`//' 'change map: M1 has no files and no slice in `At`'
}

t_build_bad_grid() {
  bad_ticket 's/| 0,1 |/| -1,1 |/' 'change map: M1 grid `-1,1` is not `column,row` with both 0 or more'
}

t_build_same_grid() {
  bad_ticket 's/| 2,1 |/| 1,1 |/' 'change map: M3 and M2 share the grid cell 1,1'
}

t_build_job_limit() {
  bad_ticket 's/asks for an export/asks for an export with all rows/' 'change map: M1 job is 32 characters, the limit is 30'
}

t_build_label_limit() {
  bad_ticket 's/asks for CSV/asks for CSV with all rows/' 'change map: flow M1 → M2 label is 26 characters, the limit is 20'
}

t_build_bad_flow() {
  bad_ticket 's/- M1 → M2: asks for CSV (new)/- M1 sends CSV to M2/' 'change map: a flow line is not `- M1 → M2: what moves (change)`: - M1 sends CSV to M2
change map: M1 has no change and no changed flow touches it; leave it out'
}

t_build_unknown_ref() {
  bad_ticket 's/M2 → M3/M2 → M4/' 'change map: flow M2 → M4 names M4, which is not a part of this map
change map: M3 has no change and no changed flow touches it; leave it out'
}

t_build_run_one_review() {
  T="$(mktemp -d)"
  sed '/^## Layer /,$ { /^## Review$/,/^## Summary$/ { /^## Summary$/!d; }; }' "$here/build-page/run-one.md" > "$T/plan-acme-shop-75-run.md"
  build "$T/plan-acme-shop-75-run.md"
  eq exit 1 "$code"
  eq stdout 'review: the .md has 1 `## Review` block(s), a run of 1 layer needs 2' "$out"
  [ ! -e "$T/plan-acme-shop-75-run.html" ]
}

t_build_stack_count() {
  T="$(mktemp -d)"
  sed '/^| 2 | #73 /d' "$here/build-page/run.md" > "$T/plan-acme-shop-71-run.md"
  build "$T/plan-acme-shop-71-run.md"
  eq exit 1 "$code"
  eq stdout 'stack: 1 rows, 2 `## Layer` headings' "$out"
  [ ! -e "$T/plan-acme-shop-71-run.html" ]
}

t_build_preserves_old() {
  T="$(mktemp -d)"
  cp "$here/build-page/ticket.md" "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  cp "$T/plan-acme-shop-42.html" "$T/old.html"
  sed '/^  Schema:/d' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 1 "$code"
  eq stdout 'review: `Blast radius` has no `Schema` line' "$out"
  cmp "$T/old.html" "$T/plan-acme-shop-42.html"
  [ ! -e "$T/plan-acme-shop-42.html.tmp" ]
}

t_build_all_problems() {
  bad_ticket '/^  Schema:/d; s/- O1 orders export as PDF/&`/' 'review: `Blast radius` has no `Schema` line
layers[0].out[0]: odd number of backticks, one shows raw: orders export as PDF`'
}

t_build_wrapped_text() {
  T="$(mktemp -d)"
  sed 's/Run: pnpm dev          UI: web/Run: env URL=http:\/\/localhost:3000 pnpm dev          UI: web/;
    s/Standards: the code/Standards: the\n  code/;
    s/- P1 csv-stringify/- P1 CSV: csv-stringify/;
    s/streamed three rows in a temp folder, /streamed three rows in a temp folder,\n  /;
    s/orders export as CSV |/orders export as CSV \\| JSON |/;
    s/notes may contain newlines. If wrong:/notes may contain newlines.\n    If wrong:/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.facts.run = "env URL=http://localhost:3000 pnpm dev" |
    .proved[0].fact = "CSV: csv-stringify keeps a note with a newline whole" |
    .layers[0].proof[0].line = "orders export as CSV | JSON"' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_script_text() {
  T="$(mktemp -d)"
  sed 's/orders export as PDF/orders export as <\/script> PDF/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[0].out[0] = "orders export as </script> PDF"' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
  has escaped '<\/script>' "$(sed -n '/^const DATA = /p' "$T/plan-acme-shop-42.html")"
}

t_build_no_bend() {
  T="$(mktemp -d)"
  run grep -ci bend "$here/../assets/shell.html" "$here/../../../shared/plan-page.md"
  eq stdout "$here/../assets/shell.html:0
$here/../../../shared/plan-page.md:0" "$out"
}

t_build_earlier_seam() {
  T="$(mktemp -d)"
  sed 's/`src\/members.ts:10`, the public command/layer 1, slice 2, the public command/' "$here/build-page/run.md" > "$T/plan-acme-shop-71-run.md"
  build "$T/plan-acme-shop-71-run.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[1].seams[0].at = "layer 1, slice 2"' "$here/build-page/run.json")" "$(page_data "$T/plan-acme-shop-71-run.html")"
}

t_build_mixed_at() {
  T="$(mktemp -d)"
  sed 's/`src\/web\/orders.tsx:12` |/`src\/web\/orders.tsx:12`, src\/types.ts:7, S2 |/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.maps[0].parts[0].at = ["src/web/orders.tsx:12", "src/types.ts:7", "S2"]' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_multiple_proofs() {
  T="$(mktemp -d)"
  sed 's/Slice 1, proves #1:/Slice 1, proves #1 and #2:/;
    s/Walk 1, proves #1$/Walk 1, proves #1 and #2/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[0].slices[0].proves = [1, 2] |
    .layers[0].walks[0].proves = [1, 2]' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_serial_comma_proofs() {
  # Given: slice 1 and walk 1 prove three lines, with a serial comma
  T="$(mktemp -d)"
  sed 's/Slice 1, proves #1:/Slice 1, proves #1, #2, and #3:/;
    s/Walk 1, proves #1$/Walk 1, proves #1, #2, and #3/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  # When
  build "$T/plan-acme-shop-42.md"
  # Then
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[0].slices[0].proves = [1, 2, 3] |
    .layers[0].walks[0].proves = [1, 2, 3]' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_video_one_walk() {
  # Given: video 1 shows one walk, as `shows walk 9`
  T="$(mktemp -d)"
  sed 's/Video 1, Setup of walk 1, shows walks 1/Video 1, Setup of walk 9, shows walk 9/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  # When
  build "$T/plan-acme-shop-42.md"
  # Then
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[0].videos[0].walks = [9] | .layers[0].videos[0].setup = "walk 9" |
    .layers[0].videos[0].title = "Setup of walk 9"' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_video_two_walks() {
  # Given: video 1 shows two walks, as `shows walks 1, 3`
  T="$(mktemp -d)"
  sed 's/shows walks 1$/shows walks 1, 3/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  # When
  build "$T/plan-acme-shop-42.md"
  # Then
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[0].videos[0].walks = [1, 3]' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_at_comma() {
  T="$(mktemp -d)"
  sed 's/`src\/web\/orders.tsx:12` |/`src\/web\/orders,v2.tsx:12`, `src\/db\/orders,v2.ts:4`, src\/types.ts:7, S2 |/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.maps[0].parts[0].at = ["src/web/orders,v2.tsx:12", "src/db/orders,v2.ts:4", "src/types.ts:7", "S2"]' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_no_file_changes() {
  bad_ticket '/^## File changes$/,/^$/d' 'file changes: layer 1 has no `## File changes` block'
}

t_build_run_no_file_changes() {
  bad_run '/^## Layer 2/,$ { /^## File changes$/,$d; }' 'file changes: layer 2 has no `## File changes` block'
}

t_build_file_unknown_change() {
  bad_ticket 's/| edited | S1 | CSV next to JSON |/| changed | S1 | CSV next to JSON |/' \
    'file changes: layer 1 `src/README.md` change `changed` is not new, edited, deleted, or moved'
}

t_build_file_moved_one_path() {
  bad_ticket 's/| edited | S1 | CSV next to JSON |/| moved | S1 | CSV next to JSON |/' \
    'file changes: layer 1 `src/README.md` is moved and needs `<old> → <new>`'
}

t_build_file_arrow_not_moved() {
  bad_ticket 's/^| `src\/README.md` |/| `src\/docs.md` → `src\/README.md` |/' \
    'file changes: layer 1 `src/README.md` has `→`, and only a moved row has it'
}

t_build_file_no_slice() {
  bad_ticket 's/| edited | S1 | CSV next to JSON |/| edited |  | CSV next to JSON |/' \
    'file changes: layer 1 `src/README.md` names no slice'
}

t_build_file_missing_slice() {
  bad_ticket 's/| edited | S1 | CSV next to JSON |/| edited | S3 | CSV next to JSON |/' \
    'file changes: layer 1 `src/README.md` names S3; layer 1 has no slice 3'
}

t_build_file_slice_does_not_name_it() {
  bad_ticket 's/| edited | S1 | CSV next to JSON |/| edited | S2 | CSV next to JSON |/' \
    'file changes: layer 1 `src/README.md` names S2, and slice 2 does not name it'
}

t_build_file_listed_twice() {
  bad_ticket '/^| `src\/README.md`/p' 'file changes: layer 1 `src/README.md` is listed twice'
}

bad_run() {
  T="$(mktemp -d)"
  sed "$1" "$here/build-page/run.md" > "$T/plan-acme-shop-71-run.md"
  build "$T/plan-acme-shop-71-run.md"
  eq exit 1 "$code"
  eq stdout "$2" "$out"
  eq stderr "" "$err"
  [ ! -e "$T/plan-acme-shop-71-run.html" ]
  [ ! -e "$T/plan-acme-shop-71-run.html.tmp" ]
}

t_build_stack_identity() {
  bad_run 's/## Layer 2 ·/## Layer 3 ·/' 'stack: layer heading 3 is not layer 2'
  bad_run 's/| 2 | #73 /| 3 | #73 /' 'stack: row 2 names layer 3, needs 2'
  bad_run 's/| 2 | #73 /| two | #73 /' 'stack: row 2 names layer two, needs 2'
  bad_run 's/| 2 | #73 /| 2 | #74 /' 'stack: row 2 issue `#74 Add a member` is not `#73 Add a member`'
  bad_run 's/| #73 Add a member |/| #73 Join a team |/' 'stack: row 2 issue `#73 Join a team` is not `#73 Add a member`'
  bad_run 's/| layer 1 | S | 2 |/| layer 1 | S |/' 'stack: row 2 has 4 cells, needs 5'
  bad_run 's/| layer 1 | S | 2 |/| | S | 2 |/' 'stack: row 2 has no base'
  bad_run 's/| layer 1 | S | 2 |/| layer 1 | tiny | 2 |/' 'stack: row 2 size `tiny` is not XS, S, M, L, or XL'
  bad_run 's/| layer 1 | S | 2 |/| layer 1 | S | two |/' 'stack: row 2 points `two` is not an integer'
}

t_build_bad_record_headings() {
  bad_ticket 's/Slice 2, proves/Slice two, proves/' 'slices: Slice two, proves #2: export route is not a `Slice <n>, proves #<n>: <seam>` or `Slice 1, deletes dead code: <area>` heading'
  bad_ticket 's/Slice 1, proves #1:/Slice 1 proves #1:/' 'slices: Slice 1 proves #1: export route is not a `Slice <n>, proves #<n>: <seam>` or `Slice 1, deletes dead code: <area>` heading'
  bad_ticket 's/Slice 1, proves #1:/Slice 1, proves #1 and two:/' 'slices: Slice 1, proves #1 and two: export route is not a `Slice <n>, proves #<n>: <seam>` or `Slice 1, deletes dead code: <area>` heading'
  bad_ticket 's/Walk 1, proves/Walk one, proves/' 'UI walks: Walk one, proves #1 is not a `Walk <n>, proves #<n>` heading'
  bad_ticket 's/Video 1, Setup/Video one, Setup/' 'videos: Video one, Setup of walk 1, shows walks 1 is not a `Video <n>, Setup of walk <n>, shows walks <n>` heading'
  bad_ticket 's/Video 1, Setup of walk 1, shows walks 1/Video 1, Setup of walk 1, shows walks one/' 'videos: Video 1, Setup of walk 1, shows walks one is not a `Video <n>, Setup of walk <n>, shows walks <n>` heading'
}

t_build_video_step_semicolon() {
  bad_ticket 's/  2\. Click Export, pick CSV\./  2. Type `tally status; tally list`, press Return./' \
    'video 1 step 2: `tally status; tally list` joins commands with `;`; type one command per step'
}

t_build_walk_steps_and() {
  bad_ticket 's/  Steps:    click Export, pick CSV/  Steps:    type `tally status \&\& tally list`, press Return/' \
    'walk 1 steps: `tally status && tally list` joins commands with `&&`; type one command per step'
}

t_build_before_clear_and() {
  bad_ticket 's/  Before:   none/  Before:   type `clear \&\& tally status`, press Return/' \
    'walk 1 before: `clear && tally status` joins commands with `&&`; type one command per step
walk 1 before: `clear && tally status` starts with `clear`; never clear the screen in a walk'
}

t_build_video_step_clear() {
  bad_ticket 's/  2\. Click Export, pick CSV\./  2. Type `clear`, press Return./' \
    'video 1 step 2: `clear` starts with `clear`; never clear the screen in a walk'
}

t_build_quoted_semicolon() {
  T="$(mktemp -d)"
  sed "s/  2\\. Click Export, pick CSV\\./  2. Type \`tally list | awk '{print \$1; print \$2}'\`, press Return./;
    s/  Before:   none/  Before:   the list shows \`a; b\` under the type filter/" "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq stdout "page: $T/plan-acme-shop-42.html" "$out"
}

t_build_viewport_too_tall() {
  # Given: the walk opens a 1440x900 page, as the repro's plan did
  bad_ticket 's|  Setup:    `pnpm seed:orders`|  Setup:    `pnpm seed:orders`, then `walk-browser http://localhost:3000/orders --viewport-size=1440,900`|' \
    'walk 1 setup: `--viewport-size=1440,900` is 900 px tall; the Sandbox shows a page at most 795 px tall under the browser bars and the taskbar, so use 1440,795 or 390,664'
}

t_build_setup_no_command() {
  # Given: a walk whose Setup says what to do but names no command
  bad_ticket 's|  Setup:    `pnpm seed:orders`|  Setup:    add three orders in the shop|' \
    'walk 1 setup: names no command; write the seed or fixture command in backticks, or none'
}

t_build_setup_none() {
  # Given: a walk that needs no data
  T="$(mktemp -d)"
  sed 's|  Setup:    `pnpm seed:orders`|  Setup:    none|' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  # When
  build "$T/plan-acme-shop-42.md"
  # Then
  eq exit 0 "$code"
  eq stderr "" "$err"
}

t_build_viewport_fits() {
  # Given: the walk opens a laptop page and the Open line a phone page, both of a size that fits
  T="$(mktemp -d)"
  sed 's|  Setup:    `pnpm seed:orders`|  Setup:    `pnpm seed:orders`, then `walk-browser http://localhost:3000/orders --viewport-size=1440,795`|;
    s|^Open: http://localhost:3000/orders|Open: `bunx playwright open --viewport-size=390,664 http://localhost:3000/orders`|' \
    "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  # When
  build "$T/plan-acme-shop-42.md"
  # Then
  eq exit 0 "$code"
  eq stdout "page: $T/plan-acme-shop-42.html" "$out"
}

t_build_viewport_in_note() {
  # Given: a fitting walk, and a Decided line that quotes the old size it replaced
  T="$(mktemp -d)"
  sed 's|  Setup:    `pnpm seed:orders`|  Setup:    `pnpm seed:orders`, then `walk-browser http://localhost:3000/orders --viewport-size=1440,795`|;
    s|^- D2 delimiter: `,` as the spec says|&\
- W1 Setup changed after round 2: "`--viewport-size=1440,900`" -> "`--viewport-size=1440,795`". The page ran under the taskbar|' \
    "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  # When
  build "$T/plan-acme-shop-42.md"
  # Then
  eq exit 0 "$code"
  eq stdout "page: $T/plan-acme-shop-42.html" "$out"
}

t_build_video_step_two_commands() {
  bad_ticket 's/  2\. Click Export, pick CSV\./  2. Type `tally status`, press Return; type `tally list`, press Return./' \
    'video 1 step 2: types 2 commands; type one command per step'
}

t_build_escaped_semicolon() {
  T="$(mktemp -d)"
  sed 's/  2\. Click Export, pick CSV\./  2. Type `echo a\\;b "c\\"; d"`, press Return./' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq stdout "page: $T/plan-acme-shop-42.html" "$out"
}

t_build_untyped_video_step() {
  bad_ticket 's/  2\. Click Export, pick CSV\./  2. Type tally status; tally list, press Return./' \
    'video 1 step 2: put the text to type in backticks right after `type`'
}

t_build_untyped_walk_steps() {
  bad_ticket 's/  Steps:    click Export, pick CSV/  Steps:    click Export, then type Alice in Name/' \
    'walk 1 steps: put the text to type in backticks right after `type`'
}

t_build_typed_spacing_and_output() {
  T="$(mktemp -d)"
  sed 's/  2\. Click Export, pick CSV\./  2. Type  `tally status`, press Return./;
    s/  Before:   none/  Before:   the screen shows `Ready, type a name`/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq stdout "page: $T/plan-acme-shop-42.html" "$out"
}

t_build_task_protections() {
  T="$(mktemp -d)"
  sed 's/Task done: full suite green, lint green, build green./Task done: full suite green, and these existing tests untouched and green:\n  `src\/orders.test.ts` "exports JSON"./' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[0].gates.task = "full suite green, and these existing tests untouched and green: `src/orders.test.ts` \"exports JSON\"."' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_terminal_must_not_stream() {
  bad_ticket 's/UI: web/UI: terminal/; s/  Must not: a console error/  Must not: output on stderr/' \
    'walk 1 must not: names `stderr`; a terminal shows stdout and stderr mixed, so name text on the screen, as in `no line starting Error:`'
}

t_build_terminal_must_not_screen() {
  T="$(mktemp -d)"
  sed 's/UI: web/UI: terminal/; s/  Must not: a console error/  Must not: a line starting Error:/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq stdout "page: $T/plan-acme-shop-42.html" "$out"
}

t_build_long_dash() {
  bad_ticket 's/export route, not/export route — not/' 'line 6: long dash; write a comma, a colon, or two sentences'
}

t_build_curly_quotes() {
  bad_ticket 's/the orders export/the order’s export/; s/receives the chosen format/receives the “chosen” format/' \
    "$(printf 'line 48: curly quote; write a straight quote\nline 57: curly quote; write a straight quote')"
}

t_build_marks_in_backticks() {
  T="$(mktemp -d)"
  sed 's/delimiter is `,`/delimiter is `—’`/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq stdout "page: $T/plan-acme-shop-42.html" "$out"
}

t_build_red_line() {
  T="$(mktemp -d)"
  sed '66a\
    Red:    the rows split at the note
' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[0].slices[0].tests[0].red = "the rows split at the note"' "$here/build-page/ticket.json")" \
    "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_mutate_line() {
  T="$(mktemp -d)"
  sed '66a\
    Mutate: `src/orders/export.ts:31`, return an empty string
' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[0].slices[0].tests[0].mutate = "`src/orders/export.ts:31`, return an empty string"' "$here/build-page/ticket.json")" \
    "$(page_data "$T/plan-acme-shop-42.html")"
}

# delete_slice: ticket.md with slice 1 turned into a delete slice: one Change
# that deletes, no Docs, and the existing test it keeps green.
delete_slice() {
  sed -e 's/^Slice 1, proves #1: export route$/Slice 1, deletes dead code: export route/' \
    -e 's/^  Change: `src\/orders\/export.ts:31`, stream CSV beside JSON\.$/  Change: `src\/orders\/export.ts:12`, delete `exportXml`. No caller: `rg -n exportXml` hits only its definition./' \
    -e '/^  Docs:   `src\/README.md:88`, CSV next to JSON\.$/d' \
    -e '/^| `src\/README.md`/d' \
    -e 's/^    Given:  three orders, one note with a newline$/    Given:  the base/' \
    -e '1,/^Slice 2/s/^    When:   export CSV$/    When:   `pnpm test export`/' \
    -e 's/^    Then:   all three rows with the note whole$/    Then:   pass, before and after the delete/' \
    "$here/build-page/ticket.md"
}

t_build_delete_slice() {
  T="$(mktemp -d)"
  delete_slice > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[0].slices[0] |= (.proves = [] | .deletes = true | .docs = []
    | .change = ["`src/orders/export.ts:12`, delete `exportXml`. No caller: `rg -n exportXml` hits only its definition."]
    | .tests[0] += {given: "the base", when: "`pnpm test export`", then: "pass, before and after the delete"})
    | .layers[0].files |= map(select(.path != "src/README.md"))' "$here/build-page/ticket.json")" \
    "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_delete_slice_number() {
  T="$(mktemp -d)"
  delete_slice | sed 's/^Slice 1, deletes dead code:/Slice 2, deletes dead code:/; s/^Slice 2, proves #2:/Slice 3, proves #2:/' \
    > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 1 "$code"
  eq stdout 'slices: layer 1 delete slice is headed `Slice 2`; it is `Slice 1`
file changes: layer 1 `src/orders/export.ts` names S1; layer 1 has no slice 1
file changes: layer 1 `src/orders/export.test.ts` names S1; layer 1 has no slice 1' "$out"
}

t_build_late_delete_slice() {
  bad_ticket 's/^Slice 2, proves #2: export route$/Slice 2, deletes dead code: export route/' \
    'slices: layer 1 slice 2 deletes dead code; only slice 1 may'
}

t_build_same_drawing() {
  # Given: the six fixtures, each built
  T="$(mktemp -d)"
  for f in files none-map perf run-one run ticket; do
    cp "$here/build-page/$f.md" "$T/plan-$f.md"
    build "$T/plan-$f.md"
    eq "exit $f" 0 "$code"
    # When
    render "$T/plan-$f.html"
    eq "render exit $f" 0 "$code"
    # Then
    eq "drawing $f" "$(cat "$here/build-page/$f.page.txt")" "$out"
  done
}

t_build_draws_layout_map() {
  # Given: the built page of files.md, and a fake PlanLayout with one part and one flow
  T="$(mktemp -d)"
  cp "$here/build-page/files.md" "$T/plan-acme-shop-44.md"
  build "$T/plan-acme-shop-44.md"
  cat > "$T/fake.js" <<'EOF'
const PlanLayout = {
  map: () => ({ width: 400, height: 200, groups: [],
    parts: [{ ref: 'M1', name: 'Orders page', job: '', change: 'same', kind: 'part', at: [], cx: 100, cy: 100, w: 190, h: 56, text: 'Fake part' }],
    flows: [{ from: 'M1', to: 'M1', change: 'same', d: 'M1,2 L3,4', label: { x: 50, y: 60, lines: ['fake label'], box: { x1: 0, y1: 50, x2: 100, y2: 70 } } }] }),
};
EOF
  # When
  render --fake-layout "$T/fake.js" "$T/plan-acme-shop-44.html"
  # Then
  eq exit 0 "$code"
  eq drawing "path d=M1,2 L3,4 fill=none marker-end=url(#map0-same) stroke-width=1.5 style=stroke:var(--muted)
text font-size=14 font-weight=600 style=fill:var(--ink) text-anchor=middle x=100 y=106 | Fake part
tspan x=50 | fake label" "$(printf '%s\n' "$out" | grep -E '^(path d=M1|text .*\| Fake part|tspan )')"
  eq "flows drawn" 1 "$(printf '%s\n' "$out" | grep -c 'marker-end=')"
  eq "boxes drawn" 1 "$(printf '%s\n' "$out" | grep -c '^rect .*rx=8 ')"
  eq "labels drawn" 1 "$(printf '%s\n' "$out" | grep -c '^tspan ')"
}

cases=(
  "build-page builds a ticket page from its .md|t_build_ticket"
  "build-page builds a run page from its .md|t_build_run"
  "build-page builds a one-layer run page from its .md|t_build_run_one"
  "build-page builds a None map page|t_build_none_map"
  "build-page reads moved and generated file rows|t_build_files"
  "build-page refuses a plan with no File changes block|t_build_no_file_changes"
  "build-page refuses a run layer with no File changes block|t_build_run_no_file_changes"
  "build-page refuses a file row with an unknown change|t_build_file_unknown_change"
  "build-page refuses a moved row with one path|t_build_file_moved_one_path"
  "build-page refuses an arrow on a row that is not moved|t_build_file_arrow_not_moved"
  "build-page refuses a file row with no slice|t_build_file_no_slice"
  "build-page refuses a file row that names a missing slice|t_build_file_missing_slice"
  "build-page refuses a file row whose slice does not name it|t_build_file_slice_does_not_name_it"
  "build-page refuses a file listed twice|t_build_file_listed_twice"
  "build-page builds a plan whose first slice deletes dead code|t_build_delete_slice"
  "build-page refuses a delete slice that is not slice 1|t_build_late_delete_slice"
  "build-page refuses a first delete slice not headed Slice 1|t_build_delete_slice_number"
  "build-page shows the Perf block of a perf plan|t_build_perf"
  "build-page refuses a Perf block with no Pass rule|t_build_perf_no_pass"
  "build-page refuses a [perf] ticket with no Perf block|t_build_perf_no_block"
  "build-page refuses a [perf] run layer with no Perf block|t_build_run_perf_no_block"
  "build-page builds a chat plan with no issue|t_build_chat"
  "build-page builds a plan whose Plan check block comes last|t_build_plan_check_last"
  "build-page refuses a chat plan with no Brief|t_build_chat_no_brief"
  "build-page refuses a Brief with no Task or Done when|t_build_chat_brief_gaps"
  "build-page stops on a file with no Review|t_build_no_review"
  "build-page refuses a Review with no Schema line|t_build_no_schema"
  "build-page refuses a part name over its limit|t_build_name_limit"
  "build-page refuses a layer with no Summary|t_build_no_summary"
  "build-page refuses a blank Before|t_build_blank_before"
  "build-page refuses a Proved line with no date|t_build_no_proved_date"
  "build-page refuses an odd backtick|t_build_odd_tick"
  "build-page refuses a plan with no Date|t_build_no_date"
  "build-page refuses a plan with no head|t_build_no_head"
  "build-page refuses a ticket with no Size|t_build_no_size"
  "build-page refuses a Summary over three lines|t_build_summary_limit"
  "build-page refuses a walk with no Before|t_build_no_before"
  "build-page refuses a Before naming a later walk|t_build_later_before"
  "build-page refuses a part with no At|t_build_no_at"
  "build-page refuses a bad grid|t_build_bad_grid"
  "build-page refuses parts sharing a grid cell|t_build_same_grid"
  "build-page refuses a job over its limit|t_build_job_limit"
  "build-page refuses a label over its limit|t_build_label_limit"
  "build-page refuses a malformed flow|t_build_bad_flow"
  "build-page refuses a flow to an unknown part|t_build_unknown_ref"
  "build-page refuses a one-layer run with one Review|t_build_run_one_review"
  "build-page refuses a mismatched Stack|t_build_stack_count"
  "build-page keeps the old page when a block is bad|t_build_preserves_old"
  "build-page reports every problem before writing|t_build_all_problems"
  "build-page preserves wrapped text, colons and escaped pipes|t_build_wrapped_text"
  "build-page escapes script closing text|t_build_script_text"
  "the shell and plan-page.md hold no bend|t_build_no_bend"
  "build-page preserves earlier-layer seam locations|t_build_earlier_seam"
  "build-page keeps every mixed-format map location|t_build_mixed_at"
  "build-page accepts and-separated proof references|t_build_multiple_proofs"
  "build-page accepts a serial comma in proof lists|t_build_serial_comma_proofs"
  "build-page accepts a video that shows one walk|t_build_video_one_walk"
  "build-page reads a video that shows two walks|t_build_video_two_walks"
  "build-page keeps commas inside quoted map locations|t_build_at_comma"
  "build-page refuses malformed or mismatched Stack rows|t_build_stack_identity"
  "build-page refuses malformed Slice Walk and Video headings|t_build_bad_record_headings"
  "build-page keeps existing test protections in Task done text|t_build_task_protections"
  "build-page refuses a video step that joins commands with a semicolon|t_build_video_step_semicolon"
  "build-page refuses walk steps that join commands with &&|t_build_walk_steps_and"
  "build-page refuses a Before that starts with clear and joins|t_build_before_clear_and"
  "build-page refuses a video step that types clear|t_build_video_step_clear"
  "build-page passes a semicolon inside quotes|t_build_quoted_semicolon"
  "build-page refuses a video step that types two commands|t_build_video_step_two_commands"
  "build-page passes an escaped semicolon|t_build_escaped_semicolon"
  "build-page refuses a video step that types text with no backticks|t_build_untyped_video_step"
  "build-page refuses walk steps that type text with no backticks|t_build_untyped_walk_steps"
  "build-page passes two spaces before a typed command and type inside quoted output|t_build_typed_spacing_and_output"
  "build-page refuses stderr in a terminal walk's Must not|t_build_terminal_must_not_stream"
  "build-page passes screen text in a terminal walk's Must not|t_build_terminal_must_not_screen"
  "build-page refuses a long dash|t_build_long_dash"
  "build-page refuses curly quotes|t_build_curly_quotes"
  "build-page passes a long dash and a curly quote inside backticks|t_build_marks_in_backticks"
  "build-page keeps a test's Red line|t_build_red_line"
  "build-page keeps a test's Mutate line|t_build_mutate_line"
  "build-page refuses a page taller than the Sandbox shows|t_build_viewport_too_tall"
  "build-page passes the laptop and phone sizes that fit|t_build_viewport_fits"
  "build-page passes an old size quoted in a note|t_build_viewport_in_note"
  "build-page refuses a Setup with no command|t_build_setup_no_command"
  "build-page passes a Setup of none|t_build_setup_none"
  "build-page draws the same map and file tree|t_build_same_drawing"
  "the page draws the map PlanLayout gives|t_build_draws_layout_map"
)
