# Plan rules

The plan is what the executor follows; `executor.md` says what it has,
what it lacks, and how it works a plan. Every decision that needs
judgment is made here.

## Vocabulary

- **Seam**: where a module's interface lives, per
  `../../shared-skill-core/codebase-design.md`. A plan's seams are external
  ones: the public place a caller and a test both cross, a function, a
  route, a command, a screen. Tests live at seams, never inside.
- **Slice**: one change and the tests that prove it. One seam, one
  change, one commit. Each test has one `Then`. A test that needs no
  change of its own rides in the slice whose change covers it.
- **Probe**: a small run, outside the repo's tree, that settles a fact
  reading cannot, per `references/probes.md`. Its answer is a `Proved` line.
- **Stale doc**: a doc that says what the code did before the change: a
  README section, a guide, a `CHANGELOG`, an ADR, `--help` text, an
  `.env.example`. A doc the change needs and nobody wrote is stale too.
- **Tracer bullet**: the first slice runs the thinnest path end to end, so
  every later slice widens a path that already works.
- **On a screen**: a Done-when line a person checks by looking at the
  running app: text, layout, color, wrap, width, order, a dialog. A web
  page, a desktop window, and a command's printed output in a terminal
  all count, so a CLI that prints lines is `UI: terminal`. A line only a
  program reads (a return value, `--json`, an API or MCP field, a file)
  is off a screen.
- **Proof**: the artifact that shows a Done-when line holds: a test case,
  or the reason no test can see the line; for a line on a screen, also a
  UI walk's screenshot plus the video that shows it.
- **UI walk**: a scripted pass through the running app, by hand in the
  executor's desktop: web in a browser, a desktop app, or a terminal.
- **Before shot**: a screenshot of a walk's screen on the base, taken
  before any change, so a reader of the PR sees what changed. Only a
  walk whose screen exists on the base, and looks or acts different
  after the change, has one.
- **Video**: one recording of one or more walks, in order, from one
  `Setup`. Every walk is in exactly one video.
- **Review block**: the plan in the words a person needs to approve it:
  what changes, how, what it touches, the choices, the risks, how we
  know it works, and the scope. The page shows it as the Review view,
  its first tab. Everything under it is for the executor.
- **Change map**: the one diagram in the Review view. A box is a part
  with a job, named in the repo's own words (`CONTEXT.md` first); an
  arrow is what moves between parts, or who asks whom; a group is the
  app or package the parts live in. A store box names the tables,
  columns, or keys that change. Files are a box's details, never boxes,
  and an import is never an arrow.
- **Run**: one path through an epic, or a set of plain tickets with no parent, landed as a stack of PRs. Each
  ticket is one **layer**; layer 1's PR targets the base, each later
  layer's PR targets the branch of the layer below.

## Shape

Write every block in this order. Drop a block only when no probe ran
(`Proved`), no Done-when line is on a screen (`UI walks`, `Videos`), or
nothing was decided (`Decided`).

