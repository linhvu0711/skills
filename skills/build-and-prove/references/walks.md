# Step 6: Proof rounds

Step 6 of SKILL.md. Paths start at the skill folder. `CLIENT`, `AGENT`,
and `PROOF` are the ones SKILL.md holds.

Rounds, at most three. Each sends one note to the Proof agent, fetches
its files, and sorts what failed. The Gates and the perf measure are not
the agent's: `references/checks.md` runs them in the same round. A setup fault (SKILL.md § Proof agent)
runs the same round again and does not count as a round.

## 6a. Send

Write the round's note to
`$HOME/.agents/artifacts/plan/proof-note-<slug>-<r>.md`, one line per
field, only the fields this round needs:

```
# Round <r>
Branch: <branch> at <short SHA of HEAD>
Check secrets: <names>
Before: walks <w>, <w>
Videos: <n>, <n>
Install: <tool>
```

- `Check secrets`: round 1, when run 1 ended with `MISSING SECRETS`.
- `Before`: the walks whose `Before` line names steps and that have no
  `before-<walk>.png` in `PROOF`, as when run 1 ended on a setup fault
  or a missing secret. The agent takes them on the base, before it
  checks out the branch.
- `Videos`: round 1, every video; a later round or a rerun, only the
  videos 6c names to film again.
- `Install`: a setup fault, the tool and how to install it when you
  know, as in `Install: ffmpeg (apt-get install -y ffmpeg)`.

Send it, then wait for the run to end:

```bash
bash "$CLIENT" say "$AGENT" <note-path>
bash "$CLIENT" wait "$AGENT"
```

`409 agent_busy` on `say`: the run before it still goes. `wait` for
that run, whose line is not this round's and is not sorted here, then
`say` again, then the `wait` above for the note's run. In Claude Code
run `wait` in the background; the tool wakes you when it ends. Sort the
line `wait` printed:
- `error`, `cancelled`, or `expired`: SKILL.md § Proof agent.
- The last message is `MISSING SECRETS: <names>`: the names were not
  added, or a running agent cannot see them. Show them with `Add them to
  this repo's environment on cursor.com (Cloud Agents, Secrets), then
  run /build-and-prove again: a new agent gets them.`, `down`, and stop.
- `SETUP FAULT: <tool> not found`: a setup fault; the same round again
  with `Install: <tool>`.
- `BRANCH NOT FOUND: …`: the push did not land. Push again (SKILL.md
  step 5) and send the same note once more. A second one: `down`, stop.
- Else 6b.

## 6b. Fetch

```bash
bash "$CLIENT" artifacts "$AGENT"
```

It prints `<path>\t<bytes>`, one line per file. The files this round
expects: `walk-report-after-<r>.md`
and `videos.txt` when it filmed, each `video-<n>.mp4` it filmed, each
`after-<walk>.png` or `short-<walk>.png` of their walks, each
`fail-<walk>.png` the report names, and each `before-<walk>.png` with
its `walk-report-before-<run>.md` from run 1 or a `Before` line. For
each listed path whose file name is one of them:

```bash
bash "$CLIENT" download "$AGENT" <path> "$PROOF/<file name>"
```

**Empty.** An expected file the list lacks, or a download that stops:
send one note that names that walk's video under `Videos`, with a
first line `<file> did not reach the artifacts folder; film it again
and save it there.`, then wait and fetch again (6a, 6b). Once per file
per run. Still missing: that walk fails, and its line in
`walk-report-after-<r>.md` becomes `walk <w>: FAIL · missing <file>`.
A missing walk report: the same note once, then `down` and stop with
`Proof agent sent no <file>`.

**Report.** The walk report must end with its `WALKS` lines, or
`BEFORE` lines. It does not: send a note once with § Report of
`references/proof-agent.md` pasted whole. A second miss: `down`, then
stop with `Proof report unreadable`.

## 6c. Sort

Every walk passed and `references/checks.md` says the checks are done:
SKILL.md step 7. Each failed
walk, by its screenshot and the plan, never by the agent's guess:
- **Setup fault**: the screen shows the agent's machine, not the app,
  is wrong: `command not found` for a tool the walk or the `Open` line
  uses, a window the `Open` line starts never shows, or a mark drawn
  as other bytes (`â` where the app prints `✔`). The same round again
  with `Install:`, not counted (SKILL.md § Proof agent); the other
  failed walks wait for that round.
- **App bug**: the steps reached the screen the walk names, and
  `See` is not there or a `Must not` is. A follow-up to the
  builder per `render.sh local prompt` § Follow-up: `# Changed`
  names the walk, what it saw, and the screenshot's path; `#
  Check` names the tests to run again. The pane gets it with
  `herdr-send`; as the builder, you do it yourself. Then push
  (SKILL.md step 5), and the next round runs the checks again
  (`references/checks.md`).
- **Wrong walk**: a label, route, or step the plan named is not on
  the screen, and the Done-when line still holds there. A change
  to a failed walk's `See` or `Must not`, or to a number in them
  such as a time limit, or to the step its video's `Shows` names,
  the proof frame, is a Wrong walk fix too, never a pass: it gets a
  `Decided` line with the reason, in this shape:
  `- W<w> <See|Must not|Shows> changed after round <r>: "<old>" → "<new>". <the reason>`.
  The walk counts as
  passed only when a later round's video shows it pass. Sort it
  by the two tests in `../plan-up/SKILL.md` step 5. Small fork:
  fix the walk in the plan `.md`, add a `Decided` line, and say so
  in one line. Big fork, such as a walk whose fix changes what a
  Done-when line means: one question to the user, your pick first.
  Wait.
- **Missing file**: 6b's Empty rule already sent it once; it stays
  failed, and the report names the file.

A failed before shot is sorted the same way, and its `before-<walk>.png`
is deleted from `PROOF`, so no failed shot reaches the PR; a wrong
`Before` line is fixed in the plan and named under `Before` in the next
note.

Say `Proof round <r>: <p> passed, <f> failed`. Then the next round from
6a, which films only the videos that need it. A video is filmed again,
whole, when one of its walks failed, or when
`git -C "$WT" diff --name-only <its SHA> HEAD`, with its SHA from
its line in `videos.txt`, names a file that a walk of it shows:
a file a slice behind the walk's Proof rows changes, or a file you
read and find on that walk's screen. Not sure, or the video has no
line in the list: film it again. The note holds only those videos;
every other video keeps its `video-<n>.mp4`, its `after-<walk>.png`
files, and its passes. A rerun (SKILL.md § Rerun) sorts the videos in
`PROOF` the same way. After round three with a failed walk: `down`,
then stop with the failing videos' paths, one per line.
