# HTML report

The candidate report is one HTML file, published with the Artifact tool. Write it to the scratchpad as `architecture-review-<repo>.html`, then publish with favicon `🏗️`. Load the `artifact-design` skill before writing.

Artifact rules that shape the file:

- The host wraps the file in the document skeleton. Write no `<!doctype>`, `<html>`, `<head>`, or `<body>`. Put `<title>` and `<style>` at the top.
- Tailwind loads from its play CDN (`<script src="https://cdn.tailwindcss.com"></script>`). It is the one allowed script.
- Mermaid renders natively in `<pre class="mermaid">` blocks. Load no Mermaid library.
- The page renders in the viewer's theme. Define the light palette on `:root`, redefine it under `@media (prefers-color-scheme: dark)` guarded as `:root:not([data-theme="light"])`, and again under `:root[data-theme="dark"]`. Give `body` a token background.

## Scaffold

```html
<title>Architecture review: {{repo name}}</title>
<script src="https://cdn.tailwindcss.com"></script>
<style>
  :root { --bg: #fafaf9; --fg: #0f172a; --card: #ffffff; --line: #e2e8f0; --deep: #0f172a; --leak: #dc2626; --warn: #f59e0b; --accent: #059669; }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) { --bg: #0c0a09; --fg: #e7e5e4; --card: #1c1917; --line: #292524; --deep: #e7e5e4; }
  }
  :root[data-theme="dark"] { --bg: #0c0a09; --fg: #e7e5e4; --card: #1c1917; --line: #292524; --deep: #e7e5e4; }
  body { background: var(--bg); color: var(--fg); }
  .card { background: var(--card); border-color: var(--line); }
  .seam { stroke-dasharray: 4 4; }
  .leak { stroke: var(--leak); }
  .deep { background: var(--deep); color: var(--bg); }
</style>
<main class="max-w-5xl mx-auto px-6 py-12 space-y-12">
  <header>...</header>
  <section id="candidates" class="space-y-10">...</section>
  <section id="top-recommendation">...</section>
</main>
```

## Header

Repo name, branch, commit, date, and a compact legend: solid box = module, dashed line = seam, red arrow = leakage, thick dark box = deep module. The candidates follow at once, with no introduction paragraph.

## Candidate card

The diagrams carry the weight. Prose is sparse and uses the glossary terms from `codebase-design.md` without ceremony.

Each candidate is one `<article class="card rounded-xl border p-6">`:

- **Title**: short, names the deepening ("Collapse the Order intake pipeline").
- **Badge row**: strength (`Strong` = emerald, `Worth exploring` = amber, `Speculative` = slate) plus the dependency category from `deepening.md` (`in-process`, `local-substitutable`, `ports & adapters`, `mock`).
- **Files**: monospaced list, `font-mono text-sm`.
- **Before / After diagram**: the centrepiece. Two columns, side by side. Patterns below.
- **Problem**: one sentence. What hurts.
- **Solution**: one sentence. What changes.
- **Wins**: bullets, six words or fewer each. "Tests hit one interface", "Pricing stops leaking", "Delete 4 shallow wrappers".
- **ADR callout** (when it applies): one line in an amber-tinted box.

A diagram that needs a paragraph to be understood gets redrawn.

## Diagram patterns

Pick the pattern that fits the candidate. Mix them; variety is part of the point.

### Mermaid graph (the workhorse for dependencies and call flow)

A `flowchart` when the point is "X calls Y calls Z, and look at the mess". Wrap it in a card. Colour leakage edges red and the deep module dark with `classDef`. Sequence diagrams fit "before: 6 round-trips; after: 1".

```html
<div class="card rounded-lg border p-4">
  <pre class="mermaid">
    flowchart LR
      A[OrderHandler] --> B[OrderValidator]
      B --> C[OrderRepo]
      C -.leak.-> D[PricingClient]
      classDef leak stroke:#dc2626,stroke-width:2px;
      class C,D leak
  </pre>
</div>
```

### Hand-built boxes and arrows (when Mermaid's layout fights you)

Modules as `<div>`s with borders and labels. Arrows as inline SVG `<line>` or `<path>` positioned absolutely over a relative container. Use this when the "after" side should read as one thick-bordered deep module with greyed-out internals; Mermaid will not give that weight.

### Cross-section (layered shallowness)

Stack horizontal bands (`h-12 border-l-4`) for the layers a call passes through. Before: six thin bands each doing nothing. After: one thick band with the consolidated responsibility.

### Mass diagram (interface as wide as implementation)

Two rectangles per module: interface surface and implementation. Before: the interface rectangle is nearly as tall as the implementation (shallow). After: a short interface over a tall implementation (deep).

### Call-graph collapse

Before: a tree of calls as nested boxes. After: the same tree inside one box, the now-internal calls faded.

## Style

- Editorial, not dashboard. Generous whitespace. Serif headings (`font-serif`) sit well with stone and slate.
- One accent (emerald or indigo), red for leakage, amber for warnings.
- Diagrams about 320px tall, so before and after sit side by side without scrolling. Wide diagrams scroll inside their own `overflow-x-auto` box.
- `text-xs uppercase tracking-wider` for module labels inside diagrams, so they read as schematic.
- No app code, no interactivity beyond Mermaid's own rendering.

## Top recommendation

One larger card. Candidate name, one sentence on why, an anchor link to its card.

## Tone

Plain English, concise, with the architectural nouns and verbs straight from `codebase-design.md`.

**Use exactly:** module, interface, implementation, depth, deep, shallow, seam, adapter, leverage, locality.

**Never substitute:** component, service, unit (for module) · API, signature (for interface) · boundary (for seam) · layer, wrapper (for module, when you mean module).

**Phrasings that fit:**

- "Order intake module is shallow: interface nearly matches the implementation."
- "Pricing leaks across the seam."
- "Deepen: one interface, one place to test."
- "Two adapters justify the seam: HTTP in prod, in-memory in tests."

**Wins** name the gain in glossary terms: *"locality: bugs concentrate in one module"*, *"leverage: one interface, N call sites"*, *"interface shrinks; implementation absorbs the wrappers"*. "Easier to maintain" and "cleaner code" are not glossary terms and earn no place.

If a sentence could be a bullet, make it a bullet. If a bullet could be cut, cut it. If a term is not in the glossary, reach for one that is before inventing a new one.
