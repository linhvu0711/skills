# improve-architecture

Finds code that needs a new design: modules too thin, parts that leak their inside, code that is hard to test, and parts built for more than their job. It shows each one as a card with a before and after diagram, and after your go it files the redesigns as tickets. It changes no code and commits nothing.

## Use it when

Agents in your repo copy the shape they see. Five modules that each pass an order on to the next one tell the next agent to add a sixth. Type `/improve-architecture` (`$improve-architecture` in Codex) to read the whole repo, or add a folder to read less: `/improve-architecture src/notify`. It leaves out vendored, generated, and gitignored files.

## What you get

A report page in your browser. Its first line says what "new" means for this run, such as "since the last improve-architecture run, 2026-11-01". Then one sentence sums it up: "I found 3 things. I would fix 1. 1 needs your choice. 1 is Known: an open ticket covers it."

Each candidate is a card. A card shows the advice (fix, or keep and mark), the change as a title, one reason, a strength badge (`Strong`, `Worth exploring`, or `Speculative`), the kind, and two diagrams side by side: the code as it is, and as it would be. The page builder refuses a diagram that would not draw, and names the card, the side, and the line. It ends with the files involved and how the agent knows, marked Seen or Inferred. There are four kinds:

- Too thin: a module whose interface is nearly as complex as what it does, or one that only passes calls on. A deepening merges them into one deep module.
- Leaks its inside: a caller reads another part's inside, as Checkout reading the Pricing cache.
- Hard to test: no test reaches the part through its interface.
- Heavier than its job: a queue, a layer, or a seam built for one caller.

The parts of the code that changed most in the repo's last 200 commits come first, and cards with new lines sit under Still spreading at the top. A card that needs your choice stands out, and buttons filter the cards by advice. A card an open ticket already covers shows as Known and gets no question.

Then it asks only about the cards that need you, one question at a time, through [grill](../grill/). For a deepening it asks what the new module must hold, which dependencies sit behind its seam, its shape, and which tests stay. Then it prints one change list in chat: the tickets, the new rules, and the ADRs. Small redesigns of one type that one PR would do together share a ticket, such as two thin modules in one folder, and a big one gets a ticket of its own. Say `go`, or name a line to change, such as `split R2 out of Ticket 1`.

After the go it files the redesigns as tickets typed `refactor`, so [plan-up](../plan-up/) plans it with a lock test where no test covers the code. A design you keep on purpose gets an ADR, and the next run leaves it out. It adds each rule to `CODING_STANDARDS.md` and one line to the Run table in `docs/standards/runs.md`. Nothing is committed. The last line is `Ready for a pull request` when a file changed.

When it finds nothing, the page says so, and the skill asks nothing and writes nothing. Stop the talk before the go and it files and writes nothing. Without GitHub, you still get the report, the talk, and the change list in chat, but it files no ticket and writes no file. A ticket it cannot file, as with a login that may not file issues, stops the run before it writes any file.

## Needs

- `gh`, signed in, for the tickets and the Known check. Without it the run stops at the change list.
- A browser (`open` on macOS, `xdg-open` on Linux), with `python3`, `curl`, and `lsof` for the local server, and the network for Mermaid, which draws the diagrams. Without a browser, the `to-artifact` skill (not in this repo) publishes the page instead.
- `git`, for the change counts.
- An agent that can start subagents: the `design-judge` helper in `agents/`, one per batch of about ten files. [link.sh](../../scripts/link.sh) installs it into Claude Code and Codex.
- The shared core: [clean-codebase](../../shared/clean-codebase/) runs the five steps and builds the page, [codebase-design.md](../../shared/codebase-design.md) holds the vocabulary and the deletion test, and [facts.md](../../shared/facts.md) says how facts are fetched.
- [grill](../grill/) for the talk, and [to-issue](../to-issue/) and [capture](../capture/) for the tickets and seeds.

## Fits with

- Calls [grill](../grill/), [to-issue](../to-issue/), and [capture](../capture/). A rule goes in through the Standard's shared step, as in [prune-codebase](../prune-codebase/).
- Hands off to [make-pr](../make-pr/) for the ADRs and rules it leaves uncommitted.
- [plan-up](../plan-up/) and [ship](../ship/) build a ticket it filed: `/ship #42`.
- Unused code, copies, hacks, and comments go to [prune-codebase](../prune-codebase/).
- Two ways to do one job go to [audit-coding-standards](../audit-coding-standards/).

## Credits

Adapted from the `improve-codebase-architecture` and `codebase-design` skills in [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). The structure and some sentences come from there, rewritten around this repo's skills. `codebase-design.md` and `references/deepening.md` are copied as they are, with only their links to each other changed; `codebase-design.md` lives in the shared core, so plan-up reads it too.
