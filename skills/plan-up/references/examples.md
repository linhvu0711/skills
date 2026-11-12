# Examples

**User:** `/plan-up https://github.com/acme/shop/issues/42` (size/M feat,
export orders as CSV, six Done-when lines)

The tree is on `feat/old-work` with two edits; it stays as it is. Base
copy of `origin/main` in a temp folder. Gate passes. Round 1: five agents fetch
`orders/export.ts` and its callers, the `orders.test.ts` seam, the
`pnpm test` and `pnpm typecheck` scripts, how `ErrorToast.tsx:12` shows
errors, the `csv-stringify` docs, and the docs on export:
`README.md:88` lists JSON as the only export format. The docs say
`csv-stringify` escapes quotes but are silent on newlines inside a
field, and order notes hold newlines. One free probe, in a temp
folder: install `csv-stringify`, stream three rows, one note with a
newline. It comes back quoted and whole: a `Proved` line. Two big forks. First: a big shop
can hold more orders than one request should carry, and the repo has no
background jobs. Question with `A` stream the file in one request
(pick, `export.ts:31` streams JSON the same way) and `B` a job queue,
new to the repo. User: `A`. Second: `csv-stringify` is not in
`package.json`, a new dependency, so it is asked no matter what.
Question with `A` add `csv-stringify` (its docs show a stream API that
fits `export.ts:31`, and the probe shows a note with a newline comes
through whole) and `B` a hand-written `toCsvRow()` next to
`lib/format.ts:14`, which already quotes strings but has no escaping.
User: `A`. Both go under Decided marked `(user)`. Small forks under
Decided: stream, since `export.ts:31` does; the file response goes
through `lib/download.ts:8`, which already sets the headers, so no new
helper; file name `orders-<date>.csv`; delimiter `,`.
Plan: a Review block on top (Change: orders export as JSON only → as
JSON or CSV; Blast radius flags `Dependency: csv-stringify, D2` and
nothing else; one risk, backed by P1), one Proved line, six Proof rows,
six slices (slice 1 carries
`Docs: README.md:88`, CSV next to JSON), three UI walks (happy, empty,
failed), two videos: happy and failed from the seeded shop, empty from
an empty seed.
Done rule holds. Present, `ok`, `Ready for /handoff.`

**User:** `/plan-up https://github.com/acme/shop/issues/88` (PR 90 by
`@bob` is open and closes #88)

`claims.py acme/shop 88` prints `#88 pr #90 "Add order notes" @bob
https://github.com/acme/shop/pull/90`. One message: `#88 Order notes`,
under it `PR #90 Add order notes · @bob · https://github.com/acme/shop/pull/90`,
then the question with `A` review their PR instead, `B` build anyway,
`C` stop. User: `A`. Print `/review-pr https://github.com/acme/shop/pull/90`,
remove the base copy. Stop.

**User:** `/plan-up https://github.com/acme/shop/issues/57` (size/XS fix,
`ready-to-build`, three Steps, two Done-when lines)

Step 2 sees the label: short path. One Explore round: `pnpm test` and
`pnpm typecheck` from `package.json`, the seam of `export.ts:57` is
`exportOrders()` and `export.test.ts` already tests it, `CODING_STANDARDS.md`
exists, no screen, `docs/export.md:12` shows the old date format. Steps 1 and 2 become slice 1 (`Change` at
`export.ts:57`, copy `export.ts:49`) with the test from step 3, `Then`
the ISO date from the issue, and `Docs: docs/export.md:12`, the ISO
date. No probe: the Steps leave no doubt. Two Proof rows: row 1 the case, row 2 the
`pnpm test export` command. No walks, no videos. Gates: the existing
`export.test.ts` cases. Decided: none, the issue had no `Open` line.
Done rule holds. Present, `ok`, `Ready for /handoff.`

**User:** `/plan-up https://github.com/acme/tally/issues/12` (size/S fix,
a CLI; Done when: `status` wraps its hints on a narrow terminal, `rules
list` prints each id whole)

Round 1: both commands print through `format.ts:219`, and
`status.test.ts:83` already sets a fake width. A person reads both lines
in a terminal, so both are on a screen: `UI: terminal`, `Screen: 60 x
24`, `Open: tally status`. Each row gets its test at width 60 and a
walk: `Setup` a 60-column terminal, `Steps` run the command, `See` the
wrapped hint, the whole id. Both screens exist on the base, so each
walk's `Before` names the same command and the old output: the hint
cut at column 60, the id cut short. Plan: two slices, two walks, one
video.
Done rule holds. Present, `ok`, `Ready for /handoff.`

**User:** `/plan-up https://github.com/acme/shop/issues/61` (body has What
to build, no Done when)

Gate fails on "Done means". One block: the question that closes it, and
`/grill` named. Stop.

**User:** `/plan-up https://github.com/acme/shop/issues/70 #71 #73 #74`
(epic "teams"; #71 Team entity M, #73 add member S, #74 invite S; #73
and #74 blocked by #71)

Base copy of `origin/main`. Edges hold: #71 first, #73 and #74 after it. Gates
pass. Round 1 fans out per ticket. #71's plan decides the seam
`teams/service.ts` `createTeam()`. #73's Seams block points at it as
`layer 1, slice 1`, since the file does not exist yet. One big fork on
#74 (invite token lifetime is not in the repo), asked, answered. Plan:
Stack block with three layers, one Facts block, 7 points, then Proof
through Out of scope for each layer. Done rule holds. Present, `ok`,
`Ready for /handoff.`

**User:** `/plan-up https://github.com/acme/shop/issues/70` (same epic; #72
is closed)

Bare epic URL. Sub-issues that are open: #71, #73, #74. Parent body
lists them in that order. Say `Run: #71, #73, #74`, then continue as the
run above.

**User:** `/plan-up https://github.com/acme/shop/issues/75 on https://github.com/acme/shop/pull/80`
(#75 team switcher, S; PR 80 is the top of the open stack)

Base is PR 80's head branch; the base copy is of that branch. One layer, base named
in the Stack block as `PR #80`. Rest as a single ticket. Present, `ok`,
`Ready for /handoff.`
