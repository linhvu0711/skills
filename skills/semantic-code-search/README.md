# semantic-code-search

Finds code by what it does, with `semble`, before the agent falls back to grep.

## Use it when

You or the agent need to find code by meaning: "where is login expiry handled?", "how does session renewal work?", a symbol by name, or code related to a hit you already have. The agent reaches for it on its own whenever a brief says find, search, explore, or grep for a concept.

## What you get

A few ranked snippets with `file:line`, and the agent opens those files directly instead of grepping around.

```
semble search "refresh the session token" . -k 5 --max-snippet-lines 10
```

Grep still wins for exact literals: counting every use, auditing callers before a rename.

## Needs

- The `semble` CLI on your `PATH`.

## Fits with

- [embed-source](../embed-source/) runs `semble search` once after it embeds a library, so the index covers the new source.
