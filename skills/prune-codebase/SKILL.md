---
name: prune-codebase
description: "Find code comments that teach agents bad habits, show them on a report page, talk through your choices, and after your go edit the comments, file tickets for the hacks, and add rules, with nothing committed."
disable-model-invocation: true
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

Agents copy what the code shows them. A `// temp fix, clean up later` comment reads as "hacks are fine here", and a stale comment reads as truth. This skill finds those comments, and after the user's go it edits them, files a ticket for each hack it keeps, and adds a rule where one stops the next. It changes comment lines only.

Read `../../shared/facts.md` first: you are the brain, helpers retrieve, short lookups are yours.

Then read `../../shared/clean-codebase/run.md` and follow it whole. It runs the five steps, and it asks this skill for four things: § Kinds, § Search, § Helper, and § Apply, below.

## Always stays

These comments are never a place, and no row names them:

- a short comment that says why: a reason, a limit, or a source the code cannot show, such as the reason for a magic number;
- a license header;
- a doc comment on a public function or type;
- a tool line with a reason, as `// eslint-disable-next-line no-console -- CLI output`;
- a shebang;
- a pragma;
- the `Given`, `When`, and `Then` lines in a test.

A hack and a long note of why are rows per § Kinds, even when they say why.

## Kinds

One report kind: id `comments`, title `Comments`. Six kinds of row, each with its advice:

- **Repeats the code**: `// loop over users` above the loop. Advice `fix`: delete. All such places are one row.
- **No longer true**: `// returns null` above code that throws. Advice `fix`: delete it, or correct it when the comment says something the code cannot show; the change list gives the new text. All such places are one row.
- **Code inside a comment**: `// const old = fetchV1()`. Advice `fix`: delete. All such places are one row.
- **Banner line**: `// ===== helpers =====`. Advice `fix`: delete. All such places are one row.
- **Long note of why**: many lines that explain a decision, as a twenty-line block above a retry loop. Advice `fix`: move it to an ADR and leave one line with its link. One row per note, and `choice` is true: whether it is worth an ADR, and its title, are the user's.
- **Hack or `TODO` with no ticket or ADR link**: `// temp fix, Safari drops the first event`, `// TODO: retry`, `// don't touch, breaks prod`. One row per hack, unless one fix covers several. The advice:
  - `keep-and-mark` with a ticket, when a fix can come;
  - `keep-and-mark` with an ADR, when the hack stays for good;
  - `fix`: delete, when the code already does what the note asks, as a `TODO: retry` above code that retries.

  `choice` is true when the fix is unclear, or when the hack may still be needed.

A tool line with no reason is not a row.

## Search

From the repo root, list the files in scope with `git ls-files`, minus what the run leaves out. Then find the comment lines with `rg -n`, using the comment markers of the languages present: `//`, `#`, `/*`, `--`, `<!--`, `;`. Keep only the files with a hit. A file's places are its comment lines.

## Helper

`comment-judge`, one per batch. Its brief holds the batch's files, the span start, and § Always stays and § Kinds of this file, pasted in whole.

## Apply

- **Ticket or seed.** A hack row whose answer is `keep-and-mark` with a ticket: a ticket row when its fix is known, as a workaround for a browser version the repo no longer supports; a seed row when the fix is unclear, as `// don't touch, breaks prod`. The run files them.
- **Edits.** After the run filed the tickets and wrote the ADRs:
  - delete: the whole line when the comment is the whole line, else only the comment and the space before it;
  - correct: replace the comment's text with the new text from the change list;
  - long note of why: replace the note with one line in the file's comment form, `Why: see docs/adr/<file>.md`;
  - keep and mark: add ` see #<n>` for a ticket or ` see docs/adr/<file>.md` for an ADR at the end of the comment, in the repo's form for links when it has one.
- **Diff check.** Then `git diff -U0` on the files you edited. Each changed line is a comment line, or keeps its code outside the comment as it was, as `foo(); // loop` that becomes `foo();`. A file with any other change: undo your edits in that file, and name it in chat with the line whose code changed.

## Examples

**User:** `/prune-codebase`

The search finds comments in 120 files: 12 helpers. The report: `I found 7 things. I would fix 4. 2 need your choice. 1 is Known: an open ticket covers it.` `Comments that repeat the code` is Still spreading, with 3 new places since the last run. The talk asks two questions: a long note of why in `src/orders/retry.ts` becomes an ADR, and the Safari hack gets a ticket. The change list holds 1 ticket, 1 ADR, and 251 comment edits. The user says go. `R3 → #123 (ticket)`, the ADR, the edits, a line in the Run table, then `Ready for a pull request`.

**User:** `/prune-codebase src/billing`

The search finds comments in 6 files: 1 helper. Every comment there always stays. The page says `I found nothing to change.`, and the run ends with nothing written.
