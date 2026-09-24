---
name: capture
description: "Capture a raw idea or a noticed bug as a lightweight GitHub issue so it is not lost, without diagnosing, planning, or typing it. The issue is a seed (an idea that may grow into work or be dropped) or a bug (a thing seen broken, not yet defined as a fix). Works in any repo. Priority (p0 to p3) is optional: when the user gives one it becomes a label, otherwise none. Use when the user invokes '$capture' in Codex or '/capture' in Claude Code followed by the thing, or says things like 'capture this', 'park this', 'seed this', 'log this bug', 'track this for later', 'note this as an issue', 'just log it, no plan'. Do NOT trigger for 'create an issue', 'write a fix ticket', 'open a feature request', or any request that wants a proper, triaged issue with a real type; those go through /to-issue."
---

# capture

Write one small GitHub issue that holds a raw thing. Two kinds:

- a **seed**: an idea. A feature, a refactor, a cleanup, anything that
  could be done. Nobody has decided to do it. It may be dropped.
- a **bug**: a thing seen broken. Behaviour that is wrong today. Nobody
  has decided how it must behave after a fix; that is what `/to-issue`
  writes when it turns the bug into a `fix` ticket.

Both are raw. Neither is a real, typed ticket. `[bug]` is not `[fix]`.

The whole point is speed and low noise. Get in, file it, get out.

## Hard rules

