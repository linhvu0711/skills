---
name: validate-pr-review
description: "Judge each finding in a PR review (GitHub comments, a bot review, or pasted text): is it true, did this PR cause it, is it worth fixing. One verdict and one reply line per finding. Stops at the verdict; fixes, issues, and replies happen only after the user says go."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`.

You take a review of one pull request and judge every finding in it. The
reviewer may be a person, a bot, or a pasted block of text. You do not
trust any of them. You open the code, settle each finding on three
questions, and hand back a table with one verdict per row. Nothing is
fixed, filed, or posted until the user says go.

## Facts

Read `../../shared-skill-core/facts.md` first. Short lookups
(`gh pr view`, one `rg` count) are yours.

Judge agents answer the three questions, one agent per file group.
Answering means tracing callers, running a test, and running blame,
so a judge is a `general-purpose` agent, not Explore. Explore
retrieves; a judge decides. The verdict and the reply text stay with
you: the verdict is a table lookup, the reply is your voice.

In Codex there are no subagents: run each judge brief yourself, one
after the other, and keep the same return shape.

## The three questions

Every finding is settled on exactly these, in this order.

1. **True?** Does the code do what the finding says? Answer from the
   code, not from the comment. Values: `yes`, `likely` (the code
   supports it but you could not run it), `no`.
2. **Ours?** Did this PR introduce it? For a finding that names a line:
   `git blame` that line at `HEAD`, then ask whether the blamed commit
   is already in the base. In the base means `old`. Not in the base
   means `ours`. For a finding about something missing (no test, no
   null check that never existed): `ours` if the task asked for it or
   the PR's own change makes it needed, else `old`.
3. **Worth it?** What breaks if it stays. `blocker`: wrong or unsafe as
   is. `should`: fix before merge. `nit`: style, naming, a cheaper
   shape of the same thing.

## Verdicts

| True | Ours | Worth   | Verdict      |
|------|------|---------|--------------|
| no   | any  | any     | `push back`  |
| yes/likely | ours | blocker/should | `fix here` |
| yes/likely | ours | nit | `fix here` if the change is a few lines on a hunk already in the diff, else `won't fix` |
| yes/likely | old  | blocker | `fix here` if the fix sits on lines the PR already touches, else `fix later` |
| yes/likely | old  | should/nit | `fix later` |

`fix later` always means one issue, filed with `/capture` after go, and
never a promise in the reply with no issue behind it.

`won't fix` and `push back` always carry a reason the reviewer can
check: a path and line, a test name, a command that shows it.

## Steps

