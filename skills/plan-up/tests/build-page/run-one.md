# Plan: #75 Team switcher
Date: 2026-10-04

## Stack
| Layer | Issue | Base | Size | Points |
|---|---|---|---|---|
| 1 | #75 Team switcher | PR #80 | S | 2 |
Points: 2 (XS 1, S 2, M 4, L 8)

## Review
Change:   header has one team → header switches teams
Approach: reuse the header and the active team
Blast radius:
  Touches:    Web, API
  Dependency: none
  Schema:     none
  API:        team commands
  Config:     none
  CI:         none
Risks:
  - none
In: teams
Out: invitations, O1

## Change map · Teams
| Ref | Part | Job | Change | Group | Kind | At | Grid | Layer |
|---|---|---|---|---|---|---|---|---|
| M1 | Team switcher | the header switches teams | new | | part | `src/switcher.ts:10` | 0,0 | L1 |
Flows:


## Facts
Repo: acme/shop        Base: main
Test: pnpm test        Typecheck: none    Lint: pnpm lint    Build: none
Run: pnpm dev          UI: web
Open: http://localhost:3000/teams
Screen: 1024 x 768
Platform: linux
Standards: the code

## Layer 1 · #75 Team switcher
## Review
Change:   adds the team switcher to the header
Choices:
  - none
Works when:
  - #1 the header switches teams

## Summary
Adds the team switcher to the header. Slice 1 switches the active team. 1 done-when, 1 slice.

## Proof
| # | Done-when line | Test (file, case) | UI walk | Video | Artifact |
|---|---|---|---|---|---|
| 1 | the header switches teams | `src/switcher.test.ts` "switches teams" | none | none | test |

## Seams
- team command: `src/switcher.ts:10`, the public command

## Slices
Slice 1, proves #1: team command
  Change: `src/switcher.ts:10`, adds the team switcher to the header.
  Test `src/switcher.test.ts` "switches teams"
    Given: a signed-in user
    When: run the command
    Then: the header switches teams

## Gates
Slice done: its test green.
Task done: full suite green, lint green.

## Out of scope
- O1 team creation
