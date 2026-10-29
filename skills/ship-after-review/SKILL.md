---
name: ship-after-review
description: "The run of /ship-ready with one stop: the plan opens as a page for you to read and edit, and the build starts only after you say ok. Same arguments as /ship-ready: one issue, a run of epic tickets, a set, a whole epic, a new layer on a stack, devin or cursor, or no URL. It never merges. /ship-ready does the run with no stop; /ship-full does it with no stop and merges."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

Read `../ship-ready/SKILL.md` and follow it whole: its § Never, its
todo list, its forms, its steps 1 to 7, and its § No URL. Every
`/ship-ready` in it names this command too. The parts below win over
it. The one change: the user reviews the plan before anything is
built. Never merge a PR: ship-ready's § Never holds whole.

## Steps

1. **Plan.** Ship-ready's step 1, with plan-up step 8 whole, as
   `../plan-up/SKILL.md` writes it, in place of ship-ready's two
   changes there: build the page, serve and open it, or publish it on a
   headless host, print the summary of `../../shared/plan-page.md`
   § Chat with its URL and its `Say ok` line, and wait. Nothing is
   built while it waits. The answer picks the next move:
   - An edit, a ref and what to change: change the `.md`, rebuild,
     bump `v`, show the summary again, and wait again.
   - `ok`: remove the base copy, leave out `Ready for /handoff.`, and go
     on at once to step 2.
   - `stop`: remove the base copy, say `Stopped: nothing built. Plan:
     <path>`, and end the run.

   The stop points before plan-up step 8 are ship-ready's, as written.
   Done when `ok` was given and you hold the plan `.md`.

Ship-ready's steps 2 to 7 run as written, from the plan the user
approved.

## No URL

Ship-ready's § No URL, with its case 2 changed:

2. **A plan this chat made**, by `/plan-up` or by this skill's step 1,
   with no build yet. Hold its `.md`, the path its summary names.
   - It got `ok` already, as `/plan-up` alone ends: say `Plan: <path>`
     and go on to step 2.
   - It has no ok yet: run `../../shared/serve.sh` again for its page,
     print its summary with the URL and the `Say ok` line, and wait as
     step 1 does. Its base copy stays until `ok` or `stop`. Words with
     it are an edit, as in step 1.

Case 3, a chat plan, waits at step 1 like any plan.

## Examples

**User:** `/ship-after-review https://github.com/acme/shop/issues/42`;
the plan has three UI walks.

Plan-up runs steps 1 to 8 whole. The page opens, the summary ends
`Say ok, or name a ref (S2, W1, D3, #4) and what to change.` The user
says `S2: keep the JSON export as the default`. The `.md` changes, the
page is rebuilt with `v=2`, the summary shows again. The user says
`ok`: the base copy is removed, `Route: local (3 walks)`, and the run
goes on as ship-ready's. The report ends
`READY https://github.com/acme/shop/pull/43`. The merge is the user's.

**User:** `/plan-up https://github.com/acme/shop/issues/42`, then, with
the page open and no `ok`, `/ship-after-review`.

§ No URL case 2, no ok yet. `serve.sh` gives the page URL again, the
summary shows, and the run waits. `ok`: step 2, as above.

**User:** `/ship-after-review https://github.com/acme/shop/issues/57`;
at the wait the user says `stop`.

The base copy is removed. `Stopped: nothing built. Plan:
~/.agents/artifacts/plan/plan-acme-shop-57.md`. No worktree, no PR.