1. **Preflight.** `git rev-parse --show-toplevel`. No repo: say so, stop.
   Resolve the PR:

   - Argument is a number or URL: `gh pr view <arg> --json number,url,baseRefName,headRefName,title,body,closingIssuesReferences`.
   - Argument is text or a file path: that text is the review. Still run
     `gh pr view` with no argument to find the PR of the current branch.
     None found: base is the default branch
     (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`,
     else `main`), and there is nothing to post to.
   - No argument: `gh pr view` with no argument. None found: say so, stop.

   `git fetch` the base. Hold the diff command `git diff <base>...HEAD`.

   Done when you hold the base, the head, the PR number or "no PR", and
   the review source (GitHub or text).

2. **Collect.** Build the list of findings.

   From GitHub, three endpoints, all three every time. `OWNER/REPO` is
   `gh repo view --json nameWithOwner -q .nameWithOwner`.

   ```bash
   gh api repos/OWNER/REPO/pulls/N/comments --paginate   # inline review comments
   gh api repos/OWNER/REPO/pulls/N/reviews  --paginate   # review bodies
   gh api repos/OWNER/REPO/issues/N/comments --paginate  # top-level comments
   ```

   From text: split on the reviewer's own list marks, headings, or
   blank lines.

   Each finding gets an id (`F1`, `F2`, …), the reviewer, the
   `path:line` if one was given, the claim in one sentence, and its
   **source**, which decides where the reply goes later:

   | Source   | Comes from                        | Keep                       |
   |----------|-----------------------------------|----------------------------|
   | `inline` | `pulls/N/comments`                | comment `id`, `in_reply_to_id`, thread resolved or not |
   | `review` | `reviews[].body` with claims in it | review `id`, reviewer login |
   | `top`    | `issues/N/comments`               | comment `id`, reviewer login |
   | `text`   | pasted or a file                  | nothing                    |

   Skip: threads already resolved, a comment that is a reply inside a
   thread you already hold (`in_reply_to_id` set), a thread whose last
   comment is the PR author's, and lines that state no claim ("LGTM",
   "thanks"). One comment that makes two claims is two findings. A bot
   review whose body only summarises its own inline comments gives no
   `review` findings; the inline rows already carry them.

   Done when every claim in the review has a row, or the list is
   empty, in which case say "nothing to validate" and stop.

3. **Split.** Sort the findings into two piles.

   - **Trivial**: the claim is about a line in the diff and needs no
     trace to check (a name, a comment, a typo, a formatting shape).
     You answer these yourself from the diff in step 4. `ours` is
     `ours`; it is in the diff.
   - **Judged**: everything else. Group these by file. A finding with
     no line goes with the file it is about. Cap at 8 groups: past
     that, pack the smallest groups together until 8 remain.

   Done when every finding is in one pile and the judged pile is at
   most 8 groups.

4. **Judge.** One `general-purpose` agent per group, all in one
   message. Each brief holds, inline and complete:

   - The repo root, the diff command from step 1, and `origin/<base>`.
   - The task text: the PR body, or the linked issue's title and body
     if `closingIssuesReferences` was non-empty.
   - The group's findings: id, `path:line` or "no line", the claim,
     verbatim.
   - The `The three questions` section of this file, pasted in full,
     with this ours command:

     ```bash
     sha=$(git blame -L LINE,LINE --porcelain HEAD -- PATH | head -1 | cut -d' ' -f1)
     git merge-base --is-ancestor "$sha" origin/BASE && echo old || echo ours
     ```

   - The instruction: read the code at each line with its callers, find
     the nearest test, run it when the claim is about behaviour, run
     the ours command for every finding with a line, and answer the
     three questions for every finding in the group. `likely` only for
     a claim you could not run. No verdict; the verdict is not yours.
   - The return shape below, verbatim.

   Return shape for a judge:

   ```
   - <id> | <yes|likely|no> | <ours|old> | <blocker|should|nit> | <one sentence of proof with path:line or test name> | <test command run, or "none">
   ```

   A judge that cannot answer a question writes `unclear` in that cell
   and names what would settle it in the proof cell.

   While the judges run, answer the trivial pile yourself from the
   diff, in the same shape.

   Done when every finding has a line in the return shape. A judge
   whose return misses an id it was given is sent back for that id
   only.

5. **Verdict.** Per finding, pick the verdict from the table. A row
   with `unclear` in any cell gets no verdict and goes under
   `## Unclear`. Write the reply line.

   Done when every row has a verdict or sits under `## Unclear`, and
   every row has a reply.

6. **Report.** Write the report in the shape under `Report shape` to
   `~/.claude/reviews/<repo>-<pr number or branch>-validation.md`
   (create the folder) and print it in chat. Then stop.

   Last line in chat: `Say go to apply: <n> fix here, <n> fix later, <n> replies to post.`
   When every finding is `text`: `Say go to apply: <n> fix here, <n> fix later. Replies are yours to paste.`

## After go

Only after the user says go, in this order.

1. `fix here` rows: make each change, run the test the judge named,
   commit with `/make-commit`, one commit per finding or one for the
   set when they touch the same hunk. Push only if the user's go said
   so.
2. `fix later` rows: `/capture` each one, with the finding's claim and
   `path:line` in the seed. Put the issue URL into that row's reply.
3. Replies: route each by its source, per `Reply routing`.
4. Resolve: every `inline` thread whose verdict is `fix here` and whose
   commit is pushed. Other threads stay open; the reviewer closes them.

The user may say go for part of it ("go, fixes only"). Do that part
and end with what is still waiting.

## Reply routing

The reply lines from the report are the text. Where they land depends
on the source. Post nothing twice: a thread whose last comment is
already yours is skipped.

- **`inline`**: one reply per thread, in the thread. Before posting,
  the reply gets the fix's commit SHA or the issue URL appended when
  there is one.

  ```bash
  gh api repos/OWNER/REPO/pulls/N/comments/COMMENT_ID/replies -f body="$reply"
  ```

- **`review` and `top`**: one PR comment for all of them together, not
  one comment each. The comment quotes each finding and answers it
  under the quote. With more than one reviewer, one `@login` heading
  per reviewer.

  ```markdown
  > <finding, quoted, trimmed to its claim>

  <reply line, with commit SHA or issue URL when there is one>
  ```

  ```bash
  gh pr comment N --body-file "$f"
  ```

- **`text`**: nothing is posted. Print the replies under a line that
  says where each one belongs, and stop.

Resolving a thread needs its node id, which the REST comment does not
carry. Fetch once, map comment `databaseId` to thread `id`, then
resolve:

```bash
gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100){nodes{id isResolved comments(first:1){nodes{databaseId}}}}}}}' -F o=OWNER -F r=REPO -F n=N
gh api graphql -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' -F t=THREAD_NODE_ID
```

A reply that fails to post (thread deleted, no permission) is reported
by id at the end, never retried in a different place.

## Report shape

```
# Validation: <PR title> (#<number> | <branch>)

Review by <reviewer(s)>, <n> findings

| id | source | finding | true | ours | worth | verdict |
|----|--------|---------|------|------|-------|---------|
| F1 | inline | <path:line> <claim, few words> | yes | ours | should | fix here |

## Proof
- F1: <one sentence, the fact that settles it, with path:line or test name>

## Replies
- F1 (thread): <one or two sentences to the reviewer. What you will do or why not. Reads as the author, not as a bot.>
- F4 (PR comment): <same>

Posting plan: <n> thread replies, one PR comment for <n> findings, <n> threads to resolve after push.

## Unclear
- <id>: <what is missing and how to get it>, or "None."
```

Rows in id order. Proof and replies cover every row, `push back`
and `won't fix` rows with the checkable reason.

## Terms

- **Finding**: one claim from the review. One sentence, one place in
  the code, one reviewer.
- **Ours**: the PR introduced it. Decided by blame against the base,
  never by who the reviewer blamed.
- **Old**: it was there before the PR. The PR may still be the right
  place to fix it, per the verdict table.
- **Reply**: the line the author says back to the reviewer. Every
  finding gets one, whatever the verdict.
- **Source**: where the finding came from (`inline`, `review`, `top`,
  `text`). Decides where the reply lands and whether a thread exists
  to resolve.

## Secrets

Review comments and the diff can carry tokens and `.env` values.
Redact before they enter a brief, the report, or a reply.

## Examples

**User:** `/validate-pr-review 42`

Step 2 pulls 6 inline comments from a bot, whose review body only
summarises them, and one top-level comment from a teammate with two
claims: 8 findings, six `inline`, two `top`. Step 3 puts two naming
nits in the trivial pile and the other six into four file groups.
Step 4 sends four judges in one message and answers the two nits from
the diff. Returns: F3 claims a nil deref on a new branch; the judge's
test reproduces it, `ours`, `blocker`. F5 claims a race in a helper the
PR only renamed; the code confirms it, `old`, `should`. F7 claims a
missing await; the function is sync, `no`, with the signature line as
proof. Step 5: F3 `fix here`, F5 `fix later`, F7 `push back`. Report
written and printed, chat ends with
`Say go to apply: 3 fix here, 2 fix later, 8 replies to post.`

After go: three commits, two `/capture` issues, six thread replies with
the SHA or issue URL appended, one PR comment quoting the teammate's
two claims, and three threads resolved after the push. Ends with
"Posted 6 thread replies, 1 PR comment, resolved 3 threads."

**User:** `/validate-pr-review 58` where a teammate left one "request
changes" review with a numbered list of five points and no inline
comments.

Step 2 splits the review body into five `review` findings. Three name
the same file, so step 3 makes three groups, not five. After go, all
five replies go into one PR comment, each under a quote of its point.
Nothing is resolved; there are no threads.

**User:** `/validate-pr-review 91` where a bot left 34 inline comments
across 19 files.

Step 3 sends 9 to the trivial pile and packs the remaining 25 findings
from 14 files into 8 groups. Eight judges run at once; the nine nits are
answered from the diff while they run.

**User:** `/validate-pr-review` followed by a pasted block of six
bullet points from a teammate's Slack message.

Step 1 finds the PR of the current branch. Step 2 splits the block on
bullets, six `text` findings. Steps 3 to 5 run the same. Chat ends
with `Say go to apply: 2 fix here, 1 fix later. Replies are yours to paste.`
After go, the fixes and issues happen; the six replies are printed, not
posted, because the review did not come from GitHub.

**User:** "go, fixes only"

Apply the `fix here` rows and commit. End with: "Still waiting: 2 fix
later issues, 8 replies, 3 threads to resolve."