```markdown
# Plan: #<n> <issue title>
Size: size/<x>    Date: YYYY-MM-DD

## Review
Change:   <before> → <after>, at most 4 lines
Approach: <how it is built, and why not the other way>, at most 4 lines
Blast radius:
  Touches:    <the modules or packages the change reaches, comma list>
  Dependency: none | <name>, D<n>
  Schema:     none | <table, column, migration>
  API:        none | <route, command, tool, or export a caller uses>
  Config:     none | <env var, config key, flag>
  CI:         none | <workflow, job>
Choices:
  - Fork: <question> → <pick> (user)
  - D<n>: <the decision>. Risk: <what a wrong pick costs>
Risks:
  - <what we believe>. If wrong: <what breaks>. Proved: P<n> | not proved
Works when:
  - #1 <Done-when line 1 in plain words>
  - #2 <...>
In:  <what the plan builds>, at most 4 lines
Out: <what it leaves, with O refs>, at most 4 lines

## Change map
| Ref | Part | Job | Change | Group | Kind | At | Grid |
|---|---|---|---|---|---|---|---|
| M1 | setup command | now only asks Lifecycle | changed | CLI | part | `apps/cli/src/setup.ts` | 0,1 |
| M2 | Lifecycle | install order, restore on fail | new | Collector | part | S1 | 1,1 |
| M3 | Store | settings: + grant.<browser> keys | same | | store | `core/src/store.ts` | 3,1 |
| M4 | plutil | macOS tool | new | | outside | | 2,0 |
Flows:
- M1 → M2: install (new)
- M1 → M3: writes agent (removed)

## Facts
Repo: owner/name        Base: main
Test: <cmd>             Typecheck: <cmd>      Lint: <cmd>       Build: <cmd>
Run: <cmd>              UI: web | desktop | terminal | none
Open: <how the executor reaches the UI after Run>
Screen: <web: 1440 and 375 wide | desktop: window size | terminal: cols x rows>
Platform: linux | windows | macos-outpost
Standards: <the files that hold the rules, or "the code">

## Proved
- P1 <the fact, with the value, shape, or limit the build needs>: <what ran,
  one clause>, <YYYY-MM-DD>. Used by <S2, D1>.

## Summary
<2 to 3 lines: what changes, the path slice 1 takes, the counts>

## Proof
| # | Done-when line | Test (file, case) | UI walk | Video | Artifact |
|---|---|---|---|---|---|
| 1 | <line verbatim> | `orders.test.ts` "exports csv" | walk 1 | video 1 @ step 4 | screenshot 1 |
| 2 | <line verbatim> | `api.test.ts` "returns 400 on bad range" | none | none | test |

## Seams
- <name>: `file:line`, <why the interface lives here>

## Slices
Slice 1, proves #1 and #2: <seam name>
  Change: `file:line`, <what>. Copy the shape of `file:line`.
  Docs:   `README.md:88`, <what the doc says after this slice>.
  Test `orders.test.ts` "exports csv"
    Given:  <fixtures, data, login state, exact values>
    When:   <the one call through the seam>
    Then:   <a literal result, never computed>
  Test `orders.test.ts` "exports nothing for an empty store"
    Given:  <...>
    When:   <...>
    Then:   <...>

## UI walks
Walk 1, proves #1
  Setup:    <seed command or fixture, user role, login state>
  Where:    <route, window, or screen name>
  Steps:    <click "Export CSV", type ..., press Enter; exact labels>
  See:      <exact text or element>
  Must not: <console errors, failed requests, error text in the log>
  Before:   <none | as walk n | the steps on the base that reach the same screen; what it shows there now>

## Videos
Video 1, Setup of walk 1, shows walks 1, 3
  1. <step with exact label>
  2. ...
  Shows: #1 at step 4, #3 at step 7

## Gates
Slice done: its test green, typecheck green.
Task done:  every Proof row has its artifact, full suite green, lint green,
            build green, and these existing tests untouched and green:
            <names>.

## Decided
- <choice>: <what was picked, one clause why, file:line>
- new `<name>`: nearest is `file:line`, <the line that keeps it from serving>; hides <what it hides behind its interface>

## Out of scope
- <from the issue's Scope Out, plus anything the plan chose to leave>
```

## Chat plan

A chat plan (`SKILL.md` § Six forms) has no issue. It takes the shape
of one ticket, with two changes. The head line has no number:
`# Plan: <brief title>`. And a `## Brief` block comes last, after Out
of scope: the brief's `Task` and `Done when` lines from `SKILL.md`
step 2, word for word, since there is no issue for the build prompt to
quote.

```markdown
## Brief
Task: <one to three lines>
Done when:
- <Done-when line 1>
- <...>
```

## Run

A run is one plan with the blocks above written once per layer. These
blocks come first and once:

```markdown
# Plan: #<first ticket or epic> <title>
Date: YYYY-MM-DD

## Stack
| Layer | Issue | Base | Size | Points |
|---|---|---|---|---|
| 1 | #71 Team entity | main | M | 4 |
| 2 | #73 Add a member | layer 1 | S | 2 |
Points: 6 (XS 1, S 2, M 4, L 8)

## Review
<the stack's: Change, Approach, Blast radius, Risks, In, Out, as above,
for the whole stack>

## Change map
<as above, for the whole stack, with a Layer column>

## Facts
<as above, once; Base is the stack's base>

## Proved
<as above, once, every layer's probes; `Used by` names the layer, `L2 S1`>
```

