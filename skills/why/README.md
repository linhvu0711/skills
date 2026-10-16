# why

Answers why code is the way it is from the record: git history, the PR and its reviews, the issue, the ADRs, `CONTEXT.md`, and past Claude Code and Codex sessions. Each reason carries an evidence label and its source.

## Use it when

You look at odd code and want the reason before you change it. Type `/why src/app.py:40`, `/why src/app.py:40-52`, a symbol, or a question such as `/why is ids a set?` (`$why ...` in Codex). `/why src/app.py` asks about the whole file, and its history follows renames. It only runs when you call it.

## What you get

One answer in a fixed shape. Each reason is one line with its label and where it came from: Seen when a source says it, Inferred when it follows from what was seen, Guess or Unknown with the places it searched.

```
Why: why is ids a set?
Code: src/app.py:40-40
- Seen: lookups in the ids list were slow with 50k entries. Source: https://github.com/acme/app/issues/7
- Seen: the order of the ids does not matter. Source: commit 1a2b3c4
- Inferred: a set was picked because the code only asks whether an id is there. From: the two Seen lines. Source: https://github.com/acme/app/pull/12
- Unknown: why 50k ids are loaded at once. Searched: git (2 commits), PR #12 and its reviews, issue #7, docs/adr and CONTEXT.md, sessions (Claude Code 1, Codex 0)
Searched: git (2 commits), GitHub (1 PR, 1 issue), docs/adr and CONTEXT.md, sessions (Claude Code 1, Codex 0)
```

A long history shows the 9 newest commits and the oldest one, which made the lines.

When the record is thin or odd:

- No history, as for code not committed yet: an `Unknown` line that lists where it looked. Lines you edited but did not commit have no history; the lines around them keep theirs.
- `gh` cannot reach GitHub: it answers from git, the docs, and the sessions, and its `Searched:` line says GitHub was not reached.
- Two sources disagree: both reasons, each with its label and source, then a `Disagree:` line.
- The code you name is not in the repo: it asks which code you mean.

It only reads: no change to the repo, no comment on GitHub.

## Needs

- `git`.
- `gh`, signed in, for the PR, its reviews, and the issue of each commit: one call per commit. Without it, the answer comes from git, the docs, and the sessions, and says so.
- `python3` (standard library only).
- The shared finders and extractors in [`sessions/`](../../shared-skill-core/sessions/), for past sessions.
- The evidence labels in [`facts.md`](../../shared-skill-core/facts.md).

## Fits with

- [find-cc-session](../find-cc-session/) and [find-co-session](../find-co-session/) use the same session finders it runs.
- [triage](../triage/) finds the root cause of a bug; `/why` gives the reason for code that works.
- [grill](../grill/): a reason `/why` finds can settle a question in a grill.

## Tests

The cases for [trail.py](scripts/trail.py) are in [tests/trail.sh](tests/trail.sh), on the helpers and fake `gh` in the repo's [test-lib.sh](../../scripts/test-lib.sh). The repo's [test.sh](../../scripts/test.sh) runs them with the rest.

## Credits

The idea of `/why` and of its sorted evidence takes an idea from the `why` skill and its `references/epistemics.md` in [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). No text was copied.
