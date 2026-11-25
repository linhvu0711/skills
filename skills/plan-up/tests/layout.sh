# layout.sh: the cases for assets/layout.js, run by node on the page data
# build_page.py builds from each fixture.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# built <fixture>...: each fixture built in T, its DATA at $T/<fixture>.json.
built() {
  T="$(mktemp -d)"
  for f in "$@"; do
    cp "$here/build-page/$f.md" "$T/plan-$f.md"
    python3 "$here/../scripts/build_page.py" "$T/plan-$f.md" >/dev/null
    sed -n 's/^const DATA = \(.*\);$/\1/p' "$T/plan-$f.html" > "$T/$f.json"
  done
}

# layout <js> <fixture>...: run <js> with `PlanLayout` from layout.js, loaded
# alone in a context with no page, `width` at 7 px per character, `data` the
# DATA of each fixture by name, and `points(d)`, the points every 2 px along
# a path's M, L, and Q commands.
layout() {
  local js="$1"; shift
  run env T="$T" node -e "
const fs = require('node:fs'), vm = require('node:vm');
const box = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8'), box);
const PlanLayout = vm.runInContext('PlanLayout', box);
const width = (s) => s.length * 7;
const data = Object.fromEntries(process.argv.slice(2).map((f) => [f, JSON.parse(fs.readFileSync(process.env.T + '/' + f + '.json', 'utf8'))]));
const points = (d) => {
  const got = []; let at = [0, 0];
  const add = (n, f) => { for (let i = 1; i <= n; i++) got.push(f(i / n)); };
  for (const [, cmd, args] of d.matchAll(/([MLQ])([^MLQ]*)/g)) {
    const v = args.trim().split(/[ ,]+/).map(Number);
    if (cmd === 'M') { at = v; got.push(at); continue; }
    const [x0, y0] = at;
    if (cmd === 'L') add(Math.ceil(Math.hypot(v[0] - x0, v[1] - y0) / 2), (t) => [x0 + (v[0] - x0) * t, y0 + (v[1] - y0) * t]);
    else add(Math.ceil((Math.hypot(v[0] - x0, v[1] - y0) + Math.hypot(v[2] - v[0], v[3] - v[1])) / 2),
      (t) => [(1 - t) ** 2 * x0 + 2 * (1 - t) * t * v[0] + t * t * v[2], (1 - t) ** 2 * y0 + 2 * (1 - t) * t * v[1] + t * t * v[3]]);
    at = v.slice(-2);
  }
  return got;
};
const partBox = (p) => ({ x1: p.cx - p.w / 2, y1: p.cy - p.h / 2, x2: p.cx + p.w / 2, y2: p.cy + p.h / 2 });
const overlap = (r, s) => Math.max(0, Math.min(r.x2, s.x2) - Math.max(r.x1, s.x1)) * Math.max(0, Math.min(r.y2, s.y2) - Math.max(r.y1, s.y1));
$js" "$here/../assets/layout.js" "$@"
}

MAPPED="files perf run-one run ticket run-three"

t_layout_alone() {
  # Given: layout.js alone in a context with no document and no window; the map of run-three.md
  built run-three
  # When
  layout "const m = PlanLayout.map(data['run-three'].maps[0], width);
console.log(m.parts.length + ' parts, ' + m.groups.length + ' groups, ' + m.flows.length + ' flows');" run-three
  # Then
  eq exit 0 "$code"
  eq stderr "" "$err"
  eq layout "7 parts, 2 groups, 7 flows" "$out"
}

t_layout_labels() {
  # Given: every map of the fixtures that hold one
  # shellcheck disable=SC2086
  built $MAPPED
  # When
  # shellcheck disable=SC2086
  layout "for (const [f, d] of Object.entries(data)) d.maps.forEach((map, i) => {
  const m = PlanLayout.map(map, width), labels = m.flows.map((x) => x.label.box);
  const walls = [...m.parts.map(partBox), ...m.groups.map((g) => g.title.box)];
  let n = 0;
  labels.forEach((r, j) => { for (const w of [...walls, ...labels.slice(j + 1)]) n += overlap(r, w); });
  console.log(f + ' map ' + i + ': overlap ' + n);
});" $MAPPED
  # Then
  eq exit 0 "$code"
  eq overlaps "files map 0: overlap 0
