# Issue rules

Shared by `to-issue` and `to-epic`. One issue here is a **ticket**: a unit of
work an agent can pick up cold, in a fresh context window, and ship as one PR.
The one exception is a `task`: work a person does cold in a platform outside
the repo, and reports back. Everything below serves those two readers.

## Vocabulary

Titles and bodies use the repo's own words. The glossary is `CONTEXT.md` (or
the `CONTEXT.md` of the bounded context named in `CONTEXT-MAP.md`). Decisions
already made live in `docs/adr/`; a ticket in that area respects them and
names the ADR in Context. When neither file exists, use the names the code
uses.

## Readiness gate

A ticket can be written only when all three hold, from the conversation alone:

1. **Who and what**: the user-visible behaviour is stated. You can say who
   does what and what they see.
2. **Done means**: you can write the done checklist from the user's view.
   For `feat` and `fix` that includes the unhappy paths that change what gets
   built (see Unhappy paths). A missing one that the repo has no pattern for
   and that changes the work is a gap.
3. **Where**: the repo is known (`gh repo view --json nameWithOwner`, or the
   repo the conversation is clearly about).

For a `task`, "what" is the thing that must exist at the end, "done" is the
code ticket being able to use it, and "where" is the platform and account on
top of the repo. Unhappy paths do not apply.

Any one missing: stop. List the gaps in one short block, each as the question
whose answer would close it. Name `/grill` as the way to close many at once,
or `/diagnose` when the ticket is a `fix` or `perf` and the cause is not yet
known. Write nothing on GitHub.

## Types

Nine. The type is the leading word of the title.

| Type | Use when |
|---|---|
| `feat` | New user-visible behaviour |
| `fix` | Expected and actual behaviour differ |
| `docs` | Only prose changes |
| `refactor` | Structure changes, behaviour does not (includes debt and prefactor work) |
| `perf` | Same behaviour, measurably faster or lighter |
| `test` | Coverage only |
| `chore` | Deps, tooling, config, CI, build |
| `spike` | Time-boxed research; the output is a decision, not code |
| `task` | Work a person does in a platform outside the repo: an account, an app, a key, a bucket, DNS, billing. The output is a thing that exists, not a PR |

Security work is `fix` or `feat`. Design or UX work is `spike` until a
behaviour is decided, then `feat`.

A `task` is always human work. Setup an agent can run from a CLI with a token
(`railway init`, `wrangler r2 bucket create`) is a `chore` that lands as a
script. One task per platform and account: Railway and Cloudflare R2 are two
tasks, two logins, two owners.

A ticket is **pure**: all code, or all human work. Walk the Done when list
and ask of each line: can an agent tick it from the repo, with no login of
the user's? A line that needs a person's login, a platform page, or a real
account (set a variable, paste a secret, cut over DNS, log in as the user
and prove it live) leaves the code ticket and becomes its own `task`. Human
work the code needs first is a task that blocks the code ticket. Human work
that comes after the code lands is a task blocked by the code ticket. The
code ticket's Done when then ends on what an agent can prove alone: tests
green, a local build, an image that starts, a doc that names the variables.

`discover-path` has its own `task:` tickets under `discovery/task`; those
live in a map, not an epic, and keep their own rules.

## Title

`<prefix><noun phrase>`, under 70 characters, no trailing period.

- **Style** comes from the repo convention (`style`): `bracket` gives
  `[feat] Export orders as CSV`, `colon` gives `feat: export orders as CSV`.
- **Word** is the type name, unless the convention maps it (`words`, e.g.
  the repo writes `bug:` where we write `fix:`).
- The epic parent uses `epic` in the type slot: `[epic] …` or `epic: …`.

Priority and size never appear in the title. They are labels.

## Size

The ruler is `~/.agents/shared-skill-core/size.md`. Read it. It is one
table, XS to L under the ceiling, shared with the handoff rules that size
the PR, so the ticket's label and the PR's label mean the same thing. Judge
by its facts, not by hours. XL is over the ceiling and never a ticket label.

