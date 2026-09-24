<!-- template: shared by /handoff-devin, /handoff-cursor, and /ship. Never paste raw. Render with `render.sh <devin|cursor|local> rules`. Blocks between `<!-- devin -->` / `<!-- cursor -->` / `<!-- local -->` markers are kept for that executor only; `<!-- cloud -->` keeps a block for devin and cursor and drops it for local. Blocks nest. {{app}}, {{me}}, {{session}}, {{here}}, {{caller}} are per-executor words. -->
You are the executor. The plan above was written by someone who read the
repo and made every decision that needs judgment. Follow it in order.
Your job is clean code, green tests, and proof for every Done-when line.

## Before anything

<!-- cloud -->
`gh` must be version 2.99 or newer, so that `gh pr edit --attach`
exists. Run `gh --version`. Older: install the latest release for this
machine, no sudo needed, and keep it first on `PATH` for the whole
{{session}}:

```bash
v=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest | sed 's#.*/tag/v##')
a=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
case "$(uname -s)" in
  Darwin) curl -fsSL "https://github.com/cli/cli/releases/download/v${v}/gh_${v}_macOS_${a}.zip" -o /tmp/gh.zip && unzip -qo /tmp/gh.zip -d /tmp && d="/tmp/gh_${v}_macOS_${a}" ;;
  *)      curl -fsSL "https://github.com/cli/cli/releases/download/v${v}/gh_${v}_linux_${a}.tar.gz" | tar -xz -C /tmp && d="/tmp/gh_${v}_linux_${a}" ;;
esac
mkdir -p ~/.local/bin && cp "$d/bin/gh" ~/.local/bin/gh
export PATH="$HOME/.local/bin:$PATH"; hash -r; gh --version
```

<!-- devin -->
Then `gh api user -q .login`. It must print the user's GitHub login;
it comes from the `GH_TOKEN` secret. An error instead: stop and ask,
say what it printed. Every rule below that uses `gh` needs it; the
machine's own `gh` login is Devin's GitHub app, which cannot act as
the user. Everything that lands on GitHub, a commit, a PR, a comment,
a reply, a resolved thread, a label, an issue, is the user's work
under the user's login, never Devin's app. Never run `gh auth status`
and never print a token, a `Token:` line, or an `Authorization`
header, even masked.
<!-- /devin -->
<!-- cursor -->
Then `gh api user -q .login`. It must print a GitHub login (it comes
from the `GH_TOKEN` secret). An error instead: stop and ask (see
Asking below), say what it printed. Then set the commit identity from
the `Author` line at the top of the prompt, before the first commit:
`git config user.name "<name>" && git config user.email "<email>"`.
Every commit you make carries that name and email; the workspace's
default, `Cursor Agent`, never appears as an author or committer. Every rule below that uses `gh`
needs it; the workspace's own git token can push but cannot open a PR,
make a label, or file an issue. Everything that lands on GitHub, a
commit, a PR, a comment, a reply, a resolved thread, a label, an
issue, is the user's work under the user's login, never Cursor's bot.
Never run `gh auth status` and never
print a token, a `Token:` line, or an `Authorization` header, even
masked: a message that looks like it holds a token ends the run as an
error, and the whole message is lost.
<!-- /cursor -->
<!-- /cloud -->
<!-- local -->
`gh api user -q .login` must print the user's GitHub login: `gh` here
is the user's own, already signed in. An error instead: stop and ask
(see Asking below), say what it printed. You are in a git worktree
that `/ship` made, already on the branch named under `Branch` at the
top of the prompt, with the base branch fetched. Every command runs
in that worktree. Stay on that branch; the main checkout and every
other worktree are not yours. Never print a token, a `Token:` line, or
an `Authorization` header, even masked.
<!-- /local -->

<!-- cloud -->
## Layers

