# grill

An interview that sharpens a plan or a design, one question at a time, and settles the glossary entries and the ADRs that ship with the work.

## Use it when

You have a plan with decisions still open, and you want them found and settled before anyone builds. Type `/grill` or say "grill me on this". `/grill #12` starts from a GitHub issue, most often a seed that [capture](../capture/) filed. A plain design chat does not start it; you have to ask.

## What you get

One question per message, each with its options and a recommended pick (the clean, long-term option, with any quick fix shown as a labelled fallback), until you agree the plan is understood. Each question explains the problem in plain words, with a small example when the idea is not obvious, and puts the code it rests on in a last `Seen:` line. Each question also comes with a picture that puts its options side by side, with one real example each. T3 Code shows it in the chat, and other hosts open it in your browser. After you answer, the next message starts with the next question and ends with a short `Got it:` line. New terms get a glossary entry, and a decision that is hard to reverse, surprising, and the result of a real trade-off gets an ADR. No doc file changes while you talk.

At the end you get the settled list, and the docs go with the work. When there is code to build, it files one issue through [file-issue](../file-issue/), a few issues through file-issue when they do not depend on each other, or an epic through [file-epic](../file-epic/) when they do. With more than one ticket, it names the shape (`3 issues`, `an epic with 4 children`) when it asks you to confirm. For an epic, a second model reads the decisions you agreed on, once, before anything is filed. In T3 Code it comes from another company; elsewhere it runs on your own harness's model. It looks for missing pieces and for decisions whose reason states a fact the code contradicts. Each finding the chat has not answered comes back to you as a question, and you confirm again. The check never runs twice, and the settled list shows its result, as `Gap check: 4 found · 3 asked · 1 already settled`. When the work changes a screen, grill stops before it files anything and suggests `/create-prototype`, so you can click through the design first. Whatever you change there joins the settled list, and the issues are filed when you say `go`. The agreed text goes in the issue under `## Docs to write`. The PR that ships the code writes the docs, so no doc says what the code does not do yet. A seed issue you started from becomes that issue, same number; it is never closed:

```
Grill done.
- Export streams in one request; no job queue.
- "Order" means a placed order, never a cart.
https://github.com/acme/shop/issues/12 · M: about 60 lines, 3 files · feat
```

When no code follows ("we will not build X", or a word for code that exists), the docs are true now, so you get one docs PR, opened by [make-pr](../make-pr/). It never merges the PR.

When the caller files the work itself ([triage](../triage/), [audit-coding-standards](../audit-coding-standards/)) or keeps a map ([discover-path](../discover-path/)), the grill writes nothing and hands back the doc text.

Each fact it states now carries an evidence label (Seen, Inferred, Guess, or Unknown), and it tries to see a fact itself, by safe reads, searches, and runs, before it calls it a guess, per the shared `facts.md`.

A `perf` ticket's body now carries a `Baseline:` line (the number, its median, spread, run count, command, and machine) and a `Target:` line, so the number reaches the plan and the PR.

## Needs

- `gh`, signed in, for seed issues.
- `git`.
- Readers for the code and for research, per the reader job in `../../shared/facts.md`. Codex has none, so there it reads the files itself.
- [file-issue](../file-issue/) and [file-epic](../file-epic/), to file the work with its doc text.
- The `gap-checker` subagent, in `agents/`, for work filed as an epic. It starts per `../../shared/facts.md` § Skill agents, on the try list its tier gives for your harness. [link.sh](../../scripts/link.sh) installs it into Claude Code and Codex.
- [make-pr](../make-pr/), for the docs PR when no work follows.
- [unslop](../unslop/), run on the prose before the commit.
- From the shared core: [grilling.md](../../shared/grilling.md) and [facts.md](../../shared/facts.md).

## Fits with

- Calls [unslop](../unslop/), then [file-issue](../file-issue/) or [file-epic](../file-epic/), or [make-pr](../make-pr/) when no work follows.
- Suggests [create-prototype](../create-prototype/) before it files work that changes a screen.
- Sends a bug to [triage](../triage/) first, and work too big for one session to [discover-path](../discover-path/).
- Called with a seed by [discover-path](../discover-path/), [triage](../triage/), [improve-architecture](../improve-architecture/), and [audit-coding-standards](../audit-coding-standards/).
- Named as the next step when a gate fails in [file-issue](../file-issue/), [file-epic](../file-epic/), [plan-up](../plan-up/), and [create-prototype](../create-prototype/).

## Credits

Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT): the `grilling`, `grill-me`, `grill-with-docs`, `domain-modeling`, and `research` skills. The structure and some sentences come from there, rewritten around this repo's skills. `references/ADR-FORMAT.md` and `references/CONTEXT-FORMAT.md` are copied as they are.
