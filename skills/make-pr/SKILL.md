---
name: make-pr
description: "Open or update the pull request for the work in this checkout, in the shared PR shape: branch, commit, run the repo's checks, push, open, size label. Use for 'make a PR', 'open a PR', 'put this up for review', /make-pr in Claude Code, $make-pr in Codex, and when another skill hands over its files for a PR. Stops at the open PR; the review loop is /make-pr-ready."
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

Turn the work in this checkout into one pull request. Read
`../../shared-skill-core/pr-shape.md` first: it owns the branch name,
the title, the body, and the label. This skill owns the steps around
it. It stops when the PR is open, and it never merges.

## When a skill calls you

A caller can set four things: the branch name, the files that go in,
the issue line, and what goes under `Summary` and `Follow-ups`. The
rest is this skill's.

## Steps

1. **Facts.**

   ```bash
   gh api user -q .login
   gh repo view --json nameWithOwner,defaultBranchRef -q '.nameWithOwner + " " + .defaultBranchRef.name'
   git branch --show-current
   git status --short
   ```

   `gh` missing or not signed in: stop, and give the user
   `gh auth login`. The base is the default branch, or the branch the
   user named. `git fetch origin <base>`. Done when you hold the repo,
   the base, the current branch, and the changed files.

2. **Scope.** The PR holds the work of this chat, or the files a caller
   named. Read `git status --short` and
   `git log --oneline origin/<base>..HEAD`.
   - No changed file and no commit ahead of the base: say
     `Nothing to put in a PR.` and stop.
   - A changed file that this chat did not touch and no caller named:
     list those files and ask which go in. Wait.
   - A token, a key, a password, or a `.env` value in the diff: stop,
     and name the file and the line.

   Done when every file that goes in belongs to this work.

3. **Issue.** Look in this order: the caller's issue line; the branch
   name (`fix/57-export-date-iso` is #57); a `#<n>` in the commits; an
   issue named in the chat. Found: `gh issue view <n> --json
   number,title,body,state`, and hold its Done-when lines. Done when you
   hold the issue and its Done-when lines, or know there is no issue.

4. **Branch.** On the base: `git switch -c <branch>`, named by the PR
   shape § Branch, or the caller's name. On another branch: stay on
   it. Done when HEAD is on the PR's branch.

5. **Commit.** Stage the files by name, `git add -- <files>`, so only
   this work goes in. Write each message by `../commit/SKILL.md`, one
   commit per logical change. Done when `git status --short` lists none
   of the PR's files.

6. **Checks.** The repo's checks are the commands `AGENTS.md` or
   `CLAUDE.md` names; else the `test`, `lint`, and `typecheck` scripts
   in `package.json`; else the ones `CONTRIBUTING.md` names. Run each
   one. A check that passed in this session after the last file change
   already counts: use that result and say so. A red check: show its
   failing lines and stop, with the PR not opened. Done when every
   check is green and you hold each command, the short SHA of HEAD, and
   the result, for `Proof`.

7. **Push.** `git push -u origin HEAD`. Rejected: show the message and
   stop. A force push is the user's call. Done when `origin/<branch>`
   is at HEAD.

8. **Body.** Read the repo's PR template when it has one
   (`.github/pull_request_template.md`, or `.github/PULL_REQUEST_TEMPLATE/`).
   Write the title and the body by the PR shape, for the whole branch
   against the base (`git diff origin/<base>...HEAD`), to a file
   outside the tree: `f=$(mktemp)`. Done when every part of the shape
   is written or left out for the reason the shape gives, and no
   placeholder is left.

9. **Open.** `gh pr list --head <branch> --state open --json number,url`.
   - No PR: `gh pr create --base <base> --head <branch> --title
     "<title>" --body-file "$f"`, ready for review.
   - An open PR: `gh pr edit <n> --title "<title>" --body-file "$f"`.
     The new body covers the whole branch and replaces the old one;
     GitHub keeps the old one in the edit history.

   Done when `gh pr view <n> --json title,body` shows what you wrote.

10. **Label.** `gh label list --search size --json name -q '.[].name'`.
    The repo has size labels: size the diff with
    `../../shared-skill-core/size.md`, put on the label for that size,
    and take off any other size label. No size labels: no label. Done
    when the PR has one size label, or the repo has none.

11. **Report.** Chat gets this and nothing more:

    ```
    PR: feat(export): write ISO dates (#61) · size S · checks: 2 green
    https://github.com/acme/shop/pull/61
    Next: /make-pr-ready
    ```

    An open PR that you updated: `PR (updated): …`.

## Examples

**User:** "make a PR" on `main`, after a chat that renamed one skill; no
issue anywhere.

Scope: the six files the chat touched. No issue, so no issue line.
Branch `refactor/rename-load-skills`. Two commits by `/commit`.
`AGENTS.md` names `scripts/check.sh`; it passed after the last edit, so
that result counts. Push, body with `Summary`, `Where to look`, and
`Proof` as a list, no template in the repo. `gh pr create`. Size XS.
Report.

**User:** `/make-pr` on `fix/57-export-date-iso` with two commits and
`src/export.ts` still changed.

Issue #57 from the branch name, three Done-when lines. One more commit.
`bun test` runs on the new HEAD, green. `Closes #57`, and `Proof` is a
three-row table with each test linked.

**User:** "open a PR", and the tree also holds `notes.txt`, which the
chat never touched.

Ask: `notes.txt` is changed too; put it in the PR, A no, B yes. Wait.

**Grill** hands over at its close-out: branch `docs/grill-12-export-queue`,
files `CONTEXT.md` and `docs/adr/0004-no-job-queue.md`, `Closes #12`,
the settled decisions for `Summary`.

The steps run with those four set. The report goes back to grill.

**`npm run lint`** fails on the new HEAD.

Show the failing lines. Stop; no push, no PR.