XL in `to-issue`: stop, state which facts push it over (files, seams,
packages, migrations), and say the work needs `to-epic`. XL in `to-epic`: cut
it further.

A `task` has no size. Size measures code in a window; a task costs wall clock,
and its `Lead time:` line carries that. Skip the table, the lookup for size,
and the XL check.

When the facts are unknown and the chat does not settle them, one read-only
lookup round is allowed (see Lookup). Still unknown after that: pick the larger
size and write the unknown under `Open` in Context.

XS is special. By the time a ticket is XS, the chat plus the one lookup round
already say which lines change and what to copy. So an XS ticket carries a
`Steps` section (see Body) and the `handoff-ready` label. The Steps are
final: `plan-up` trusts them and takes its short path (no repo read for
seams, no forks), and the executor gets a plan built from them. If the
steps cannot be written from what is known, the ticket was never XS. Make
it S, and drop Steps and the label.

S gets Steps only when they are free. Free means every step names a file and
line that the chat or the lookup actually showed, and no step needs a choice
the chat did not make. Then write Steps and add `handoff-ready`, same as XS.
One step that would be a guess: no Steps, no label. Never pad an S ticket
with steps to earn the label. M and L never carry Steps.

## Labels

- **Size**: always one, from the convention's `size` map.
- **Priority**: only when the user named one in this request. Words map as in
  the table below. Never ask for one, never infer one.
- **Handoff**: `handoff-ready`, on every ticket that carries Steps. Always
  XS, sometimes S, never M or L. It says the Steps are final: every
  `file:line` was seen, no choice is open. `plan-up` reads it as "trust
  the Steps" and takes its short path
  (`../skills/plan-up/references/plan.md` § Handoff-ready); the ticket still gets a
  plan before it goes to an executor. Created on first use. Never on a
  `task`, even though a task always carries Steps: the label means code
  steps a plan can be built from.
- **Manual**: `manual`, on every `task` and on nothing else. It is the one
  label a task carries: no size, no handoff. `plan-up` skips tickets that
  carry it, and lists them before planning an epic or a run. Created on first
  use.
- **Type**: no label. The prefix carries the type. Exceptions, both only when
  the repo already has them: pass `--type <Name>` when the repo (an org repo)
  has issue types matching ours; add the repo's existing type label when it
  keeps such labels. Never create a type label. The one group outside this
  rule is `discovery/*`, owned by `discover-path` and made only by it.
- **Plain names**: labels are plain text, no icon. A name in a command or a
  convention (`handoff-ready`, `size/M`) means the repo's existing
  label of that name, matched case folded. Only a label the repo lacks is
  created, from the block below. A repo's labels are used as they are and
  are never renamed. One color per family (the block below) tells families
  apart at a glance; the text tells labels apart inside a family.

| User says | Level |
|---|---|
| p0, urgent, critical, blocker, asap | p0 |
| p1, high, soon, important | p1 |
| p2, medium, normal | p2 |
| p3, low, someday, nice to have | p3 |

## Body

Write it to a temp file, pass it with `--body-file`. Four sections, in this
order. XS adds a fifth, `Steps`, after Done when, and S adds it when the
steps are free (see Size). Every line is from the user's view: what someone
sees, runs, or gets. Without Steps, implementation plans and file-by-file
instructions stay out; the worker owns those. With Steps the ticket owns
them.

```markdown
## What to build
The end-to-end behaviour this ticket makes work. Who does what, and what they
see at the end. Two to six sentences.

## Done when
- [ ] One observable outcome per line. Something you can click, run, query,
      or read. The list is complete: when every box is ticked the ticket is done.
- [ ] For feat and fix: what the user sees on each unhappy path that applies
      (error, empty, slow or loading, bad input, no permission). Same shape
      as the happy lines. A state that does not apply is named under Out in
      Scope.

## Steps
(XS always, S when free. See the Steps rules below.)
1. In `path/to/file:42`, <one concrete change>. Copy the shape of `path/to/other:17`.
2. …
N. Add or update `path/to/test.ts`, case `<name>`. Run `<command>`; it passes.

## Scope
**In:** the behaviour above and only that.
**Out:** the nearby things a worker would reach for, named so they can leave
them alone.
**Noted for later:** (epic sub-issues only) work that belongs to a sibling
ticket, each as `#N owns <thing>. Do not build it here.`

