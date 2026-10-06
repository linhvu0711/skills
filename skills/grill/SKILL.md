---
name: grill
description: A relentless interview to sharpen a plan or design, which also settles its docs (ADRs and glossary) to ship with the work. Fires only when the user types /grill or says "grill me on this" in so many words, or when another skill hands over a seed. A plan or design discussion with no such words stays a normal conversation.
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

Read `../../shared-skill-core/grilling.md`, `references/domain-modeling.md`, and `../../shared-skill-core/facts.md` first, and follow all three at once:

- `grilling.md` is the interview: design tree, frontier, one question per message, the branches always in the tree, and the done rule.
- `domain-modeling.md` is the glossary and ADR discipline, applied the whole time: challenge terms, sharpen fuzzy language, keep each settled term and ADR in a list, offer an ADR only when its three conditions hold. No doc file changes before § Close out.
- `facts.md` is how facts are fetched: agents retrieve, you comprehend, the user decides.

## Seed

A **seed** is what another skill hands you when it invokes you: a source (an audit, a report, a card, a diagnosis) and its open decisions, named. A seed can also be a GitHub issue the user points at, most often one the capture skill filed (`/grill #12`, "grill me on issue 12"): read it with `gh issue view <n>`, and its number is the seed number for § Close out. The seed is round 0: build the first frontier from its open decisions, and fan out only for facts it does not carry.

A caller writes one block and nothing more: `Invoke the grill skill with the Skill tool. Seed: <the source>. Open decisions: <the list>. [Close out: caller.|Close out: text.] Then continue at step N.` A caller whose own work is docs, written after the grill, adds `Close out: caller.`, so its files and the grill's go in one PR. A caller that files or records the work itself adds `Close out: text.`, so it gets the doc text back and puts it there. § Close out says what changes. How the interview runs, how it ends, and what it writes are this skill's, not the caller's.

During a seeded grill, the glossary entries and the ADRs are yours to settle. New terms join the list. A rejected option with a load-bearing reason becomes an ADR in the list, so a later run of the caller does not suggest it again.

The grill ends per `grilling.md` § Done, when the user confirms shared understanding. Then say `Grill done.`, list the settled decisions, run § Close out, and hand control back. The caller continues at its next step.

## Before round 1

When the plan touches an existing codebase, pull the relevant context before the first question.

Fan out per `facts.md`. The usual split is the code the plan touches, the callers and tests of that code, and the docs (`CONTEXT.md`, `docs/adr/`, the research folder, README, design notes). The docs include the open issues with a `## Docs to write` section (`gh issue list --state open --search '"Docs to write" in:body'`): their text is decided, not built, and binds the plan like an ADR. Add or drop agents to fit the plan. Existing research notes are caches, so check the date on each before you lean on it.

Explore in rounds. Round 1 ends when every file, symbol, and doc the plan names has been fetched. Run another round only when the picture has a gap that a question to the user would fall into. A round that comes back with nothing new ends the exploring. Carry what is still open into the frontier as a question.

Build the first frontier from the plan and from what you found. Every question that rests on a fact from the code cites it as `file:line`, so the user can see why you ask.

## During the interview

Each answer can expose a fact you have not seen: an answer names a file, a service, an API, or a behaviour that nothing you fetched covers. `facts.md` § A fact that arrives late says what to do. Ask the rest of the frontier while the fetch runs.

## Close out

After `Grill done.` and the settled list, place the doc text the grill kept: the glossary entries, the ADRs, and any other doc line it settled (sometimes `docs/spec` or `docs/cli.md`). A doc that becomes true only when code lands waits in an issue, so no doc says what the code does not do yet. Run the unslop skill on the text first. Then follow the seed's close-out line.

**No line**, the default:

- Work follows, code to build: invoke the to-issue skill with the Skill tool, or to-epic when the work is over one ticket. The seed issue, when there is one, is the origin: it becomes the ticket or the parent, per `../../shared-skill-core/issue-rules.md` § Origin seed, and is never closed. Every doc entry goes under `## Docs to write`, word for word, per the same file § Docs to write; one that is true already rides on the first code ticket. No docs PR.
- No work follows (the answer was "we will not build X", or a term for code that exists): the docs are true now, so they ship now. Write them, then:
  1. Check the tree. `git status --short` on the files you wrote. Nothing changed: say so and stop. No PR.
  2. Invoke the make-pr skill with the Skill tool, with its four caller settings:
     - Branch: `docs/grill-<seed>-<slug>`, or `docs/grill-<slug>` when the grill started from an idea in chat. Already on a non-main branch that the user made for this work: that branch.
     - Files: only the grill files, in one `docs:` commit.
     - Issue line: `Closes #<seed>` for a seed issue. A grill that started from an idea in chat has no issue, so no line.
     - Summary: the settled decisions list.
  3. Print the PR link. Never merge: the merge waits for the user's explicit go-ahead.

**`Close out: caller.`** Write the docs, list the files under the settled decisions, one per line, and hand back. They stay uncommitted on the branch the run started on, and the caller ships them with its own files.

**`Close out: text.`** Write nothing. Under the settled decisions, list each doc entry: the file, the full text in a fenced block, and `already true` or `with code`. Hand back. The caller puts the entries in the issue it files, or on its map.

Edge cases:

- A seed issue with no doc text and no work (the grill only confirmed what the docs already say): comment the outcome on the seed with `gh issue comment` and leave it open for the user to close.
- The user says to skip the PR, or the issue: leave nothing written, and print the doc entries in chat.
