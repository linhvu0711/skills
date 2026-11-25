# Plan: #80 Team invites
Date: 2026-11-25

## Stack
| Layer | Issue | Base | Size | Points |
|---|---|---|---|---|
| 1 | #80 Team roles | main | M | 4 |
| 2 | #81 Invites | layer 1 | M | 4 |
| 3 | #82 Audit log | layer 2 | S | 2 |
Points: 10 (XS 1, S 2, M 4, L 8)

## Review
Change:   members with no role and no invites → roles, invites, and an audit log
Approach: add roles to the team table, then invites through their own service, then the audit log
Blast radius:
  Touches:    Web, API
  Dependency: none
  Schema:     teams.role column, audit table
  API:        invite commands
  Config:     none
  CI:         none
Risks:
  - none
In: roles, invites, audit
Out: billing, O1

## Change map · Teams
| Ref | Part | Job | Change | Group | Kind | At | Grid | Layer |
|---|---|---|---|---|---|---|---|---|
| M1 | Members page | lists members | same | Web | part | `src/web/members.tsx:5` | 0,0 | |
| M2 | Invite form | sends an invite | new | Web | part | L2 S1 | 0,1 | L2 |
| M3 | Team service | owns teams and roles | changed | API | part | `src/teams.ts:10` | 1,0 | L1 |
| M4 | Invite service | makes and checks invites | new | API | part | L2 S2 | 1,1 | L2 |
| M5 | Teams table | + role column | changed | | store | `src/db/teams.ts:4` | 3,0 | L1 |
| M6 | Mailer | sends mail | same | | outside | | 3,1 | |
| M7 | Audit log | who changed what | new | | store | L3 S2 | 2,2 | L3 |
Flows:
- M1 → M5: reads members (new, L1)
- M2 → M4: invite (new, L2)
- M2 → M6: invite mail (new, L2)
- M3 → M5: writes role (changed, L1)
- M4 → M5: adds member (new, L2)
- M3 → M7: role change (new, L3)
- M4 → M7: invite used (new, L3)

## Facts
Repo: acme/shop        Base: main
Test: pnpm test        Typecheck: none    Lint: pnpm lint    Build: none
Run: pnpm dev          UI: web
Open: http://localhost:3000/teams
Screen: 1024 x 768
Platform: linux
Standards: the code

## Layer 1 · #80 Team roles
## Review
Change:   gives each member a role
Choices:
  - none
Works when:
  - #1 a member has a role

## Summary
Adds a role to each member. Slice 1 writes the role through the team service. 1 done-when, 1 slice.

## Proof
| # | Done-when line | Test (file, case) | UI walk | Video | Artifact |
|---|---|---|---|---|---|
| 1 | a member has a role | `src/teams.test.ts` "keeps a member's role" | none | none | test |

## Seams
- team command: `src/teams.ts:10`, the public command

## Slices
Slice 1, proves #1: team command
  Change: `src/teams.ts:10`, writes the member's role.
  Test `src/teams.test.ts` "keeps a member's role"
    Given: a team with one member
    When: set the member's role to admin
    Then: the member's role is admin
    Mutate: `src/teams.ts:12`, drop the role from the write

## Gates
Slice done: its test green.
Task done: full suite green, lint green.

## Out of scope
- O1 billing

## File changes
| File | Change | Slices | Note |
|---|---|---|---|
| `src/teams.ts` | edited | S1 | writes the role |
| `src/teams.test.ts` | edited | S1 | keeps a role |

## Layer 2 · #81 Invites
## Review
Change:   invites a person to a team by mail
Choices:
  - none
Works when:
  - #1 an invite adds a member

## Summary
Adds invites. Slice 1 sends an invite from the form and adds the member when it is used. 1 done-when, 1 slice.

## Proof
| # | Done-when line | Test (file, case) | UI walk | Video | Artifact |
|---|---|---|---|---|---|
| 1 | an invite adds a member | `src/invites.test.ts` "adds the invited member" | none | none | test |

## Seams
- invite command: `src/invites.ts:3`, the public command

## Slices
Slice 1, proves #1: invite command
  Change: `src/invites.ts:3`, makes, mails, and checks an invite.
  Test `src/invites.test.ts` "adds the invited member"
    Given: an invite for Bo
    When: use the invite
    Then: Bo is a member
    Red:    the invite is used and no member is added

## Gates
Slice done: its test green.
Task done: full suite green, lint green.

## Out of scope
- O1 invites that expire

## File changes
| File | Change | Slices | Note |
|---|---|---|---|
| `src/invites.ts` | new | S1 | the invite service |
| `src/invites.test.ts` | new | S1 | adds the invited member |

## Layer 3 · #82 Audit log
## Review
Change:   records who changed a role or used an invite
Choices:
  - none
Works when:
  - #1 a role change is in the log

## Summary
Adds the audit log. Slice 1 deletes the old change notes; slice 2 writes each change to the log. 1 done-when, 2 slices.

## Proof
| # | Done-when line | Test (file, case) | UI walk | Video | Artifact |
|---|---|---|---|---|---|
| 1 | a role change is in the log | `src/audit.test.ts` "logs a role change" | none | none | test |

## Seams
- audit command: `src/audit.ts:1`, the public command

## Slices
Slice 1, deletes dead code: audit
  Change: `src/notes.ts:1`, delete `changeNotes`. No caller: `rg -n changeNotes` hits only its definition.
  Test `src/teams.test.ts` "keeps a member's role"
    Given: the base
    When: `pnpm test teams`
    Then: pass, before and after the delete

Slice 2, proves #1: audit command
  Change: `src/audit.ts:1`, writes each role change to the log.
  Test `src/audit.test.ts` "logs a role change"
    Given: a team with one member
    When: set the member's role to admin
    Then: the log holds one line, the member's role set to admin

## Gates
Slice done: its test green.
Task done: full suite green, lint green.

## Out of scope
- O1 reading the log in the app

## File changes
| File | Change | Slices | Note |
|---|---|---|---|
| `src/notes.ts` | deleted | S1 | old change notes |
| `src/audit.ts` | new | S2 | the audit log |
| `src/audit.test.ts` | new | S2 | logs a role change |
