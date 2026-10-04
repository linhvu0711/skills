# Plan: #71 Team membership
Date: 2026-10-04

## Stack
| Layer | Issue | Base | Size | Points |
|---|---|---|---|---|
| 1 | #71 Team entity | main | M | 4 |
| 2 | #73 Add a member | layer 1 | S | 2 |
Points: 6 (XS 1, S 2, M 4, L 8)

## Review
Change:   no teams → teams and members
Approach: add the team route, then its membership route
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
| M1 | Team entity | a team can be created | new | | part | `src/teams.ts:10` | 0,0 | L1 |
| M2 | Add a member | a member can join a team | new | | part | `src/members.ts:10` | 1,0 | L2 |
Flows:
- M1 → M2: team id (new, L2)

## Facts
Repo: acme/shop        Base: main
Test: pnpm test        Typecheck: none    Lint: pnpm lint    Build: none
Run: pnpm dev          UI: web
Open: http://localhost:3000/teams
Screen: 1024 x 768
Platform: linux
Standards: the code

## Layer 1 · #71 Team entity
## Review
Change:   adds the team entity
Choices:
  - none
Works when:
  - #1 a team can be created

## Summary
Adds the team entity. Slice 1 creates a team through the route. 1 done-when, 1 slice.

## Proof
| # | Done-when line | Test (file, case) | UI walk | Video | Artifact |
|---|---|---|---|---|---|
| 1 | a team can be created | `src/teams.test.ts` "creates a team" | none | none | test |

## Seams
- team command: `src/teams.ts:10`, the public command

## Slices
Slice 1, proves #1: team command
  Change: `src/teams.ts:10`, adds the team entity.
  Test `src/teams.test.ts` "creates a team"
    Given: a signed-in user
    When: run the command
    Then: a team can be created

## Gates
Slice done: its test green.
Task done: full suite green, lint green.

## Out of scope
- O1 invitations

## Layer 2 · #73 Add a member
## Review
Change:   adds a member to a team
Choices:
  - none
Works when:
  - #1 a member can join a team

## Summary
Adds team membership. Slice 1 joins a member through the route. 1 done-when, 1 slice.

## Proof
| # | Done-when line | Test (file, case) | UI walk | Video | Artifact |
|---|---|---|---|---|---|
| 1 | a member can join a team | `src/members.test.ts` "joins a team" | none | none | test |

## Seams
- team command: `src/members.ts:10`, the public command

## Slices
Slice 1, proves #1: team command
  Change: `src/members.ts:10`, adds a member to a team.
  Test `src/members.test.ts` "joins a team"
    Given: a signed-in user
    When: run the command
    Then: a member can join a team

## Gates
Slice done: its test green.
Task done: full suite green, lint green.

## Out of scope
- O1 roles
