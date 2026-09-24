# Use case

Answers: who uses the system and what they get done with it. Scope and requirements. Good early, and good when a feature adds a new kind of user or a new external system.

## Facts to collect

- Actors: each role that starts an interaction (`actor`) and each outside system the system calls or is called by (`external`). Find them in auth roles, permission checks, webhook handlers, API clients.
- Use cases: the goals, not the screens. One per top-level route, command, or job that an actor triggers. `path` to the handler.
- Which actor triggers which use case.
- Includes and extends, only when the code shows a shared sub-flow (a use case that always calls another).

## Draw it

| Thing | Node | Notes |
|---|---|---|
| Person or role | `actor` | label with the role name as the code names it |
| Outside system | `external` | payment gateway, identity provider, mail |
| Use case | `usecase` | verb phrase: "Place order", "Reset password" |
| System boundary | group `boundary` around all use cases | `label` is the system name |

Edges: actor to use case, no head (`head: "none"`) or plain arrow. `include` and `extend` as `dashed` edges with the label `include` / `extend`.

## Layout

Primary actors on `x: 0`, use cases in one or two columns (`x: 1`, `x: 2`), external systems on the far right. Group use cases so those an actor touches sit near each other.

## Budget

6 to 14 use cases. Past that, split by actor.

## Pitfalls

- A use case named after a screen ("Settings page") is a screen, not a goal. Rename to what the person wants.
- CRUD on every entity is a database listing, not a use case set. Keep the goals a person would say aloud.
