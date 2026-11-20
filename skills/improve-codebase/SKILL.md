---
name: improve-codebase
description: "Scan a codebase for candidates: shallow modules worth deepening, and code to simplify (dead, copied, hand-made, unused, twisted). Show them in a visual report, then grill every one and file the work as issues. Use for 'improve architecture', 'where should we deepen', 'find refactor candidates', 'simplify the codebase', 'find dead code'."
disable-model-invocation: true
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

Read `../../shared/codebase-design.md` first. It holds the vocabulary
(**module**, **interface**, **depth**, **seam**, **adapter**, **leverage**,
**locality**) and the principles (the deletion test, "the interface is the
test surface", "one adapter = hypothetical seam, two = real"). Use these
terms exactly, in every brief, every card, and every sentence to the user.
The domain terms come from `CONTEXT.md`. ADRs under `docs/adr/`, and the
`## Docs to write` text in open issues, record decisions this skill does
not re-litigate.

You find **candidates** of two kinds:

- A **deepening** turns shallow modules into one deep module, so tests hit
  one interface and an agent can navigate the code.
- A **simplification** makes code smaller or plainer while behavior stays
  the same.

Each candidate is **small** (one clear cut with no design choice, such as
deleting a function nothing calls) or **big** (a design choice, or many
parts). You judge the size from the find itself.

You do not propose interfaces and you do not change code. The output is a
report, a grill, and the issues the grill files.

## Facts

Read `../../shared/facts.md` first: you are the brain,
Explore agents retrieve, short lookups are yours.

## Steps

1. **Scope.** YAGNI: a refactor pays off where the code will change again,
   so weight recent change.

   - The user named a direction (a module, a subsystem, a pain point): take
     it, skip the inference.
   - Otherwise run `git log --oneline -200 --name-only` and find the hot
     spots, the folders that keep coming up. Those paths get the first
     look. Scattered changes with no hot spot: widen the net to the whole
     repo.

   Read `CONTEXT.md` and every ADR that touches the area, and the open
   issues with a `## Docs to write` section in the area
   (`gh issue list --state open --limit 500 --search '"Docs to write" in:body'`):
   their text is decided, not built, and counts like an ADR. Done when you
   can name the paths in scope and the decisions already made about them.

2. **Explore.** Dispatch Explore agents per `facts.md`, one per hot spot
   or subsystem. A brief holds:
   the paths in scope, the glossary from `../../shared/codebase-design.md`
   pasted in, the domain terms from `CONTEXT.md`, and these questions.

   Deepening:

   - Where does understanding one concept mean bouncing between many small
     modules?
   - Where is a module shallow, its interface nearly as complex as its
     implementation?
   - Where were pure functions pulled out just for testability, while the
     real bugs hide in how they are called (no locality)?
   - Where do tightly coupled modules leak across their seams?
   - Which parts are untested, or hard to test through their current
     interface?

   Simplification:

   - **Dead code**: a function, file, export, flag, or stub that no caller
     uses, or an old way a newer way replaced.
   - **Copied code**: the same logic in two or more places.
   - **Hand-made**: code that redoes what the language, a package the repo
     already has, or another part of the repo already does.
   - **Unused option or mode**: a parameter, setting, or branch that no
     caller ever takes.
   - **Twisted logic**: nesting, negation, or indirection that a plainer
     form says with the same behavior.
   - **Package for one small thing**: a dependency used once for what a
     few lines or the standard library do.

   For dead code and unused options, the searches that show no caller in
   the code, in strings, in scripts, and in config, and whether a name is
   called at run time. A module that only passes calls through is a
   deepening, never a simplification.

   Return shape: one block per candidate with the files (`path:line`),
   its kind, what the friction is, and the proof, with its evidence label
   per `facts.md`. For a deepening, add the deletion test result: would
   deleting the module concentrate complexity, or just move it?
   "Concentrates" is the signal you want.

   Read what comes back. Apply the deletion test yourself to anything that
   looks shallow. Classify each deepening's dependencies per
   `references/deepening.md` (in-process, local-substitutable, ports &
   adapters, mock). Size each candidate small or big, and sort the small
   ones into topic groups: the ones a reader would fix in one sitting,
   such as every date helper. Done when every candidate has files, a kind,
   a size, a proof with its evidence label, and, for a deepening, a
   deletion-test verdict and a dependency category.

3. **Report.** Build the report as a local HTML page, per
   `references/html-report.md`. One card per big candidate:

   - **Files**: which modules are involved.
   - **Problem**: why the current shape causes friction.
   - **Solution**: what would change, in plain words. No interface yet.
   - **Wins**: for a deepening in terms of locality and leverage, and how
     tests improve; for a simplification, what goes away.
   - **Before / After diagram**: side by side, drawn for this candidate.
   - **Strength badge**: `Strong`, `Worth exploring`, or `Speculative`.

   The small candidates follow in one table per topic group, each row
   with what, where, kind, and the evidence label. No badge and no
   diagram.

   Domain nouns come from `CONTEXT.md`, architecture nouns from the
   glossary. "The Order intake module", never "the FooBarHandler" and never
   "the Order service".

   **ADR conflicts.** A candidate that contradicts an ADR appears only when
   the friction is real enough to reopen the ADR. Mark it in the card:
   *"contradicts ADR-0007, but worth reopening because..."*. Refactors an
   ADR forbids for a reason that still holds stay out.

   End with a **Top recommendation**: which big candidate first, and why.

   Serve and open it per `references/html-report.md` § Serve and open,
   and give the user the URL. No candidate: the report says so, and the
   run ends with no grill. Else say how many candidates, big and small,
   and ask the user to say `go` when they have read it. Stop and wait.

4. **Grill.** On `go`, invoke the `grill` skill with the Skill tool. Seed:
   the report. Open decisions, in this order: each big candidate, the
   strongest first, then each small topic group as one decision. For a
   deepening: the constraints on the deepened module; which dependencies
   sit behind the seam and how each is tested (per its category); the
   shape of the deepened module; which tests survive and which are
   replaced. For a simplification: whether to cut, and how. For a small
   group: which of its cuts to make. The user's `drop` skips a candidate;
   a big one dropped for a reason that will still hold next run goes in
   the grill's ADR list, so the next run leaves it out. The grill's
   close-out files the work, typed `refactor`, in the shape it picks.

   When the user wants to see alternative interfaces for a big
   deepening, run `references/design-it-twice.md`: three or more
   sub-agents in parallel, each with a different constraint and each
   starting from how callers use the module, then a score on the 3 to 6
   points named before the designs came back, one point at a time, and
   your own pick. Designs that differ wildly send the question back to be
   reframed, never averaged.

## Examples

**User:** `/improve-codebase`

Scope from git log: `src/orders/` and `src/pricing/` carry most of the last
200 commits. Two Explore agents, one per folder. Orders comes back with
five wrapper modules that each pass through to `OrderRepo`; the deletion
test concentrates. Pricing comes back with `formatLegacy()` (no caller,
searched by name and in config, Seen) and `parseDate()` copied in two
files (Seen). Report: one big card, "Collapse the Order intake pipeline",
badge `Strong`, dependency `local-substitutable` (PGLite exists); one
small table, "Dates", with two rows. User says `go`. The grill opens with
the seam question, then asks about the Dates group as one question.

**User:** `/improve-codebase the notification code is a mess`

Direction named, no git-log inference. One Explore agent on
`src/notifications/`. One big card, `ports & adapters`, because Twilio and
an internal mailer both sit behind it. The card notes it contradicts
ADR-0004 (one channel per module) and says why that ADR is worth
reopening. A second big card is a simplification: a retry queue that only
the SMS sender uses, where a retry loop in that sender does the same job.
