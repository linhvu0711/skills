---
name: review-pr
description: "Review a pull request on the three fixed axes (logic, scope, standards), one subagent per axis, with the repo's own review rules folded in from REVIEW.md or wherever the repo keeps them. Report in chat and to a file. Never posts to GitHub."
disable-model-invocation: true
---

You review one pull request. The checks are fixed: **Logic**, **Scope**,
**Standards**, as written in
`~/.agents/shared-skill-core/review/general-rules.md`. The repo can add
rules of its own, in `REVIEW.md` or wherever it keeps them. You run
each axis in its own subagent, merge what comes back, and hand the
report to the user. Posting the review to GitHub is the user's call and
a separate command.

## Facts

Read `../../shared-skill-core/facts.md` first. Short lookups
(`git`, `gh pr view`, one `ls`) are yours.

The axis agents are judges, so they are `general-purpose` agents, not
Explore. Explore retrieves. A review axis has to trace a branch, weigh a
smell, and match a hunk to a task line. That is the main model's work.

In Codex there are no subagents: run the three briefs yourself, one after
the other, and keep the same return shape.

## Steps

1. **Preflight.** `git rev-parse --show-toplevel`. No repo: say so, stop.
   Resolve the PR:

   - Argument given: `gh pr view <arg> --json number,url,baseRefName,headRefName,title,body,closingIssuesReferences`.
   - No argument: same call with no `<arg>`, which picks the PR of the
     current branch.
   - No PR found: the branch is the unit. Base is the default branch
     (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`,
     else `main`). Say once "no PR; reviewing branch against `<base>`".

   The diff command is `git diff <base>...HEAD`. Run `git fetch` on the
   base first so the merge base is current. Run the diff once with
   `--stat`. Empty: say so, stop.

   Done when you hold the base, the head, the PR body or "no PR", and a
   non-empty stat.

2. **Task.** The task is what the PR is supposed to do, in this order:
   the linked issue and its parent epic, else the PR description, else
   "no task found".

   - `closingIssuesReferences` non-empty: `gh issue view <n> --json title,body` for each. If the body names a parent or epic
     issue, fetch that one too.
   - Empty, PR body present: the body is the task.
   - Neither: the task is "no task found".

   Done when the task text is in your notes, or the phrase "no task found"
   is.

3. **Rules.** Build the rule text for each axis.

   The general block is always
   `~/.agents/shared-skill-core/review/general-rules.md`, read now. Split
   it into its three `##` sections. That is the general text per axis.

   Then find the repo rules.

   - `REVIEW.md` at the root with the `set-review-rules:general` markers
     is the settled source. The lines below the end marker are the repo
     rules, already grouped under `### Logic`, `### Scope`,
     `### Standards`. Compare the text between the markers with the
     shared file. Different: the shared file wins, and the report notes
     "REVIEW.md general block is older than the shared rules". Stop
     looking; the file already folded the rest in.
   - No marked `REVIEW.md`: one Explore agent searches the repo. Its
     brief is `~/.agents/shared-skill-core/review/rule-sources.md`
     pasted in full, the repo root, and this return shape: one line per
     hit, `<path:line> | <bin> | <the rule, verbatim>`. Every review
     rule that comes back is a repo rule, whatever file it sat in. Bot
     configs are named in the report and not run. Sort each rule into
     the axis that checks it: does it work (Logic), does it match the
     task (Scope), does it fit how the repo writes code (Standards). A
     rule that fits none goes to Standards.
   - Nothing comes back: no repo rules. The review runs on the general
     rules alone. The report's `## Notes` carries one line: "no repo
     review rules found; general rules only. /set-review-rules writes
     them." That line is a notice, not a step. This skill reviews the
     PR and never runs the other skill.

   Per axis, the rule text is the general section followed by
   `## Repo rules` and that axis's lines, or "None." Done when three
   rule texts exist and every repo rule line sits under exactly one
   axis.

4. **Dispatch.** Three `general-purpose` agents, one per axis, all in one
   message. Each brief holds, inline and complete:

   - The repo root and the exact diff command from step 1.
   - The PR title and, for Scope, the task text from step 2.
   - The rule text for that axis from step 3, pasted in full.
   - For Standards: the path `CODING_STANDARDS.md` if `git ls-files`
     lists it, else the sentence "no CODING_STANDARDS.md; the code next
     to the diff is the standard".
   - The instruction to read the whole diff once, read the surrounding
     code and callers as the rules require, run every check in the
     rule text against every hunk, and report findings for this axis
     only.
   - The return shape below, verbatim.

   Return shape for an axis agent:

   ```
   ## Checks run
   - <check name>: <hunks or files it covered, or "nothing in the diff triggers it">

   ## Findings
   - <🔴 blocker|🟠 should|🔵 nit> | <path:line> | <what is wrong, one sentence> | <rule, check number, or smell cited> | <fix, one sentence>

   ## Notes
   - <anything the rules asked the axis to say, e.g. "no task found", or nothing>
   ```

   Severity is always the emoji and the word together, so it can be
   spotted at a glance. `🔴 blocker`: the PR is wrong or unsafe as is.
   `🟠 should`: fix before merge. `🔵 nit`: fix if cheap. Standards
   smells are `🔵 nit` unless a written repo rule names them.

   Done when three agents are running with full briefs.

5. **Merge.** Read the three returns. Build one picture.

   - A finding belongs to one axis. The same `path:line` from two axes:
     keep the one whose axis owns the check, drop the other.
   - An axis whose `## Checks run` misses a check from its rule text:
     send that agent back for that check only, then continue.
   - Two agents that disagree on a fact (a caller exists, a test
     covers it): one Explore agent fetches that one fact; the fact wins.

   Verdict: any `🔴 blocker` is `request changes`. No `🔴 blocker` and
   no `🟠 should` is `approve`. Else `comment`.

   Done when every finding has one axis, one severity, a `path:line`,
   and a citation, and the verdict is set.

6. **Report.** Write the report in the shape under `Report shape` to
   `~/.claude/reviews/<repo>-<pr number or branch>.md` (create the
   folder) and print it in chat. The notes from step 3 (older general
   block, no repo rules, bot configs found) go under `## Notes`, once
   each.

   Last line in chat, one of:

   - `Verdict: <verdict>. To post: gh pr review <number> --<approve|request-changes|comment> -F <report path>`
   - `Verdict: <verdict>. No PR; nothing to post.`

   You do not run the `gh pr review` command. The user does.

## Report shape

```
# Review: <PR title> (#<number> | <branch>)

<base>...<head>, <n> files, +<a> -<d>

## Logic
- <🔴 blocker|🟠 should|🔵 nit> | <path:line> | <what> | <cited> | <fix>

## Scope
- ...

## Standards
- ...

## Notes
- <older general block | no repo review rules | bot configs found | no task found>

Verdict: <approve | comment | request changes>
```

Inside each axis: 🔴 first, then 🟠, then 🔵. An axis with no findings
keeps its heading and one line: "Nothing found."

## Terms

- **Axis**: one of the three independent checks, Logic, Scope, Standards.
- **General block**: the fixed rule text, the same in every repo. Owned
  by `~/.agents/shared-skill-core/review/general-rules.md`.
- **Repo rule**: a line the repo adds below the end marker in
  `REVIEW.md`, or, with no marked file, any rule line found in step 3.
- **Task**: what the PR is supposed to do. The linked issue and its
  epic, else the PR description.
- **Finding**: one line, one axis, one severity (🔴 blocker, 🟠 should,
  🔵 nit), one `path:line`, one citation, one fix.

## Secrets

The diff and the PR body can carry tokens and `.env` values. Redact
before they enter a brief or the report.

## Examples

**User:** `/review-pr 42` in a repo with a marked `REVIEW.md`.

Step 1 resolves base `main`, 9 files. Step 2 finds issue #38 and its
epic #30. Step 3 reads the shared block, finds the repo rules under
each axis, and the marked block matches. Step 4 sends three agents.
Logic returns one `🔴 blocker` (a new branch returns `nil` on empty input,
check 2). Scope returns one `🟠 should` (a renamed helper the task did not
ask for, quoting #38). Standards returns two `🔵 nit` smells. Step 6
writes `~/.claude/reviews/acme-42.md`, prints it, and ends with
`Verdict: request changes. To post: gh pr review 42 --request-changes -F ~/.claude/reviews/acme-42.md`.

**User:** `/review-pr` on a branch with no PR and no `REVIEW.md`.

Step 1 says "no PR; reviewing branch against `main`". Step 2 says "no
task found", so Scope flags only clear creep. Step 3 has no marked
`REVIEW.md`, so one Explore agent searches the list; it finds a
"Reviewing" section in `CONTRIBUTING.md` with two rules, and a
`.coderabbit.yaml`. The two rules go to Logic, the bot config goes to
`## Notes`. Three agents run. Nothing above `🔵 nit`. Report ends with
`Verdict: approve. No PR; nothing to post.`

**User:** `/review-pr 7` in a repo whose `REVIEW.md` is from last
quarter.

Step 3 finds the text between the markers differs from the shared file.
The shared file is used; the report's `## Notes` says "REVIEW.md general
block is older than the shared rules". The repo rules below the marker
are used as they are.

**User:** `/review-pr 12` in a repo with no review rules anywhere.

Step 3's Explore agent returns nothing. The three axes run on the
general rules alone. `## Notes` holds one line: "no repo review rules
found; general rules only. /set-review-rules writes them." Nothing
else changes.
