<!-- template: shared by /handoff-devin, /handoff-cursor, and /ship. Render with `render.sh <devin|cursor|local> prompt`. Blocks between `<!-- devin -->` / `<!-- cursor -->` / `<!-- local -->` markers are kept for that executor only; `<!-- cloud -->` keeps a block for devin and cursor and drops it for local. Blocks nest. {{app}}, {{me}}, {{session}}, {{here}}, {{caller}} are per-executor words. -->
# Prompt rules

The prompt file is the only thing the executor gets. It reads no file
of ours beyond it. So it carries the issue, the plan, and the rules in
<!-- local -->
full, in this order. `/ship` writes the file and the executor reads it
whole: the Devin CLI pane gets `Read <path> whole and follow it` as its
first prompt, or the planning session follows the file itself. The
head lines (everything above the first `# ` heading) open the file,
because the rules block reads `Repo`, `Base branch`, `Branch`, and
`Size labels` by name. A local prompt never has `UI walks`, `Videos`,
or a `Stack`: a plan with any of those goes to a cloud executor.
<!-- /local -->
<!-- devin -->
full, in this order. `devin.sh` sends it as an attachment: Devin's
prompt is the head lines (everything above the first `# ` heading) and
an `ATTACHMENT:"<url>"` line, and it reads the file whole. So the head
lines must stand on their own, and every heading below stays in the
file.
<!-- /devin -->
<!-- cursor -->
full, in this order. `cursor.sh` sends the file whole as the prompt
text: there is no attachment and no pointer line. The head lines
(everything above the first `# ` heading) still open the file, because
the rules block reads `Repo`, `Base branch`, and `Size labels` by name.
<!-- /cursor -->

## Skeleton

```markdown
Repo: owner/name
Base branch: main
<!-- cursor -->
Author: Name <email>
<!-- /cursor -->
<!-- local -->
Branch: feat/42-export-orders-csv
Worktree: /Users/me/development/worktrees/shop/feat-42-export-orders-csv
<!-- /local -->
Size labels: XS size/XS · S size/S · M size/M · L size/L · XL size/XL
Issue: #42 <title> (<url>) · size M

# Task
<What to build, verbatim from the issue. For a fix: Expected, Actual, Repro.>

# Done when
<the Done-when list, verbatim, numbered to match the Proof rows>

# Facts
<the plan's Facts block>

# Proof
<the plan's Proof table>

# Seams
<the plan's Seams block>

# Slices
<the plan's Slices block, in order>

# UI walks
<the plan's UI walks block; drop when UI is none>

# Videos
<the plan's Videos block; drop when UI is none>

# Gates
<the plan's Gates block>

# Decided
<the plan's Decided block, so the executor knows these are closed>

# Out of scope
<the plan's Out of scope block>

# Rules
<the rules block, `render.sh {{me}} rules`, pasted whole>
```

The headings are fixed. The rules block refers to them by name.

<!-- cursor -->
## Author

`Author` is the user's git identity, `git config user.name` and
`git config user.email` on the user's machine, as `Name <email>`. The
rules block sets it in the workspace before the first commit, so the
commits are the user's and not `Cursor Agent`'s.

<!-- /cursor -->
## Size

`Size labels` lists the five PR size labels in the repo's own spelling,
as `{{caller}}` resolved and created them; the rules block picks
one from the facts of the diff, with the same table the issue was
sized by (§ Size in the rules). The line starts with `bot ·` when a workflow
in the repo labels PRs by size; then the names are the bot's, and the
executor leaves the labelling to it. `size M` after the issue line is
the issue's size label mapped to its letter, `size none` when the issue
has no size label. A run carries the letter per layer in the `Size`
column of `Stack`, copied from the plan's Stack table without the
`Points` column. The executor uses these only to say when the diff
lands on another size than the forecast.

<!-- cloud -->
## Run

A run stacks several layers in one prompt. The head names the stack,
`Facts` and `Rules` appear once, and every other block appears once per
layer under a layer heading. The rules block reads the stack from
`# Stack`.

