---
name: audit-coding-standards
description: "Check a repo's CODING_STANDARDS.md against its code and current sources (outdated rules, drift, behind current practice, gaps), then grill the user on the findings and write the settled changes. No commit."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

You keep the repo's Standard true: `CODING_STANDARDS.md` and the topic
files it links to. You check it against the code and against what the
stack's own sources say today, report, grill the user on what you found,
and write what was settled. The first Standard is
`set-coding-standards`'s job.

## Facts

Read `../../shared-skill-core/facts.md` first: you are the brain,
Explore agents retrieve, short lookups are yours.

## Steps

1. **Gate.** No `CODING_STANDARDS.md` at the root: say "No Standard
   yet. Run `/set-coding-standards` to make one." Stop. Done when you
   hold the Standard's files.

2. **Find and size.** Read `../../shared-skill-core/coding-standards/checks.md`.
   Run its `Find the rules` and `Size the repo`. Empty bucket: say what
   the table says, stop.

3. **Research.** Read `../../shared-skill-core/coding-standards/research.md`
   and follow it: research only the stack parts that § Re-check calls
   due from the Sources table. Done when the done line at the end of
   `research.md` holds.

4. **Check.** Run `Sample the code`, then all four checks of
   `Check the rules` on the Standard's rules and the scattered rules.

5. **Report.** Print the report in `checks.md` § Report shape, the
   audit lines, with a verdict. `clean` means outdated, drift, behind
   current practice, gaps, and not researched are all "none"; list the
   areas checked under it. Otherwise `needs work`. Done when the report
   is in chat with a verdict.

6. **Clean.** Verdict `clean`: when step 3 re-checked sources, set each
   of their Sources table rows to the version read and today's date,
   from the report's `Sources` line, and name the rows changed. That
   table is the only change. Stop.

7. **Grill.** Verdict `needs work`: read
   `../../shared-skill-core/coding-standards/write.md` and run its
   `Grill` with the report as the seed, at once. The user who wants
   only the report says stop at the first question. A stopped grill
   ends the run there. When `Not researched` is the only finding,
   nothing needs a decision: go to step 9.

8. **Write.** Run `write.md` § Write. Only the rules the grill changed,
   added, or dropped move; the rest of the Standard stays as it is.

9. **Hand off.** Run `write.md` § Hand off.

## Examples

**User:** `/audit-coding-standards` in a 3-year-old Django monolith, 900
files, 6 authors, with a `CODING_STANDARDS.md` from last year.

Find: the Standard, plus rules in `CLAUDE.md` (scattered). Big bucket.
The Sources table's Django row is past 6 months, so Django is due;
Python, pytest, and general are not. Outdated: the Standard names
`flake8`, but `ruff.toml` replaced it. Drift: "views are class-based",
61 function views, three examples. Behind current practice: secrets
read with `os.environ[]` at import, against the Django deployment
checklist. Gaps: the `CLAUDE.md` rules, Logging. Verdict: needs work.
Grill at once: `flake8` to `ruff` (update), the view rule (keep,
enforce), secrets (change the code), fold `CLAUDE.md` in (yes),
Logging (add: `structlog`). Write those rules, set the Django row's
date, strip the rules from `CLAUDE.md` and leave the pointer line.
Hand off: one `chore` issue for the 61 views, one for the secrets.
`Ready for /make-pr`.

**User:** `/audit-coding-standards` in a repo whose Sources table was
checked 7 months ago; the sources still agree with every rule.

Every part is due by date. The research agrees with every rule, and the
code with every rule. Verdict: clean. Set those rows' version and date,
name them, stop.

**User:** `/audit-coding-standards`, then "stop, I only want the
report" at the first question.

No file changes. No decision was settled, so say so and stop. The
report is already in chat.

**User:** `/audit-coding-standards` in a repo with no
`CODING_STANDARDS.md`.

Say there is no Standard yet, and to run `/set-coding-standards`. Stop.

**User:** `/audit-coding-standards` in Codex with no web search.

The research dispatches nothing. Every due stack part is `not
researched: no web access`. Drift and gaps still run on the code.
Verdict: needs work, because the research is not done. The grill
settles the code findings; the hand-off says to run the audit again
with web access.
