# The clean-codebase run

Paths in this file are relative to its own folder, after links are followed. Before you run or read one, put that folder's absolute path in front of it.

The five steps every clean-codebase skill runs on a repo: scan, report, talk, change list, do it. The skill that reads this file gives four things the steps ask for, each in its own section, and may give a fifth:

- **Kinds**: the report kinds it finds, each an `id` and a `title`, and for each kind of row its advice and when a row needs the user's choice. It may also give the order of the rows, as `hottest first`.
- **Search**: for each kind, how search tools find its places, before any helper reads. One search may serve every kind.
- **Helper**: for each kind, the skill agent that judges a batch of its places, how big a batch is, and what its brief pastes in. One helper may judge every kind in one pass.
- **Apply**: which rows become a ticket and which a seed, and how the skill writes its own edits after the go.
- **Talk**, when the skill has one: what a decision asks for its kinds, and each step that runs during the talk when the user asks for it.

Words such as **Row**, **Known**, **Came back**, **Keep and mark**, **Change list**, and **Run table** mean what `../../CONTEXT.md` § Clean codebase says.

The run reads the whole repo and has no time limit. A big repo takes long, so print one line as each step starts, with what it holds, as `Scan: 1,240 files, 38 helpers.` or `Talk: 4 decisions.`

The run makes no commit, no branch, and no pull request. Until the user's go, it files and writes nothing.

## Scan

1. **Scope.** The whole repo, or the folder the user names, any way they name it. A named folder that does not exist: say `No folder
   <path> in this repo.` and stop. Leave out what the repo does not own:
   vendored and generated files, gitignored files, lockfiles, and embedded sources.
2. **GitHub.** Once:

   ```bash
   gh repo view --json nameWithOwner,hasIssuesEnabled,isArchived
   ```

   It fails, issues are off, or the repo is archived: the run is in no-GitHub mode (§ No GitHub). Hold the error line, or `issues are off`, or `the repo is archived`.
3. **Span.** What "new" means for this run. Read the Run table (§ Run table). Its last line for this skill gives the span start: that date and commit, as `since the last prune-codebase run, 2026-11-01 at 9c1d2e3`. No line for this skill: pick the span from the pace of the repo, as `git log --since=<date> --oneline | wc -l` shows it, with no fixed number, and say why in the phrase, as `the last 3 weeks: about 40 commits a week, no earlier run`. Hold the phrase as `new`, and the span start as a date.
4. **Places.** Run the skill's § Search on the scope, for each kind, or once when it serves every kind. Hold `HEAD`'s short SHA as the run's commit.
5. **Judge.** Batch each kind's places as the skill's § Helper says, about ten files per batch, per `../facts.md` § Brain and hands. Start each kind's helper on each of its batches per `../facts.md` § Skill agents, all in one message. A helper that judges every kind starts once per batch, not once per kind. Each brief holds the batch's files, the span start, and what the skill's § Helper says to paste in. Each place comes back with its `path:line`, its text, its row kind, its evidence label (`Seen` or `Inferred`, per `../facts.md` § Evidence labels) and proof, and `new`: its line is newer than the span start.

Done when every helper came back.

## Rows

Group the places into rows. A row is one kind of problem: every place it shows, its advice, one reason, and whether it needs the user's choice. The skill's § Kinds says how its places group. The advice is `fix`, `keep-and-mark`, or `fine` (not a bad example). `choice` is true only when the right answer needs a fact only the user holds, such as whether a hack is still needed; every other row has a clear answer, its advice.

A row is **Still spreading** when one of its places is new.

The rows go in the rows file in the order the skill's § Kinds gives, else as they came back.

The rows file's shape, every key and its values, is the one `build-report.py` checks; its problem lines name each fault. A skill whose report shows each row as a card, with a before and an after diagram, sets `view` to `cards` and gives each row a `card`; its § Kinds says what a card holds.

## Known and Came back

GitHub mode only. For each row, search the repo's issues by its words and by a place's path:

```bash
gh issue list --state all --search "<2 or 3 words of the row>" --limit 20 --json number,title,url,state,closedAt
```