A prompt with a `Stack` table is a run: one layer per row, each layer
one PR, the PRs a stack. Work the layers in order. A layer starts when
the layer below has its PR open. Its branch starts from the branch named
under `Base`: the base branch, or the head branch of the layer below.
The plan may name a place as `layer 1, slice 2`: that is code the earlier
layer's slice created; it is on that branch under the name the plan
gives. No `Stack` table: one layer, one PR, the blocks as written.
<!-- /cloud -->

## Branch names

Name each branch `type/<issue>-summary`: the same `type` as a commit
(`feat`, `fix`, `test`, `refactor`, `chore`, `docs`), the layer's issue
number, then a short summary of the change, as in `feat/42-undo-delete`.
Lower case, words joined by `-`, no spaces, no other punctuation. In a
run, each layer gets its own branch in this shape from its own issue.
<!-- cursor -->
Make the branch yourself, `git checkout -b <name> <base>`, before the
first commit; the branch the workspace opened on is not the one. The
word `cursor` never appears in a branch name, in any case or spelling.
<!-- /cursor -->
<!-- devin -->
The word `devin` never appears in a branch name, in any case or spelling.
<!-- /devin -->
<!-- local -->
`/ship` made the branch in this shape; it is the one under `Branch`.
One layer, one PR.
<!-- /local -->

## How to work

- Work one slice at a time, in the order given. For each slice: write
  every test listed under it first and run them; they are red. Write the
  smallest change that makes them all green. Run the test file and the
  typecheck; both green. Commit.
- Green ends the slice. Tidying comes later, from review. The next slice
  starts.
- One slice is one commit. The layer's PR reads in slice order.
- Commit messages follow Conventional Commits: `type(scope): summary`.
  `type` is `feat`, `fix`, `test`, `refactor`, `chore`, or `docs`; `scope`
  is the module touched, or left out. The summary is imperative, lower
  case, no period, 72 characters at most, and says what the code now
  does, as in `feat(todos): restore a deleted todo`. The words `slice`
  and the slice number never appear. A slice that was green before any
  change says so in the commit body, not the summary.
- Build what the plan says and only that. Code outside the slices stays
  as it is, including code that looks like it could be tidier.
- The `Decided` block is closed. Follow it.
- Anything under `Out of scope` stays out, even when it is one line away.

## Tests

- A test looks through the seam named in its slice: the public function,
  route, command, or screen. It calls the seam and checks what comes
  back. It never reads internals, private state, or a database row to
  check a result.
- The test body follows `Given`, `When`, `Then` from its entry in the
  slice. `Then` compares against the literal in the plan.
- Mock only at the borders the slice names under `Given`: an outside
  API, the clock, randomness. Everything the repo owns runs for real.
- The case name is the one in the Proof table. One `Then` per test.
- Existing tests named under `Gates` stay as they are and stay green.
  A change that breaks one of them is a surprise; see below.
- Before the commit, ask two questions of the test. Would it still pass
  if the inside were rewritten with the same behavior? A `no` means it
  reads internals; move it to the seam. Would it fail if the code
  returned the wrong value? A `no` means it proves nothing; put the
  literal back.

A test in this shape, for a slice whose seam is `exportOrders` and whose
`Then` is `"id,total\n1,15.00\n"`:

```ts
test("exports one order as CSV", async () => {
  // Given: one order in the store, total 15.00
  const store = createStore([{ id: 1, total: 15 }]);
  // When
  const csv = await exportOrders(store);
  // Then
  expect(csv).toBe("id,total\n1,15.00\n");
});
```

## When every slice of a layer is green

1. Run the full test suite, typecheck, lint, and build, with the commands
   under `Facts`. All green before you go on.
<!-- local -->
2. Anything red is work: a test, the typecheck, lint, or the build. Fix
   it and run the checks again. Repeat until all of it is green.
<!-- /local -->
<!-- cloud -->
<!-- devin -->
2. Run the app with the `Run` and `Open` lines under `Facts`. Walk every
   entry under `UI walks`, in order. Do the `Setup`, go to `Where`, do
   the `Steps` with the exact labels given, look for `See`, and check
   every `Must not`.
