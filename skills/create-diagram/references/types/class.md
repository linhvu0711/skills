# Class

Answers: what types exist in this area, what they hold, and how they relate. Also for TypeScript interfaces, Rust structs and traits, Go structs, Python dataclasses.

## Facts to collect

- Each type in scope: name, `path` to its declaration.
- Fields that matter for the question (ids, foreign references, status, the ones the plan touches). Type after the name: `status: OrderStatus`.
- Methods that matter: public ones that other types call. Signatures shortened: `charge(amount)`.
- Inheritance and interface implementation.
- Composition (owns, lifetime bound) vs aggregation (has, lifetime separate) vs plain association (uses, references). Cardinality when it is knowable from the field type: `items: Item[]` is `1..*`.

## Draw it

| Thing | Draws as |
|---|---|
| Type | `table` with `sections: [[fields], [methods]]`; abstract or interface gets `tag: "interface"` |
| Enum | `table` with one section listing values, `tag: "enum"` |
| Extends / implements | edge `head: "open"`, `kind: "solid"` for extends, `"dashed"` for implements, from child to parent |
| Composition | edge `tail: "fdiamond"`, `head: "none"`, from owner to part |
| Aggregation | edge `tail: "diamond"`, `head: "none"` |
| Association | edge `head: "arrow"` with the field name or verb as label; cardinality in the label: `items 1..*` |
| Dependency (uses in a method) | edge `kind: "dashed"`, label `uses` |

Legend entries: `open` "extends", `fdiamond` "owns", `dashed` "uses" when they appear.

## Layout

Parents above children. Owners left of parts. Keep each `sections` list to the fields that carry the answer; the panel can list the rest in `note`.

## Budget

4 to 12 tables. Over that, draw the aggregate root and its neighbors only.

## Pitfalls

- Listing every field turns the diagram into the source file. Keep 3 to 6 rows per section.
- Utilities and DTOs with no relationships add noise; leave them out.
