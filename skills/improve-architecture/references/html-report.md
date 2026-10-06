# HTML report

The candidate report is one full HTML page, a copy of `assets/report.html`. Write it to `$HOME/.agents/artifacts/architecture/architecture-review-<repo>.html`, and create the folder when needed. It never goes into the repo it reviews. In the copy, replace the `{{…}}` placeholders, the example card, and the empty top recommendation.

Page rules that shape the file:

- A full document that shows correctly when it is opened alone. Keep the head of `assets/report.html` as it is.
- Tailwind loads from its play CDN, and Mermaid 11 from jsdelivr. They are the only scripts.
- Mermaid draws every `<pre class="mermaid">` block once its module loads, in its dark or default theme by the system setting.
- The page follows the system light or dark theme through the `:root` tokens. A new colour is a token, set in both themes.

## Serve and open

Serve the page with the shared serve script, which prints its URL:

```sh
URL=$(../../shared-skill-core/serve.sh "$HOME/.agents/artifacts/architecture" "architecture-review-<repo>.html")
```

The script exits with an error (no free port, or the server does not give back the file): chat gets its error line and the `.html` path, and the run stops.

Then open it in the user's browser: `open "$URL?v=$(date +%s)"` on macOS, `xdg-open` on Linux. The `v` makes a rerun on the same repo show the new page, not the cached one. Chat gives `$URL`.

**Headless host** (`command -v open xdg-open` finds neither): there is no browser to leave the page in. Skip the server. Publish the page with the `to-artifact` skill and give the artifact link in place of the URL. Publish fails: say why, give the `.html` path, stop.

## Scaffold

`assets/report.html` holds the head, the tokens, the Mermaid loader, and the `<main>` with its `header`, `#candidates`, and `#top-recommendation` sections.

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
