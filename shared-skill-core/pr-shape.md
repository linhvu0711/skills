<!-- template: the PR shape, one source. make-pr reads it, grill through make-pr; render.sh pastes it into the handoff rules under ## The pull request. Keep it free of executor blocks and of links to other files: the include pastes it raw. Edit here only. -->
Every pull request has this shape: a branch, a title, a body, a label.

### Branch

`type/<issue>-<words>`, as in `feat/42-undo-delete`. With no issue,
`type/<words>`, as in `refactor/rename-create-pr`. `type` is a commit
type: `feat`, `fix`, `test`, `refactor`, `chore`, `docs`, `perf`, `ci`,
or `build`. Two to four words that name the change. Lower case, words
joined by `-`, no spaces, no other punctuation.

### Title

The shape of a commit summary, `type(scope): summary`, naming the whole
change, as in `feat(todos): undo delete, clear done, due badges`.
Imperative, lower case, no period, 72 characters at most. A change that
breaks a caller, a config, or a deploy puts `!` before the colon, as in
`feat(cli)!: rename --out to --output`, and its body has
`## Breaking changes`.

### Body

The body is for a reader who never saw the plan or the chat. Plan words
such as `slice 2`, `walk 1`, or `step 3` mean nothing to them, so the
body names behavior, tests, and what is on screen.

The parts, in this order. `Summary`, `Where to look`, and `Proof` are
always there. Every other part is there only when it has something to
say; with nothing to say, the heading goes too.

1. **The issue line**, first line of the body. `Closes #<n>` when the
   PR finishes the issue. `Refs #<n>` when it is part of the issue and
   another PR finishes it. No issue: no line.
2. **`## Summary`**: what the change does, why, and how to try it, in a
   few plain sentences.
3. **`## Where to look`**: how hard the change is to undo, then where
   the reviewer spends their time.

   First line, always: `Risk: <door> door, blast radius: <what>.`
   - A **two-way door** is undone by reverting the PR. A **one-way
     door** is not: it writes stored data in a new shape, deletes data,
     sends something out (an email, a webhook, a published package), or
     removes something callers use. A one-way door names what cannot
     come back, in brackets after `door`.
   - The **blast radius** is what breaks if the change is wrong, in a
     few words: one screen, one command, every caller of an API, all
     stored orders.
   - Judge from the issue, the plan, and the diff, not the diff alone. A
     big fork the plan settled is the first place to look. In doubt,
     call it one-way.

   ```markdown
   Risk: two-way door, blast radius: the CSV export only.
   Risk: one-way door (the migration rewrites every order date), blast radius: all stored orders.
   ```

   Then one to three bullets that point:
   - the core change, as `file:line`;
   - what they can skim: wiring, renames, moved code, generated files;
   - a choice they may question, with its reason: a decision made
     during the work, or a surprise that changed what the code does
     (the code was not what the plan or the issue said, and the change
     went another way).

   The diff already lists the files; the bullets point. A PR whose diff
   is one place that the Summary already names keeps only the `Risk`
   line.
4. **`## Breaking changes`**: what else must happen for the change to
   work. Who it breaks and what they do now; a migration to run; an env
   var or a config to set; the order to deploy in. Undo steps only when
   a revert of the PR does not undo it, as with a data migration. This
   part and the `!` in the title go together: one is there exactly when
   the other is.