## Context
- Files: `path/to/file:42` for every place the chat or lookup named.
- Terms: glossary words this ticket uses, when a glossary exists.
- ADRs: `docs/adr/NNNN-slug.md`, when one governs this area.
- Related: `Blocked by #N (<why>)`, `Blocks #M (<why>)`, `Part of #P`.
- Known: facts the chat proved by running something, one per line, each
  with its proof (see Known). Drop the line when none.
- Open: facts you could not settle, one per line. Drop the line when none.
```

Type variants:

- `fix`: inside **What to build**, three labelled lines: `Expected:`,
  `Actual:`, `Repro:` (numbered steps or a command).
- `spike`: replace **Done when** with `Question:` (one line), `Time box:`
  (a duration), `Output:` (where the decision is written, usually an ADR or a
  comment on this issue).
- `task`: see Task body below.

Drop a Context bullet that would be empty. Keep the four headings.

### Task body

The reader is a person, in a platform they may not know, doing it cold. The
four headings stay. Inside them:

```markdown
## What to build
What must exist at the end, and which code ticket needs it. Two sentences.
- **Where:** the platform, the account, the page. `developer.x.com, the Perch account, Projects`.
- **Bring:** what to have in hand before you start: a login, 2FA, a card on file.
- **Lead time:** the wait between doing it and being able to use it, or `none`. `about 3 days, X reviews the app`.
- **Hand back:** the names to save when it is done, one per line. Names only; where each value lives is the person's choice.
  - `X_CLIENT_ID`
  - `X_CLIENT_SECRET`. Secret: never paste the value into this issue or a PR.

## Done when
- [ ] The thing exists, as seen in the platform: <what the page shows>.
- [ ] Every Hand back name is saved.
- [ ] The blocked code ticket can use it: <the command or check that proves it>.

## Steps
1. …

## Scope
**In:** the thing above and only that.
**Out:** nearby platform work that is its own task or nobody's.
**Noted for later:** (epic sub-issues only) as for any ticket.