```markdown
Repo: owner/name
Base branch: main
<!-- cursor -->
Author: Name <email>
<!-- /cursor -->
Size labels: XS size/XS · S size/S · M size/M · L size/L · XL size/XL

# Stack
| Layer | Issue | Base | Size |
|---|---|---|---|
| 1 | #71 Team entity (<url>) | main | M |
| 2 | #73 Add a member (<url>) | layer 1 | S |

# Facts
<the plan's Facts block>

# Layer 1 · #71 Team entity
## Task
<What to build, verbatim from #71>
## Done when
<#71's list, verbatim, numbered to match its Proof rows>
## Proof
## Seams
## Slices
## UI walks
## Videos
## Gates
## Decided
## Out of scope
<each from layer 1 of the plan>

# Layer 2 · #73 Add a member
<same headings, from layer 2 of the plan>

# Rules
<the rules block, `render.sh {{me}} rules`, pasted whole>
```

A `layer 1, slice 2` pointer in the plan stays as written; the rules
block tells the executor what it means.
<!-- /cloud -->

## Follow-up

<!-- devin -->
A follow-up goes into a session that already holds the first prompt.
Only what changed, same headings, nothing repeated:
<!-- /devin -->
<!-- local -->
A follow-up goes into the pane that already holds the first prompt,
with `herdr-send`, or is the next thing the planning session does
itself. Only what changed, same headings, nothing repeated:
<!-- /local -->
<!-- cursor -->
A follow-up goes into an agent that already holds the first prompt. It
is a new run on the same agent, same workspace, same branch. Only what
changed, same headings, nothing repeated:
<!-- /cursor -->

```markdown
# Changed
<one or two lines: what is different from the first prompt, and why>

# Proof
<only the rows added or changed, numbered to continue the table>

# Slices
<only the slices added or changed>

# UI walks
<only the walks added or changed>

# Videos
<only the videos a changed walk sits in, whole, with their Shows line>

# Check
<which gates to run again: named tests, named walks, named videos>
```

<!-- devin -->
The session keeps the rules it already has. When a follow-up changes a
<!-- /devin -->
<!-- cursor -->
The agent keeps the rules it already has. When a follow-up changes a
<!-- /cursor -->
<!-- local -->
The pane keeps the rules it already has. When a follow-up changes a
<!-- /local -->
Decided line, say so under `Changed`.

## Answer

<!-- devin -->
An answer goes into a session that stopped on a question. It is short:
the pick, the fact behind it, and what to do now. No headings the
question did not ask for.
<!-- /devin -->
<!-- local -->
An answer goes into a pane whose last message was a `QUESTION`. It is
short: the pick, the fact behind it, and what to do now. No headings
the question did not ask for.
<!-- /local -->
<!-- cursor -->
An answer goes into an agent whose last run ended on a question. It is
short: the pick, the fact behind it, and what to do now. No headings
the question did not ask for.
<!-- /cursor -->

```markdown
# Answer
<the pick, one line, with the file:line that settles it>

# Why
<one or two lines: what the plan said, what the repo holds, why this pick>

# Changed
<only when the pick moves a Decided line, a Proof row, or a slice; else drop the block>

# Check
<which gates to run again: named tests, named walks, named videos>
```

<!-- devin -->
The session keeps the rules it already has. When the user made the pick
<!-- /devin -->
<!-- cursor -->
The agent keeps the rules it already has. When the user made the pick
<!-- /cursor -->
<!-- local -->
The pane keeps the rules it already has. When the user made the pick
<!-- /local -->
(a big fork), `Why` says so in one line and still gives the `file:line`.

<!-- cloud -->
## New layer

A plan prepped `on` the top PR of the running stack goes in as a
follow-up that adds one layer. `Changed` says which PR it stacks on;
`Stack` carries the layer whole, in the shape of a layer block from
§ Run, with its own Task and Done when; `Check` names its gates.

```markdown
# Changed
Layer 4 goes on top of PR #80. Nothing below changes.

# Stack
| Layer | Issue | Base | Size |
|---|---|---|---|
| 4 | #75 Team switcher (<url>) | PR #80 | S |

# Layer 4 · #75 Team switcher
## Task
…
## Out of scope
…

# Check
<its gates>
```

<!-- /cloud -->