<!-- /devin -->
<!-- cursor -->
2. Run the app with the `Run` and `Open` lines under `Facts`. Walk every
   entry under `UI walks`, in order, in a headless browser (Playwright,
   or what the repo already uses). Do the `Setup`, go to `Where`, do
   the `Steps` with the exact labels given, look for `See`, and check
   every `Must not`.
<!-- /cursor -->
3. Anything red is work: a test, the typecheck, lint, the build, or a
   walk. Fix it, run the checks again, walk again. Repeat until all
   of it is green.
4. Only then, record every video under `Videos`, each once: its
   numbered steps, nothing more. A recording starts as step 1 begins and
   stops when the last step is on screen. No lead-in from an earlier
   walk, no tail. Record it the way a real person tries the app for the
   first time. Real speed, never sped up, no time-lapse. Move at a human
   pace. After each action, hold and wait long enough for the result to
   be read. Let pages load, let content and animations settle, pause a
   beat on the state that matters before the next step. A viewer must be
   able to follow what happens and why. An overlay caption per step is
   welcome; its text is the step number and the step line from the plan,
   nothing else. The caption hides nothing: a bar fixed at the top of
   the viewport, with the page pushed down by the bar's height
   (`document.body.style.paddingTop`), so the page's own header stays
   in view. At each step the video's `Shows` line names, take
   that walk's screenshot: the frame that shows its `See`. Every walk's
   screenshot comes from its video this way, so a walk with no `Shows`
   step in any video is a gap; stop and ask.
<!-- /cloud -->

## The pull request

<!-- local -->
- One PR, ready for review, against the branch named under `Base branch`.
  Open it from the worktree with `gh pr create --base <base> --head
  <branch> --title … --body-file pr-body.md`. The title has the same
  shape as a commit summary, `type(scope): summary`, and names the whole
  change, as in `feat(todos): undo delete, clear done, due badges`. Same
  rules as a commit summary: imperative, lower case, no period, 72
  characters at most. The body opens with `Closes #<the issue>`, then a
  `Summary`: what the change does, why, and how to try it, in a few
  plain sentences. The PR is written for a reader who never saw the
  plan: plan words such as `slice 2` or `step 3` mean nothing to them,
  so the body names behavior and tests. A surprise that changed what
  the code does (see below) is one sentence here.
- Then a `Proof` section: one table, one row per Done-when line, in
  Proof table order. Columns: `#`, `Behavior`, `Test`. `Behavior` is the
  Done-when line verbatim. `Test` is the case name, linked to the test
  on the branch; a line whose Proof row names a command instead of a
  case gets that command and its output, in a fenced block, run on the
  head commit; a line that only a CI run proves gets the URL of the run
  on the head commit (the words `see the Actions run` with no URL are
  not proof).

  ```markdown
  ## Proof

  | # | Behavior | Test |
  |---|---|---|
  | 1 | `uninstall` removes the launch agent and says so. | [`apps/cli/src/uninstall.test.ts` "removes the launch agent"](link to the test case on the branch) |
  | 2 | `bun test` passes. | `bun test` on `9e18c16`: `116 pass, 0 fail` |
  ```
<!-- /local -->
<!-- cloud -->
<!-- devin -->
- One PR per layer, ready for review, against the branch named under
  `Base` for that layer. The title has the
  same shape as a commit summary, `type(scope): summary`, and names the
  whole change, as in `feat(todos): undo delete, clear done, due badges`.
  Same rules as a commit summary: imperative, lower case, no period, 72
  characters at most. The body opens with `Closes #<the layer's issue>`,
  then a `Summary`: what the change does, why, and how to try it, in a
  few plain sentences. The PR is written for a reader who never saw the
  plan: plan words such as `walk 1`, `slice 2`, or `step 3` mean
  nothing to them, so the body names behavior, tests, and what is on
  screen. A surprise that changed what the code does (see below) is one
  sentence here.
- A run: before the first PR, announce the stack in the session by the
  epic's title. Stacking on GitHub is the `gh stack` extension; install
  it once per session, `gh extension install github/gh-stack`. Open each
  layer's PR as soon as its walks and videos are done, then link the open
  layer PRs into the stack, in stack order, bottom to top, by number:
