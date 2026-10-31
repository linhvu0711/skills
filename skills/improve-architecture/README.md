# improve-architecture

Scans a codebase for shallow modules worth deepening, shows the candidates in a visual report, then grills you on the one you pick.

## Use it when

The code has become hard to change or hard to test, and you want to know where a refactor would pay off most. Type `/improve-architecture` (`$improve-architecture` in Codex), or add a direction: `/improve-architecture the notification code is a mess`. With no direction it looks where the last 200 commits landed.

## What you get

An HTML report that opens in your browser as a local page, one card per candidate. Each card names the files, the problem, the change in plain words, the wins, a before and after diagram, and a strength badge (`Strong`, `Worth exploring`, `Speculative`). The report ends with a top pick. You choose a card, and a [grill](../grill/) works out the shape of the deeper module with you, then files the refactor as an issue, with the agreed glossary and ADR text inside. If you want to compare interfaces, three or more sub-agents each design one under a different constraint. Each design starts from how a caller uses the code, then fits its interface to that use. The designs are scored on 3 to 6 points named before they come back, one point at a time, and you get the scores and a pick. Parts the designs agree on count as a strong sign. Designs that differ wildly mean the question is unclear, so it is reframed, not averaged; a split that stays after one reframe comes to you as an open question, with the scores and a pick, and waits for your answer. A merge takes one or two parts from each design at most.

It changes no code and proposes no interface on its own.

Each fact it states now carries an evidence label (Seen, Inferred, Guess, or Unknown), and it tries to see a fact itself, by safe reads, searches, and runs, before it calls it a guess, per the shared `facts.md`.

## Needs

- `git`, for the recent history.
- Sub-agents: readers for the code, per the reader job in `../../shared/facts.md`, and for the design-it-twice step the `interface-designer` agent in `agents/` (Opus, xhigh), which [link.sh](../../scripts/link.sh) links into Claude Code; in Codex, its normal sub-agent.
- A browser (`open` on macOS, `xdg-open` on Linux), with `python3`, `curl`, and `lsof` for the local server, and the network for Tailwind and Mermaid. Without a browser, the `to-artifact` skill (not in this repo) publishes the page instead.
- [grill](../grill/), for the chosen candidate.
- From the shared core: [facts.md](../../shared/facts.md), [codebase-design.md](../../shared/codebase-design.md) for the vocabulary and the principles, and [serve.sh](../../shared/serve.sh) to serve the report.

## Fits with

- Calls [grill](../grill/) on the candidate you pick.
- No other skill calls it; you start it yourself.

## Credits

Adapted from the `improve-codebase-architecture` and `codebase-design` skills in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). The structure and some sentences come from there, rewritten around this repo's skills. `codebase-design.md` and `references/deepening.md` are copied as they are, with only their links to each other changed, and `references/design-it-twice.md` started as a copy and is now rewritten in parts; `codebase-design.md` lives in the shared core, so plan-up reads it too.

The caller-first brief, the scoring points named before the designs come back, and the rule to reframe a wild split instead of averaging it take ideas from the `architect` and `arena` skills in [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.
