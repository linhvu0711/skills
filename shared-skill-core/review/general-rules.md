<!-- set-review-rules:general:start -->
# Review rules

Every pull request in this repo is reviewed on three axes: **Logic**,
**Scope**, **Standards**. The axes are independent. Run each one on its
own, all three at once when you can. Keep their findings apart. A
finding belongs to one axis, and no axis outranks another. How you hand
findings back (inline comments, one summary comment, a review verdict) is
your call. What you check is fixed here.

The diff is `git diff <base>...HEAD`, three-dot, against the merge base.
Read the whole diff once per axis.

## Logic

Does the change work, and does it break anything? Six checks on every PR:

1. **New paths**: every new branch, loop, and return does what the code
   around it needs. Trace each one with a concrete input.
2. **Edges and errors**: empty input, null, the boundary value, and the
   failure of every call that can fail. Each one is handled, or the PR
   says why it is not.
3. **Regressions**: every caller of changed code still gets what it
   expects. Find the callers. Changed signatures, return shapes, and side
   effects are where regressions live.
4. **Security**: injection, missing auth checks, secrets in the diff,
   unsafe deserialization, path traversal. Anything that touches user
   input or credentials gets read twice.
5. **Data**: migrations run backwards, no write can half-complete, no
   path loses data.
6. **Tests**: the change has a test that fails without it. A test edited
   so it passes is a finding.

Performance is a check only when the diff touches a hot path or a loop
over data.

Done when all six checks have run against every hunk and each finding
cites a file and line.

## Scope

Does the change match the task, and nothing more?

The task is, in this order: the linked GitHub issue and its parent epic;
if none, the PR description; if neither, report "no task found" and flag
only clear creep.

1. **Creep**: behaviour in the diff the task did not ask for. Name it and
   quote the task.
2. **Missing**: what the task asked for that the diff does not do, or
   does in part.
3. **Extra work**: recommend more work only when it is tight to this PR,
   the same files or the same feature. Before you recommend, check
   whether something already covers it: a sibling issue in the epic, an
   open issue, a TODO in the code. Covered means you name the issue and
   move on. A recommendation about code the PR did not touch is out. With
   no issue tracker, skip the coverage check and say so.

Done when every hunk is matched to a line of the task or flagged as
creep, and every recommendation carries the task line or the coverage
check.

## Standards

Does the change fit how this repo writes code?

The rules are in `CODING_STANDARDS.md`. Cite the rule for each finding.
Skip anything a linter or formatter already enforces.

When `CODING_STANDARDS.md` is missing, the code next to the diff is the
standard and the smell list below is the floor. Say once in the review:
"no CODING_STANDARDS.md; run /set-coding-standards".

Smell list (Fowler, _Refactoring_ ch.3). Each is a judgement call,
labelled "possible", and a written repo rule always wins over it:

- **Mysterious Name**: the name hides what it does or holds.
- **Duplicated Code**: the same logic shape in more than one hunk.
- **Feature Envy**: a function that reads another object's data more than
  its own.
- **Data Clumps**: the same few fields travel together and want a type.
- **Primitive Obsession**: a string or number standing in for a concept.
- **Repeated Switches**: the same switch on the same type, again.
- **Shotgun Surgery**: one change scattered across many files.
- **Divergent Change**: one file edited for several unrelated reasons.
- **Speculative Generality**: an abstraction or hook the task did not
  need.
- **Message Chains**: `a.b().c().d()` the caller should not know about.
- **Middle Man**: a function that only delegates.
- **Refused Bequest**: a subclass that ignores most of what it inherits.

Done when every hunk has been read against the rules and each finding
cites a rule or names a smell.
<!-- set-review-rules:general:end -->
