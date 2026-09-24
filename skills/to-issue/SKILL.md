---
name: to-issue
description: "Turn the current conversation into one typed, sized GitHub issue an agent can pick up cold. No interview."
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`.

Read `../../shared-skill-core/issue-rules.md` first. It holds the gate, types, sizes,
labels, body template, lookup rule, repo convention, duplicate check, and
report. This file is the order of operations.

## Steps

1. **Gate.** Apply the readiness gate to what the conversation already holds.
   Pass: continue. Fail: list the gaps and stop.

2. **Repo convention.** Load it, or learn it once. Done when `style`, `size`
   labels, and (only if the user named a priority) the priority label are
   known.

3. **Type and size.** Pick the type from the table. Size from the facts
   table. When a size fact is unknown, run the one lookup round, then decide.
   When the ticket looks XS or S, the same round also fetches the lines, the
   pattern to copy, and the test, so Steps can be written.
   XL: stop. Say which facts push it over the ceiling and that `to-epic` is
   the tool for it. Nothing is created.
   `task`: no size, no XL check. The lookup round goes to the platform's
   docs instead, per the rules file § Lookup, so Steps can be written.

4. **Duplicate check.** One search. Same work, not a seed: show it, stop.
   Origin seed found: remember its number.

5. **Write.** Title per the title rule. Body per the template, with the type
   variant when it applies. Every Done-when line is observable from outside
   the code. For `feat` and `fix`, walk the five unhappy-path states per the
   rules file: copy the repo's pattern, else default and mark Open, else the
   gate fails and you ask in one block. XS also gets Steps, per the Steps
   rules. S gets Steps only when
   every step comes from a line that was seen and no choice is open. If a
   step needs a decision the chat never made: XS becomes S, and S gets no
   Steps. `task`: body per the rules file § Task body, Steps always. Go on.

6. **Create.**

   ```bash
   gh issue create --repo owner/repo --title "<title>" --body-file "$f" \
     --label "<size label>" [--label "<handoff-ready label>"] [--label "<priority label>"] \
     [--type <Name>]
   ```

   `handoff-ready` goes on every ticket that has Steps, and on no other.
   A `task` is the exception: its only label is `manual`, no size label.

   A missing label from the rules file: create it, retry once. Any other
   failure: show the error, stop.

7. **Close the origin seed**, when there is one.

8. **Report.** URL on the clipboard, one line. Add the size and type in the
   same line, nothing else.

## Examples

**User:** `/to-issue` after a chat that settled how order export should work,
named `src/orders/export.ts:40`, and said "p1".

Title `[feat] Export orders as CSV from the orders page`. Labels `size/M`,
`p1`. Body: What to build in two sentences, six Done-when boxes (four happy,
one for the empty list, one for a failed export copying the toast at
`ErrorToast.tsx:12`), Scope with the PDF export and "no permission" named as
out, Context with the file and the glossary term `Order`. One line back with
the URL.

**User:** `/to-issue` after a chat that found the CSV export writes dates as
epoch numbers, and pinned it to `src/orders/export.ts:57` and the
`formatDate` helper in `src/lib/date.ts:12`.

Size XS: one file, one test. Title `[FIX] CSV export shows dates as epoch
numbers`. Labels `size/XS`, `handoff-ready`. Body has Expected, Actual, Repro,
two Done-when boxes, and three Steps: wrap the value at `export.ts:57` in
`formatDate` like `export.ts:49` already does, add case `formats createdAt
as ISO date` to `export.test.ts`, run `pnpm test export`. One line back with
the URL.

**User:** `/to-issue` after a chat about a login bug, with no repro steps.

Gate fails on "what": the actual behaviour is not stated. Reply lists one gap:
"What does the user see instead of the dashboard? Error text, blank page, or
redirect?" Nothing is created.

**User:** `/to-issue` after a chat that settled that sign-in with X needs
an X developer app, and named the code ticket #5 that will read the
credentials.

Type `task`. Title `task: create the X developer app for sign-in`. Label
`manual`. Lookup with `SEARCH=on` fetches the X developer portal pages: the
Projects page, the OAuth 2.0 settings, the callback URL field, the review
wait. Body: What to build with Where (developer.x.com, the Perch account),
Bring (the X login and 2FA), Lead time (about 3 days, app review), Hand back
(`X_CLIENT_ID`, `X_CLIENT_SECRET` with the secret warning). Three Done-when
boxes, five Steps from the docs, Context with the doc URLs and `Blocks #5`.
One line back with the URL.

**User:** `/to-issue` for "move all services to the new config loader".

Lookup counts 41 files across 6 packages. Size is XL. Reply names the count
and the packages, and says the work needs `to-epic`.
