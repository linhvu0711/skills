# Step 9: Walks

Step 9 of SKILL.md. Step 7 uses 9a to 9c too. Paths start at the skill folder.

Rounds, at most three:

## 9a. Start the app

You start it; the walker never does:

```bash
bash scripts/box.sh start "$PROOF" --url <url> -- '<Run line>'
```

`--url` only when the `Open` line is a URL. `start` runs the app and
every process it starts in one process group, so the stop reaches
them all. It prints `TREE=base` or `TREE=branch`, the tree the app
runs, then waits up to 120 s for the URL to answer.

It does not answer: `start` prints the app log's last 50 lines,
stops the app, then prints its `stop:` line. A missing tool or package is the setup
script's: fix it, `box.sh down`, then step 6 again. A crash in the
code is the builder's: a follow-up (step 9c). Still down after that:
`box.sh down`, then stop with the log's last line.

**Stop the app.** The only stop in this skill:

```bash
bash scripts/box.sh stop "$PROOF" --url <url>
```

`--url` only when the `Open` line is a URL. `stop` ends the app's
process group, waiting up to 30 s before it kills it, then waits up
to 30 s until the URL no longer answers, so the port is free for the
next start. Its `stop: <url> still answers after the app stopped`: a
process outside the group holds the port; `box.sh down`, then stop
with that line.

A walk's `Setup` that sets the clock is how the app opens for that
walk; the run never waits for the real clock to reach a time.

## 9b. Walker

In Claude Code, the skill agent `walker`
(`agents/walker.md`, which sets its model and effort; not found:
`../../shared/facts.md` § Skill agents); in Codex, no sub-agent, so
you read `agents/walker.md` and follow it yourself, reading no code
while you walk. Its brief, whole:
- the mode, `before` or `after`, and the round;
- the Sandbox id (`BOX_ID` in `$PROOF/box.env`), the OS, and the
  screen size (1440x900 on linux, 1280x800 on macos);
