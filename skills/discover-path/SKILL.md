---
name: discover-path
description: "Plan work too big for one /grill session as a map of open questions on GitHub: one parent issue, child decision tickets, resolved one per run until the way to the goal is clear, then handed to /to-epic."
disable-model-invocation: true
argument-hint: "<idea, seed url, or map url>"
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`.

Read `references/map.md` first: bodies, labels, titles, and every `gh`
command live there. This file is the flow.

A loose idea has arrived, too big for one `/grill` session, and the way from
here to the goal is in **fog**. This skill draws the **map**: one parent
issue on the repo's GitHub, with child **tickets** that are questions to
settle. Each run settles one ticket. When no ticket is left and the fog is
gone, the map is clear and `/to-epic` takes over.

A map is the parent of questions not yet decided. An epic is the parent of
work already decided. The map comes first.

## Hard rules

- **Plan only.** Every ticket is a question whose answer is a decision. A
  ticket that reads "build X" gets reshaped into the question behind it, or
  ruled out of scope. The one doing on a map is a `task` ticket, and it earns
  its place by unblocking a decision.
- **One ticket per run.** Resolve it, record it, stop. The map is the memory.
- **The user decides.** A grill ticket resolves through the live exchange. An
  experiment ticket closes on the user's word, and the user picks among
  variants. When the user is away, wait.
- **Refer by name.** In chat and on the map a ticket is its title with the
  link inside: `[[grill] Which plan model?](url)`.
- **Titles follow the repo.** The prefix style (`[grill] …` or `grill: …`)
  is the repo's, learned per `references/map.md` § Titles before the first
  `gh issue create` of a run, in Chart and in Work alike. Never assumed.
- **Re-read before write.** Other runs edit the tracker at the same time.
  Fetch the map body right before each edit, change one thing, write once.
- **Chart what is sharp.** Every question that can be phrased precisely now
  is a ticket, however many. What cannot is fog.

## Ticket types

| Label | Mode | Reach for it when |
|---|---|---|
| `discovery/grill` | with the user | The default. Talking settles it. |
| `discovery/research` | agent alone | A fact outside the repo blocks a decision. |
| `discovery/experiment` | with the user | Only trying it answers it: a mock, a diagram, a call to a service. |
| `discovery/task` | either | Nothing to learn, but manual work blocks a decision: sign up, get access, move data. |

## Resolve the argument

- An issue URL or number carrying `discovery/map`: **Work**.
- One carrying `seed`: **Chart**, the seed is the idea. Keep it as the origin
  seed.
- Any other issue: say what it is and stop.
- Text, or nothing: **Chart** from the text or the chat.

`gh` missing, logged out, or no repo: say so and stop. Nothing is written.

## Chart

1. **Destination.** Invoke the `grill` skill with the Skill tool. Seed: the
   idea. Open decisions: what reaching the end of this map looks like (a
   spec to hand off, a decision to lock, a change made in place); what is
   near but out. Then continue at step 2. Done when the destination is one
   or two lines the user agreed to.

2. **Wide grill.** Invoke `grill` again, breadth-first: fan out across the
   whole space, one level deep on every thread. Open decisions: every
   question that must be settled before the work can be cut; which are sharp
   now and which are fog; which need an outside fact (research), a thing to
   react to (experiment), or manual work first (task); what gates what. Then
   continue at step 3. Done when grill has said `Grill done.` and every
   settled question carries a type.

   No fog, and the whole thing fits one session: say `/grill settled it.
   /to-issue or /to-epic is the tool.` and stop.

3. **Propose in chat.** The proposal format in `references/map.md`. End with
   the three questions, verbatim:

   > Is every ticket a question, not a job?
   > Are the blocking edges right: does each ticket wait only on what truly gates it?
   > Is anything in the fog sharp enough to be a ticket now, or the other way round?

   A reply that is not an approve word (`approve`, `approved`, `go`,
   `create`) is a change request: apply it, show the whole proposal again,
   ask again. Done when the user has said an approve word; GitHub is
   untouched until then.

4. **Labels and title style.** The five `discovery/*` labels, per
   `references/map.md` § Labels. Then the repo's title style, per
   `references/map.md` § Titles, and the `t` helper defined from it. Done
   when each label exists and `t grill "x?"` prints a title in the repo's
   style.

5. **Create.** Map first, then tickets in proposal order, free ones first,
   one `gh issue create` each per `references/map.md` § Commands. Numbers
   from earlier calls feed `--blocked-by` on later ones. Then rewrite the
   map body with real links. On failure: stop, report what exists and what
   is left; on `continue`, list the map's children, match by title, create
   the rest. Done when every proposed ticket exists and the map body links
   each closed-or-fog line correctly.

6. **Origin seed.** When there is one:
   `gh issue close <seed> --comment "Grew into #<map>"`.

7. **Report.** Map URL on its own line, and on the clipboard when `pbcopy`
   exists. One line per ticket: name, type,
   blocked by. Then `Free now: <names>. Run /discover-path <map-url> to work
   one.` Stop. Charting resolves nothing.

## Work

1. **Load the map.** Body only. Done when Destination, Decisions so far, and
   the fog are in context.

2. **Pick.** The user named a ticket that is open and unclaimed: that one.
   Otherwise the **frontier** query in `references/map.md`: open, no open
   blocker, no assignee, first in map order. No free ticket: the unhappy
   paths below.

3. **Claim.** `gh issue edit <n> --add-assignee @me`, the first write.

4. **Resolve**, by type. Zoom into a closed ticket only when the question
   rests on it.
   - **grill**: invoke `grill` with the Skill tool. Seed: the ticket's
     question, the map's Destination, and Decisions so far. Open decisions:
     the question and the terms it touches. Then continue at step 5.
     `CONTEXT.md` and ADRs are grill's.
   - **research**: one Explore agent, `SEARCH=on`, brief inline. The note
     lands at `docs/research/<slug>.md` per `../grill/references/research.md`,
     committed with `/make-commit`.
   - **experiment**: `/create-mockup` for a UI question, `/create-diagram`
     for a structure question, a hand test for "does this service or library
     do X". Iterate; the user picks and says done. What was proven becomes
     `Known` lines per `../../shared-skill-core/issue-rules.md` § Known.
   - **task**: do it where the agent can; otherwise hand the user a
     checklist and wait. Record what was done and the facts later tickets
     need: where a credential lives, never its value; new URLs; counts.

   Done when the answer is a decision the user confirmed, or a fact with its
   proof. Unsettled at the end of the run: leave it open and claimed, post
   what was settled so far as a comment, say so, stop.

5. **Record.** The resolution comment per `references/map.md`, then
   `gh issue close <n>`, then one gist line with the link under Decisions so
   far, map body re-read first. Done when the ticket is closed and the map
   links it.

6. **Advance the map.** A question the answer made sharp becomes a ticket,
   titled with the `t` helper, create then wire, and its fog line leaves
   Not yet specified. A ticket the
   answer pushed past the destination: close it, one line under Out of
   scope. A closed decision the answer made wrong: the revisit flow below.
   Done when no fog line and no ticket contradicts the new answer.

7. **Clear check, or report.** Open tickets remain: say `Closed <name>. Next
   free: <names>. Run /discover-path <map-url> again.` and stop.

   No open ticket and no fog: walk the readiness gate in
   `../../shared-skill-core/issue-rules.md` § Readiness gate over the whole
   Decisions so far list, unhappy paths included. Each gap becomes one
   ticket, created now, then report as above. No gap: print `Map clear.`,
   the Decisions so far list in full, and `Run /to-epic in this chat.`

## Revisit

The user says a closed decision was wrong. Challenge the decision, not the
tickets around it.

1. New ticket: same title plus ` (revisit)`, same type and prefix style,
   blocked by nothing.
2. One comment on the old ticket, `Revisited in <name with link>`. It stays
   closed.
3. Every ticket that rested on the old answer gets the new one as a blocker.
4. When the new ticket resolves, the old map line becomes `superseded by
   <name with link>`, and an ADR born of the old answer gets
   `status: superseded by ADR-NNNN`.

## Unhappy paths

- **`--parent` or `--blocked-by` unavailable** on the repo's plan:
  `references/map.md` § Fallback.
- **Every free ticket is claimed by someone else:** list them with their
  assignees, stop.
- **No free ticket, open blocked ones remain:** a cycle or a stale claim.
  Show the graph, ask which to unblock.
