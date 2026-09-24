---
name: improve-architecture
description: "Scan a codebase for shallow modules worth deepening, show the candidates in a visual report, then grill the one the user picks. Use for 'improve architecture', 'where should we deepen', 'find refactor candidates'."
disable-model-invocation: true
---

Read `references/codebase-design.md` first. It holds the vocabulary
(**module**, **interface**, **depth**, **seam**, **adapter**, **leverage**,
**locality**) and the principles (the deletion test, "the interface is the
test surface", "one adapter = hypothetical seam, two = real"). Use these
terms exactly, in every brief, every card, and every sentence to the user.
The domain terms come from `CONTEXT.md`. ADRs under `docs/adr/` record
decisions this skill does not re-litigate.

You find **deepening candidates**: refactors that turn shallow modules into
deep ones, so tests hit one interface and an agent can navigate the code.
You do not propose interfaces and you do not change code. The output is a
report and a grill.

## Facts

Read `../../shared-skill-core/facts.md` first: you are the brain,
Explore agents retrieve, short lookups are yours.

## Steps

1. **Scope.** YAGNI: deepening pays off where the code will change again,
   so weight recent change.

   - The user named a direction (a module, a subsystem, a pain point): take
     it, skip the inference.
   - Otherwise run `git log --oneline -200 --name-only` and find the hot
     spots, the folders that keep coming up. Those paths get the first
     look. Scattered changes with no hot spot: widen the net to the whole
     repo.

   Read `CONTEXT.md` and every ADR that touches the area. Done when you can
   name the paths in scope and the decisions already made about them.

2. **Explore.** Dispatch Explore agents, all in one message, one per
   hot spot or subsystem, each with its full brief inline. A brief holds:
   the paths in scope, the glossary from `references/codebase-design.md`
   pasted in, the domain terms from `CONTEXT.md`, and these questions:

   - Where does understanding one concept mean bouncing between many small
     modules?
   - Where is a module shallow, its interface nearly as complex as its
     implementation?
   - Where were pure functions pulled out just for testability, while the
     real bugs hide in how they are called (no locality)?
   - Where do tightly coupled modules leak across their seams?
   - Which parts are untested, or hard to test through their current
     interface?

   Return shape: one block per friction point with the files (`path:line`),
   what the friction is, and the deletion test result: would deleting the
   module concentrate complexity, or just move it? "Concentrates" is the
   signal you want.

   Read what comes back. Apply the deletion test yourself to anything that
   looks shallow. Classify each candidate's dependencies per
   `references/deepening.md` (in-process, local-substitutable, ports &
   adapters, mock). Done when every candidate has files, a friction, a
   deletion-test verdict, and a dependency category.

3. **Report.** Build the candidate report as an Artifact, per
   `references/html-report.md`. One card per candidate:

   - **Files**: which modules are involved.
   - **Problem**: why the current shape causes friction.
   - **Solution**: what would change, in plain words. No interface yet.
   - **Wins**: in terms of locality and leverage, and how tests improve.
   - **Before / After diagram**: side by side, drawn for this candidate.
   - **Strength badge**: `Strong`, `Worth exploring`, or `Speculative`.

   Domain nouns come from `CONTEXT.md`, architecture nouns from the
   glossary. "The Order intake module", never "the FooBarHandler" and never
   "the Order service".

   **ADR conflicts.** A candidate that contradicts an ADR appears only when
   the friction is real enough to reopen the ADR. Mark it in the card:
   *"contradicts ADR-0007, but worth reopening because..."*. Refactors an
   ADR forbids for a reason that still holds stay out.

   End with a **Top recommendation**: which candidate first, and why.

   Publish, give the user the link, and ask: "Which of these would you
   like to explore?" Stop and wait.

4. **Grill.** The user picked a candidate. Invoke the `grill` skill with the
   Skill tool. Seed: the card. Open decisions: the constraints on the
   deepened module; which dependencies sit behind the seam and how each
   is tested (per its category); the shape of the deepened module; which
   tests survive and which are replaced.

   When the user wants to see alternative interfaces for the deepened
   module, run `references/design-it-twice.md`: three or more sub-agents
   in parallel, each with a different constraint, then compare on depth,
   locality, and seam placement and give your own pick.

## Examples

**User:** `/improve-architecture`

Scope from git log: `src/orders/` and `src/pricing/` carry most of the last
200 commits. Two Explore agents, one per folder. Orders comes back with
five wrapper modules that each pass through to `OrderRepo`; the deletion
test concentrates. Report has three cards, top recommendation "Collapse the
Order intake pipeline", badge `Strong`, dependency `local-substitutable`
(PGLite exists). User picks it. Grill opens with the seam question.

**User:** `/improve-architecture the notification code is a mess`

Direction named, no git-log inference. One Explore agent on
`src/notifications/`. One card, `ports & adapters`, because Twilio and
an internal mailer both sit behind it. The card notes it contradicts
ADR-0004 (one channel per module) and says why that ADR is worth
reopening.
