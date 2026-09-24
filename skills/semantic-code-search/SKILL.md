---
name: semantic-code-search
description: "Find code by meaning with semble instead of grep. Use whenever you need to locate code by what it does ('where is login expiry handled?', 'how does session renewal work?'), find a symbol by name, or find code related to a hit you already have. Any brief that says 'find', 'search', 'explore', or 'grep' for a concept is this skill."
---

Use `semble` for conceptual searches — "where is X handled", "how does Y work", or finding a symbol by name — instead of grep. It returns ranked snippets and uses far fewer tokens.

- Search: `semble search "<what the code does>" <repo-root> -k 5 --max-snippet-lines 10`
  - `-k N` = number of results. `--max-snippet-lines 10` = signature + first lines; omit for the full chunk; `0` = no code.
  - `--content all` also searches docs and config (default is code only).
- Related code: `semble find-related <file> <line> <repo-root>` — from a good hit.
- Go straight to the returned file:line. Do not repeat the search, and do not re-grep a hit to "confirm" it.
- A brief that says "find", "grep", or "search" for a concept still means semble — not an order to reach for `rg`.
- Use `rg`/grep only when you need EVERY occurrence of a literal: exhaustive counts, rename or caller audits, or when semble returns nothing useful.
