# prune-codebase

Finds code comments that teach agents bad habits, shows them on a report page, and after your go edits them, files tickets for the hacks, and adds rules. Nothing is committed.

## Use it when

Agents in your repo keep copying hacks and trusting stale comments. A `// temp fix, clean up later` tells the next agent that hacks are fine there. Type `/prune-codebase` (`$prune-codebase` in Codex) to read the whole repo, or add a folder to read less: `/prune-codebase src/billing`. It leaves out vendored, generated, and gitignored files.

## What you get

A report page in your browser. Its first line says what "new" means for this run, such as "since the last prune-codebase run, 2026-11-01". Then one sentence sums it up: "I found 7 things. I would fix 4. 2 need your choice. 1 is Known: an open ticket covers it."

Each row is one kind of bad comment with every place it shows: comments that repeat the code, comments that are no longer true, code inside a comment, banner lines, long notes of why, and hacks or `TODO`s with no ticket link. A row shows the advice (fix, keep and mark, or not a bad example), a reason, and a count. Click a row to see each place and how the agent knows, marked Seen or Inferred. Rows with new places come first, under Still spreading. A row that needs your choice stands out, and buttons filter the rows by advice. A row an open ticket already covers shows as Known and gets no question. A row whose ticket was closed but whose problem is back shows as Came back.

Some comments always stay: a short comment that says why, a license header, a doc comment on a public function, a tool line with a reason, a shebang, a pragma, and the `Given`, `When`, and `Then` lines in a test. A hack or a long note of why still gets a row, even when it says why.

Then it asks only about the rows that need you, one question at a time, through [grill](../grill/). Rows with a clear answer get no question. Then it prints one change list in chat: the tickets, the new rules, the lint settings, the comment edits, and the ADRs. Say `go`, or name a line to change.

After the go it files the tickets first: a hack with a known fix becomes a ticket, and an unclear one becomes a seed. It writes an ADR for each long note of why and leaves one line with the link in the code. It edits the comments, adds a ticket or ADR link to each hack you keep, and checks that `git diff` on the code files shows only comment lines. It adds each rule to `CODING_STANDARDS.md`, and one line to the Run table in `docs/standards/runs.md`, so the next run knows what is new. Nothing is committed. The last line is `Ready for a pull request` when a file changed.

When it finds nothing, the page says so, and the skill asks nothing and writes nothing. Stop the talk before the go and it files and writes nothing. Without GitHub, or with no right to file issues there, you still get the report, the talk, and the change list in chat, but it files no ticket and writes no file.

## Needs

- `gh`, signed in, for the tickets and the Known check. Without it the run stops at the change list.
- A browser (`open` on macOS, `xdg-open` on Linux), with `python3`, `curl`, and `lsof` for the local server. Without a browser, the `to-artifact` skill (not in this repo) publishes the page instead.
- An agent that can start subagents, for the comment-judge helper, which reads about ten files at a time.
- The shared core: [clean-codebase](../../shared/clean-codebase/) runs the five steps and builds the page, and [facts.md](../../shared/facts.md) says how facts are fetched.
- [grill](../grill/) for the talk, and [to-issue](../to-issue/) and [capture](../capture/) for the tickets and seeds.

## Fits with

- Calls [grill](../grill/), [to-issue](../to-issue/), and [capture](../capture/). A rule goes in through the Standard's shared step, as in [audit-coding-standards](../audit-coding-standards/).
- Hands off to [make-pr](../make-pr/) for the files it leaves uncommitted.
- [ship](../ship/) can fix a ticket it filed later: `/ship #42`.