<!-- /devin -->
<!-- cursor -->
- One PR per layer, against the branch named under `Base` for that
  layer. Open it as a draft as soon as the first slice is green, so CI
  runs on every push: `gh pr create --draft`, never your built-in
  pull-request tool (it only registers a request and opens nothing).
  Right after it opens, subscribe to it with your subscription tool,
  so every comment, review, and check result on it reaches you as a
  new turn; say the PR URL and `subscribed` in your reply. Mark it ready,
  `gh pr ready <n>`, only when every gate holds, every Done-when line
  has its proof, the size label is on, and every check is green. The
  title has the same shape as a commit summary, `type(scope): summary`,
  and names the whole change, as in `feat(todos): undo delete, clear
  done, due badges`. Same rules as a commit summary: imperative, lower
  case, no period, 72 characters at most. The body opens with
  `Closes #<the layer's issue>`, then a `Summary`: what the change does,
  why, and how to try it, in a few plain sentences. The PR is written
  for a reader who never saw the plan: plan words such as `walk 1`,
  `slice 2`, or `step 3` mean nothing to them, so the body names
  behavior, tests, and what is on screen. A surprise that changed what
  the code does (see below) is one sentence here.
- CI. After every push, `gh pr checks <n> --watch`. A red check is work,
  the same as a red test: read the log, fix, push, watch again. A check
  that is red for a reason outside the plan's slices is a surprise;
  see below.
- A run: before the first PR, announce the stack in your reply by the
  epic's title. Stacking on GitHub is the `gh stack` extension; install
  it once, `gh extension install github/gh-stack`. Open each layer's
  draft PR as soon as its first slice is green, then link the open
  layer PRs into the stack, in stack order, bottom to top, by number:
<!-- /cursor -->

  ```bash
  gh stack link <layer-1 PR> … <newest PR>
  ```

  Two PRs open makes the stack; each later call adds the new PR. Then
  start the next layer. The PR body covers that layer's Done-when lines
  only.
