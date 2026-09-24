# Dependency graph

Answers: which modules or packages depend on which, where the cycles are, and what is affected by a change to one of them. Import graphs, workspace package graphs, service call graphs.

## Facts to collect

- Units: modules, packages, or services at one chosen grain. Pick the grain by the question: files for one feature folder, packages for a monorepo, services for a platform. `path` to each.
- Edges: A imports or calls B. From import statements, package manifests, workspace configs, client instantiation. Prefer a tool output when one exists (`madge`, `cargo tree`, `go mod graph`, `pnpm ls`, `nx graph`); cite the command in `scope`.
- Direction: from dependent to dependency.
- Cycles: every one found. Each goes in `findings` with the members.
- Fan-in and fan-out counts for the unit the question names. Put them in that node's `note`.
- Boundaries: layers or packages the units belong to.

## Draw it

| Thing | Data |
|---|---|
| Unit | `box`, `sub` is the path; the unit the question names gets `tag: "focus"` |
| Depends on | edge, label omitted when all edges mean "imports"; put "arrows point at what is imported" in `guide` |
| Type-only or dev dependency | `kind: "dotted"` |
| Runtime call across a process | `kind: "dashed"` with the protocol |
| Layer or package | group `zone` |
| Cycle members | `tag: "cycle"` on each, and the cycle listed in `findings` |

## Layout

Layered top to bottom: units with no dependents on top, leaves at the bottom. Compute each unit's depth as the longest path to a leaf and use it as `y`. Cycles break this; place cycle members on one row and note it. Within a row, order to reduce crossings.

## Budget

8 to 24 units, 40 edges. Beyond that, raise the grain (files to folders, folders to packages) or draw only the neighborhood of the focus unit: its dependents and its dependencies, two hops.

## Pitfalls

- Node modules and the standard library as units. Only the code the user owns, plus at most a few third-party units that matter to the question.
- Transitive edges. Draw direct dependencies; the reader follows the chain.
