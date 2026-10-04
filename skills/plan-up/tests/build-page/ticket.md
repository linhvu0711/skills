# Plan: #42 [feat] Export orders as CSV
Size: size/M    Date: 2026-10-04

## Review
Change:   orders export as JSON only → as JSON or CSV
Approach: stream CSV through the existing export route, not a second route
Blast radius:
  Touches:    Web, API
  Dependency: csv-stringify, D2
  Schema:     none
  API:        export accepts CSV
  Config:     none
  CI:         none
Choices:
  - Fork: stream or buffer → stream (user)
  - D2: delimiter is `,`. Risk: a different delimiter breaks imports
Risks:
  - notes may contain newlines. If wrong: rows split. Proved: P1
Works when:
  - #1 orders export as CSV
  - #2 an empty export has a header
In:  CSV beside JSON
Out: PDF, O1

## Change map
| Ref | Part | Job | Change | Group | Kind | At | Grid |
|---|---|---|---|---|---|---|---|
| M1 | Orders page | asks for an export | same | Web | part | `src/web/orders.tsx:12` | 0,1 |
| M2 | Export | JSON or CSV | changed | API | part | `src/orders/export.ts:31` | 1,1 |
| M3 | Orders store | order rows | same | | store | `src/db/orders.ts:4` | 2,1 |
Flows:
- M1 → M2: asks for CSV (new)
- M2 → M3: streams orders (changed)

## Facts
Repo: acme/shop        Base: main
Test: pnpm test        Typecheck: pnpm typecheck    Lint: pnpm lint    Build: pnpm build
Run: pnpm dev          UI: web
Open: http://localhost:3000/orders
Screen: 1024 x 768
Platform: linux
Standards: the code

## Proved
- P1 csv-stringify keeps a note with a newline whole: streamed three rows in a temp folder, 2026-10-04. Used by S1.

## Summary
Adds CSV next to JSON in the orders export. Slice 1 runs the CSV path end to end; slice 2 adds the empty export. 2 done-when, 2 slices, 1 walk, 1 video.

## Proof
| # | Done-when line | Test (file, case) | UI walk | Video | Artifact |
|---|---|---|---|---|---|
| 1 | orders export as CSV | `src/orders/export.test.ts` "exports csv" | walk 1 | video 1 @ step 2 | screenshot 1 |
| 2 | an empty export has a header | `src/orders/export.test.ts` "exports an empty list" | none | none | test |

## Seams
- export route: `src/orders/export.ts:31`, receives the chosen format

## Slices
Slice 1, proves #1: export route
  Change: `src/orders/export.ts:31`, stream CSV beside JSON.
  Docs:   `src/README.md:88`, CSV next to JSON.
  Test `src/orders/export.test.ts` "exports csv"
    Given:  three orders, one note with a newline
    When:   export CSV
    Then:   all three rows with the note whole

Slice 2, proves #2: export route
  Change: `src/orders/export.ts:31`, keep the header with no orders.
  Test `src/orders/export.test.ts` "exports an empty list"
    Given:  no orders
    When:   export CSV
    Then:   the header alone

## UI walks
Walk 1, proves #1
  Setup:    three orders
  Where:    `/orders`
  Steps:    click Export, pick CSV
  See:      three orders in the download
  Must not: a console error
  Before:   none

## Videos
Video 1, Setup of walk 1, shows walks 1
  1. Open `/orders`.
  2. Click Export, pick CSV.
  Shows: #1 at step 2

## Gates
Slice done: its test green, typecheck green.
Task done: full suite green, lint green, build green.

## Decided
- D1 file name: `orders-<date>.csv`
- D2 delimiter: `,` as the spec says

## Out of scope
- O1 orders export as PDF
