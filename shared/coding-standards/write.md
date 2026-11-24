# Writing the Standard

How `set-coding-standards` and `audit-coding-standards` settle the
report with the user and write what was settled. The report comes from
`checks.md`, next to this file. A rule comes from a source the research
read, the code, or the user; `research.md` defines the source levels.
The Standard's shape and the step that adds one rule are in
`standard.md`, next to this file.

## Grill

Invoke the `grill` skill with the Skill tool. Seed: the report. Open
decisions, one per finding the report holds:

- Scattered rules: fold each file's rules into the Standard, or keep
  them where they are.
- Outdated rule: update it to what the repo has now, or drop it.
- Drifted rule: keep and enforce it, or change the rule to the code's
  way.
- Gap: add a rule, or leave the area out on purpose.
- Proposal: accept, change, or drop.
- Behind current practice: change the code (a `chore` issue), or keep
  the code's way as the rule.
- Conflict: the level 1 rule or the level 2 rule, with both links shown.
- `model's view, no source`: keep the pattern, or change it.
- `no source`: the user writes the rule, or leaves the area out.

End the seed with `Close out: caller.`, so the grill's files wait
uncommitted next to the files under Write.

A stack part the user names as planned during the grill is researched
per `research.md` before its areas are settled.

The grill ends with `Grill done.` and the settled list: go on to Write.
The user stops it first, at the first question or later: none of the
files under Write change. Print the decisions settled so far, one per
line, so they can go into the next run. Name any file the grill wrote
itself (a `CONTEXT.md` term, an ADR); those are the grill's. Stop.

## Write

Files in the working tree, nothing else:

- `CODING_STANDARDS.md` at the root, in the shape of `standard.md`
  § Shape. Each settled rule is added by `standard.md` § Add one rule.
  Rules folded in from other files are removed from those files.
- `docs/standards/<topic>.md` for a topic past about 40 rules, per
  `standard.md` § Shape.
- `docs/standards/sources.md`, the Sources table, per `standard.md`
  § Sources table.
- `.editorconfig`, written or updated to match.
- Configs of the tools the project already has: each lint setting
  `standard.md` § Lint settings allows. New tools and CI changes become
  issues in Hand off.
- `CLAUDE.md` and `AGENTS.md`, where they exist: add one line, "Read
  `CODING_STANDARDS.md` before you write or review code." The rest of
  each file stays, except the rules the grill folded in.

The Sources table gets a row for every source in the report's
`Sources` line, and for every source the research read during the
grill, per `standard.md` § Sources table.

Done when every settled rule is in `CODING_STANDARDS.md` or one topic
file exactly once, every rule from a source names a row of the Sources
table, every lint setting `standard.md` § Lint settings allows is in a
config and each one it holds back is named under Hand off, and
`git status` lists only the files above and any the grill wrote itself.

## Hand off

In chat:

- Files changed, one line each, the grill's among them.
- Drift kept as code problems: one line per rule with count and the
  issue you recommend for it (`fix` ticket, or a `chore` when it is a
  sweep), and the lint setting that issue turns on, per `standard.md`
  § Lint settings. Name `/to-issue` for one, `/capture` for a seed.
- New tools or CI the rules need: one recommended issue each.
- Agent-ready sources the research found: one line each, "you can
  install <name> as an extra: <URL>".
- Stack parts under `Not researched`: name them, and say to run
  `/audit-coding-standards` with web access.
- Last line: `Ready for /commit` or `Ready for /make-pr`.
