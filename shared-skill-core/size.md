<!-- template: one ruler for tickets and PRs. to-issue and to-epic read it through issue-rules.md § Size; render.sh pastes it into the handoff rules under ## Size. Edit here only. -->
One ruler sizes a ticket and the PR that ships it. Judge by the facts in
the table, never by hours and never by lines changed.

The **ceiling**: one fresh context window and one PR. Size splits the
space under it.

| Size | Facts |
|---|---|
| XS | One place. 1 to 2 files. No schema or API change. At most one test touched. |
| S | One thin path through existing seams. About 3 to 5 files. Tests at one seam. Under half a window. |
| M | Full vertical slice (schema, API, UI, tests) through existing seams, or one new seam. Fills most of a window. |
| L | Vertical slice plus a new seam, a migration, or 2+ packages. Just fits one window and one PR. |
| XL | Over the ceiling. A ticket is never XL: it becomes an epic. A PR lands XL only when the work outgrew its ticket, and the label says so. |

Words. A *place* is one function, component, or command. A *seam* is a
boundary the code already has: a module other code imports, a service, a
route, a table. A *new seam* is one of those that did not exist before.
A *package* is a unit the repo builds on its own: each `apps/*` and
`packages/*`, or the one root when there is no split. A *schema or API
change* is a migration, a schema file, or a route or handler that adds
or changes an endpoint. Test files count as files.

Pick the smallest row whose every fact holds. One fact over a row's
limit moves the work to the next row. Files a tool wrote whole (a
lockfile, a `linguist-generated` file, a snapshot) do not count.

Reading the facts off a diff, for the PR side:

```bash
git diff --name-status <base>...HEAD -- . ':!*.lock' ':!package-lock.json' ':!pnpm-lock.yaml'
```

Count the files, the distinct packages, the schema, migration, and
route files, and the test files. A new seam is an added file that
another changed file imports, an added route, or an added table. Say
the size with its facts in one line, as in `M: 6 files, 1 package, one
new route, 212 lines`. The line count (`git diff --shortstat`) tells
the reader the review effort; it never picks the size.
