# Component

Answers: what the modules of one system are, what each provides, and what each needs from the others. The high-level map of one repo or one service.

## Facts to collect

- Components: packages, modules, services, or top-level folders with a clear responsibility. `path` to the folder or entry file. Name them as the repo names them.
- What each provides: its public surface (exported API, routes, events published). Two or three items in `note`.
- What each requires: the interfaces it imports or calls. These become edges.
- Shared infrastructure the components depend on: database, cache, queue, config.
- Ownership boundaries: workspace packages, deployable units.

## Draw it

| Thing | Node |
|---|---|
| Component | `component`, `sub` is its path or package name |
| Provided interface worth naming | edge label: `OrderApi`, `GET /orders`, `order.created` |
| Required interface | edge from requirer to provider, `head: "arrow"`; `dashed` when it is an event subscription |
| Infrastructure | `store`, `queue` |
| External system | `external` |
| Package or deployable boundary | group `zone` |

## Layout

Entry points (UI, API, CLI) on the left or top. Domain components in the middle. Infrastructure on the right or bottom. Edges point in the direction of dependency, from the one that needs to the one that provides. Aim for all edges to point one way; a backward edge is a finding.

## Budget

6 to 16 components. Beyond that, group into zones and draw the zones as components in a second overview page.

## Pitfalls

- Folders as components. A folder with no public surface is not a component; fold it into its parent.
- Drawing every import. Draw the interface a component relies on, once, with its name.
