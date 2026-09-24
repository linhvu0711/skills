# UI component tree

Answers: how a screen or feature is built from UI components, where state lives, which component owns which data, and where the boundaries are (routes, providers, packages). React, Vue, Svelte, SwiftUI, Compose, and similar.

## Facts to collect

- The root: the route or screen component. `path` to it.
- The render tree: each child component that matters, in order. Skip presentational leaves (buttons, icons) unless the question is about them.
- State: where each piece of state is declared (`useState`, store slice, signal, view model) and which components read it. Mark the owner with `tag: "state"` in its `note` or a child `note` node.
- Data fetching: which component calls the API or hook, and the hook name.
- Context or providers, and which subtree they cover.
- Package or module boundaries: shared UI library vs app code.
- Props that carry the answer (the callback that closes the modal, the id that selects the row). One or two, as edge labels.

## Draw it

| Thing | Data |
|---|---|
| Component | `box`, label is the component name in `<Angle>` form, `sub` is the file path relative to the package |
| Hook or store used by a component | `rounded` with `tag: "hook"` or `tag: "store"`, placed beside its consumer |
| Provider boundary | group `zone` labelled with the provider |
| Package boundary | group `boundary` with the package name |
| Parent renders child | edge, `head: "none"`, unlabelled |
| Prop that carries the answer | edge label on that render edge: `onClose`, `selectedId` |
| Reads state / calls hook | `dashed` edge from component to hook or store, label `reads` / `writes` |
| Conditional render | edge `kind: "dotted"`, label with the condition: `if open` |

## Layout

Root at top center. Each depth level is one row. Siblings share a row, ordered as rendered, left to right. Center a parent over its children with fractional `x`. Hooks and stores sit in the row of their consumer, to the right, or on a separate right column when shared.

## Budget

8 to 24 components. Over that, draw one subtree per page.

## Pitfalls

- Every div drawn. Draw components with a name and a file, not markup.
- State drawn as a leaf. State is a node with edges from every reader; that fan-in is the point of the diagram.
