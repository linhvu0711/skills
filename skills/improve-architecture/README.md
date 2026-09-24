# improve-architecture

Scans a codebase for shallow modules worth deepening, shows the candidates in a visual report, then grills you on the one you pick.

## Use it when

The code has become hard to change or hard to test, and you want to know where a refactor would pay off most. Type `/improve-architecture` (`$improve-architecture` in Codex), or add a direction: `/improve-architecture the notification code is a mess`. With no direction it looks where the last 200 commits landed.

## What you get

An HTML report published as an Artifact, one card per candidate. Each card names the files, the problem, the change in plain words, the wins, a before and after diagram, and a strength badge (`Strong`, `Worth exploring`, `Speculative`). The report ends with a top pick. You choose a card, and a [grill](../grill/) works out the shape of the deeper module with you. If you want to compare interfaces, three or more sub-agents each design one under a different constraint, and you get a side-by-side comparison with a pick.

It changes no code and proposes no interface on its own.

## Needs

- `git`, for the recent history.
- Sub-agents: Explore agents to read the code, and for the design-it-twice step an `interface-designer` agent in Claude Code (its definition is not in this repo) or Codex's normal sub-agent.
- Claude Code's Artifact tool and its `artifact-design` skill, to publish the report.
- [grill](../grill/), for the chosen candidate.
- From the shared core: [facts.md](../../shared-skill-core/facts.md).

## Fits with

- Calls [grill](../grill/) on the candidate you pick.
- No other skill calls it; you start it yourself.

## Credits

Adapted from the `improve-codebase-architecture` and `codebase-design` skills in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). The structure and some sentences come from there, rewritten around this repo's skills. `references/codebase-design.md`, `references/deepening.md`, and `references/design-it-twice.md` are copied as they are.