Then, for each layer in stack order, a heading `## Layer n · #N <title>`
and under it a small `## Review` block, then `## Summary`, Proof, Seams, Slices, UI
walks, Videos, Gates, Decided, Out of scope, exactly as for one ticket.
The layer's Review holds three parts: `Change`, at most 2 lines, what
this layer's PR adds to the stack; `Choices`, its forks and decisions;
`Works when`, its Proof rows.

A run has one Change map, after the stack's Review, for the whole stack.
Each part and flow that is not `same` ends with the layer that makes
it: a `Layer` column (`L1`) on the parts table, and `, L1` inside a
flow's brackets, as in `(new, L1)`. The page lists each layer's refs
under its small Review. Proof rows number from 1 in each
layer. Each layer's videos are its own PR's proof.

A seam or a `Change` in layer n may name code that an earlier layer's
slice creates and the repo does not hold yet. Write the place as
`layer 1, slice 2` where `file:line` would go, plus the name the earlier
slice gives it. Nothing points at a later layer. The points line is
information, not a cap: the user chose the run.

A single ticket prepped `on` an open stack is a run of one layer whose
Base is `PR #<n>`. It has both the stack Review and the layer Review.
The H1 and Date come first and once; each layer has its own Summary.

## Ready-to-build

An issue with `ready-to-build` carries Steps that `to-issue` checked line
by line: every `file:line` was seen, no choice is open. The plan trusts
them. This is the **short path**: the repo is read only for what the
Steps do not say, and no step is re-planned. The plan still has every
block above, and the Done rule holds whole.

- **Slices.** Each step that changes code is one slice, in step order.
  Its `file:line` is the `Change`; the pattern the step names to copy
  stays in `Change`. A step that only adds or edits a test case is not a
  slice; it is a test in the slice whose change it proves.
- **Tests.** The last step names the test file, the case, and the
  command. `Given`, `When`, `Then` come from the Done-when line the case
  proves; `Then` is the literal the issue gives (`116 pass`, the ISO
  date). No literal in the issue: the Explore round reads the test file
  and the code, and the plan writes one.
- **Proof.** One row per Done-when line, as always. A line the named
  case proves points at it. A line only a command shows (`grep … is
  empty`, `bun test` passes) puts that command in the Test column; its
  artifact is the command's output. A line neither reaches gets a test
  written here, at the seam, like any plan.
- **UI.** A Done-when line on a screen gets a walk and a video, written
  here as for any plan. The label does not say the ticket has no screen;
  XS rarely does.
- **Facts.** One Explore round, and only this: the commands from CI,
  scripts, or README; the seam each changed line sits behind; the tests
  that already cover those seams; the standards files; the docs the
  Steps make stale; the UI kind and how it opens when a line is on a
  screen. Every field of `Facts` is filled. No probe, unless an `Open`
  line needs one.
- **Docs.** Each stale doc is a `Docs` line in the slice of the step
  that makes it stale. The Steps need not name it.
- **Seams and Gates.** From that round. A seam is the public thing the
  changed line sits behind, the one its existing test uses.
- **Decided.** Only the issue's `Open` lines, each closed by a fact from
  the round or by a question to the user, and the docs the round found
  that stay as they are. Nothing else is decided here; the Steps decided
  it.
- **Out of scope.** The issue's Scope `Out`, verbatim.
- **Review.** As for any plan, from the blocks above. `Choices` holds
  only the `Decided` lines the issue's `Open` lines left.
- **Change map.** As for any plan. The Explore round adds one ask: the
  parts and flows around each seam the Steps touch.

Two things end the short path:

- **A stale step.** The code at a step's `file:line` is not what the
  step says: the line moved and still shows the same code, fix the
  `file:line` in `Change` and say so in the summary; the code, the name,
  or the pattern is gone, say which step and what is there now, and
  stop. The issue gets fixed, not the plan.
- **A choice.** A step that needs a decision the issue did not make
  means the label was wrong. Say which step and why, then plan the
  ticket on the full path from SKILL.md step 4, with the Steps as input.

In a run, a labelled layer is built the same way.

## Filling the blocks

