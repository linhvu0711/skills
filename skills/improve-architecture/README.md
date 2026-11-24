# improve-architecture

Scans a codebase for two kinds of candidate: shallow modules worth deepening, and code to simplify. Shows them in a visual report, then grills you on every one and files the work as issues.

## Use it when

The code has become hard to change or hard to test, or has grown parts nobody needs, and you want to know where a refactor or a cut would pay off most. Type `/improve-architecture`, or add a direction: `/improve-architecture the notification code is a mess`. With no direction it looks where the last 200 commits landed.

## What you get

An HTML report that opens in your browser as a local page. A candidate is a deepening (merge small modules that only pass work along into one deep module) or a simplification: dead code, copied code, code that redoes what the language or a package already does, an option no caller uses, twisted logic, or a package used for one small thing.

Each big candidate gets a card with the files, the problem, the change in plain words, the wins, a before and after diagram, and a strength badge (`Strong`, `Worth exploring`, `Speculative`). Small ones, such as a function nothing calls, sit in short tables grouped by topic, each row with its proof, as in `Seen: 0 hits, also by name and in config`. The report ends with a top pick.

When you say `go`, a [grill](../grill/) asks about every candidate: the big ones first, then each small table as one question. Say `drop` to skip one. A big one you drop for a lasting reason gets an ADR, so the next run leaves it out. Then the grill files the work as issues, as few as make sense, with the agreed glossary and ADR text inside. If you want to compare interfaces, three or more sub-agents each design one under a different constraint. Each design starts from how a caller uses the code, then fits its interface to that use. The designs are scored on 3 to 6 points named before they come back, one point at a time, and you get the scores and a pick. Parts the designs agree on count as a strong sign. Designs that differ wildly mean the question is unclear, so it is reframed, not averaged; a split that stays after one reframe comes to you as an open question, with the scores and a pick, and waits for your answer. A merge takes one or two parts from each design at most.

It changes no code and proposes no interface on its own.

Each fact it states now carries an evidence label (Seen, Inferred, Guess, or Unknown), and it tries to see a fact itself, by safe reads, searches, and runs, before it calls it a guess, per the shared `facts.md`.

## Needs

- `git`, for the recent history.
- Sub-agents: explorers for the code, per the reader job in `../../shared/facts.md`, and for the design-it-twice step the `interface-designer` agent in `agents/`, each started per `../../shared/facts.md` § Skill agents on the model its file names for your harness. The harness table, `../../shared/harness.md`, says how your harness starts them. [link.sh](../../scripts/link.sh) installs the agent file into Claude Code, Codex, and Antigravity.
- A browser (`open` on macOS, `xdg-open` on Linux), with `python3`, `curl`, and `lsof` for the local server, and the network for Tailwind and Mermaid. Without a browser, the `to-artifact` skill (not in this repo) publishes the page instead.
- [grill](../grill/), for the candidates.
- From the shared core: [facts.md](../../shared/facts.md), [codebase-design.md](../../shared/codebase-design.md) for the vocabulary and the principles, and [serve.sh](../../shared/serve.sh) to serve the report.

## Fits with

- Calls [grill](../grill/) on every candidate. The issues it files are typed `refactor`, so [plan-up](../plan-up/) adds a lock test where no test covers the code.
- [prune-codebase](../prune-codebase/) finds bad comments, edits them after your go, and files tickets for the hacks.
- No other skill calls it; you start it yourself.

## Credits

Adapted from the `improve-codebase-architecture` and `codebase-design` skills in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). The structure and some sentences come from there, rewritten around this repo's skills. `codebase-design.md` and `references/deepening.md` are copied as they are, with only their links to each other changed, and `references/design-it-twice.md` started as a copy and is now rewritten in parts; `codebase-design.md` lives in the shared core, so plan-up reads it too.

The caller-first brief, the scoring points named before the designs come back, and the rule to reframe a wild split instead of averaging it take ideas from the `architect` and `arena` skills in [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.