perf map 0: overlap 0
run-one map 0: overlap 0
run map 0: overlap 0
ticket map 0: overlap 0
run-three map 0: overlap 0" "$out"
}

t_layout_routes() {
  # Given: the same maps
  # shellcheck disable=SC2086
  built $MAPPED
  # When
  # shellcheck disable=SC2086
  layout "for (const [f, d] of Object.entries(data)) d.maps.forEach((map, i) => {
  const m = PlanLayout.map(map, width);
  let n = 0;
  for (const x of m.flows) for (const [px, py] of points(x.d)) for (const p of m.parts) {
    const r = partBox(p);
    if (p.ref !== x.from && p.ref !== x.to && px > r.x1 && px < r.x2 && py > r.y1 && py < r.y2) n++;
  }
  console.log(f + ' map ' + i + ': ' + n + ' points in another box');
});" $MAPPED
  # Then
  eq exit 0 "$code"
  eq routes "files map 0: 0 points in another box
perf map 0: 0 points in another box
run-one map 0: 0 points in another box
run map 0: 0 points in another box
ticket map 0: 0 points in another box
run-three map 0: 0 points in another box" "$out"
}

t_layout_lanes() {
  # Given: a flow from the top left box to the bottom right one, with a wall of three boxes in the middle column, so every curve hits a box
  T="$(mktemp -d)"
  # When
  layout "const p = (ref, x, y) => ({ ref, name: ref, job: '', change: 'same', group: '', kind: 'part', at: [], x, y, layer: '' });
const m = PlanLayout.map({ parts: [p('A', 0, 0), p('W1', 1, 0), p('W2', 1, 1), p('W3', 1, 2), p('B', 2, 2)],
  flows: [{ from: 'A', to: 'B', label: 'around', change: 'new', layer: '' }] }, width);
const f = m.flows[0];
let n = 0, off = 0;
for (const [px, py] of points(f.d)) {
  if (px < 0 || py < 0 || px > m.width || py > m.height) off++;
  for (const q of m.parts.filter((q) => q.ref.startsWith('W'))) {
    const r = partBox(q);
    if (px > r.x1 && px < r.x2 && py > r.y1 && py < r.y2) n++;
  }
}
console.log((/ L/.test(f.d) ? 'lanes' : 'curve') + ', ' + n + ' points in another box, ' + off + ' off the map');"
  # Then
  eq exit 0 "$code"
  eq route "lanes, 0 points in another box, 0 off the map" "$out"
}

# tree_rows <filter>: the rows of fileTree on files.md's files that pass <filter>, as branch, name, and / after a folder.
tree_rows() {
  built files
  layout "for (const r of PlanLayout.fileTree(data.files.layers[0].files.filter($1))) console.log(r.branch + r.name + (r.dir ? '/' : ''));" files
}

t_layout_tree() {
  # Given: the files of files.md
  # When
  tree_rows '() => true'
  # Then
  eq exit 0 "$code"
  eq rows "src/
├── orders/
│   ├── formats/
│   │   └── json.ts
│   ├── __snapshots__/
│   │   └── export.test.ts.snap
│   ├── csv.ts
│   ├── export.ts
│   ├── json-only.ts
│   └── export.test.ts
└── README.md" "$out"
}

t_layout_tree_fold() {
  # Given: the one deleted file of files.md, src/orders/json-only.ts
  # When
  tree_rows "(f) => f.change === 'deleted'"
  # Then
  eq exit 0 "$code"
  eq rows "src/orders/
└── json-only.ts" "$out"
}

cases=(
  "layout lays out a map with no page around it|t_layout_alone"
  "layout places no label over a box, a group title, or another label|t_layout_labels"
  "layout routes each flow clear of every box but its own two|t_layout_routes"
  "layout runs a flow along the lanes when every curve hits a box|t_layout_lanes"
  "layout builds the file tree of a plan|t_layout_tree"
  "layout folds a folder that holds only one folder|t_layout_tree_fold"
)