**Summary.** Two to three lines: what changes, the path slice 1 takes,
and the counts. The page shows it as the layer's Overview lead.

**Review.** Written last, from the blocks under it, and placed first.
It is for a person who approves the plan and never reads a slice, so it
uses the issue's words and the repo's names, and no plan words (`slice
2`, `walk 1`); refs (`D2`, `P1`, `#3`, `O1`) are fine, since the page
links them. Each part keeps its limit; a part that needs more says less.
- `Change` says what a user or a caller sees before and after, not which
  files move.
- `Approach` names the way the plan builds it and the way it does not,
  with the reason in one clause.
- `Blast radius` has all six lines. `none` is a finding: it tells the
  reader the plan checked. `Dependency` names every package the plan
  adds or bumps, with its `Decided` ref.
- `Choices` lists every big fork, marked `(user)`, then at most 3 lines
  from `Decided`: the ones whose wrong pick costs the most. Nothing was
  forked or decided: one line, `- none`.
- `Risks` holds at most 3 beliefs the plan rests on, the ones with the
  worst failure, each with what breaks if it is wrong and the `P` line
  that proves it, or `not proved`. No belief carries a risk: `- none`.
- `Works when` has one line per Proof row, in order, the Done-when line
  in plain words.
- `In` and `Out` are the scope. `Out` names the `Out of scope` lines by
  their `O` ref.

**Change map.** Drawn when a part is added or removed, a job moves from
one part to another, or a flow is added, removed, or changes. A change
inside one part's job draws no map: the block holds one line, `None: no
part or flow changes.`, so the reader sees that the plan checked.
- A part is named in the repo's words and carries its job, or how its
  job changes, short enough to fit the box. `scripts/build-page.py`
  holds the limits and names each line over one. `Change` is `new`, `changed` (the job
  changes), `removed`, or `same`. A `same` part is on the map only when
  a changed flow touches it.
- `Kind` is `part`, `store` (a table, a file, a cache: its `Job` names
  what changes in it), or `outside` (a tool, a service, a person, or an
  app the repo does not hold).
- `At` is the files of a part that exists now, `file` or `file:line`,
  comma list, or the slice that makes a new one (`S2`, `L2 S1`). An
  `outside` part leaves it empty.
- A flow names what moves or what is asked, never `imports`, in a few
  words within the label limit in `scripts/build-page.py`. `(same)` may be left out.
- At most 12 parts. More: merge the `same` parts no changed flow needs,
  then parts of one group whose flows match. Still more: two maps, one
  per area, each block headed `## Change map · <area>`.
- `Grid` is `column,row`, both 0 or more, and no two parts share a
  cell. Flow goes left to right: people and outside callers on the left,
  stores on the right. The parts of one group sit in cells next to each
  other, with no other part inside the group's area.

**Facts.** Every command is read from CI config, package scripts, or the
README, never guessed. `Open` says how the executor reaches the UI from a
fresh machine: a URL after `Run`, a window that appears, a command to
type in a terminal of the size `Screen` names. `Platform` and `Screen` fit the executor as
`executor.md` describes it; its screen is 1024x768, so a wide layout
needs a scroll or zoom step in the walk.

**Proved.** One line per probe, numbered `P1`, `P2`. The fact first, as
exact as a `Then`: the value, the shape, the limit, the error. Then what
ran, in one clause, and the day. `Used by` names each slice, walk, or
`Decided` line that rests on it; a probe nothing uses was not needed,
and its line goes. A big fork's option that a probe backs names its
`P` line.

**Proof.** One row per Done-when line, verbatim. A row names a test, or
says in the Test column why a test cannot see the line. A row on a
screen also names its UI walk and the video step that shows its `See`,
even when its test passes: the test proves the code gives the right
output, the walk proves a person sees it right, at the real width, in
the real colors, with the real dialog. A row with no test and no reason
is a gap; a row on a screen with no walk is a gap.

**Seams.** A seam is public: something a caller, a user, or a client
reaches without knowing the inside. Prefer the seam the repo already
tests. A new seam goes under `Decided`, with the seam it copies. A new
seam that is a public API is a big fork. A new seam that swaps one thing
for another (an interface, a port, a client passed in) needs
two adapters, such as the real one and the test fake. One adapter is a
hypothetical seam: the code calls that one thing direct.

