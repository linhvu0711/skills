---
name: improve-architecture
description: "Find design problems in a repo: modules too thin, parts that leak their inside, code hard to test, and parts heavier than their job. Show each as a card with a before and after diagram, talk through your choices, and after your go file the redesigns as tickets, with no code changed and nothing committed."
disable-model-invocation: true
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

Agents copy the design they read. A module that only passes calls on reads as "add one more layer here", and a caller that reaches into another part's cache reads as "reach in". This skill finds the code that needs a new design, files a ticket for each redesign after the user's go, and records an ADR for each design that stays on purpose. It changes no code.

Read `../../shared/codebase-design.md` first. It holds the vocabulary (**module**, **interface**, **depth**, **seam**, **adapter**, **leverage**, **locality**) and the principles (the deletion test, "the interface is the test surface", "one adapter = hypothetical seam, two = real"). Use these terms exactly, in every brief, every card, and every sentence to the user. Domain nouns come from `CONTEXT.md`: "the Order intake module", never "the FooBarHandler" and never "the Order service".

Read `../../shared/facts.md`: you are the brain, helpers retrieve, short lookups are yours.

Then read `../../shared/clean-codebase/run.md` and follow it whole. It runs the five steps, and it asks this skill for five things: § Kinds, § Search, § Helper, § Talk, and § Apply, below.

## Kinds

Four kinds. Every row is a **candidate**, shown as a card: the rows file sets `view` to `cards`.

- **Too thin**, id `deepening`, title `Too thin`. A module whose interface is nearly as complex as its implementation, one concept spread over many small modules, or a module that only passes calls on. It carries the deletion test result: deleting the module concentrates complexity in one place, or only moves it.
- **Leaks its inside**, id `leaks`, title `Leaks its inside`. A part whose callers read or set its inside across a seam, as Checkout reading the Pricing cache.
- **Hard to test**, id `hard-to-test`, title `Hard to test`. A part no test reaches through its interface, or pure functions pulled out for tests while the bugs sit in how they are called.
- **Heavier than its job**, id `too-heavy`, title `Heavier than its job`. A seam with one adapter, or a queue, a layer, or a config that one caller uses, as a retry queue only the SMS sender uses.

One row per candidate; its places are the files and lines involved. Every row's advice is one of two:

- `fix`: a ticket for the redesign.
- `keep-and-mark`: the part stays, and an ADR says why, so the next run leaves it out.

`choice` is true when the redesign holds a pick only the user can make, as the shape of the deepened module or which dependencies sit behind the seam, or when its worth rests on where the code goes next. Every other candidate has a clear answer, its advice.

A candidate an ADR turned down for a reason that still holds is no row. A candidate that goes against an ADR is a row only when the friction is real enough to reopen the ADR; its card's `adr` line says so, as `contradicts ADR-0007, but worth reopening because ...`.

**Order.** Hottest first: by the summed § Search count of each row's places, so the page lists the parts that change most at the top of each section.

**The card.** Each row's `card`, drawn per `references/cards.md`:

- `badge`: `Strong`, `Worth exploring`, or `Speculative`.
- `tag`: for a deepening, its dependency category per `references/deepening.md` (`in-process`, `local-substitutable`, `ports & adapters`, `mock`).
- `before` and `after`: one Mermaid diagram each, drawn for this candidate.
- `solution`: one sentence, what changes. No interface yet.
- `wins`: short bullets in glossary terms.
- `adr`: the ADR line above, when it applies.

The row's `name` is the card's title, and its `reason` the problem in one sentence.

## Borders

Some finds look like design and belong to another skill. Leave them out of the report:

- Unused code, copies, hacks, and comments belong to `prune-codebase`.
- Two different ways to do one job, as `fetch` in one module and `axios` in another, belong to `audit-coding-standards`.
- A wait or a retry in a test or in CI belongs to `improve-ci`.

A module that only passes calls on is this skill's: a Too thin candidate.

## Search

One search serves every kind. From the repo root, list the files in scope with `git ls-files`, minus what the run leaves out and minus prose, such as `.md` and `.txt`: code, scripts, and config. Count each file's changes over the last 200 commits:

```bash
git log -200 --name-only --format= -- <scope> | sort | uniq -c
```

## Helper

One helper judges every kind in one pass: `design-judge`. A batch is one folder's files, about ten, hottest folder first by § Search's counts; a bigger folder is split. Its brief holds:

- the batch's files and the span start;
- the full path of `../../shared/codebase-design.md`, and the domain terms from `CONTEXT.md`;
- each ADR, and each open issue's `## Docs to write` entry, that settles a design in the scope. In GitHub mode, the open issues come from `gh issue list --state open --limit 500 --search '"Docs to write" in:body'`; their text is decided, not built, and counts like an ADR. In no-GitHub mode, or when that search fails, the brief holds the ADRs alone, and the run goes on;
- § Kinds and § Borders, pasted whole.

When the helpers are back: apply the deletion test yourself to each Too thin candidate, give each deepening its dependency category per `references/deepening.md`, merge places that name one candidate, and draw each card per `references/cards.md`.

## Talk

What a decision asks, by kind:

- **Too thin**: the constraints on the deepened module; which dependencies sit behind the seam and how each is tested, per its category; the shape of the deepened module; which tests survive and which are replaced.
- **Leaks its inside**, **Hard to test**, **Heavier than its job**: whether to redesign, and how.

When the user asks to see other interfaces for a candidate, run `references/design-it-twice.md` before that decision closes.

A candidate the user turns down for a reason that stays true is answered `keep-and-mark`: the grill hands back its ADR, so the next run leaves the candidate out.

## Apply

- **Ticket or seed.** A `fix` row is a ticket row, typed `refactor`, with the design the talk settled in it. A `fix` row whose design the talk left open is a seed row.
- **ADRs.** A `keep-and-mark` row is its ADR, which the run writes at § Do it step 2.
- **Rules.** A rule a candidate makes, as "a seam needs two adapters", goes in the change list, and the run adds it by the Standard's shared step.
- **Edits.** The skill writes no edits of its own: every redesign is a ticket.

## Examples

**User:** `/improve-architecture`

The scan holds 420 files: 42 design-judge helpers, hottest folders first. `src/orders/` comes back with five modules that each pass the order on to `OrderRepo`; the deletion test concentrates. `src/checkout/total.ts` reads the Pricing cache. The page: `I found 2 things. I would fix 1. 1 needs your choice.` The Order intake card is Still spreading, badge `Strong`, tag `local-substitutable`, with a before diagram of five boxes and an after diagram of one. The talk asks the seam question for Order intake, and the user asks for three designs, so design-it-twice runs. The change list holds 2 tickets. The user says go: `R1 → #140 (ticket)`, `R2 → #141 (ticket)`, a line in the Run table, then `Ready for a pull request`.

**User:** `/improve-architecture src/notify`

The scan holds 12 files: 2 helpers. The one candidate, `Drop the retry queue`, is Known: open ticket #12 covers it. The page says `I found 1 thing. 1 is Known: an open ticket covers it.`, the run asks nothing, and the change list is empty.