- **Seed or bug, nothing else.** Never classify as one of the real
  types (`feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `chore`,
  `spike`, `task`, the nine in
  `../../shared-skill-core/issue-rules.md` § Types) or as
  `improve` or any other word. Those words mean "decided". A seed and a
  bug are not decided. A bug becomes a `fix` ticket only through
  `/to-issue`, once the behaviour after the fix is written down.
- **The kind comes from the words.** It is a bug when the text says
  something behaves wrong today: `bug:`, "broken", "wrong", "crashes",
  "fails", "shows X but should Y", a stack trace, a review finding that
  is true. Anything else is a seed. Not sure: seed.
- **Priority is optional.** If the user states one of p0, p1, p2, p3, it
  becomes the priority label. If they did not, file the seed with no priority
  label. Do not ask for it, and never guess it.
- **No diagnosis. No plan.** Do not root-cause, estimate, propose an approach,
  or write acceptance criteria.
- **No digging.** Do not read code or run searches to "understand it better".
  Use only what is already in the conversation.
- **One question allowed, at most.** "Which repo?" when it cannot be
  determined. Nothing else. Never ask about priority.
- **Learn the repo convention once.** It is saved per repo. Do not re-read old
  issues on a repo that already has a saved entry.
- **Labels:** the kind's label, `seed` or `bug`, plus one priority
  label only when the user gave a priority. Only ever create `seed`,
  `bug`, or a `p<N>` when the repo lacks it. A repo's own `seed`, `bug`,
  or `p1`, any case, is used as it is. Never any other label.
- **No assignee, no milestone, no project board.**
- **Never edit or close existing issues.**

## Steps

### 1. Find the repo

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

If this fails, use the repo the conversation is clearly about. If still
unknown, ask the user which `owner/repo`.

If `gh` is not authenticated, stop and tell the user to run `gh auth login`.

### 2. Get the priority (optional)

Read the user's words onto one level:

| User says                                   | Level |
|---------------------------------------------|-------|
| p0, P0, urgent, critical, blocker, asap     | p0    |
| p1, high, soon, important                   | p1    |
| p2, medium, normal                          | p2    |
| p3, low, someday, nice to have, whenever    | p3    |

If none of that is present, there is no priority. Do not ask and do not
stop: continue, and file it with the kind's label only.

### 3. Load or learn the repo convention

```bash
CONV="$HOME/.agents/skills/capture/scripts/conventions.py"
python3 "$CONV" get owner/repo
```

**Hit** (exit 0, prints JSON with `prefix`, `seed_label`, `bug_label`, and
`priority.p0..p3` when the repo has priority labels): use those values and go
to step 4. Do not run the learning commands. The bug prefix is the seed
prefix with the word swapped: `[seed] ` gives `[bug] `, `seed: ` gives
`bug: `.

The priority labels live in a general, tool-agnostic store
(`~/.config/gh-issues/priority-labels.json`), separate from the seed naming, so
any issue tool can reuse them. The seed `prefix` and `seed_label` live in the
capture store (`~/.config/capture/conventions.json`). This script reads and
writes both; you do not touch the files directly.

**Miss** (prints `MISS`, exit 3), or the user said `--relearn` / "relearn":
learn it now, once.

```bash
python3 "$CONV" forget owner/repo   # only for --relearn
gh issue list --state all --limit 30 --json title -q '.[].title'
gh label list --limit 200 --json name -q '.[].name'
```

Prefix shape from the titles:

| Most titles look like          | Use          |
|--------------------------------|--------------|
| `[BUG] …`, `[FEAT] …`          | `[seed] …`   |
| `bug: …`, `feat(scope): …`     | `seed: …`    |
| No clear pattern, or no issues | `[seed] …`   |

The word is always `seed` (or `bug` for a bug), lowercase, like the type
words in the repo. Only the wrapping follows the repo.

Seed label: the repo's `seed`, any case. Bug label: the repo's `bug`, any
case. If the repo lacks one, it gets created in step 6.

Priority label names, from what the repo already has:

| Repo labels look like                        | Use                          |
|----------------------------------------------|------------------------------|
| `p0`, `p1` … or `P0`, `P1` …                 | that exact name              |
| `priority/p0`, `priority: P1`, `prio-p2` …   | same style, each level       |
| `priority: high`, `priority-low` … (words)   | p0 -> critical if present, else high; p1 -> high; p2 -> medium; p3 -> low |
| No priority labels at all                    | `p0`, `p1`, `p2`, `p3` (created on demand) |

Save it:

```bash
python3 "$CONV" set owner/repo --prefix "[seed] " --seed-label seed --bug-label bug \
  --p0 p0 --p1 p1 --p2 p2 --p3 p3 --sampled <number of titles seen>
```

Save only when at least 5 titles were seen. With fewer, use the defaults
above for this run and do not save, so the repo gets learned again once it
has real history.

### 4. Quick duplicate check

One search, 2 or 3 keywords from the idea:

```bash
gh issue list --state open --search "<keywords>" --limit 10 --json number,title,url
```

If one of the results is clearly the same thing, show it to the user and stop.
Do not create a second one. If nothing matches, continue.

### 5. Write the title and body

The title is the kind's prefix plus a short noun phrase, under 70
characters, no trailing period. Examples: `[seed] Cache user avatars on the
profile page`, `[bug] Nightly job skips rows with null email`. The priority
goes in the label, not the title.

Write the body to a temp file and pass it with `--body-file`. Keep it short.
Three sections at most. A seed:

```markdown
## Seed
One to three sentences in the user's own words. What the thing is.

## Context
Only facts already in the conversation: file paths as `path/to/file:42`,
an error line verbatim, a branch or PR ref. Drop this section if there
is nothing concrete.

## Status
Seed only. Not triaged, not planned. May be dropped.
```

A bug:

```markdown
## Bug
Seen: one to three sentences in the user's own words. What happens.
Expected: one sentence. What should happen instead, when the user said
it; drop the line when they did not.

## Context
Same as a seed: only facts already in the conversation.

## Status
Bug only. Not triaged, not planned. Becomes a `fix` ticket through
/to-issue once the behaviour after the fix is written.
```

Do not add steps, approach, root cause, acceptance criteria, estimates,
or open questions. If the user gave more detail than fits, keep it in
`## Seed` or `## Bug` as plain prose. Do not expand it.

### 6. Create the issue

```bash
f=$(mktemp) && cat > "$f" <<'EOF'
<body>
EOF
gh issue create --title "<title>" --body-file "$f" --label "<seed_label or bug_label>" --label "<priority_label>"
# When the user gave no priority, drop the second --label and create with
# the kind's label alone.
```

Use `--repo owner/repo` if the current directory is not the target repo.

**If `gh` fails because a label does not exist**, handle it once, then retry
once:

- The missing label is `seed`, `bug`, or a lowercase `p<N>`: create it
  and retry.

  ```bash
  gh label create "seed" --color C5DEF5 --description "Captured idea. Not triaged. May be dropped."
  gh label create "bug"  --color 8250DF --description "Seen broken. Not triaged. Becomes a fix ticket through to-issue."
  gh label create "p1"   --color D93F0B --description "Priority 1"
  ```

  Colors: `p0` `B60205`, `p1` `D93F0B`, `p2` `FBCA04`, `p3` `FEF2C0`, a
  heat ramp. These names and colors are owned by
  `../../shared-skill-core/issue-rules.md` § Labels and
  § Repo convention; change them there first.

- The missing label is anything else (the repo renamed or deleted it): the
  saved convention is stale. Run `forget`, redo step 3, retry.

If the retry also fails, show the error and stop.

### 7. Report

Copy the URL to the clipboard when `pbcopy` exists, then say one line:

```bash
command -v pbcopy >/dev/null && printf "%s" "<url>" | pbcopy
```

> Captured: <url> (on your clipboard)

No `pbcopy` (a headless host): `Captured: <url>`.

Nothing else. No summary of the body, no next steps.

## Edge cases, handled

- **Store file missing or corrupt.** Either store is treated as empty; a
  corrupt file is moved aside to `<name>.bak-<time>` and the get returns `MISS`. Just
  learn again.
- **Label renamed or deleted in the repo.** Step 6 catches the create error,
  forgets the entry, learns again, retries once.
- **Repo renamed or moved.** `gh repo view` returns the new name, which is a
  miss. It gets learned under the new name. The old entry is harmless.
- **Repo had no history when first seen.** Nothing was saved (under 5
  titles), so it gets learned properly later.
- **User wants a fresh read.** `--relearn` or the word "relearn" in the
  request forces step 3 to run again.
- **Saved entry has no `bug_label`.** It was learned before bugs existed
  here. Use `bug` for this run; `set` again with `--bug-label` when the
  repo's own label differs.

## Examples

**User:** `$capture p2: ...` in Codex or `/capture p2: ...` in Claude Code, followed by `the settings page re-fetches the whole user object on every tab switch`.

Title: `[seed] Settings page re-fetches user object on every tab switch`.
Labels: `seed`, `p2`. Body `## Seed`: their sentence. `## Context`: only if a
file path was already named in the chat. Done.

**User:** "park this: we could let users export their data as CSV"

No priority given. Do not ask. File it with the `seed` label only.
Title: `[seed] Export user data as CSV`. Labels: `seed`.

**User:** "capture this, urgent: the nightly job silently skips rows with a null email"

"Silently skips" is behaviour that is wrong today: a bug. Title:
`[bug] Nightly job skips rows with null email`. Labels: `bug` and the
repo's p0 label (`p0`, `priority/p0`, or `priority: critical`, whichever the
saved convention says). Body `## Bug`: `Seen:` their sentence; no
`Expected:` line, they did not say.

**User:** `/capture bug: the post modal shows ready while a media file is missing; the server rejects the publish`

Title: `[bug] Post modal shows ready while a media file is missing`.
Labels: `bug`. Body `## Bug`: `Seen:` the modal shows ready while a media
file is missing; `Expected:` the server rejects the publish, so the modal
should not say ready. `## Context`: the file path only if the chat named
one.

**User:** "write the fix ticket for the login bug"

Not this skill. That asks for a real, typed issue: a `fix` through
`/to-issue`, which writes what the behaviour must be after the fix. A
`[bug]` that already exists is its origin; `/to-issue` closes it.
