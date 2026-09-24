---
name: semantic-code-search
description: "Find code by meaning with semble instead of grep. Use whenever you need to locate code by what it does ('where is login expiry handled?', 'how does session renewal work?'), find a symbol by name, or find code related to a hit you already have. Any brief that says 'find', 'search', 'explore', or 'grep' for a concept is this skill."
---

Search by meaning with `semble`: "where is X handled", "how does Y work", a symbol by name. It returns ranked snippets for far fewer tokens than grep.

- Search: `semble search "<what the code does>" <repo-root> -k 5 --max-snippet-lines 10`
  - `-k N` is the number of results. `--max-snippet-lines 10` gives the signature and first lines; leave it out for the full chunk, `0` for no code.
  - `--content all` searches docs and config too; the default is code only.
- Related code, from a good hit: `semble find-related <file> <line> <repo-root>`.
- Go straight to the returned `file:line`. A hit is already confirmed: open it, and move on from there.
- A brief that says "find", "grep", or "search" for a concept means semble.
- Reach for `rg` or grep when you need every occurrence of a literal: exhaustive counts, rename or caller audits, or when semble returns nothing useful.