## Context
- Docs: the platform page each step came from, as a URL.
- Related: `Blocks #N (<why>)`, `Part of #P`.
- Known, Open: as for any ticket.
```

Every credential in Hand back carries the warning on its line. The value of
one never appears in an issue, a comment, or a PR.

Steps are always written. They come from the platform's docs, fetched in the
one lookup round with `SEARCH=on` (see Lookup). Each step names the page,
the button or field, and the value to enter. A step with no doc source goes
under Open as the question it leaves, never into Steps. The last step is the
proof: the check that shows the code ticket can use the result.

`Lead time:` is what `to-epic` reads to place the task: a wait of days puts
the task in the first phase, whatever phase needs it.

### Unhappy paths (feat and fix)

A Done when list written by reflex holds only the happy path. The worker then
guesses what the user sees when things go wrong. So for every `feat` and
`fix`, walk five states before the list is done:

| State | Question |
|---|---|
| Error | The action fails. What does the user see? |
| Empty | There is nothing to show. What does the user see? |
| Slow or loading | The action is slow. What does the user see meanwhile? |
| Bad input | The input is wrong. What stops it, and what says so? |
| No permission | The user may not do this. What do they see? |

The states are not screen-only. An API, a job, or a CLI has the same five;
the answers look different: a status code and body, `200` with `[]`, a
timeout or partial result, `400` naming the field, `403`.

Each state that applies becomes one Done when line, as observable as the
happy lines: "Wrong file type shows `Only CSV files` under the field". Each
state that does not apply is named under **Out** in Scope, so the worker
knows it was a choice. Never write "errors are handled" or "edge cases are
covered". Those are not outcomes.

When the chat did not settle a state, in this order:

1. **The repo has a pattern.** Most apps already show errors, empty lists,
   and spinners one way. The lookup round finds it. Copy it and name the
   file: "Error shows the toast from `ErrorToast.tsx:12`". No question.
2. **No pattern, and the choice does not change the work.** Empty-state
   text, a spinner's place. Pick a sane default, write it as the line, and
   add one line under **Open** in Context: "Empty text is a guess." The user
   fixes it in the issue. No round trip.
3. **No pattern, and the choice changes the work.** Retry or roll back, keep
   half the data or none. This is a product decision. The gate fails. Ask.

Ask as one short block, not one question per state. Each line is a state,
your proposed default, and it wants only a yes or a change:

```
Unhappy paths, tell me which are wrong:
- Upload fails: show error, keep nothing. Retry is out.
- File over 10 MB: reject before upload, show the size limit.
- Loading: spinner on the button, page stays usable.
```

"ok" or an edited line closes it. Then write the issue.

### Known (when the chat ran something)

Sometimes the chat already ran the thing: called the vendor's API, sent
the webhook, tried the library against real data. What came back is a
fact the repo does not hold, and the next stage will go looking for it
again unless the ticket carries it. So each fact the chat proved by
running something becomes one **Known** line in Context, with its proof:

- the auth that worked: the kind, and where the credential lives, never
  the value;
- the request and response shape as seen, where it differs from the docs;
- a limit that was hit: rate, size, timeout, page size;
- the script or command that shows it, and the day it ran.

One line, one fact, one proof: "Refunds on ACH come back `status:
pending`, not `succeeded`: `scratch/refund-spike.sh`, 2026-09-08". A
fact the chat only read about is not Known. It stays out, or goes under
Open when it still needs proof.

### Steps (XS always, S when free)

Three to seven numbered steps a worker can follow cold, in order. For S,
every file and line in the steps must have been seen, in the chat or in the
lookup. A line you did not see is a guess, and one guess means no Steps. A
`task` has its own Steps rules under Task body.

- Each step names one file and line, one concrete change, and, when it is not
  obvious, how to see it worked.
- At least one step points at an existing pattern to copy: "like
  `statsController.js:40`". Never describe a shape the code already shows.
- The last step is the test: the file, the case name, the command that runs
  it.
- Concrete words only. Name the route, the field, the label text, the enum
  values. "Nicer", "cleaner", "handle errors properly" are not steps.
- If a step needs a decision the chat did not make: an XS ticket becomes S,
  an S ticket gets no Steps.

Bad:

```
1. Add a user stats endpoint.
2. Make sure it is tested.
```

Good:

```
1. In `src/api/routes.ts:88`, add `GET /users/stats` next to `/orders/stats`.
2. In `src/api/statsController.ts`, add `userStats()` shaped like
   `orderStats()` at line 40: return `{ count, avgSignupAgeDays }` from the
   `users` table.
3. Add case `returns user count and average signup age` to
   `src/api/statsController.test.ts`. Run `pnpm test statsController`; it
   passes.
