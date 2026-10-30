# Step 9: Walks

Step 9 of SKILL.md. Step 7 uses 9a to 9c too. Paths start at the skill folder.

Rounds, at most three:

a. **Start the app.** You start it; the walker never does.

   ```bash
   bash scripts/box.sh run "$PROOF" -- sh -c '<Run line> >/tmp/app.log 2>&1 & echo $! >/tmp/app.pid'
   ```

   Then wait until it answers, the way the `Open` line reaches it:
   for a URL, `box.sh run "$PROOF" -- sh -c 'for i in $(seq 60); do
   curl -fsS -o /dev/null <url> && exit 0; sleep 2; done; exit 1'`.
   It does not answer: read `box.sh run "$PROOF" -- tail -n 50
   /tmp/app.log`. A missing tool or package is the setup script's:
   fix it, `box.sh down`, then step 6 again. A crash in the code is
   the builder's: a follow-up (step 9c). Still down after that:
   `box.sh down`, then stop with the log's last line.

b. **Walker.** In Claude Code, the `walker` agent
   (`agents/walker.md`, linked into `~/.claude/agents/`), started with
   `model: sonnet` and `effort: high` on the Agent call, so no default
   model or effort changes them; in Codex,
   no sub-agent, so you read `agents/walker.md` and follow it
   yourself, reading no code while you walk. Its brief, whole:
   - the mode, `before` or `after`, and the round;
   - the Sandbox id (`BOX_ID` in `$PROOF/box.env`), the OS, and the
     screen size (1440x900 on linux, 1280x800 on macos);
   - how to open the app: the `Open` line, as a command it runs with
     `proofbox exec`;
   - the plan's `UI walks` and `Videos` blocks, verbatim;
   - the folder to write in, `PROOF`.

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
   nothing and go to 9c. Else stop the app: `box.sh run "$PROOF" --
   sh -c 'kill $(cat /tmp/app.pid)'`. Read `/tmp/app.log` for each walk's `Must not`
   that the screen cannot show (console errors, failed requests):
   one found is a failed walk.

   **Video check.** After mode, when the walker did not end with
   `GONE`, before the sort: for each video under the plan's `Videos`,
   the `video-<n>.mp4` this round filmed, find its cuts on a
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
   Remove the temp folder.

c. **Sort.** The walker ended with `GONE <id>`: the Sandbox died
   under it, idle or at its max life. No walk failed; run the round
   again from 9a, where `box.sh run` makes a new Sandbox, and it does
   not count as a round. A second `GONE` in the same round: `box.sh
   down`, then stop with that line. Every walk passed: step 10. Each
   failed walk, by its screenshot and the plan, never by the walker's
   guess:
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
     Check` names the tests to run again. The pane gets it with
     `herdr-send`; as the builder, you do it yourself. Then the
     Gates again (step 8).
   - **Video cut**: the video check found a hidden step. Not the
     builder's and not the plan's: no follow-up, no plan change; the
     next round films the video again.
   - **Wrong walk**: a label, route, or step the plan named is not on
     the screen, and the Done-when line still holds there. A change
     to a failed walk's `See` or `Must not`, or to a number in them
     such as a time limit, is a Wrong walk fix too, never a pass: it
     gets a `Decided` line with the reason, and the walk counts as
     passed only when a later round's video shows it pass. Sort it
     by the two tests in `../plan-up/SKILL.md` step 5. Small fork:
     fix the walk in the plan `.md`, add a `Decided` line, and say so
     in one line. Big fork, such as a walk whose fix changes what a
     Done-when line means: one question to the user, your pick first.
     Wait.

   Say `Walks round <r>: <p> passed, <f> failed`. Then the next round
   from 9a; every walk again, from the start. After round three with
   a failed walk: `box.sh down`, then stop with the failing videos'
   paths, one per line.