**Slices.** One per change, in tracer-bullet order. A slice lists every
test its change makes green, and nothing else: a test that would be green
without a change of its own belongs to the slice that covers it, not to a
slice of its own. `Then` is a known literal: a value from the issue, the
spec, or a worked example. `Change` names a line you saw this session and
a pattern to copy; describing a shape the code already shows is waste.
`Change` extends before it adds: a helper, a component, a type, a
fixture that does the job or part of it is called or widened, never
written twice. A new one is added only when the nearest existing one
is named and the line that keeps it from serving is quoted, under
`Decided`. A new module also passes the deletion test: delete it, and
its complexity comes back in its callers. A module that only passes a
call on fails it; the callers call the code under it. Its `Decided` line
says what it hides. A job the repo has never done gets a new thing; that is the
plain case, and `Decided` says so in one clause. A new dependency is
never the plain case: it is a big fork, per `SKILL.md` step 5, asked and
answered before the `Change` names it.
Unhappy paths are tests like any other, usually in the same slice as the
happy path of their seam. Mocks only at borders, named in `Given`. A
border the repo already mocks: copy that mock. A border the repo has never mocked: decide the
shape here, one function per outside call and the client passed in, and
write it in `Change`. `Change` follows the rules under `Standards`. A
rule the copied `file:line` breaks, or one no line shows, is quoted in
`Change`.
Each stale doc is a `Docs` line in the slice whose change makes it
stale, so the code and its doc land in one commit. The line names the
`file:line`, or the new file, and what the doc says after the slice, as
exact as a `Change`. A doc that is wrong on the base about code a slice
touches goes in the first slice that touches that code. A doc that is
wrong about code no slice touches is not this plan's: it goes under
`Out of scope` with its `file:line`. A doc the facts round found that
stays true goes under `Decided`, one line, with why. `Docs` lines need
no test and no Proof row, unless a Done-when line is about the doc.
Each entry under the issue's `## Docs to write` is a `Docs` line in the
slice whose change makes it true, its text copied word for word: the
words were agreed, and the plan does not write them again. An entry
already true goes in slice 1. A new ADR is `docs/adr/<next>-<slug>.md`:
the builder takes the next free number on its base when the slice runs.

**Look.** The executor has no taste, so the plan holds every look
decision. A slice on a screen names in `Change` the mockup frame it
matches and the component or screen it copies, `file:line`. What the
mockup and the repo leave open (spacing, copy, empty and error text, a
color) is a small fork: pick, write it under `Decided`. No mockup and no
rule to copy: a big fork, ask.

**UI walks.** Every step names an exact label, route, key, or element.
`Setup` puts the app in the state the line assumes, from a command or
fixture the repo has. `Must not` is the negative check. In a web or
desktop walk it is often what the screenshot cannot show (a console
error, a failed request). In a terminal walk it is text the screen
shows or must not show, as in `no line starting Error:`, never `stderr`
or `stdout`, which a terminal shows mixed; `scripts/build-page.py`
refuses those words there. One walk per row on a screen, happy and unhappy. No two
walks end in the same picture: the screenshot is the proof, so a walk
whose `See` matches another walk's proves nothing on its own. Change the
steps until each walk ends in its own state; a `Cancel` walk first types
a new value, then cancels, and `See` names the old value.

A step is one action: one click, one key, or one command typed and sent
with `Return`. Text to type, a command or a value, sits in backticks
right after the word `type`. A command stands alone: never two joined
with `;` or `&&`, never two in one step, and never `clear` first, since
a viewer of the video must see each command and its result.
`scripts/build-page.py` refuses a step that breaks this, naming the walk
or video and the step. In a terminal:

```markdown
  1. Type `tally status`, press Return.
  2. Type `tally rules list`, press Return.
```

never one step that types `clear; tally status; tally rules list`.

