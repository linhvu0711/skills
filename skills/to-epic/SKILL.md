---
name: to-epic
description: "Cut a large piece of work into a phased GitHub epic: one parent, native sub-issues, native blocked-by edges. Breakdown is approved in chat before anything is created."
---

Read `$HOME/.agents/skills/to-issue/references/issue-rules.md` first. Every
sub-issue obeys it. This file adds the cutting rules and the epic flow.

## Steps

1. **Gate.** The readiness gate, applied to the whole piece of work. Then the
   mirror check: if the work fits one ticket under the ceiling, stop and say
   `to-issue` is the tool. Fail: list the gaps, stop.

2. **Repo convention.** Load or learn. Done when `style`, `size`,
   and (if named) the priority label are known.

3. **Facts.** Cutting needs the seams, the layers each slice crosses, and for a
   wide refactor the call-site count per package or directory. Take them from
   the chat. What the chat lacks, fetch in the one lookup round. For every
   ticket that looks XS or S, the same round also fetches its lines, the
   pattern to copy, and the test, so its Steps can be written. Also list
   every thing outside the repo a ticket needs before it can land (an
   account, an app, a key, a bucket, DNS, billing) and every thing a person
   must do after it lands (set the variables, cut over, log in as the user
   and prove it live). Each one is a `task` ticket, and the same round
   fetches its platform docs and lead time with `SEARCH=on`. Done when every
   ticket you are about to propose has its size facts, every task has its
   Steps and lead time, and every code ticket is pure (rules file, Types).

4. **Cut.** Apply the cutting rules below. Output: phases, and per ticket a
   title, type, size, blocked-by list, and one line of what it delivers.

5. **Approve in chat.** Show the breakdown in the format below. End with the
   three questions, verbatim:

   > Does the granularity feel right? (too coarse / too fine)
   > Are the blocking edges correct: does each ticket only depend on tickets that genuinely gate it?
   > Should any tickets be merged or split further?

   Any reply that is not an approve word (`approve`, `approved`, `go`,
   `create`, `ship it`) is a change request: apply it, show the full
   breakdown again, ask the three questions again. Loop until the approve
   word. Nothing exists on GitHub before it.

6. **Duplicate check.** One search on the epic's keywords. Same work, not a
   seed: show it, stop. Origin seed: remember it.

7. **Create, in phase order.** Each call is one `gh issue create`. Numbers
   from earlier calls feed later ones.

   1. Parent: title with `epic` in the type slot, priority
      label if named, body per the parent template with the phase list
      holding titles only. The parent holds no prerequisite prose: every
      "before you start" item is a task ticket in the phase list.
   2. Phase 1 tickets: `--parent <P>`, size label, body per the rules file
      with `Part of #P`. XS tickets carry Steps and `--label handoff-ready`.
      S tickets carry both only when the steps are free, per the rules file.
      An XS ticket whose Steps cannot be written is really S. Drop Steps and
      `handoff-ready`, use the S size label. A `task` ticket, in this or any
      phase: `--parent <P>`, `--label manual`, no size label, body per the
      rules file § Task body. A task the code needs first: the code ticket
      carries `--blocked-by` the task's number. A task that follows the
      code: the task carries `--blocked-by` the code ticket's number.
   3. Each later phase: same, plus `--blocked-by <n1>,<n2>` with the numbers
      of the tickets that gate it, and the `Related` and `Noted for later`
      lines filled with real numbers.
   4. Rewrite the parent body with the numbers filled in:
      `gh issue edit <P> --body-file "$f"`.

   On any failure: stop. Report what exists (numbers) and what is left
   (titles). When the user says "continue", read what exists and create only
   the rest:

   ```bash
   gh issue view <P> --json subIssues -q '.subIssues.nodes[] | "\(.number)\t\(.title)"'
   ```

   Match by title, skip those, resume the sequence, then finish step 7.4.

8. **Close the origin seed**, when there is one, with `Grew into #<P>`.

9. **Report.** Parent URL on the clipboard. Then one line per ticket: number,
   title, size, phase. Then two lines: the tickets with no blockers, free for
   an agent now; and the tasks, which are yours.

## Cutting rules

**Skyscraper.** Phase 1 is the foundation: the schema, contract, or seam that
everything later stands on. A phase is done when the next phase can build on
it without touching it again. Fewest phases wins, but a ticket that cannot be
verified on its own goes one phase later, never earlier.

