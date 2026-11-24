# audit-coding-standards

Makes your repo's `CODING_STANDARDS.md` when it has none, and checks it when it has one. It shows what it found on a report page, and after your go it files tickets and writes the rules. Nothing is committed.

## Use it when

Your repo has no Standard yet, or its rules are spread over `CONTRIBUTING.md`, `CLAUDE.md`, or `.cursor/rules/`. Or it has a `CODING_STANDARDS.md` that may have gone stale after a big upgrade or a few months. Type `/audit-coding-standards` (`$audit-coding-standards` in Codex) to read the whole repo, or add a folder to read less. It only runs when you call it.

## What you get

A report page in your browser. Its first line says what "new" means for this run, such as "since the last audit-coding-standards run, 2026-11-01". Then one sentence sums it up: "I found 9 things. I would fix 6. 3 need your choice."

Each row is one of three kinds:

- A rule that is old or wrong, such as "run flake8" when `ruff.toml` replaced flake8, or a rule the stack's own docs now say the opposite of.
- A job with no rule, with the rule it proposes and where that rule came from. Errors with no rule, where most of your code throws `HttpError`, is one.
- Code that breaks a rule, with every place it does. Tests count: a test named against your Tests rule is a place like any other.

In a repo with no Standard, every area (Names, Structure, Errors, Logging, Tests, and so on) is a job with no rule, so the first run writes the whole file. Rows with new places come first, under Still spreading. A row an open ticket already covers shows as Known and gets no question. A row whose ticket was closed but whose problem is back shows as Came back.

Each proposed rule names where it came from: a page read on this run, what most of your code already does, or you. The model's memory never counts as a source. The size of the repo decides which wins when they differ. In a small repo the docs win. In a bigger one your code's way wins, and the row asks you, with the docs' rule in its reason. The research reads only the stack parts that are due: after a major version bump, after 6 months, or when a part has no row in the Sources table yet. The details are in [research.md](references/research.md).

Then it asks only about the rows that need you, one question at a time, through [grill](../grill/). Rows with a clear answer get no question. Then it prints one change list in chat: the tickets, the rules, the lint settings, the scattered rules it moves in, and the Sources table rows. Say `go`, or name a line to change.

After the go it files the tickets first: code that breaks a rule gets a ticket that fixes it and turns on the lint setting. Then it moves scattered rules into the Standard and takes them out of their old files. It adds one line to `CLAUDE.md` and `AGENTS.md` that points at the Standard, updates `.editorconfig`, and writes the Sources table in `docs/standards/sources.md`. Each rule goes in through the Standard's one shared step. That step first looks for a rule that already says it, and writes a tool setting only when no code breaks it today. Then it adds a line to the Run table in `docs/standards/runs.md`, so the next run knows what is new. The last line is `Ready for a pull request`.

The Standard opens with three lines that explain its marks. A rule a tool checks lives in that tool's config, not in the file. `(name)` after a rule names its source. `[eslint, after #61]` means a tool will check the rule once ticket #61 lands. `Old way:` means existing code still uses a way you should not copy. The first area is One way for each job, as in `Dates: date-fns. Old way: moment (#61).` A topic with more than about 40 rules moves to `docs/standards/<topic>.md`. The shape is in [standard.md](../../shared/coding-standards/standard.md).

When it finds nothing, the page says so and nothing is written. When it found nothing wrong but checked some sources again, the page says "I found nothing to fix." and the change list offers to write their new dates. Stop the talk before the go and it files and writes nothing. Without GitHub, or with no right to file issues there, you still get the report, the talk, and the change list in chat, but it files no ticket and writes no file.

## Needs

- `gh`, signed in, for the tickets, the Known check, and open issues that name planned work.
- `git`, for the author count and the age of the rules.
- A browser (`open` on macOS, `xdg-open` on Linux), with `python3`, `curl`, and `lsof` for the local server. Without a browser, the `to-artifact` skill (not in this repo) publishes the page instead.
- Web search or the context7 MCP server, for the research.
- An agent that can start subagents, for the research and for the `rule-judge` helper in `agents/`, which reads about ten files at a time. It starts per `../../shared/facts.md` § Skill agents, on the home models its file names for your harness, or on its backup. [link.sh](../../scripts/link.sh) installs it.
- The shared core: [clean-codebase](../../shared/clean-codebase/) runs the five steps and builds the page, [coding-standards](../../shared/coding-standards/) holds the Standard's shape, and [facts.md](../../shared/facts.md) says how facts are fetched.
- Its own [checks.md](references/checks.md) and [research.md](references/research.md): where rules live, the four checks, the size of the repo, and how sources are read.
- [grill](../grill/) for the talk, and [to-issue](../to-issue/) and [capture](../capture/) for the tickets.

## Fits with

- Calls [grill](../grill/), [to-issue](../to-issue/), and [capture](../capture/).
- [prune-codebase](../prune-codebase/) runs the same five steps on bad comments.
- Hands off to [make-pr](../make-pr/) for the files it leaves uncommitted.
- [ship](../ship/) can fix a ticket it filed later: `/ship #42`.
