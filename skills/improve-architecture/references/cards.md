# Cards

How to fill each candidate's `card` in the rows file. The shared report page draws it: the advice, the title, the tags, the reason, the solution, the before and after diagrams side by side, the wins, the ADR line, and the places.

## Candidate card

The diagrams carry the weight. Prose is sparse and uses the glossary terms from `codebase-design.md` without ceremony.

- **Title**, the row's `name`: short, names the change ("Collapse the Order intake pipeline", "Drop the retry queue").
- **Badge**, `badge`: `Strong`, `Worth exploring`, or `Speculative`.
- **Tag**, `tag`: for a deepening, the dependency category from `deepening.md` (`in-process`, `local-substitutable`, `ports & adapters`, `mock`). The page adds the kind's title beside it.
- **Problem**, the row's `reason`: one sentence. What hurts.
- **Solution**, `solution`: one sentence. What changes.
- **Before** and **After**, `before` and `after`: one Mermaid diagram each. Patterns below.
- **Wins**, `wins`: bullets, six words or fewer each. "Tests hit one interface", "Pricing stops leaking", "Delete 4 shallow modules".
- **ADR line**, `adr` (when it applies): "contradicts ADR-0007, but worth reopening because ...".

The files are the row's places, each with its evidence label and proof.

A diagram that needs a paragraph to be understood gets redrawn.

## Diagram patterns

Each side is Mermaid 11 source, as a string in the rows file. Pick the pattern that fits the candidate, and draw both sides in the same pattern, so the two read as before and after.

### Flowchart (the workhorse for dependencies and call flow)

A `flowchart LR` when the point is "X calls Y calls Z, and look at the mess". Colour a leak edge red and the deep module dark with `classDef`.

```
flowchart LR
  A[OrderHandler] --> B[OrderValidator]
  B --> C[OrderRepo]
  C -. leak .-> D[PricingClient]
  classDef leak stroke:#dc2626,stroke-width:2px;
  class C,D leak
```

### Sequence (round trips)

A `sequenceDiagram` when the point is "before: 6 round trips; after: 1".

### Collapse into one deep module

Before: the call tree as separate boxes. After: one `subgraph` for the deep module, its now-internal parts inside it, styled dark with `classDef deep fill:#0f172a,color:#fff`.

```
flowchart LR
  Caller --> M
  subgraph M[Order intake]
    V[validate] --> S[save]
  end
  classDef deep fill:#0f172a,color:#fff;
  class M deep
```

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
