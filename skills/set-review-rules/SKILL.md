---
name: set-review-rules
description: "Write REVIEW.md for a repo: the fixed three-axis review (logic, scope, standards) on top, repo-specific rules below. Finds rules already in the repo, proposes more, grills the user, writes. Points CLAUDE.md and AGENTS.md at the file. No commit."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

You set what a reviewer checks on every pull request in this repo:
`REVIEW.md` at the root, pointed at from `CLAUDE.md` and `AGENTS.md`. The
file has two parts. The **general block** is fixed, the same for every
repo, and lives in `../../shared-skill-core/review/general-rules.md`. The **repo rules** are
what this repo alone cares about. Steps 2 to 4 propose them, the grill
settles them, then you write.

`REVIEW.md` says what to check, never how to hand findings back. Each
reviewer has its own channel.

## Facts

Read `../../shared-skill-core/facts.md` first: you are the brain,
Explore agents retrieve, short lookups are yours.

## Steps

1. **Preflight.** `git rev-parse --show-toplevel`. No repo: say so, stop.
   Count source files, ignoring vendored and generated trees. Zero: the
   repo gets the general block only. Skip to step 6 with no repo rules
   and say in the hand-off that repo rules can come later.

2. **Find the rules.** Search the repo for every file that says how code
   is reviewed. The list of paths and the three bins (review rule, bot
   config, not a rule) are in
   `../../shared-skill-core/review/rule-sources.md`. Read it, look
   for every path, sort every hit.

   Done when every path in the list has been looked for and every hit is
   in a bin.

3. **Hot spots.** One command, seconds on any repo:

   ```
   git log --since=6.months --grep=fix --grep=revert -i --name-only --format= | cut -d/ -f1-2 | sort | uniq -c | sort -rn | head -5
   ```

   It lists the five folders that fix and revert commits touch most. Each
   is a proposal for the Logic axis: "changes under `<folder>` get a second
   pass on <what breaks there>". Done when the five lines are written
   down, or the command returns nothing and you say so.

4. **Old REVIEW.md.** When one exists, the repo rules in it are kept.
   Check each one for one thing only: does the path, tool, or issue it
   names still exist? `git ls-files` for a path, the manifest for a tool,
   `gh issue view` for an issue. A dead one becomes a proposal: drop or
   fix. Rules with no marker block are all repo rules. Done when every
   existing rule is marked live or dead.

5. **Propose, then grill.** Each proposal is one line, one axis, one
   source:

   ```
   <axis>: <rule in positive, checkable form>   (<file:line> | hot spot, <n> commits | dead: <what is gone>)
   ```

   Print them grouped by axis, then the bot configs found, then the files
   that hold review prose to fold in. Invoke the `grill` skill with the
   Skill tool. Seed: this report. Open decisions: for each proposal,
   accept, change, or drop; for each dead rule, drop or fix; for each
   file with review prose, fold it into `REVIEW.md` or leave it; and what
   rules the user adds. Then continue at step 6.

6. **Write.** Files in the working tree, nothing else:

   - `REVIEW.md` at the root, in the shape under `File shape`. The general
     block is `../../shared-skill-core/review/general-rules.md` copied in full, markers
     included. On a rerun, only the text between the markers is replaced;
     everything below the end marker is left as the grill settled it.
   - Files that held review prose the user chose to fold in: the prose is
     removed and one line stays, "Review rules are in `REVIEW.md`."
   - `CLAUDE.md` and `AGENTS.md`, where they exist: one line, "Read
     `REVIEW.md` before you review a pull request." When neither exists,
     create `AGENTS.md` with that one line.

   Done when every settled rule is in `REVIEW.md` exactly once under its
   axis, the markers are present, and `git status` lists only the files
   above.

7. **Hand off.** In chat:

   - Files changed, one line each.
   - Bot configs found, one line each, with the pointer line you
     recommend adding to each. You did not edit them.
   - Last line: `Ready for /make-commit`.

## File shape

```
<general block, verbatim from ../../shared-skill-core/review/general-rules.md, markers included>

## Repo rules

### Logic
- <rule>

### Scope
- <rule>

### Standards
- <rule>
```

A repo rule is one line in the positive form: "A migration PR includes
the down migration and a dry-run log", "A change under `billing/` is
traced against the invoice tests". A rule with a reason that is not
obvious gets one sentence of why under it. A rule that fits two axes is
written under both. An axis with no repo rules keeps its heading and one
line: "None yet."

## Terms

- **Axis**: one of the three independent checks, Logic, Scope, Standards.
- **General block**: the fixed text between the two markers. Same in
  every repo. Owned by `../../shared-skill-core/review/general-rules.md`.
- **Repo rule**: a line below the end marker. Owned by the repo.
- **Task**: what the PR is supposed to do. The linked issue and its epic,
  else the PR description.
- **Hot spot**: a folder that fix and revert commits touch most.

## Secrets

Configs and `.env` files carry secrets. Redact before they enter the chat
or an agent brief.

## Examples

**User:** `/set-review-rules` in a Rails app, 400 files, no `REVIEW.md`.

Step 2 finds a PR template checklist ("[ ] migration has a down") and a
"Reviewing" section in `CONTRIBUTING.md`. Step 3 shows `db/migrate` and
`app/services/billing` as hot spots. Proposals: Logic, migration down
(template); Logic, billing traced against invoice tests (hot spot, 14
commits); Scope, none; Standards, none. Grill: accept both, fold the
`CONTRIBUTING.md` section in, user adds "Scope: a PR that touches
`config/routes.rb` names the issue that owns the route". Write
`REVIEW.md`, strip the section from `CONTRIBUTING.md`, leave the pointer,
one line in `CLAUDE.md`. Hand off: `Ready for /make-commit`.

**User:** `/set-review-rules` in a repo with a `REVIEW.md` from last
quarter.

Step 4 finds one repo rule naming `scripts/check-schema.sh`, which
`git ls-files` no longer lists. Proposal: dead, drop or fix. Grill: drop.
Write: general block replaced between the markers, the dead rule removed,
the rest untouched. Hand off lists `REVIEW.md` only.

**User:** `/set-review-rules` in a repo with only a README.

Zero source files. Write `REVIEW.md` with the general block and three
empty axis headings, create `AGENTS.md` with the pointer line. Say repo
rules can come later. `Ready for /make-commit`.