5. **`## Proof`**: the evidence that the change does what it says.
   - The issue or the plan has Done-when lines: one table, one row per
     Done-when line, in order. Columns: `#`, `Behavior`, `Test`.
     `Behavior` is the Done-when line verbatim. `Test` is the case name,
     linked to the test on the branch; or the command and its output in
     a fenced block, run on the head commit; or the URL of the CI run on
     the head commit. The words `see the Actions run` with no URL are
     not proof.
   - No Done-when lines: a list of the checks that ran on the head
     commit. Each item is the command, the short SHA, and the result,
     or a test the PR added or changed, linked. The list holds only
     checks that ran.
   - The plan has UI walks: the Proof table has two more columns after `Test`: `Screenshot` and
     `Video`. `Screenshot` holds no image: it names the screenshot below
     that shows the line holding, as `Screenshot n`. Two lines one screenshot shows both name it. A
     line with no screen leaves the cell empty. `Video` is the plan's
     `video n @ step m` for the line, copied from the Proof table; a line
     with no screen leaves it empty.

     ```markdown
     ## Proof

     | # | Behavior | Test | Screenshot | Video |
     |---|---|---|---|---|
     | 1 | Clicking `Add` puts a row in the list with the title and the due date. | [`src/todos.test.ts` "adds a todo"](link to the test case on the branch) | Screenshot 1 | video 1 @ step 4 |
     | 2 | Rows are sorted by due date. | [`src/todos.test.ts` "sorts by due date"](link) | Screenshot 1 | video 1 @ step 4 |
     | 3 | The `Due` field opens a date picker on today's month. | [`src/todos.test.ts` "opens the date picker"](link) | Screenshot 2 | video 1 @ step 6 |
     | 4 | `npm test` passes in CI. | [Actions run](URL of the run on the head commit) | | |
     ```

     The screenshots go after the table, under `### Screenshots`, numbered
     in the order the table first names them, one block per walk. A block
     opens with `**Screenshot n.**` and one or two plain sentences on what
     is on screen. A walk with a before shot says what changed, then shows
     the two side by side in a two-column table; a walk with none shows its
     one image on its own line. A walk whose `Before` says `as walk n`
     shows its one image too, after a line `Before: as in Screenshot m.`,
     where m is the block of walk n. Each image is in the body once.

     ```markdown
     ### Screenshots

     **Screenshot 1.** Before, rows kept the order they were added in. After, they are sorted by due date: `Sooner 2099-01-01`, `Soon 2099-12-30`, `Later`.

     | Before | After |
     |---|---|
     | ![](./before-1.png) | ![](./after-1.png) |

     **Screenshot 2.** The `Due` field opens a date picker on today's month.

     ![](./after-2.png)
     ```

     A `Screenshot` cell that names no block, or a walk whose `Before`
     line names steps and whose block has no before image, is a gap.

     The videos go after the table, under `### Videos`, in plan order, one
     block each: one line in plain words, `Video n:` then what it shows,
     then an empty line, then `![video-n](./video-n.mp4)` alone on its own
     line with an empty line after it. That image form is what `--attach`
     rewrites to the upload URL; it is not what GitHub plays. GitHub shows
     a player only when the bare `https://github.com/user-attachments/…`
     URL is the whole paragraph: no `![…](…)` around it, no caption on the
     same line. So after the attach step below, read the body back and
     unwrap every video line, then write the body once more:

     ```bash
     gh pr view <n> --json body -q .body \
       | sed -E 's#^!\[video-[0-9]+\]\((https://github\.com/user-attachments/assets/[^)]+)\)$#\1#' \
       > pr-body.md
     gh pr edit <n> --body-file pr-body.md
     ```

     Then open the PR and check that each video shows a player, not a
     broken image. Every video of the plan has a block; a `Video` cell
     that names a video with no block is a gap.
   - How the media gets in. `gh` uploads it: every `--attach <file>` on
     `gh pr edit` (or `gh pr create`, `gh pr comment`) uploads that file
     to GitHub and rewrites the `./<file>` reference in the body to the
     uploaded asset's URL, a `github.com/user-attachments` link that never
     expires. An image then shows inline and a video plays in a player,
     and only people with access to the repo can see them. Keep
     `pr-body.md` next to the media files. Then, from that directory:

     ```bash
     gh pr edit <n> --body-file pr-body.md --attach before-1.png --attach after-1.png --attach video-1.mp4 …
     ```

     One `--attach` per file the body references, up to 50 per command.
     A file the body does not reference is appended to the end, so attach
     only what the body names. Limits: an image up to 10 MB; a video up to
     10 MB on a free plan, 100 MB on a paid one; PNG, JPEG, GIF, WebP,
     SVG, MP4, MOV, WebM. A WebM recording (Playwright records WebM)
     becomes MP4 first:
     `ffmpeg -i in.webm -c:v libx264 -pix_fmt yuv420p -movflags +faststart
     video-n.mp4`. A walk done again is a new upload: edit the body file
     and run the command again with the new files. Never commit the media
     to the repo.

   ```markdown
   ## Proof

   | # | Behavior | Test |
   |---|---|---|
   | 1 | `uninstall` removes the launch agent and says so. | [`apps/cli/src/uninstall.test.ts` "removes the launch agent"](link to the test case on the branch) |
   | 2 | `bun test` passes. | `bun test` on `9e18c16`: `116 pass, 0 fail` |
   ```

   ```markdown
   ## Proof

   - `scripts/check.sh` on `9e18c16`: `check: clean`
   - `bun test` on `9e18c16`: `116 pass, 0 fail`
   - Added [`src/export.test.ts` "writes ISO dates"](link to the test case on the branch)
   ```
6. **`## Follow-ups`**: every issue filed during the work or the
   review, one line each, `#<n>: <what it is>`. Each line is an issue
   that exists. When an issue is filed after the PR opens, this part is
   updated then.

Write the body to a file kept out of every commit, and pass it with
`--body-file`.
`gh pr edit --body-file` replaces the whole body, so write the file
whole each time.

### Label

One size label: size the PR's own diff against its base with the size
table, and put on the repo's label for that size. A repo with no size
labels gets none, and no label is created.

### A repo's own PR template

A repo with a PR template (`.github/pull_request_template.md`, or a
file under `.github/PULL_REQUEST_TEMPLATE/`) keeps its structure. Each
part above goes under the template heading that matches it best; a part
with no match goes at the end under its own heading. A template heading
with nothing to say is left out. A checkbox stays, ticked only when it
is true. The branch, the title, and the label follow this shape as
written.
