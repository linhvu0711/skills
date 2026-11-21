# sync-harnesses

Checks that Claude Code, Codex, and Antigravity on your Mac have the repo's skills and subagents and your rules and gates, and that Devin in T3 answers on SWE-2.

## Use it when

You added a skill, set up a harness, or updated T3, or a skill acts as if a helper or a gate is gone. Type `/sync-harnesses` (`$sync-harnesses` in Codex). It runs only when you call it.

## What you get

First it runs the repo's [link.sh](../../scripts/link.sh), which makes every missing link and agent file. Each one it makes shows as a `fixed:` line, as `fixed: linked ~/.claude/skills/demo`. Each one it finds but cannot own, such as an agent file you wrote by hand, shows as a `problem:` line in link.sh's words. link.sh does nothing in a worktree, so run the skill from its installed copy, which points at the main checkout.

Then one line per harness, then one line for Devin in T3. On a Mac where all is well:

```
claude       skills 41/41 · subagents 11/11 · gates 6/6 · rules 1/1
codex        skills 41/41 · subagents 11/11 · gates 6/6 · rules 1/1
antigravity  skills 41/41 · subagents 11/11 · gates 7/7 · rules 2/2
devin in T3  on · swe-2-high answers
```

Each count is what the harness has out of what it should have:

- `skills` counts the repo's skills linked into the harness's skills folder: `~/.claude/skills`, `~/.agents/skills` for Codex, and `~/.gemini/config/skills` for Antigravity.
- `subagents` counts the repo's skill agents, and the explorer and the runner, that have their file in the harness's agents folder.
- `gates` counts the gates a hook command runs: your five personal gates (write-for-agents, the two unslop gates, the question gate, and the plain-style reminder) and the repo's subagent gate. Antigravity has a seventh, the start-of-chat gate that loads your rules, since T3 starts its chats without them.
- `rules` counts the files that load `~/.agents/rules/shared.md`, and is 0 while that file is missing or empty. Claude Code's `CLAUDE.md` imports it. Codex's `AGENTS.md` holds a copy of it. Antigravity's `GEMINI.md` includes it, and each private Antigravity folder T3 keeps adds one more: its `GEMINI.md` link.

A harness whose command (`claude`, `codex`, or `agy`) is not on your `PATH` shows `antigravity  skipped: not installed` in place of its counts. The check skips it, with its backup models and the links under its own folders, and the run does not fail for it.

Anything missing gets its own `problem:` line, and the run exits 1:

```
problem: codex gate question-gate is not wired in ~/.codex/hooks.json
problem: antigravity rules: ~/.t3/userdata/providers/antigravity/ac0a… has no GEMINI.md link: T3 makes it at the next Antigravity chat
```

The check never makes T3's `GEMINI.md` link. T3 makes that link itself each time it starts an Antigravity chat, so one owner keeps it.

It also checks each model a helper's file names. A home model must be in T3's list for its place, `~/.t3/caches/<provider>.json`. A helper that lists more than one home gets each one checked, and a problem names the second as `home 2`. A Claude Code backup must be in T3's Claude list, and a Codex backup in Codex's own list, `~/.codex/models_cache.json`. An Antigravity backup names no exact model, so it has no list. A model not in its list gets a line such as `problem: skills/demo/agents/helper.md: backup for codex: Codex does not offer gpt-6-luna`. The check changes no agent file: you pick the new model. A place that is off in T3 gets `skip: Antigravity is off in T3, so its home models are not checked`, and a skip line does not fail the run.

The Devin line comes from one live call to SWE-2 through Devin's CLI, for each model a helper's first home names in Devin. A later home on Devin is only a fallback, so the live call skips it. A call takes about 4 seconds and costs nothing in Devin. When Devin is off in T3 or not set up there, or it refuses the model, the helpers whose first home is Devin run on their backup, or on their next home when they list one, and a `warn:` line names them:

```
warn: Devin is off in T3, so these run on their backup: scope-reviewer, standards-reviewer, walker
warn: swe-2-high refused (Error: Unknown model: 'swe-2-high'), so these run on their backup: scope-reviewer, standards-reviewer, walker
```

A warning does not fail the run.

## Needs

- `jq` and `perl`.
- Your setup in `~/.agents/rules` and `~/.agents/hooks`, wired into each harness.
- T3 Code, for the Devin line, and Devin's `devin` CLI, signed in.

## Fits with

- [link.sh](../../scripts/link.sh) makes every link the check counts.
- The [subagent gate](../../shared/gate/) is one of the gates it counts.
- [review-pr](../review-pr/) and [build-and-prove](../build-and-prove/) start the helpers whose files it counts.

## Tests

The cases are in [tests/sync-harnesses.sh](tests/sync-harnesses.sh). Each runs on a fake Mac that [tests/fixtures/mac.sh](tests/fixtures/mac.sh) builds. The repo's [test.sh](../../scripts/test.sh) runs them with the rest.