**Before shots.** A walk's `Before` line names steps when
its screen exists on the base and the change alters what a person sees
there: a fix for a bug on a screen, a new look, layout, or text, or new
behavior on a screen that exists, such as a new sort order or a new
button on an old page. The line names the steps, from the walk's
`Setup`, that reach the same screen on the base, and what the screen
shows there now, as exact as `See`; for a bug, the wrong state. A step
that needs what the change adds is left out: the base has no `Undo`
button, so the shot is the screen before that click. `Before: none` for
a new page, a new dialog, or new output where there was none: there
is nothing to compare. Two walks whose
before shots would be the same picture: the first names the steps, the
rest say `as walk n` and share its shot. The shot uses the walk's `Setup` data and the `Screen`
size, so the two pictures line up. In a run, a layer's base is the
branch of the layer below, so its before shot shows the screen as that
layer left it.

**Videos.** The fewest recordings that show every walk. Walks that share
a `Setup` go in one video, ordered so each walk's end state is the next
walk's start state, or with a reset step between them. Start a new video
only when the `Setup` differs, or a walk leaves a state no in-video step
can undo. Numbered steps, exact labels; a `Shows` line ties each walk's
`See` to the step where it appears, and the screenshot is that frame.

**Gates.** Name the existing tests that cover the touched seams, so the
executor keeps them green rather than editing them.

**Decided.** Every small fork, one line each, so the user can veto any
with one word. A choice the user made in a question goes here too, marked
`(user)`.

## Done

The plan is done when every line below holds. A miss sends you back to
facts or forks.

- Every `Proved` line has its fact, what ran, the day, and a `Used by`
  that names a slice, a walk, or a `Decided` line. Every probe left the
  checkout's status as step 1 found it, and removed its own worktree.
- Every doc the facts round or a probe named is a `Docs` line in a
  slice, a `Decided` line that says why it stays, or an `Out of scope`
  line when it covers code no slice touches. A slice whose change makes
  a doc stale carries its `Docs` line.
- Every Done-when line has a Proof row; every row has a test or a
  stated reason why no test can see it; every row on a screen also has
  a walk.
- Every seam is at a `file:line` seen this session, or at an earlier
  layer's slice.
- Every `Then` is a literal.
- Every `Change` names a `file:line` seen this session, or an earlier
  layer's slice, and a pattern to copy.
- Every function, component, type, or file a `Change` adds has a
  `Decided` line naming the nearest existing one and why it does not
  serve, or saying the repo has never done this job. A new module's line
  says what it hides, so it passes the deletion test; a new seam that
  swaps one thing for another has two adapters.
- Every command in Facts came from CI, scripts, or README.
- `Standards` names where the rules live; every `Change` follows them,
  and a rule the copied line breaks is quoted.
- Every slice on a screen names its mockup frame and the component or
  screen it copies; every open look choice is under `Decided`.
- Every walk step names an exact label, route, key, or element, and
  does one action, a typed command alone; every walk has `Setup` and
  `Must not`; a terminal walk's `Must not` names screen text, never
  `stderr` or `stdout`; no two walks end in the same picture;
  every walk is named in a Proof row, and the row and the walk agree on
  which line it proves.
- Every walk has a `Before` line: `none`, `as walk n` for an earlier
  walk of the same layer that names steps, or steps that work on the base and the exact
  state they reach.
- Every walk is in exactly one video; no two videos share a `Setup`;
  every walk's Proof row names its video and step.
- No Open line remains. Every big fork was put to the user and answered.
- Every dependency a `Change` adds or bumps was asked as a big fork,
  and its `Decided` line is marked `(user)`.
- Gates name the existing tests on the touched seams.
- A run: the Stack block lists every layer with its base, and the order
  respects every `Blocked by` edge.
- The Review block has every part, each in its limit: `Change`,
  `Approach`, `In`, and `Out` at most 4 lines, a run layer's `Change`
  at most 2; `Blast radius` all six lines; `Choices` every big fork and
  at most 3 `Decided` lines; `Risks` at most 3; `Works when` one line
  per Proof row. A run: one stack Review, and one small Review per layer.
- The Change map block is there: a map, or the `None` line when no
  part, job, or flow changes. A map has at most 12 parts, each with a
  job, a `Change`, and a free `Grid` cell outside other groups' areas;
  names, jobs, and flow labels fit their limits; every part but an `outside`
  one has an `At`; every `same` part is touched by a changed flow; every
  flow names what moves; in a run, every part and flow that is not
  `same` names its layer.
