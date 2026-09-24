---
name: grill
description: A relentless interview to sharpen a plan or design, which also creates docs (ADRs and glossary) as we go. Fires only when the user types /grill or says "grill me on this" in so many words, or when another skill hands over a seed. A plan or design discussion with no such words stays a normal conversation.
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

Read `../../shared-skill-core/grilling.md`, `references/domain-modeling.md`, and `../../shared-skill-core/facts.md` first, and follow all three at once:

- `grilling.md` is the interview: design tree, frontier, one question per message, the branches always in the tree, and the done rule.
- `domain-modeling.md` is the glossary and ADR discipline, applied the whole time: challenge terms, sharpen fuzzy language, update `CONTEXT.md` as each term settles, offer an ADR only when its three conditions hold.
- `facts.md` is how facts are fetched: agents retrieve, you comprehend, the user decides.

## Seed

A **seed** is what another skill hands you when it invokes you: a source (an audit, a report, a card, a diagnosis) and its open decisions, named. A seed can also be a GitHub issue the user points at, most often one the capture skill filed (`/grill #12`, "grill me on issue 12"): read it with `gh issue view <n>`, and its number is the seed number for § Close out. The seed is round 0: build the first frontier from its open decisions, and fan out only for facts it does not carry.

A caller writes one block and nothing more: `Invoke the grill skill with the Skill tool. Seed: <the source>. Open decisions: <the list>. Then continue at step N.` How the interview runs, how it ends, and what it writes are this skill's, not the caller's.

During a seeded grill, `CONTEXT.md` and the ADRs are yours. New terms land in the glossary. A rejected option with a load-bearing reason becomes an ADR, so a later run of the caller does not suggest it again.

The grill ends per `grilling.md` § Done, when the user confirms shared understanding. Then say `Grill done.`, list the settled decisions, run § Close out, and hand control back. The caller continues at its next step.

## Before round 1

When the plan touches an existing codebase, pull the relevant context before the first question.

Fan out per `facts.md`. The usual split is the code the plan touches, the callers and tests of that code, and the docs (`CONTEXT.md`, `docs/adr/`, the research folder, README, design notes). Add or drop agents to fit the plan. Existing research notes are caches, so check the date on each before you lean on it.

Explore in rounds. Round 1 ends when every file, symbol, and doc the plan names has been fetched. Run another round only when the picture has a gap that a question to the user would fall into. A round that comes back with nothing new ends the exploring. Carry what is still open into the frontier as a question.

Build the first frontier from the plan and from what you found. Every question that rests on a fact from the code cites it as `file:line`, so the user can see why you ask.

## During the interview

Each answer can expose a fact you have not seen: an answer names a file, a service, an API, or a behaviour that nothing you fetched covers. `facts.md` § A fact that arrives late says what to do. Ask the rest of the frontier while the fetch runs.

## Close out

After `Grill done.` and the settled list, track the files the grill left behind (`CONTEXT.md`, a new ADR, sometimes `docs/spec` or `docs/cli.md`) the same way every time:

1. Check the tree. `git status --short` on the files the grill touched. Nothing changed: say so and stop. No seed, no PR.
2. Find the seed number.
   - The grill started from a seed issue: that number.
   - The grill started from an idea in chat: run the capture skill now, with the idea as the thing. Title is the idea in one line. The seed it files is the number. Do not write acceptance criteria into it; the PR carries the decisions.
3. Branch from main, named `docs/grill-<seed>-<slug>`. If already on a non-main branch that the user made for this work, stay on it.
4. Commit only the grill files. One commit, Conventional Commits, `docs:` type. Run the unslop skill on the prose first. No AI attribution trailer.
5. Push and open the PR against main with `gh pr create`. Body: the settled decisions list from the summary, the tickets the grill filed if any, then `Closes #<seed>` on its own line.
6. Print the PR link. Never merge: the merge waits for the user's explicit go-ahead.

Edge cases:

- The seed needs no file change at all (the grill only confirmed what the docs already say): comment the outcome on the seed with `gh issue comment` and leave it open for the user to close.
- The grill also filed tickets or edited an epic: list them in the PR body so the seed points at all of them.
- The user says to skip the PR: leave the files uncommitted and say which ones.