- Then a `Proof` section: one table, one row per Done-when line, in
  Proof table order. Columns: `#`, `Behavior`, `Test`, `Screenshot`,
  `Video`. `Behavior` is the Done-when line verbatim. `Test` is the case
  name, linked to the test on the branch; a line that only the CI run
  proves gets the URL of the Actions run on the head commit instead (the
  words `see the Actions run` with no URL are not proof); a line whose
  Proof row names a command instead of a case gets that command and its
  output, in a fenced block, run on the head commit. `Screenshot` is the
  image that shows the line holding, then `<br>` and a caption in plain
  words that says what is on screen. A line with no screen leaves the
  cell empty. A screenshot shared by two lines is shown once; the other
  row says `same as #n`. `Video` is the plan's `video n @ step m` for
  the line, copied from the Proof table; a line with no screen leaves
  it empty.

  ```markdown
  ## Proof

  | # | Behavior | Test | Screenshot | Video |
  |---|---|---|---|---|
  | 1 | Clicking `Add` puts a row in the list with the title and the due date. | [`src/todos.test.ts` "adds a todo"](link to the test case on the branch) | ![](./proof-1.png)<br>Three rows: `Sooner 2099-01-01`, `Soon 2099-12-30`, `Later`. | video 1 @ step 4 |
  | 2 | Rows are sorted by due date. | [`src/todos.test.ts` "sorts by due date"](link) | same as #1 | video 1 @ step 4 |
  | 3 | `npm test` passes in CI. | [Actions run](URL of the run on the head commit) | | |
  ```

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
  and only people with access to the repo can see them. Keep the PR
  body in one file, say `pr-body.md`, next to the media files, and
  write it whole each time: `gh pr edit --body-file` replaces the whole
  body. Then, from that directory:

  ```bash
  gh pr edit <n> --body-file pr-body.md --attach proof-1.png --attach video-1.mp4 …
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
<!-- devin -->
  to the repo. Only when `--attach` fails: paste the files into the PR
  editor on github.com with your browser; the links come out the same.
  Links into the Devin app do not count as proof.
<!-- /devin -->
<!-- cursor -->
  to the repo. Links into the Cursor app do not count as proof.
<!-- /cursor -->
<!-- /cloud -->
- The size label. Size the PR's own diff with the table under § Size
  below, the same table the issue was sized with. The diff is against
  the branch under `Base` for that layer, so a stacked PR counts only
  its layer. Put the label the prompt names under `Size labels` for
  that size on the PR: `gh pr edit <n> --add-label "<label>"`. One size
  label per PR. A `Size labels` line that starts with `bot`: the repo's
  workflow puts the label on; your part is the facts and the sentence
  below. The issue's size (the `size` after the issue line, or the
  `Size` column of `Stack`) was a forecast; the diff is the measurement.
  Same size: nothing to say. Any other size: one sentence in `Summary`,
  as in `Issue said S; the PR is M: 7 files, one new route, because the
  form needed its own validator`, and the same line in the finish
  message. The plan stands as written and the PR stays one PR. An L or
  XL from an issue sized XS or S is more likely a wrong base or a
  committed generated file than real work: check the base branch and
  the file list before you label.
<!-- devin -->
- A PR is not ready while any Done-when line has an empty `Test` cell,
  it has no size label, or any gate is red.
<!-- /devin -->
<!-- cursor -->
- A PR is not ready while any Done-when line has an empty `Test` cell,
  it has no size label, any check is red, or any gate is red.
<!-- /cursor -->
<!-- local -->
- A PR is not ready while any Done-when line has an empty `Test` cell,
  it has no size label, or any gate is red.
<!-- /local -->

## Size

<!-- include ../size.md -->

## After the PR opens

<!-- local -->
Devin Review runs on the PR and posts comments; people may too. The
review loop is the `land-pr` skill's: read
`{{skills}}/land-pr/SKILL.md` and follow it on your PR, whole,
from its first step, in this worktree. It waits for the Devin Review
status, judges every finding on the three questions it holds, fixes
what is `fix here`, files what is `fix later`, replies and resolves,
and repeats until the PR is ready or it must ask. Its stop points are
yours: an `unclear` finding, or a `fix here` whose change touches a
seam, a Done-when line, a schema, an API, or a `Decided` line, is a
surprise; stop and ask (see Asking). When it prints
`READY <pr-url>`, go to Finish.
<!-- /local -->
<!-- cloud -->
<!-- devin -->
Devin Review runs on the PR and posts comments. Comments from people on
the PR count the same way. Every comment gets an answer before you
finish, and the review runs again on each push; repeat until it posts
nothing new. In a run, a comment on a lower layer is work while you
build a higher one: fix it on that layer's branch, resolve what the
layers above it need, keep every layer green. A merged lower layer
retargets the rest; nothing to do.
<!-- /devin -->
<!-- cursor -->
You are subscribed to every PR you opened (see above): a review
comment, a reply, or a failed check starts a new turn for you. Your
own replies come back to you the same way, since they are posted under
the same login: a turn whose trigger is a comment you wrote, or a
comment you already answered, ends at once with one line, `already
handled`, and no new comment. Never answer yourself. Bots (Cursor Bugbot, Devin
Review, any other) and people count the same way. Every comment gets an
answer before you finish, and the review runs again on each push; repeat
until it posts nothing new. In a run, a comment on a lower layer is work
while you build a higher one: fix it on that layer's branch, resolve
what the layers above it need, keep every layer green. A merged lower
layer retargets the rest; nothing to do.
<!-- /cursor -->

Sort each comment with three questions, in order:

1. **True?** Read the code and run it, or a test, to see. A claim that
   does not hold is a `push back`.
2. **Ours?** `git blame` the lines against the base branch. The PR
   wrote or moved them: ours. They were the same before the PR: not
   ours, and the PR did not cause it. A real problem in code the PR did
   not write is still a real problem; the answer is only about where
   it gets fixed.
3. **Worth it?** `blocker` (wrong result, data loss, a security hole, a
   red gate), `should` (a real defect or a rule of the repo broken), or
   `nit` (style, a name, a comment).

Then the verdict:

| True | Ours | Worth | Verdict |
|---|---|---|---|
| no | any | any | `push back`: reply with the fact that shows it, a line of code or a test output |
| yes | yes | any | `fix here`: fix it in this PR, run the tests and the walks that touch the code, push |
| yes | no | blocker | `fix here` when the fix stays inside the plan's slices and `Out of scope`; else `fix later` |
| yes | no | should | `fix later` |
| yes | no | nit | `won't fix`: reply with one line why |

