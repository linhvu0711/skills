# Plan rules

The plan is what the executor follows; `executor.md` says what it has,
what it lacks, and how it works a plan. Every decision that needs
judgment is made here.

## Vocabulary

- **Seam**: the public boundary a test looks through: a function, a route,
  a command, a screen. Tests live at seams, never inside.
- **Slice**: one change and the tests that prove it. One seam, one
  change, one commit. Each test has one `Then`. A test that needs no
  change of its own rides in the slice whose change covers it.
- **Tracer bullet**: the first slice runs the thinnest path end to end, so
  every later slice widens a path that already works.
- **Proof**: the artifact that shows a Done-when line holds: a test case,
  or a UI walk's screenshot plus the video that shows it.
- **UI walk**: a scripted pass through the running app, by hand in the
  executor's desktop: web in a browser, a desktop app, or a terminal UI.
- **Video**: one recording of one or more walks, in order, from one
  `Setup`. Every walk is in exactly one video.
- **Run**: one path through an epic, or a set of plain tickets with no parent, landed as a stack of PRs. Each
  ticket is one **layer**; layer 1's PR targets the base, each later
  layer's PR targets the branch of the layer below.

## Shape

Write every block in this order. Drop a block only when the issue has no
screen (`UI walks`, `Videos`) or nothing was decided (`Decided`).

```markdown
## Facts
Repo: owner/name        Base: main
Test: <cmd>             Typecheck: <cmd>      Lint: <cmd>       Build: <cmd>
Run: <cmd>              UI: web | desktop | terminal | none
Open: <how the executor reaches the UI after Run>
Screen: <web: 1440 and 375 wide | desktop: window size | terminal: cols x rows>
Platform: linux | windows | macos-outpost
Standards: <the files that hold the rules, or "the code">

## Proof
| # | Done-when line | Test (file, case) | UI walk | Video | Artifact |
|---|---|---|---|---|---|
| 1 | <line verbatim> | `orders.test.ts` "exports csv" | walk 1 | video 1 @ step 4 | screenshot 1 |
| 2 | <line verbatim> | `api.test.ts` "returns 400 on bad range" | none | none | test |

## Seams
- <name>: `file:line`, <why this is the boundary>

## Slices
Slice 1, proves #1 and #2: <seam name>
  Change: `file:line`, <what>. Copy the shape of `file:line`.
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
- new `<name>`: nearest is `file:line`, <the line that keeps it from serving>

## Out of scope
- <from the issue's Scope Out, plus anything the plan chose to leave>
```

## Run

A run is one plan with the blocks above written once per layer. Two
blocks come first and once:

```markdown
## Stack
| Layer | Issue | Base | Size | Points |
|---|---|---|---|---|
| 1 | #71 Team entity | main | M | 4 |
| 2 | #73 Add a member | layer 1 | S | 2 |
Points: 6 (XS 1, S 2, M 4, L 8)

## Facts
<as above, once; Base is the stack's base>
```

Then, for each layer in stack order, a heading `## Layer n · #N <title>`
and under it Proof, Seams, Slices, UI walks, Videos, Gates, Decided, Out
of scope, exactly as for one ticket. Proof rows number from 1 in each
layer. Each layer's videos are its own PR's proof.

A seam or a `Change` in layer n may name code that an earlier layer's
slice creates and the repo does not hold yet. Write the place as
`layer 1, slice 2` where `file:line` would go, plus the name the earlier
slice gives it. Nothing points at a later layer. The points line is
information, not a cap: the user chose the run.

A single ticket prepped `on` an open stack is a run of one layer whose
Base is `PR #<n>`.

## Handoff-ready

An issue with `handoff-ready` carries Steps that `to-issue` checked line
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
  that already cover those seams; the standards files; the UI kind and
  how it opens when a line is on a screen. Every field of `Facts` is
  filled.
- **Seams and Gates.** From that round. A seam is the public thing the
  changed line sits behind, the one its existing test uses.
- **Decided.** Only the issue's `Open` lines, each closed by a fact from
  the round or by a question to the user. Nothing else is decided here;
  the Steps decided it.
- **Out of scope.** The issue's Scope `Out`, verbatim.

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

**Facts.** Every command is read from CI config, package scripts, or the
README, never guessed. `Open` says how the executor reaches the UI from a
fresh machine: a URL after `Run`, a window that appears, a command that
draws the terminal UI. `Platform` and `Screen` fit the executor as
`executor.md` describes it; its screen is 1024x768, so a wide layout
needs a scroll or zoom step in the walk.

**Proof.** One row per Done-when line, verbatim. A row names a test, or
says in the Test column why a test cannot see the line; then the UI walk
and the video step that shows its `See` are the proof. A row with neither
is a gap.

**Seams.** A seam is public: something a caller, a user, or a client
reaches without knowing the inside. Prefer the seam the repo already
tests. A new seam goes under `Decided`, with the seam it copies. A new
seam that is a public API is a big fork.

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
`Decided`. A job the repo has never done gets a new thing; that is the
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

**Look.** The executor has no taste, so the plan holds every look
decision. A slice on a screen names in `Change` the mockup frame it
matches and the component or screen it copies, `file:line`. What the
mockup and the repo leave open (spacing, copy, empty and error text, a
color) is a small fork: pick, write it under `Decided`. No mockup and no
rule to copy: a big fork, ask.

**UI walks.** Every step names an exact label, route, key, or element.
`Setup` puts the app in the state the line assumes, from a command or
fixture the repo has. `Must not` is the negative check the screenshot
cannot show. One walk per screen-visible row, happy and unhappy. No two
walks end in the same picture: the screenshot is the proof, so a walk
whose `See` matches another walk's proves nothing on its own. Change the
steps until each walk ends in its own state; a `Cancel` walk first types
a new value, then cancels, and `See` names the old value.

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

- Every Done-when line has a Proof row, and every row has a test or a
  stated reason plus a walk.
- Every seam is at a `file:line` seen this session, or at an earlier
  layer's slice.
- Every `Then` is a literal.
- Every `Change` names a `file:line` seen this session, or an earlier
  layer's slice, and a pattern to copy.
- Every function, component, type, or file a `Change` adds has a
  `Decided` line naming the nearest existing one and why it does not
  serve, or saying the repo has never done this job.
- Every command in Facts came from CI, scripts, or README.
- `Standards` names where the rules live; every `Change` follows them,
  and a rule the copied line breaks is quoted.
- Every slice on a screen names its mockup frame and the component or
  screen it copies; every open look choice is under `Decided`.
- Every walk step names an exact label, route, key, or element; every
  walk has `Setup` and `Must not`; no two walks end in the same picture;
  every walk is named in a Proof row, and the row and the walk agree on
  which line it proves.
- Every walk is in exactly one video; no two videos share a `Setup`;
  every walk's Proof row names its video and step.
- No Open line remains. Every big fork was put to the user and answered.
- Every dependency a `Change` adds or bumps was asked as a big fork,
  and its `Decided` line is marked `(user)`.
- Gates name the existing tests on the touched seams.
- A run: the Stack block lists every layer with its base, and the order
  respects every `Blocked by` edge.