**Vertical.** Each ticket cuts one narrow, complete path through every layer
it needs (schema, API, UI, tests). A horizontal slice ("all the models", "all
the endpoints") is not a ticket. A ticket is demoable or verifiable alone,
and fits one fresh window and one PR: size XS to L, never XL.

**Edges.** A ticket is blocked by a ticket only when it cannot land green
without it. Same phase means no edge between them. A ticket blocked by one
ticket of the previous phase is free the moment that one closes; write only
that one edge, so it can start early.

**Order.** The epic is a graph; a run (`/plan-up`) walks one path through it as
a stack of PRs, one ticket per layer. Inside a phase, the list order is the
stack order: the earlier ticket goes below. Put first the ticket that
unblocks the most, then the smallest.

**Lane.** Under Scope, each ticket lists `Noted for later` work with the
sibling that owns it: `#N owns retry. Do not build it here.` This is the fence
that keeps a worker from building a sibling's ticket. Only siblings that
gate it, that it gates, or that own such work are named.

**Outside the repo.** A thing a ticket needs that lives in a platform, not
in code, is a `task` ticket, never a note in the parent and never a line in
a code ticket. Every ticket is pure: all code, or all human work (rules
file, Types). Two directions:

- **Before.** The code needs it first (an account, a key, a bucket). Place
  it by its `Lead time:`: a wait of days goes in phase 1, whatever phase
  needs it; no wait goes in the phase before the first code ticket that
  needs it. That code ticket is blocked by the task.
- **After.** A person finishes what the code started (set the variables on
  the host, cut over DNS, log in as the user and prove a live run). It goes
  in the phase after the code ticket, blocked by it. The code ticket's Done
  when stops at what an agent can prove alone.

One task per platform and account.

**Wide refactor.** One mechanical change whose blast radius fans across the
codebase, so no vertical slice can land green. Cut as:

1. **Expand**: add the new form beside the old. One ticket. Nothing breaks.
2. **Migrate**: move call sites in batches, each batch its own ticket blocked
   by Expand. Batches follow the lookup count, grouped by package or
   directory, each sized to fit under L. Quote the counts in the parent.
3. **Contract**: delete the old form. One ticket blocked by every batch.

Fallback, only when even a batch cannot stay green alone: keep the same
sequence and land it as one stack, Expand at the bottom, batches in order,
Contract on top. Green is promised only at Contract. The parent says so under
Scope; each batch ticket's Context carries `Lands in the epic's stack; green
is promised only in #<Contract>`.

**Cap.** Over 12 tickets: say so, propose a split into epics by milestone,
and let the user choose before going on.

## Breakdown format (chat)

```
## <Epic title> · <n> tickets · <k> phases

### Phase 1 · <what this phase lays down>
1. **<title>** · <type> · <size> · blocked by: none
   Delivers: <end-to-end behaviour, one line>

### Phase 2 · <…>
3. **<title>** · <type> · <size> · blocked by: 1
   Delivers: <…>
4. **<title>** · task · lead time: <wait or none> · blocked by: none
   Delivers: <what exists at the end, and which ticket it unblocks>
```

A task shows `task` in the type slot and its lead time where size would be,
so the approve step shows the human work beside the agent work.

Numbers are positions in this list until issues exist. The order inside a
phase is the stack order (Cutting rules, Order).

## Parent body

```markdown
## What to build
The end-to-end behaviour the whole epic makes work, from the user's view.

## Done when
- [ ] Epic-level outcomes, observable, complete.

## Scope
**In:** … **Out:** …
(Wide refactor: call-site counts per package. Fallback: `Lands as one stack. Green is promised only in #N.`)

## Phases
Work the frontier: any ticket whose "after" tickets are closed. Start a phase when the one before it is done.

### Phase 1 · <name>
- [ ] #12 · S · after: none. Delivers: <one line>
- [ ] #13 · M · after: #12. Delivers: <one line>
- [ ] #14 · task · after: none. Delivers: <one line>. Yours, not an agent's.

## Context
- Terms, ADRs, files, Open. As in the rules file.
```

The parent has no size label. It closes when every sub-issue is closed.

Each phase is a checkbox list, one ticket per line. GitHub renders the title
and state beside a bare `#12` and strikes it through once closed, and the
sub-issue bar counts progress. The user ticks the box by hand when the ticket
is done; the box is theirs, never the agent's.

## Example

**User:** `/to-epic` after a chat that designed "teams": a Team entity,
members with roles, an invite flow, and team-scoped billing. Lookup finds an
existing `Org` seam and one billing hook.

Breakdown: 4 phases, 9 tickets. Phase 1: `feat` Team entity with create and
list through API and UI (M), and `task` create the Stripe Connect account
(lead time about 2 days, Stripe review). Phase 2, all free once the Team
ticket closes: add a member with a role (M), invite by email (M), team
switcher in the header (S). Phase 3: team-scoped invoices (L), blocked by
the member ticket and the Stripe task. Phase 4: `task` set the Stripe keys
on the host and send one live invoice, blocked by the invoices ticket. Three
questions asked. User says "split the invite one". Invite becomes send (S)
and accept (S), accept blocked by send. User says "go". Parent plus 10
sub-issues created, the two Stripe tasks with `manual` and no size, parent
table rewritten with numbers, URL on the clipboard, and the lines "Free to
start now: #41" and "Yours: #42 Stripe Connect account, #50 live invoice".