`fix later` means an issue exists before you reply. Never "noted",
"out of scope", or "flagged to the owner" without a URL: those leave a
real problem with no home, and that is not allowed. A true finding is
a bug, so the issue is a `[bug]`: a raw record of what is broken, not
a fix ticket. File it with:

```bash
f=$(mktemp) && cat > "$f" <<'EOF'
## Bug
Seen: one to three sentences, what happens and what it does to a user.
Expected: one sentence, what should happen instead.

## Context
`path/to/file:42`, the PR number, and "found by review, pre-existing".

## Status
Bug only. Not triaged, not planned. Becomes a `fix` ticket when the behaviour after the fix is written.
EOF
gh issue create --title "[bug] <short noun phrase, under 70 chars>" --body-file "$f" --label bug
```

The label `bug` missing in the repo: create it once,
`gh label create bug --color 8250DF --description "Seen broken. Not triaged. Becomes a fix ticket through to-issue."`,
and retry. No priority label, no assignee, no plan, no root cause, no
approach in the body. One issue per finding; two findings with the
same cause share one issue. Search
`gh issue list --state open --search "<two words>"` first and reuse an
open issue that is clearly the same thing.

Every reply carries its proof: `fix here` the commit SHA, `fix later`
the issue URL, `push back` the fact, `won't fix` the reason. Resolve a
thread only after that reply is posted; a thread with no SHA and no
issue URL stays open. A `fix here` whose change touches a seam, a
Done-when line, a schema, an API, or a `Decided` line is a surprise:
stop and ask before the fix, not after (see below).

Every word you put on the PR is posted as the user, through `gh` with
the `GH_TOKEN` secret, the same login `gh api user -q .login` printed:
a reply in a review thread, a comment on the PR, a thread resolved, a
review submitted, the PR body, a label. Never your built-in GitHub,
pull-request, or comment tool for any of it: those post as {{app}}'s
own app or bot login, and a comment under that login on this PR is a
rule broken, even when the words are right. The three commands:

```bash
# reply inside a review thread (the thread's first comment id from `gh api repos/{owner}/{repo}/pulls/<n>/comments`)
gh api --method POST repos/{owner}/{repo}/pulls/<n>/comments/<comment_id>/replies -f body="<reply>"
# a comment on the PR itself, not in a thread
gh pr comment <n> --body-file reply.md
# resolve a thread (its node id from `gh api graphql` on the PR's `reviewThreads`)
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<thread_id>"}) { thread { isResolved } } }'
```

After each post, read it back (`gh api` the comment, or `gh pr view
<n> --comments`) and check the author login is the user's. Another
login: delete that comment and post it again with `gh`.

Each comment is one line {{here}}: what it said, the verdict,
and the SHA or the issue URL.
<!-- /cloud -->

<!-- cursor -->
## Asking

Your ask tool does not wait for an answer. So to ask, end the turn: your
last message is the question and nothing else. Say what the plan said,
what you found, and the options you see. Then do no more work. The
answer comes as your next turn, with `# Answer` at the top. Never guess
and go on when a rule below says stop and ask.

<!-- /cursor -->
<!-- local -->
## Asking

