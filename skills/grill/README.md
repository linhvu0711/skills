# grill

An interview that sharpens a plan or a design, one question at a time, and writes the glossary and the ADRs as the answers settle.

## Use it when

You have a plan with decisions still open, and you want them found and settled before anyone builds. Type `/grill` (`$grill` in Codex) or say "grill me on this". `/grill #12` starts from a GitHub issue, most often a seed that [capture](../capture/) filed. A plain design chat does not start it; you have to ask.

## What you get

One question per message, each with its options and a recommended pick, until you agree the plan is understood. New terms go into `CONTEXT.md` as they settle. A decision that is hard to reverse, surprising, and the result of a real trade-off becomes an ADR in `docs/adr/`. At the end you get the settled list and a docs PR that closes the seed issue:

```
Grill done.
- Export streams in one request; no job queue.
- "Order" means a placed order, never a cart.
https://github.com/acme/shop/pull/58
```

It never merges the PR.

## Needs

- `gh`, signed in, for seed issues and the PR.
- `git`.
- Sub-agents that read code (Explore agents in Claude Code). Codex has none, so there it reads the files itself.
- [capture](../capture/), to file a seed when the grill started from a chat.
- [unslop](../unslop/), run on the prose before the commit.
- From the shared core: [grilling.md](../../shared-skill-core/grilling.md) and [facts.md](../../shared-skill-core/facts.md).

## Fits with

- Calls [capture](../capture/) and [unslop](../unslop/).
- Sends a bug to [diagnose](../diagnose/) first, and work too big for one session to [discover-path](../discover-path/).
- Called with a seed by [discover-path](../discover-path/), [diagnose](../diagnose/), [improve-architecture](../improve-architecture/), [set-coding-standards](../set-coding-standards/), and [set-review-rules](../set-review-rules/).
- Named as the next step when a gate fails in [to-issue](../to-issue/), [to-epic](../to-epic/), [plan-up](../plan-up/), and [create-mockup](../create-mockup/).

## Credits

Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT): the `grilling`, `grill-me`, `grill-with-docs`, `domain-modeling`, and `research` skills. The structure and some sentences come from there, rewritten around this repo's skills. `references/ADR-FORMAT.md` and `references/CONTEXT-FORMAT.md` are copied as they are.
