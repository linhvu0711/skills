---
name: grill
description: A relentless interview to sharpen a plan or design, which also settles its docs (ADRs and glossary) to ship with the work. Fires only when the user types /grill or says "grill me on this" in so many words, or when another skill hands over a seed. A plan or design discussion with no such words stays a normal conversation.
---

Paths in this skill are relative to its real folder: the one that holds this `SKILL.md`, after links are followed, as `realpath` prints it. Before you run or read one of them, put that real folder's absolute path in front of it.

Read `../../shared/grilling.md`, `references/domain-modeling.md`, and `../../shared/facts.md` first, and follow all three at once:

- `grilling.md` is the interview: design tree, frontier, one question per message, the branches always in the tree, and the done rule.
- `domain-modeling.md` is the glossary and ADR discipline, applied the whole time: challenge terms, sharpen fuzzy language, keep each settled term and ADR in a list, offer an ADR only when its three conditions hold. No doc file changes before § Close out.
- `facts.md` is how facts are fetched: agents retrieve, you comprehend, the user decides.

## Seed

A **seed** is what another skill hands you when it invokes you: a source (an audit, a report, a card, a diagnosis) and its open decisions, named. A seed can also be a GitHub issue the user points at, most often one the capture skill filed (`/grill #12`, "grill me on issue 12"): read it with `gh issue view <n>`, and its number is the seed number for § Close out. The seed is round 0: build the first frontier from its open decisions, and fan out only for facts it does not carry.

A caller writes one block and nothing more: `Read ../grill/SKILL.md and follow it. Seed: <the source>. Open decisions: <the list>. [Close out: caller.|Close out: text.] Then continue at step N.` A caller whose own work is docs, written after the grill, adds `Close out: caller.`, so its files and the grill's go in one PR. A caller that files or records the work itself adds `Close out: text.`, so it gets the doc text back and puts it there. § Close out says what changes. How the interview runs, how it ends, and what it writes are this skill's, not the caller's.

During a seeded grill, the glossary entries and the ADRs are yours to settle. New terms join the list. A rejected option with a load-bearing reason becomes an ADR in the list, so a later run of the caller does not suggest it again.

The grill ends per `grilling.md` § Done, when the user confirms shared understanding, after § Gap check when it runs. Then say `Grill done.`, list the settled decisions, run § Close out, and hand control back. The caller continues at its next step.

## Before round 1

When the plan touches an existing codebase, pull the relevant context before the first question.

Fan out per `facts.md`. The usual split is the code the plan touches, the callers and tests of that code, and the docs (`CONTEXT.md`, `docs/adr/`, the research folder, README, design notes). The docs include the open issues with a `## Docs to write` section (`gh issue list --state open --limit 500 --search '"Docs to write" in:body'`): their text is decided, not built, and binds the plan like an ADR. Add or drop agents to fit the plan. Existing research notes are caches, so check the date on each before you lean on it.

Explore in rounds. Round 1 ends when every file, symbol, and doc the plan names has been fetched. Run another round only when the picture has a gap that a question to the user would fall into. A round that comes back with nothing new ends the exploring. Carry what is still open into the frontier as a question.

Build the first frontier from the plan and from what you found. Every question that rests on a fact from the code cites it as `file:line` on the question's `Seen:` line, per `grilling.md`, so the user can see why you ask.

## During the interview

Each answer can expose a fact you have not seen: an answer names a file, a service, an API, or a behaviour that nothing you fetched covers. `facts.md` § A fact that arrives late says what to do. Ask the rest of the frontier while the fetch runs.

## Gap check

A second model reads the settled decisions once, with fresh eyes, before the grill files more than one ticket. It runs when the user confirms shared understanding (`grilling.md` § Done), the seed has no close-out line, and the shape you named is more than one ticket. One ticket, a close-out line, or no work to file: skip to § Close out.

1. Start `gap-checker` per `../../shared/facts.md` § Skill agents. Its brief holds the grill's source (the seed, the issue's text, or the idea in the user's words), each settled decision with its reason, each option the user turned down with why, the shape, the repo folder, and the full path of `../../shared/facts.md`. Nothing else: no chat.
2. Sort each finding. A Gap the chat already answered is `already settled`. A Wrong fact is never settled by the answer whose reason it disproves. Each other finding joins the frontier as a question in the `grilling.md` format, a code proof on its `Seen:` line.
3. Run the frontier until `grilling.md` § Done holds again, then ask the user to confirm again. The check runs once per grill: the questions after it end at this second confirm.
4. Hold one line for the settled list: `Gap check: <n> found · <a> asked · <s> already settled`, `Gap check: none found`, or `Gap check: failed · <why>` when the checker errs, refuses, or hits a usage limit. With nothing left to ask, or a failed check, the first confirm stands.

## Close out

After `Grill done.` and the settled list, place the doc text the grill kept: the glossary entries, the ADRs, and any other doc line it settled (sometimes `docs/spec` or `docs/cli.md`). A doc that becomes true only when code lands waits in an issue, so no doc says what the code does not do yet. Run the unslop skill on the text first. Then follow the seed's close-out line.

**No line**, the default:

- Work follows, code to build. When the settled work changes what a person sees or clicks (a screen, a page, a dialog, a control), first say `Run /create-prototype <the feature or page>, or say go to file the work.` and wait. A change the user makes while reviewing the prototype is a decision: add it to the settled list, and to each doc entry it changes. A change that adds or alters a user action reopens its branch of the design tree: ask its frontier until `grilling.md` § Done holds again, with no second gap check. On `go`, file. Work that changes no screen files at once. File it in the shape the work takes, with as few tickets as the work allows:
  - One ticket: invoke the to-issue skill with the Skill tool.
  - A few tickets that do not depend on each other: invoke to-issue once per ticket.
  - Tickets that depend on each other, or more than one ticket from a seed issue: invoke to-epic.

  With more than one ticket, the message that asks the user to confirm shared understanding (`../../shared/grilling.md` § Done) names the shape, as `3 issues` or `an epic with 4 children`. The seed issue, when there is one, is the origin: it becomes the ticket or the parent, per `../../shared/issue-rules.md` § Origin seed, and is never closed. Every doc entry goes under `## Docs to write`, word for word, per the same file § Docs to write; one that is true already rides on the first code ticket. No docs PR.
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
