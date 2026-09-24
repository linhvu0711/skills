# Entity relationship

Answers: what the data model is: tables or collections, their keys, and how rows relate. Before a migration, when explaining a schema, when a plan adds or moves a column.

## Facts to collect

- Entities in scope: table, collection, or model. `path` to the migration, schema file, or model class.
- Primary key and the columns that carry the answer: foreign keys, status, timestamps the plan touches, unique constraints.
- Relationships with cardinality on both ends: `1`, `0..1`, `1..*`, `0..*`. Read it from the foreign key placement and nullability, not from the ORM name.
- Join tables. Show one as an entity only when it carries extra columns; otherwise draw a many-to-many edge.
- Indexes only when the question is about a query path.

## Draw it

| Thing | Data |
|---|---|
| Entity | `table`, `sections: [[keys], [other columns]]`; row text `id uuid PK`, `user_id uuid FK`, `email text UQ` |
| Relationship | edge from the FK side to the referenced side, `head: "none"`, label with cardinality: `*..1`, `1..1` |
| Optional relationship | `kind: "dashed"` |
| Many-to-many without join table | one edge labelled `*..*` |
| Schema or service boundary | group `zone` with the database name in `sub` |

Legend: `dashed` "optional". Put the cardinality reading in `guide`: "Labels read left-end..right-end."

## Layout

The root entity (the one most others reference) in the center or top-left. Children fan out. Lookup and enum tables on the outer edge. Keep tables that share many FKs adjacent.

## Budget

4 to 12 tables. Over that, draw the cluster around the tables the question names.

## Pitfalls

- Listing every column. Keys and the columns the question needs; the rest goes in `note` as a count: "14 more columns".
- ORM relation names that hide the real FK direction. Read the schema, not the model decorator.
