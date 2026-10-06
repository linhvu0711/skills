# grill

An interview that sharpens a plan or a design, one question at a time, and settles the glossary entries and the ADRs that ship with the work.

## Use it when

You have a plan with decisions still open, and you want them found and settled before anyone builds. Type `/grill` (`$grill` in Codex) or say "grill me on this". `/grill #12` starts from a GitHub issue, most often a seed that [capture](../capture/) filed. A plain design chat does not start it; you have to ask.

## What you get

One question per message, each with its options and a recommended pick (the clean, long-term option, with any quick fix shown as a labelled fallback), until you agree the plan is understood. New terms get a glossary entry, and a decision that is hard to reverse, surprising, and the result of a real trade-off gets an ADR. No doc file changes while you talk.

At the end you get the settled list, and the docs go with the work. When there is code to build, it files the issue through [to-issue](../to-issue/), or the epic through [to-epic](../to-epic/), and the agreed text goes in the issue under `## Docs to write`. The PR that ships the code writes the docs, so no doc says what the code does not do yet. A seed issue you started from becomes that issue, same number; it is never closed:

```
Grill done.
- Export streams in one request; no job queue.
- "Order" means a placed order, never a cart.
https://github.com/acme/shop/issues/12 · size/M · feat
```

When no code follows ("we will not build X", or a word for code that exists), the docs are true now, so you get one docs PR, opened by [make-pr](../make-pr/). It never merges the PR.

When another skill calls it and writes its own docs afterwards (set-review-rules, set-coding-standards, audit-coding-standards), the grill writes its files and opens no PR, so one PR holds all of them. When the caller files the work itself ([triage](../triage/)) or keeps a map ([discover-path](../discover-path/)), the grill writes nothing and hands back the doc text.

## Needs

- `gh`, signed in, for seed issues.
- `git`.
- Sub-agents that read code (Explore agents in Claude Code). Codex has none, so there it reads the files itself.
- [to-issue](../to-issue/) and [to-epic](../to-epic/), to file the work with its doc text.
- [make-pr](../make-pr/), for the docs PR when no work follows.
- [unslop](../unslop/), run on the prose before the commit.
- From the shared core: [grilling.md](../../shared-skill-core/grilling.md) and [facts.md](../../shared-skill-core/facts.md).

## Fits with

- Calls [unslop](../unslop/), then [to-issue](../to-issue/) or [to-epic](../to-epic/), or [make-pr](../make-pr/) when no work follows.
- Sends a bug to [triage](../triage/) first, and work too big for one session to [discover-path](../discover-path/).
- Called with a seed by [discover-path](../discover-path/), [triage](../triage/), [improve-architecture](../improve-architecture/), [set-coding-standards](../set-coding-standards/), [audit-coding-standards](../audit-coding-standards/), and [set-review-rules](../set-review-rules/).
- Named as the next step when a gate fails in [to-issue](../to-issue/), [to-epic](../to-epic/), [plan-up](../plan-up/), and [create-mockup](../create-mockup/).

## Credits

Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT): the `grilling`, `grill-me`, `grill-with-docs`, `domain-modeling`, and `research` skills. The structure and some sentences come from there, rewritten around this repo's skills. `references/ADR-FORMAT.md` and `references/CONTEXT-FORMAT.md` are copied as they are.
