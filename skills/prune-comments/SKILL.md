---
name: prune-comments
description: "Find code comments that teach agents bad habits: comments that repeat the code, commented-out code, stale comments, and hack notes with no issue. Lists them in chat, and after the user's go removes the useless ones and logs an issue for each hack it keeps, in one comment-only PR taken to ready. Use for 'prune comments', 'clean up comments', 'remove useless comments'."
disable-model-invocation: true
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

Agents copy what the code shows them. A `// temp fix, clean up later` comment reads as "hacks are fine here", and a stale comment reads as truth. This skill finds those comments and cleans them up.

It changes comments only, and code stays exactly as it is. The list comes first; every edit, issue, and PR waits for the user's go.

## Facts

Read `../../shared/facts.md` first: you are the brain, readers retrieve, short lookups are yours.

## Keep test

A comment stays when it says why: a reason, a limit, or a source the code cannot show, such as a browser bug or the reason for a magic number. A comment on a workaround links the issue that tracks the real fix, as in `// Safari drops the first event, see #42`.

## Kinds

Every comment gets one kind.

- **Kept**, shown only as a count: license headers, doc comments on public functions and types, comments that pass the keep test, tool lines with a reason (`// eslint-disable-next-line no-console -- CLI output`), shebangs, and pragmas.
- **Clear to remove**, approved with one go:
  - repeats the code: `// loop over users` above the loop;
  - commented-out code: `// const old = fetchV1()`;
  - no longer true: `// returns null` above code that throws;
  - banner lines: `// ===== helpers =====`.
- **Needs your input**, one row each, with a suggested choice and its reason:
  - a workaround or hack comment with no issue link;
  - a `TODO`, `FIXME`, or `HACK` with no issue link;
  - a tool line with no reason;
  - any comment whose kind you are unsure of.

A row's choice is one of:

- `remove`: the comment goes.
- `keep`: nothing changes.
- `keep + issue (ticket)`: a hack whose fix the code or its history shows, such as a workaround for a browser version the repo no longer supports. The comment stays and links a full ticket.
- `keep + issue (seed)`: a hack whose fix is unclear, such as `// don't touch, breaks prod`. The comment stays and links a seed issue.

## Steps

1. **Scope.** The whole repo, or the folder or file the user names, any way they name it. Leave out what the repo does not own: vendored and generated files, gitignored files, lockfiles, and embedded sources. Done when you can name the paths in scope.

2. **Read.** Dispatch readers per `facts.md`, one per top folder in scope, in one message. Each brief holds its paths, § Keep test, and § Kinds pasted in, and asks for every comment as `path:line`, its text, and its kind; for a Needs-your-input comment also the suggested choice and the reason in a few words. A reader checks a stale comment against the code under it, and a hack against the code and `git log` for its fix. Done when every reader came back and every comment has a kind.

3. **List.** Chat gets this shape, then wait:

   ```
   Kept: 212 comments

   Clear to remove: 318
     Repeats the code (240), e.g. src/user.ts:14  // loop over users
     Commented-out code (51), e.g. src/api.ts:88  // const old = fetchV1()
     No longer true (19), e.g. src/cart.ts:30  // returns null (it throws now)
     Banner lines (8), e.g. src/utils.ts:1  // ===== helpers =====

   Needs your input: 3
     # | Where           | Comment                             | Pick                  | Why
     1 | src/event.ts:12 | // temp fix, Safari drops 1st event | keep + issue (ticket) | Safari 16 is no longer supported
     2 | src/pay.ts:40   | // don't touch, breaks prod         | keep + issue (seed)   | fix not clear
     3 | src/db.ts:7     | // TODO: retry                      | remove                | retry exists at src/db.ts:52

   Say go, or go with changes, as: go, but 2 keep
   ```

   Each kind shows 2 or 3 examples. Nothing to remove and no rows: say `Nothing to do: <n> comments, all kept.` and end the run with no branch and no PR.

4. **Go.** Read the answer any way the user writes it: `go`, `go, but 2 keep`, `go, 1 seed`. A row the answer does not name keeps its suggested choice. An answer that is not a go ends the run with nothing changed. Done when every row has its final choice.

5. **Issues.** Log them before any edit, so the `path:line` of each comment still matches the commit GitHub has. For each `keep + issue` row, in order:
   - `ticket`: say the row in chat (the comment, its `path:line`, the checkout path, the hack, and its fix), then invoke the `to-issue` skill with the Skill tool, with the row as the conversation's last word.
   - `seed`, or `to-issue`'s gate stops: invoke the `capture` skill with the Skill tool, with the comment, its `path:line`, the checkout path, and why it looks like a hack as the seed.
   - Neither can log it (no GitHub repo, no access): the row becomes `keep`, with the reason.

   Done when chat holds one line per row: `row 1 → #123 (ticket)`, `row 2 → #124 (seed)`, or `row 2 → not logged: <reason>`.

6. **Edit.** Delete each removed comment: the whole line when the comment is the whole line, else only the comment and the space before it. Add the issue to each comment that got one, in the repo's form for issue links, else as ` see #<n>`. Done when every choice is applied and `git diff` shows only comment lines.

7. **PR.** Invoke the `make-pr` skill with the Skill tool, with its caller settings:
   - Branch: `chore/prune-comments`, or `chore/prune-comments-<words of the path>` when a path was named.
   - Files: the files step 6 changed, and only those.
   - Issue line: none.
   - Summary: the count per kind removed, and the count of rows per choice. Follow-ups: each issue step 5 logged, one line each.

   Done when it prints the PR URL.

8. **Ready.** Read `../ready-pr/SKILL.md` and follow it whole on that PR. Its stop points are yours, and the merge stays the user's. Done when it prints `READY <url>`, or a stop line.

9. **Report.** Chat gets the PR link, one line per logged issue as step 5 wrote it, and, last, the line `/ready-pr` printed, word for word.

## Examples

**User:** `/prune-comments`

Four top folders, four readers. The list shows 212 kept, 318 to remove in four kinds, and 3 rows. The user says `go, but 3 keep`. Row 1 goes to `to-issue` as #123, row 2 to `capture` as #124. 318 comments go, two comments get ` see #123` and ` see #124`. `make-pr` opens the PR on `chore/prune-comments`, and `/ready-pr` ends with `READY <url>`.

**User:** `/prune-comments src/billing`

One reader on `src/billing`. Every comment there passes the keep test. Chat says `Nothing to do: 41 comments, all kept.` and the run ends.