- An open issue that is clearly this row's problem: the row's `state` is `known` and its `ticket` that `#<n>`. A Known row gets no question and no change, so its `choice` is false.
- A closed issue whose problem is in the code again: `state` is `came-back`, `ticket` that `#<n>`. It is asked like any other row.

A failed search: the rows stay as they are, and `not_checked` gets the line `Known and Came back, <the error line>`. In no-GitHub mode, `not_checked` gets `Known and Came back, <the line held at Scan>`.

## Report

1. Write the rows file to `$HOME/.agents/artifacts/codebase/clean-<skill>-<owner>-<repo>.json`. `<owner>` and `<repo>` come from the `origin` remote URL; a repo with no `origin` uses `local` and its folder name. Create the folder when needed. The file never goes into the repo it reads. `changes` lists what the change list will hold, one line per part with its count, as `Comment edits: 251 in 40 files` or `Tickets: 2`. `not_checked` lists each check the run could not do, one line each with why, as `Old API use, no web access`; the page shows each as `Not checked: <line>`. Leave it out when every check ran.
2. Build the page:

   ```bash
   python3 build-report.py "$HOME/.agents/artifacts/codebase/clean-<skill>-<owner>-<repo>.json"
   ```

   It prints `page: <path>`. Problem lines name each fault in the rows file: fix the file and build again.
3. Serve it with the shared serve script, which prints its URL:

   ```bash
   URL=$(../serve.sh "$HOME/.agents/artifacts/codebase" "clean-<skill>-<owner>-<repo>.html")
   ```

   The script exits with an error (no free port, or the server does not give back the file): chat gets its error line and the `.html` path, and the run stops.

   Then open it in the user's browser: `open "$URL?v=$(date +%s)"` on macOS, `xdg-open "$URL?v=$(date +%s)"` on Linux. The `v` makes a rerun on the same repo show the new page, not the cached one.

   **Headless host** (`command -v open xdg-open` finds neither, or the open command exits with an error, as `xdg-open` does on a Linux host with no display): there is no browser to leave the page in. Give no local URL. Publish the page with the `to-artifact` skill and give the artifact link in place of the URL. When the open command failed, chat also gives its error line, so the user can fix the browser setup. Publish fails: say why, give the `.html` path, stop.
4. Chat gets the URL, or the artifact link, and the page's summary line.

No rows and nothing in `changes`: the page says `I found nothing to change.`, and the run ends there. It asks nothing, files nothing, and writes nothing. No rows with a change, such as Sources table dates the research checked again: the page says `I found nothing to fix.`, the talk has no decision, and the run goes on to § Change list.

## Talk

1. **Decisions.** Sort the rows into decisions first. A row with `choice` false gets no question: its advice is its answer. Rows that one answer settles, such as three `TODO` comments that wait on the same fix, are one decision. A big row, or a row alone, is one decision. No decision is open: skip the grill and go to § Change list.
2. **Grill.** Hand the decisions over as a seed, in the caller's block that `../../skills/grill/SKILL.md` § Seed names:

   ```
   Read ../../skills/grill/SKILL.md and follow it. Seed: the report <URL> and its rows file <path>. Open decisions: <one per decision, with its rows>. Close out: text. Then continue at § Talk step 3 of the clean-codebase run.
   ```

   A skill with a § Talk: each open decision also carries what that section asks for it, as `<decision>, with its rows; ask: <what the skill's § Talk asks>`, and the block adds `Also run: <each step the skill's § Talk names>, when the user asks for it.` before `Close out: text.`

   `Close out: text.` keeps the grill from writing files: it hands back each doc entry it settled, with `already true` or `with code`.
3. **Count.** Every row has an answer: its advice, or the user's pick. A row with no answer is asked about first, one question per message, in the format of `../grilling.md`.

The user stops the talk before the go: say `Stopped: nothing filed or written.` and end the run.

Done when every row has an answer.

## Change list

First group the ticket rows into tickets. A ticket is one issue and one PR, so small work that belongs together is filed, planned, and reviewed once. Size each ticket row by `../size.md`. Rows share a ticket when all three hold:

- each row is XS or S, and the ticket stays M or smaller;
- the rows have one type, the leading word of the issue title per `../issue-rules.md` § Types, as `refactor` or `fix`;
- one PR would do them together, and a reviewer reads it as one change: they touch the same files or folder, they are the same kind of fix, or one answer in the talk settled them.

