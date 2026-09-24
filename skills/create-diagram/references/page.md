# Page data

`assets/shell.html` draws everything from one `DATA` object. Replace the line `const DATA = {};` with the object. Two shapes exist: **graph** (default) and **sequence** (`type: "sequence"`).

## Common fields

| Field | What it is |
|---|---|
| `title` | Page name. A product name, two to four words, no explainer after a colon. |
| `question` | The one question the diagram answers. Shown under the title and in the panel. |
| `scope` | Where the facts came from: repo, branch, short commit, date. |
| `mode` | First view when changes exist: `current`, `planned`, or `diff` (default). |
| `guide` | 2 to 4 short strings: how to read the picture, in order. |
| `findings` | Strings the reader should know: cycles, dead paths, plan gaps, surprises. A bare `https://` URL in a finding or a node `note` renders as a link; use it to point at a sibling diagram. |
| `legend` | `[{mark, label}]`. Marks: `solid` `dashed` `dotted` `open` `diamond` `fdiamond` `external` `box` `group`, or a hex color. Change marks are added for you. |
| `layout` | Cell size overrides: `{colWidth, rowHeight, nodeWidth, pad}`. Graph default 320×180, node 160 (boxes grow to fit their text, up to the cell). Sequence default 190×46, node 130. Override only to widen; a labelled edge needs the gap between cells to hold its label clear of both nodes. |

## Graph

```js
nodes:  [{ id, label, kind, sub, tag, path, note, x, y, w, h, sections, change }]
edges:  [{ from, to, label, kind, head, tail, path, note, change }]
groups: [{ id, label, sub, kind, members, pad, change }]
```

**Node**

- `x`, `y` are grid cells. Fractions are fine (`x: 0.5` centers a parent over two children). The node is centered in its cell.
- `label` may hold `\n` for a second line. Keep labels to three words.
- `sub` is a second line in mono type: a tech, a path, a cardinality.
- `tag` is a small uppercase eyebrow: `service`, `hook`, `table`. `component` and `container` kinds show their kind as the tag by default.
- `path` is a `file:line` string or an array of them. It is shown in the panel when the node is clicked.
- `sections` is for `table` only: `[["id uuid PK", "email text"], ["save()", "verify()"]]`. One inner array per section; a rule separates sections.
- `w`, `h` override size. Leave them out unless a label wraps badly.
- `href` makes a click open that URL in a new tab instead of the panel. Use it on a `note` node placed beside the part it zooms into, with an arrow character in the label, so a sibling diagram is one click away on the canvas.

**Node kinds**

| kind | Draws | Use for |
|---|---|---|
| `box` | rectangle | module, service, step, component |
| `rounded` | pill corners | state, activity action |
| `decision` | diamond | branch |
| `start` / `end` | filled circle / bullseye | flow start and end; label sits below |
| `store` | cylinder | database, cache, file store |
| `queue` | rectangle with bars | queue, topic, bus |
| `actor` | stick figure | person or role; label sits below |
| `external` | dashed rectangle | system outside the scope |
| `usecase` | ellipse | a goal an actor reaches |
| `table` | header plus rows | class, entity, record shape |
| `device` | 3-D box | server, VM, container host, browser, phone |
| `file` | page with folded corner | artifact, bundle, config file |
| `note` | folded corner, muted | a remark pinned to the drawing |
| `component` / `container` | rectangle with eyebrow | UML component, C4 container |

**Edge**

- `label` is a verb or a message: `reads`, `POST /orders`, `emits`, `1..*`. Every edge gets one.
- `kind`: `solid` (default), `dashed` (async, dependency, return), `dotted` (weak or optional).
- `head`: `arrow` (default), `stick` (async), `open` (inheritance), `diamond` (aggregation), `fdiamond` (composition), `dot`, `none`. `tail` takes the same values and sits at `from`.
- Two edges between the same pair fan out on their own. A self edge loops on the right.

**Group**

- `members` lists node ids or other group ids. Nesting works. The box is fitted around the members.
- `kind`: `boundary` (dashed: a system or trust boundary), `zone` (solid: a package, a deployment node), `lane` (soft band: a swimlane).
- `sub` sits at the right of the group label, in mono type: a runtime, a host name.

## Sequence

```js
type: "sequence",
participants: [{ id, label, kind, sub, path, note, change }],   // kind: box | actor | store
steps:        [{ from, to, label, kind, path, note, change }],  // kind: sync | async | return
frames:       [{ label, from, to, participants, note, change }],
notes:        [{ at, after, text, change }]
```

- Participants sit left to right in array order. Put the caller first.
- Each step is one row, top to bottom. `sync` is a filled arrow with an activation bar, `async` an open arrow, `return` a dashed open arrow. `from === to` draws a self message.
- `frames` span step indexes `from` to `to` (inclusive). `label` is `loop each item`, `alt token valid`, `opt`. `participants` narrows the frame to those columns.
- `notes` pin a remark to a lifeline just below step `after`.

## Change

Any node, edge, group, participant, step, or frame takes `change: "add" | "remove" | "modify"`. When at least one exists, the mode switch appears. See `change-mode.md`.

## Example

```js
const DATA = {
  title: "Order Checkout Path",
  question: "Which services touch an order between cart and payment?",
  scope: "shop-api · main · 4f2c1a9 · 2026-09-06",
  guide: [
    "Start at the browser on the left; follow solid arrows to the right.",
    "Dashed arrows are events on the bus, not calls.",
    "Click a box to see the file that owns it."
  ],
  findings: ["inventory-svc is called twice per order: once by cart, once by payment."],
  legend: [{ mark: "solid", label: "HTTP call" }, { mark: "dashed", label: "event" }],
  nodes: [
    { id: "web", kind: "actor", label: "Shopper", x: 0, y: 1 },
    { id: "cart", kind: "box", tag: "service", label: "cart-svc", sub: "src/cart", path: "src/cart/server.ts:12", x: 1, y: 1 },
    { id: "inv", kind: "box", tag: "service", label: "inventory-svc", path: "src/inventory/server.ts:20", x: 2, y: 0 },
    { id: "pay", kind: "box", tag: "service", label: "payment-svc", path: "src/payment/server.ts:9", x: 2, y: 2 },
    { id: "bus", kind: "queue", label: "orders topic", path: "infra/kafka.tf:44", x: 3, y: 1 },
    { id: "db", kind: "store", label: "orders db", sub: "postgres", x: 3, y: 2 }
  ],
  edges: [
    { from: "web", to: "cart", label: "POST /checkout", path: "src/cart/routes.ts:31" },
    { from: "cart", to: "inv", label: "reserve", path: "src/cart/reserve.ts:8" },
    { from: "cart", to: "pay", label: "charge" },
    { from: "pay", to: "inv", label: "confirm" },
    { from: "pay", to: "db", label: "writes" },
    { from: "pay", to: "bus", label: "order.paid", kind: "dashed", head: "stick" }
  ],
  groups: [
    { id: "core", kind: "boundary", label: "shop-api", sub: "k8s ns: shop", members: ["cart", "inv", "pay"] }
  ]
};
```
