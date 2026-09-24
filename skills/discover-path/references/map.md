# The map

Formats, labels, titles, and commands for `discover-path`. The flow is in
`SKILL.md`.

## Labels

Five labels, one group, one pink ramp. Match a label by its name,
case-insensitive: a repo that already has `discovery/map` keeps it. Create
only the missing ones.

```bash
gh label create "discovery/map"        --color 880E4F --description "Parent of open questions. Not an epic: nothing here is decided yet"
gh label create "discovery/grill"      --color C2185B --description "Settled by talking it through with the user"
gh label create "discovery/research"   --color E91E63 --description "A fact outside the repo blocks a decision; an agent reads and reports"
gh label create "discovery/experiment" --color F06292 --description "Only trying it answers it: a mock, a diagram, a call to a service"
gh label create "discovery/task"       --color F8BBD0 --description "Manual work that unblocks a decision. Never a slice of the build"
```

`issue-rules.md` § Labels forbids type labels; this group is its one
exception, owned by this skill. No size label, no priority label on a map
or its tickets.

## Titles

`<prefix><text>`, under 70 characters, no trailing period. The prefix is the
type word in the repo's title style. The prefix and the label agree.

**Learn the style once per run**, before the first `gh issue create`. It is
the same rule `to-issue` uses (`to-issue/references/issue-rules.md` § Repo
convention): most existing titles look like `[bug] …` gives `bracket`;
`bug: …` or `feat(scope): …` gives `colon`; no titles, or no pattern, gives
`bracket`.

```bash
gh issue list --state all --limit 30 --json title -q '.[].title'
```

Then define the helper every create command below uses. Pick one line:

```bash
t() { printf '[%s] %s' "$1" "$2"; }   # bracket
t() { printf '%s: %s' "$1" "$2"; }    # colon
```

A title is never typed by hand: `t grill "Which plan model?"`. Count the
characters of the result; over 70, shorten the text, never the prefix.

| Issue | `t` call | Bracket result |
|---|---|---|
| Map | `t discovery "team billing"` | `[discovery] team billing` |
| Grill | `t grill "Which plan model: per seat or per team?"` | `[grill] Which plan model: per seat or per team?` |
| Research | `t research "Does Stripe support per-seat proration?"` | `[research] Does Stripe support per-seat proration?` |
| Experiment | `t experiment "How does the invoice page look with teams?"` | `[experiment] How does the invoice page look with teams?` |
| Task | `t task "Get a Stripe test account for the team"` | `[task] Get a Stripe test account for the team` |
| Revisit | `t grill "Which plan model? (revisit)"` | `[grill] Which plan model? (revisit)` |

A question ends with `?`. A task does not. A second revisit gets
`(revisit 2)`. In chat and on the map a ticket is its title with the link
inside, prefix included: `[[grill] Which plan model?](url)`. On the map body,
a bare `#n` also works: GitHub renders the current title, so it never goes
stale.

## Map body

The whole map at low resolution. Open tickets are not listed here: they are
the open children, found by query.

```markdown
## Destination
What reaching the end of this map looks like: the spec, decision, or change
this effort is finding its way to. One or two lines.

## Notes
The domain in a line. Standing preferences for this effort. Skills every run
should consult. Never an instruction to build.

## Decisions so far
- [[grill] Which plan model?](url): per seat, billed monthly, proration on.

## Not yet specified
- The fog: a question you can feel coming but cannot phrase sharply yet. One
  line each, as loose or as full as the view allows.

## Out of scope
- Work ruled past the destination, one line each: the gist, why it is out,
  and the closed ticket's link when one existed.
```

Decisions so far is an index. A decision lives on its ticket; the map gists
it and links. A patch of fog that becomes a ticket leaves Not yet specified
the same moment. Out of scope never graduates.

## Ticket body

```markdown
## Question
The decision or investigation this ticket resolves. Two to six sentences,
enough for a fresh session to work it cold.

## Context
- Part of #<map>
- Rests on: <names of closed tickets this question builds on, with links>
- Files: `path/to/file:42`, when the question touches code.
```

A task ticket says `## Job` instead of `## Question`, and lists the steps.

## Resolution comment

Posted on the ticket, then the ticket is closed.

```markdown
## Answer
The decision, in one to three sentences.

## Why
The options weighed and the reason for the pick. Terms that landed in
`CONTEXT.md`. An ADR, when one was written: `docs/adr/NNNN-slug.md`.

## Known
- One proven fact per line with its proof, per `issue-rules.md` § Known.
  (experiment and task only; drop when none)

## Links
- The research note, the mock, the diagram. Drop when none.
```

## Proposal format (chat, before anything exists)

```
## [discovery] <effort>   (in the repo's title style)

Destination: <one or two lines>

### Tickets
1. **[grill] <question>?** · blocked by: none
2. **[research] <question>?** · blocked by: none
3. **[experiment] <question>?** · blocked by: 1, 2

### Not yet specified
- <fog line>

### Out of scope
- <line>
```

Numbers are positions in this list until issues exist. Free tickets first.

## Commands

Repo: `gh repo view --json nameWithOwner -q .nameWithOwner`. Add
`--repo owner/repo` to every command when the current directory is not the
target.

**Create the map**

```bash
f=$(mktemp) && cat > "$f" <<'B'
<map body>
B
gh issue create --title "$(t discovery "<effort>")" --body-file "$f" --label "discovery/map"
```

**Create a ticket** (numbers from earlier calls feed later ones)

```bash
gh issue create --title "$(t grill "<question>?")" --body-file "$f" \
  --label "discovery/grill" --parent <P> [--blocked-by <n1>,<n2>]
```

**List the children**

```bash
gh issue view <P> --json subIssues -q '.subIssues.nodes[] | "\(.number)\t\(.title)"'
gh issue view <n> --json state,assignees,title
```

**Open blockers of one ticket** (the live gate; counts open blockers only)

```bash
gh api repos/<owner>/<repo>/issues/<n> --jq '.issue_dependencies_summary.blocked_by'
```

**Frontier**: the children that are open, have `0` open blockers, and no
assignee. First in map order wins. Map order is the order the tickets were
created, which is the proposal order.

**Claim**: `gh issue edit <n> --add-assignee @me`

**Resolve**

```bash
gh issue comment <n> --body-file "$f"
gh issue close <n>
```

**Edit the map body** (re-read, change one thing, write once)

```bash
f=$(mktemp) && gh issue view <P> --json body -q .body > "$f"
# append or change one line
gh issue edit <P> --body-file "$f"
```

**Add a blocker to an existing ticket** (revisit flow)

```bash
id=$(gh api repos/<owner>/<repo>/issues/<blocker> --jq .id)
gh api --method POST repos/<owner>/<repo>/issues/<blocked>/dependencies/blocked_by -F issue_id="$id"
```

The `issue_id` is the blocker's numeric database id, not its `#number`.

## Fallback

When `--parent` or `--blocked-by` fails because the repo's plan lacks them:

- Child: `Part of #<map>` stays as the first Context line (it is there
  anyway) and the map body gets a `## Tickets` task list with one line per
  child.
- Blocking: a `Blocked by: #n, #n` line right under the Question heading.
  A ticket is unblocked when every issue on that line is closed.
- Frontier: read the task list, then each child's `Blocked by` line.