A row of size L gets a ticket of its own. A seed row stays alone, since its fix is not known yet. Number the tickets in list order: `Ticket 1`, `Ticket 2`.

Then print one list in chat, each part with its count and its lines:

```
Change list
Tickets: 3 for 5 rows
  Ticket 1: R2, R5, R7 · refactor · S · delete the unused date helpers
    R2 Unused: formatV1 · src/dates.ts:12
    R5 Unused: formatV2 · src/dates.ts:40
    R7 Copies: parseDate in 2 files · src/orders.ts:8
  Ticket 2: R3 · fix · S · Hack: Safari drops the first event · src/event.ts:12
  Seed: R4 · don't touch, breaks prod · src/pay.ts:40
Rules: 1
  Comments: a TODO links its ticket. (you)
Lint settings: none
Comment edits: 251 in 40 files
  delete 240 that repeat the code, 8 banner lines, 3 that are no longer true
ADRs: 1
  docs/adr/<next>-why-orders-retry-twice.md, from src/orders/retry.ts:3
Docs: none
```

Then `Say go, or name a line and what to change.` and wait. A change, as `split R7 out of Ticket 1` or `join Ticket 1 and Ticket 2`: make it, print the list again, and wait again. `Docs` holds each doc entry the grill handed back that is not an ADR, as a `CONTEXT.md` term. A part with nothing in it says `none`.

In no-GitHub mode, print the list, then `GitHub cannot be reached: nothing filed or written.` with the line held at Scan, and end the run.

## Do it

After the go, in this order:

1. **Tickets.** First, so each `path:line` still matches the commit GitHub has. The skill's § Apply says which rows are tickets and which are seeds; the change list says which rows share a ticket.
   - A ticket: start the `to-issue` skill, with the ticket as the chat's last words: its title and type, the checkout path, and for each row its name, its places, and the fix. The issue body names every row and its places, so a later run's § Known and Came back search finds it by any row. Each ADR or doc entry for that work goes in it, under `## Docs to write`, per `../issue-rules.md` § Docs to write. It files a ticket, or, when it prints a `Captured:` line, it filed the ticket through capture itself.
   - A seed row, or a to-issue gate stop with no `Captured:` line: start the `capture` skill, with the row or the ticket as the seed.
   - One line per ticket in chat: `R2, R5, R7 → #123 (ticket)` or `R4 → #124 (seed)`.
   - Each row's ticket is the issue its ticket filed. An edit or a rule that links a row's ticket, as a `see #<n>` comment or an `Old way: moment (#<n>)` mark, links that number.
   - A ticket that cannot be filed: stop before any file is written. Say `Not filed: <ticket>, <the error line>. Nothing written.` and list the tickets filed so far.
2. **ADRs.** Each ADR that is true already, as `docs/adr/<next>-<slug>.md` in the repo's ADR folder (`docs/adr/` when it has none), `<next>` the next free number. They come before the skill's edits, so an edit can link one. An ADR for work in a ticket went into that ticket in step 1.
3. **Edits.** The skill's own edits, per its § Apply.
4. **Rules.** Each rule and lint setting, by `../coding-standards/standard.md` § Add one rule and § Lint settings.
5. **Docs.** Each other doc entry that is true already, in its file.
6. **Run table.** One line, per § Run table.

Last line: `Ready for a pull request` when `git status --short` shows a file the run changed. Otherwise the ticket lines are last.

## Run table

The table in `docs/standards/runs.md`. No file yet: create it as

```
# Runs

One line per clean-codebase run. The next run of a skill reads its last line to know what is new.

| Skill | Date | Commit |
|---|---|---|
```

Add `| <skill> | <date> | <the run's commit> |`. Only § Do it adds a line, so a run that found nothing, stopped before the go, or had no GitHub adds none.

## No GitHub

GitHub cannot be reached, issues are off, or the repo is archived. The scan, the report, and the talk run; § Known and Came back is skipped. § Change list prints the list and ends the run: nothing is filed and no file is written.

The check cannot see whether the login may file issues. A login that may not is caught when its first ticket fails, at § Do it step 1, before any file is written. A change list with no ticket needs no GitHub, so its files are written.