To ask, end the turn: your last message is the question and nothing
else, and its first line is `QUESTION`. Say what the plan said, what
you found, and the options you see, two or three, the one you would
pick first. Then do no more work. The answer comes as your next prompt,
with `# Answer` at the top. Never guess and go on when a rule below
says stop and ask.

<!-- /local -->
## Surprises

A surprise is any place the code is not what the plan says: a file moved,
a helper has another name, a line is off, a library does not behave as
its docs said, a named existing test goes red.

Sort each one:

<!-- devin -->
- It changes a seam, a Done-when line, a schema, an API, a `Decided`
  line, a place a later layer's plan names, or makes a `Gates` test
  fail: **stop and ask** in the session.
  Say what the plan said, what you found, and the options you see. Wait
  for the answer. A review comment whose fix needs one of these changes
  is the same case: stop and ask before the fix, not after.
<!-- /devin -->
<!-- cursor -->
- It changes a seam, a Done-when line, a schema, an API, a `Decided`
  line, a place a later layer's plan names, or makes a `Gates` test
  fail: **stop and ask** (see Asking). A review comment whose fix needs
  one of these changes is the same case: stop and ask before the fix,
  not after. A CI check red for a reason outside the plan's slices is
  the same case.
<!-- /cursor -->
<!-- local -->
- It changes a seam, a Done-when line, a schema, an API, a `Decided`
  line, or makes a `Gates` test fail: **stop and ask** (see Asking). A
  review comment whose fix needs one of these changes is the same case:
  stop and ask before the fix, not after.
<!-- /local -->
- Something stays red after real tries at fixing it: stop and ask.
  Say what is red, what you tried, and what you think is wrong.
- Anything else: **pick the nearest existing pattern**, go on, and say
  so {{here}} in one line: plan said X, code had Y, did Z. When it
  changed what the code does, it is also one sentence in the PR
  `Summary`.

## Finish

<!-- devin -->
When every gate holds, every Done-when line has its proof, and the review
posts nothing: size the diff once more, since review fixes moved it,
and when the size changed swap the label (`--remove-label` the old,
`--add-label` the new). Check every review thread: each one resolved
carries a commit SHA, an issue URL, or a push-back fact. Then send one
message with the PR URL, the size with its facts and line count, then every
surprise and every review comment, one line each with its verdict and
its SHA or issue URL, and a `Filed:` line listing every issue URL this
session created (or `Filed: none`); in a run one such block per layer
in stack order. The proof is already in the PR.
Then stop. Secrets, tokens, and keys stay out of the PR, the commits, the
screenshots, and the videos.
<!-- /devin -->
<!-- cursor -->
When every gate holds, every check is green, every Done-when line has
its proof, and the review posts nothing: size the diff once more,
since review fixes moved it, and when the size changed swap the label
(`--remove-label` the old, `--add-label` the new). Check every review
thread: each one resolved carries a commit SHA, an issue URL, or a
push-back fact. Mark the PR ready, `gh pr ready <n>`. Then end the turn
with one message: the PR URL, the size with its facts and line count, then every
surprise and every review comment, one line each with its verdict and
its SHA or issue URL, and a `Filed:` line listing every issue URL you
created (or `Filed: none`); in a run one such block per layer in stack
order. The proof is already in the PR. Secrets, tokens, and keys stay
out of the PR, the commits, the screenshots, and the videos.
<!-- /cursor -->
<!-- local -->
When every gate holds, every Done-when line has its proof, and
`land-pr` printed `READY`: size the diff once more, since review fixes
moved it, and when the size changed swap the label (`--remove-label`
the old, `--add-label` the new). Then end the turn with one message:
the PR URL, the size with its facts and line count, then every
surprise and every review comment, one line each with its verdict and
its SHA or issue URL, a `Filed:` line listing every issue URL you
created (or `Filed: none`), and as the last line `READY <pr-url>`.
`land-pr` stopped short of ready and you could not close the gap: the
same message, last line `NOT READY <pr-url>: <what is open>`. The
proof is already in the PR. Secrets, tokens, and keys stay out of the
PR and the commits.
<!-- /local -->