```

The good one names the route, the response shape, the data source, the file
to copy, and the test. The bad one leaves all of that to the worker. That is
a planning ticket wearing an XS label.

## Lookup

Reach for the code only when the chat leaves a size fact or a Context fact
unknown. One round, read-only. In Claude Code, dispatch Explore agents with
the brief inline; in Codex, use its read tools. Ask for exactly the missing
facts: the seam, the files, the tests that cover them, and the file count
per package whenever the work may touch more than one (a wide refactor, a
`feat` that spans server and web). For `feat` and `fix`, also ask
how the repo already shows errors, empty states, loading, and bad input near
this place, with file and line, so the unhappy-path lines can copy it. When
the ticket looks XS or S, add to the brief: the exact lines that change, the
nearest existing pattern to copy, and the test file and command that cover
the place. Steps are written from those, and only from those. For a `task`,
the round is one Explore agent with `SEARCH=on` against the platform's own
docs: the page for each step, the fields and values, the review or approval
wait, and the check that proves the result works. The round is done when
every fact you listed came back or came back as "not found". No second round.

## Repo convention

Load once per repo:

```bash
CONV="$HOME/.agents/skills/to-issue/scripts/conventions.py"
python3 "$CONV" get owner/repo
```

**Hit**: use it. **Miss**, or the user said "relearn": learn now.

```bash
gh issue list --state all --limit 30 --json title -q '.[].title'
gh label list --limit 200 --json name,description -q '.[] | "\(.name)\t\(.description)"'
```

- `style`: most titles look like `[bug] …` gives `bracket`; `bug: …` or
  `feat(scope): …` gives `colon`; no pattern gives `bracket`.
- `words`: when the repo's titles use a different word for one of our types
  (`bug` for `fix`, `feature` for `feat`), record it.
- `size`: labels that clearly denote size (`size/S`, `Size: Small`,
  `effort-large`, bare `S`), matched case-insensitively across separators
  mapped onto XS, S, M, L. A repo that
  has three sizes but no XS: map XS to its smallest. A repo with none:
  `size/XS`, `size/S`, `size/M`, `size/L`, created on first use. An XL
  label, when the repo has one, is the PR-only label the handoff skills own;
  it stays out of the map.
- Priority: the shared store. `python3 "$HOME/.agents/skills/capture/scripts/conventions.py" priority-get owner/repo`.
  On miss, learn as capture does (exact `p0..p3` names, a `priority/…` or
  `priority: …` family, or words: p0 = critical else high, p1 = high,
  p2 = medium, p3 = low; none = `p0`, `p1`, `p2`, `p3` created
  on demand) and save with `priority-set`.

Save with `set` only when at least 5 titles were seen; otherwise use the
defaults for this run and leave the store empty so the repo is learned later.

Label creation, only for labels this file names and only when `gh` fails on
them:

```bash
gh label create "size/XS" --color BFDADC --description "Fits one place, 1-2 files"
gh label create "size/S"  --color 7FC8CC --description "One thin path, existing seams"
gh label create "size/M"  --color 3FA9B0 --description "Full vertical slice, one window"
gh label create "size/L"  --color 1B7A82 --description "Slice plus new seam or migration; ceiling"
gh label create "handoff-ready" --color 0E8A16 --description "Steps in the body are final; plan-up trusts them and takes its short path"
gh label create "manual" --color 6E7781 --description "Human work in a platform outside the repo; agents skip it"
```

Priority labels: `p0` `B60205`, `p1` `D93F0B`, `p2` `FBCA04`, `p3` `FEF2C0`,
a heat ramp. Seed: `seed` `C5DEF5` and bug: `bug` `8250DF`, both owned by
`capture`.

One hue per family: size teal, priority red to yellow,
handoff-ready green, manual grey, seed light blue, bug purple,
`discovery/*` pink
(`../skills/discover-path/references/map.md`). Never reuse a family hue.

A label the convention names that no longer exists: `forget` the repo, learn
again, retry once.

## Duplicates and seeds

Before creating, one search:

```bash
gh issue list --state open --search "<2 or 3 keywords>" --limit 10 --json number,title,labels,url
```

- A result that is clearly the same work and is **not** a seed: show it and
  stop. Nothing is created.
- A result that is clearly the same work and carries the `seed` or `bug`
  label, or a seed or bug number the conversation named: it is the
  **origin seed** (a `[bug]` grows into a `fix`). Continue, and after the
  create succeeds close it:

  ```bash
  gh issue close <seed> --comment "Grew into #<new>"
  ```

  For an epic, `<new>` is the parent. Only issues labelled `seed` or `bug`
  are ever closed this way.

## Report

```bash
command -v pbcopy >/dev/null && printf "%s" "<url>" | pbcopy
```

The URL is on the clipboard. Say so in one line. No `pbcopy` (a headless
host): print the URL on its own line instead.
