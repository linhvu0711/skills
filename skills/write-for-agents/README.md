# write-for-agents

A reference for writing documents that agents read: skills, `AGENTS.md`, `CLAUDE.md`, and the docs they point to.

## Use it when

You're creating or editing a skill, or changing an `AGENTS.md` or `CLAUDE.md`. `/write-for-agents` in Claude Code, `$write-for-agents` in Codex, or the agent loads it on its own when it edits one of those files.

## What you get

No output of its own. It shapes how the agent writes: what goes in the main file and what moves to a linked file, how to word a skill's description so it fires at the right time, how to end every step on a clear done condition, and how to prune lines that change nothing. For skills, `SKILL-MECHANICS.md` adds frontmatter and the choice between a skill the agent can start and one only you can.

## Needs

Nothing beyond Claude Code or Codex. No tools, no other skills.

## Fits with

No other skill in this repo calls it. The wording passes on the skills here follow its rules.

## Credits

A copy of `productivity/writing-for-agents` from [mattpocock/skills](https://github.com/mattpocock/skills), MIT license. The skill text is upstream's; this repo does not reword it.