- the full path of `scripts/box.sh`, this skill's real folder in front
  of it, for the walker's `box.sh open`, `box.sh fit`, and `box.sh
  close`;
- how to open the app: the `Open` line, as a command it runs with
  `box.sh open`. A browser opens on a new, empty profile for each
  video: Chromium with `--no-sandbox --user-data-dir=$(mktemp -d)`,
  or a browser that Playwright launches, which starts empty. So no
  history from the Sandbox image shows in the address bar.
  `--no-sandbox` is there because Chromium's own sandbox cannot
  start in a proofbox Sandbox: without it Chromium stops with `No
  usable sandbox!`;
- the plan's `UI walks` and `Videos` blocks, verbatim, as text
  pasted in the brief itself. Never a `$(cat <file>)` line or a path
  in their place, since
  the Agent tool runs no shell, so the walker gets that line, not the file.
  In mode after, a later round or a follow-up gets only the videos 9c
  films again and their walks, so the walker never overwrites a kept
  video. Mode before gets the walks step 7 names. A round run again
  after `GONE`, in either mode, gets the same videos or walks as the
  round it repeats, so a shot the dead round left unchecked is taken
  again;
- the folder to write in, `PROOF`;
- the pace rules, so the walker cannot drop them: every click
  `--settle 3s`; a state under about 3 s shot by its action's own
  `--screenshot` with `--settle 300ms`;
  a timed run as one mark, one `proofbox exec` that holds every timed
  action as an `/opt/proofbox/pixel` line, and one look, then an empty
  mark for each further step of the run, so mark numbers stay step
  numbers (`agents/walker.md` § How you see and act).

It does not get the code, the slices, or the diff. It returns
one line per walk and writes `walk-report-<mode>-<round>.md` in
`PROOF`: `walk-report-before-<round>.md` or
`walk-report-after-<round>.md`, so neither overwrites the other.
Its reply must end with its `WALKS` lines, its `BEFORE` lines, or
`GONE <id>`. It does not: send it back once with § Report of
`agents/walker.md` pasted whole (in Claude Code, a message to the
same walker). A second miss: `box.sh down`, then stop with
`Walker report unreadable`.
It ended with `GONE <id>`: the app died with its Sandbox, so stop
nothing and go to 9c. Else stop the app (9a, Stop the app). Read `/tmp/app.log` for each walk's `Must not`
that the screen cannot show (console errors, failed requests):
one found is a failed walk.

**Video check.** After mode, when the walker did not end with
`GONE`, before the sort: for each video under the plan's `Videos`,
the `video-<n>.mp4` this round filmed; a video the walker reported as
`proofbox made no video` has no file, so it has no sheet and no
`videos.txt` line. Find its cuts on a
strip sheet, then look only at the frames next to each cut. In a temp
folder outside `PROOF`, take two frames a second, then tile the
bottom sixth of each, where proofbox draws the `» <N> s later`
label, 80 to a sheet:

```bash
ffmpeg -v error -i "$PROOF/video-<n>.mp4" -vf fps=2 <tmp>/f-%03d.png
ffmpeg -v error -i <tmp>/f-%03d.png -vf "crop=iw:ih/6:0:ih*5/6,scale=480:-1,tile=4x20" <tmp>/s-%02d.png
```

Read every sheet. Tiles run left to right, then top to bottom, so
tile `t` of sheet `s` is frame `f-<80*(s-1)+t>`. A run of tiles
that show a `» <N> s later` label is one cut. For each cut, Read
two full frames: the last one before its first label tile, and the
first one after its last label tile. A video whose sheets show no
label has no cut and hides nothing; Read no frame of it. The caption
at the top of a frame names the step (`step <k>: …`). Each step's action must show: typed letters
appearing, the pointer reaching what it clicks, the screen
changing after a key. A step whose action falls in a cut, as when
the frame before a `» <N> s later` label shows none or part of the
typed text and the frame after shows all of it, hides its action.
Only a cut hides an action: a quick click or key that falls
between two frames, in a step with no `» <N> s later` label, is
not hidden. That fails the walk the step belongs to, the one whose `Shows`
step is the first at or after it: write its line in
`walk-report-after-<round>.md` as `walk <w>: FAIL · video <n>
hides step <k> (<action>)`, as in `walk 1: FAIL · video 1 hides
step 1 (typing)`, and lower the passed count in its `WALKS` line.
Remove the temp folder. Then, for each video this round filmed,
write its line in `$PROOF/videos.txt`, in place of an older one:
`video-<n>.mp4 · <short SHA>`, the head the app ran.

## 9c. Sort

The walker ended with `GONE <id>`: the Sandbox died
under it, idle or at its max life. No walk failed; run the round
again from 9a, where `box.sh run` makes a new Sandbox, and it does
not count as a round. A second `GONE` in the same round: `box.sh
down`, then stop with that line. Every walk passed: step 10. Each
failed walk whose line says `proofbox made no video` is **No video**,
read from that line, whatever its screenshot shows: the walker took
that shot after the recording, when a short `See` such as a toast is
gone. Each other failed walk, by its screenshot and the plan, never
by the walker's guess:
- **Sandbox fault**: the screen shows the Sandbox, not the app, is
  wrong: `command not found` for a tool the walk or the `Open` line
  uses, a window the `Open` line starts never shows, or a mark
  drawn as other bytes (`â` where the app prints `✔`). Check a tool
  with `box.sh run "$PROOF" -- sh -c 'command -v <tool>'`; exit 1
  is a Sandbox fault. Fix the setup script (step 4), run `box.sh
  down`, start again from step 6, and walk the round again. Like
  `GONE`, it does not count as a round, and the other failed walks
  wait for that round. After three Sandbox faults in one run:
  `box.sh down`, then stop with the last one.
- **App bug**: the steps reached the screen the walk names, and
  `See` is not there or a `Must not` is. A follow-up to the
  builder per `render.sh local prompt` § Follow-up: `# Changed`
  names the walk, what it saw, and the screenshot's path; `#
  Check` names the tests to run again. As the builder, you do it
  yourself. Then the Gates again (step 8).
- **Video cut**: the video check found a hidden step. Not the
  builder's and not the plan's: no follow-up, no plan change; the
  next round films the video again.
- **No video**: the walker reported `proofbox made no video`, after
  its one try more. proofbox's screen check misses a small change,
  such as a toggle (linhvu0711/proofbox#229). Not the builder's and
  not the plan's: no follow-up, no plan change; the next round films
  the video again. It counts as a round, so a video refused in every
  round ends at round three like any failed walk.
- **Wrong walk**: a label, route, or step the plan named is not on
  the screen, and the Done-when line still holds there. A walk that
  failed with `page taller than the screen` is a Wrong walk too: its
  `Setup` or the `Open` line goes to `--viewport-size=1440,795` at
  laptop size or `--viewport-size=390,664` at phone size. A change
  to a failed walk's `See` or `Must not`, or to a number in them
  such as a time limit, or to the step its video's `Shows` names,
  the proof frame, is a Wrong walk fix too, never a pass: it gets a
  `Decided` line with the reason, in this shape:
  `- W<w> <See|Must not|Shows|Setup> changed after round <r>: "<old>" → "<new>". <the reason>`.
  The walk counts as
  passed only when a later round's video shows it pass. Sort it
  as `../plan-up/SKILL.md` step 5 sorts a fork. Small fork:
  fix the walk in the plan `.md`, add a `Decided` line, and say so
  in one line. Big fork, such as a walk whose fix changes what a
  Done-when line means: one question to the user, your pick first.
  Wait.

Say `Walks round <r>: <p> passed, <f> failed`. Then the next round
from 9a, which films only the videos that need it. A video is
filmed again, whole, when one of its walks failed, when it has
no line in `videos.txt`, or when a hunk of
`git -C "$WT" diff <its SHA> HEAD`, its SHA from that line, changes
what one of its walks does or shows. Read only the hunks in a file
a walk of it shows: a file a slice behind the walk's Proof rows
changes, or a file you read and find on that walk's screen. Such a
hunk changes the walk when a step of the walk's `Setup` or `Steps`
runs its code, or when a screen the walk reaches shows what it
draws. A changed binary file, which `git diff` prints with no hunk,
counts the same when a screen the walk reaches loads it, as with an
image or a font. A hunk on a path the walk never takes keeps the video: an
error the walk never meets, a limit it never reaches, a mode it
never opens. For example, a fix to the save form's message for a
full list keeps a video that saves into a list with room. Then say
one line, `Videos: film 1, 3 · keep 2 (<why>)`, the reason for each
kept video in a few words, a part with no video left out. The
walker's brief holds only the videos it films and their walks (9b);
every other video keeps its `video-<n>.mp4`, its `after-<walk>.png`
files, and its passes. A follow-up (SKILL.md § Follow-up) sorts the
videos in `PROOF` the same way.
After round three with a failed walk: `box.sh down`, then stop with
the failing videos' paths, one per line.
