# The executor

The plan is written for an executor: a coding agent that gets the plan
as one prompt and builds from it alone. This file says what the plan
may assume about it. Which agent it is, and the rules it runs under,
belong to `/handoff-devin`; the plan never names it.

## What it has

- Hands: a shell, an editor, git, and the repo checked out on the base
  branch. It runs every command under `Facts` as written.
- A browser and a desktop, so it can run the app and walk a screen. The
  screen is 1024x768; a wider layout needs a scroll or zoom step in the
  walk.
- A platform, one of `linux`, `windows`, `macos-outpost`, named under
  `Facts`.
- A screen recorder and a way to attach images and video to the PR.
- Access to GitHub: it commits, opens the PR, and answers review
  comments on it.

## What it does not have

- No taste and no strategic view. It follows the plan in order and
  makes no choice the plan left open. Every decision that needs
  judgment is made in the plan. What is left for it is small and
  low-risk: a local name, the order of two lines.
- No file of ours. The prompt is all it reads, so every fact the plan
  leans on is in the plan: commands, `file:line`, the pattern to copy,
  the literal a test expects.
- No cheap way to ask. A question stops the session until the user
  answers, so the plan leaves nothing that needs one. It asks only on a
  surprise that changes a seam, a Done-when line, a schema, an API, a
  `Decided` line, or a `Gates` test; anything smaller it settles by the
  nearest existing pattern and says so.

## How it works the plan

- One slice at a time, in order. Tests under the slice first, red;
  then the smallest change that makes them green; then commit. So each
  slice must be one change with the tests that prove it, and every
  `Then` a literal it can compare against.
- Tests look through the seam the slice names and never at internals.
  Mocks only at the borders `Given` names.
- Existing tests under `Gates` stay untouched and green.
- `Decided` and `Out of scope` are closed. It builds what the slices
  say and nothing more.
- When every slice of a layer is green: full suite, typecheck, lint,
  build; then each video under `Videos` once, its steps in order, and at
  each `Shows` step a screenshot of that walk's `See`. So every walk
  must end in its own picture, and every walk must sit in a video.
- One PR per layer. The PR carries a Proof table, one row per Done-when
  line, with the test, the screenshot, and the video step. A row with
  nothing in it is a gap the plan left.
- A run: layers in stack order, each PR on the branch of the layer
  below. A `layer n, slice m` pointer in the plan means code that
  earlier layer made; it is on that branch under the name the plan
  gives.
