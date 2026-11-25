# prune-codebase

Finds what teaches agents bad habits in a repo: bad comments, unused code, copies, and hacks. It shows them on a report page, and after your go it edits comments, files tickets, and adds rules. It changes no code and commits nothing.

## Use it when

Agents in your repo keep copying hacks, calling dead code, and trusting stale comments. A `// temp fix, clean up later` tells the next agent that hacks are fine there, and an unused `formatV1` looks like the way to format a date. Type `/prune-codebase` (`$prune-codebase` in Codex) to read the whole repo, or add a folder to read less: `/prune-codebase src/billing`. It leaves out vendored, generated, and gitignored files.

## What you get

A report page in your browser. Its first line says what "new" means for this run, such as "since the last prune-codebase run, 2026-11-01". Then one sentence sums it up: "I found 7 things. I would fix 4. 2 need your choice. 1 is Known: an open ticket covers it."

The page has a section per kind. In Comments, each row is one kind of bad comment with every place it shows: comments that repeat the code, comments that are no longer true, code inside a comment, banner lines, and long notes of why. Unused code is a function, file, folder, flag, or option that nothing uses. Its row says where the agent searched: the code, text strings, scripts, and config. When a caller outside the repo might use it, as a published package's export, the row is marked Inferred and asks you. Copies are the same code in more than one place. A script finds lines repeated across the whole repo, and a helper keeps the real copies. Hacks are code that goes around a problem instead of solving it, with or without a comment: a check turned off, an `as any` cast, a `sleep` that hides a timing problem, a `catch` that drops the error, a guard that hides a bug, or a `TODO`. Before it advises on a hack, it reads the line's history: the commits, the PR, and the issue behind it. A row shows the advice (fix, keep and mark, or not a bad example), a reason, and a count. Click a row to see each place and how the agent knows, marked Seen or Inferred. Rows with new places come first, under Still spreading. A row that needs your choice stands out, and buttons filter the rows by advice. A row an open ticket already covers shows as Known and gets no question. A row whose ticket was closed but whose problem is back shows as Came back.

Some comments always stay: a short comment that says why, a license header, a doc comment on a public function, a tool line with a reason, a shebang, a pragma, and the `Given`, `When`, and `Then` lines in a test. A long note of why still gets a row, and so does a hack, even when its comment says why.

Then it asks only about the rows that need you, one question at a time, through [grill](../grill/). Rows with a clear answer get no question. Then it prints one change list in chat: the tickets, the new rules, the lint settings, the comment edits, and the ADRs. Small rows of one type that one PR would fix together share a ticket, such as two unused helpers in one file, and a big row gets a ticket of its own. Say `go`, or name a line to change, such as `split R7 out of Ticket 1`.

After the go it files the tickets first. A fix to unused code, a copy, or a hack becomes a ticket, since the skill changes no code; a hack with an unclear fix becomes a seed. It writes an ADR for each long note of why and leaves one line with the link in the code. It edits the comments, adds a ticket or ADR link to each hack you keep, as a new comment line when it had none, and checks that `git diff` on the code files shows only comment lines. It adds each rule to `CODING_STANDARDS.md`, and one line to the Run table in `docs/standards/runs.md`, so the next run knows what is new. Nothing is committed. The last line is `Ready for a pull request` when a file changed.

When it finds nothing, the page says so, and the skill asks nothing and writes nothing. Stop the talk before the go and it files and writes nothing. Without GitHub, you still get the report, the talk, and the change list in chat, but it files no ticket and writes no file. A ticket it cannot file, as with a login that may not file issues, stops the run before it writes any file.

## Needs

- `gh`, signed in, for the tickets and the Known check. Without it the run stops at the change list.
- A browser (`open` on macOS, `xdg-open` on Linux), with `python3`, `curl`, and `lsof` for the local server. `python3` also runs `scripts/copies.py`, which finds repeated lines. Without a browser, the `to-artifact` skill (not in this repo) publishes the page instead.
- An agent that can start subagents, for the helpers, one per kind, each reading about ten files at a time: comment-judge, unused-judge, copy-judge, and hack-judge.
- The shared core: [clean-codebase](../../shared/clean-codebase/) runs the five steps and builds the page, [trail.py](../../shared/trail.py) reads a hack's history, the same script [why](../why/) runs, and [facts.md](../../shared/facts.md) says how facts are fetched.
- [grill](../grill/) for the talk, and [to-issue](../to-issue/) and [capture](../capture/) for the tickets and seeds.

## Fits with

- Calls [grill](../grill/), [to-issue](../to-issue/), and [capture](../capture/). A rule goes in through the Standard's shared step, as in [audit-coding-standards](../audit-coding-standards/).
- Hands off to [make-pr](../make-pr/) for the files it leaves uncommitted.
- [ship](../ship/) can fix a ticket it filed later: `/ship #42`.
- Two ways to do one job go to [audit-coding-standards](../audit-coding-standards/); the same code twice stays here.
- A wait or a retry in a test or CI goes to [improve-ci](../improve-ci/).
- Shares its history script with [why](../why/).
- A module that only passes calls on goes to [improve-architecture](../improve-architecture/).
