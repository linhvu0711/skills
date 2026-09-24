---
name: handoff-cursor
description: "Build the Cursor prompt from the plan file /plan-up wrote in this chat (one ticket, or a run stacked as PRs), start a Cursor cloud agent by API, and watch it. Also sends a follow-up note to the running agent, including a new layer on its stack."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

The prompt skeleton and the rules block are shared with
`/handoff-devin` and live in `../../shared-skill-core/handoff/`
as templates. Read the prompt rules first, rendered for Cursor:
`bash ../../shared-skill-core/handoff/render.sh cursor prompt`
(the prompt skeleton, where each block comes from, and the follow-up
shape). The rules block is
`bash ../../shared-skill-core/handoff/render.sh cursor rules`,
pasted verbatim into every first prompt. Never paste the raw templates:
their marker lines and `{{words}}` are for the renderer. An edit to a
rule goes into the template, so both skills get it. This file is the
order of operations. It is the Cursor twin of `/handoff-devin`; the
plan, the prompt shape, and the steps are the same, only the executor
and its script differ.

`scripts/cursor.sh` is the only thing that talks to Cursor: `create`,
`status`, `say`, `watch`, `last`, `models`, `repos`. Run it with no
arguments for the usage. It reads the key itself. The prompt file goes
whole into the API as the prompt text: Cursor has no attachments and no
documented length cap.

Cursor's shape: an **agent** (`bc-…`) is the durable session, one
workspace, one conversation. Each prompt to it is a **run** (`run-…`);
`create` makes run 1, `say` makes the next. Only one run at a time; a
`say` while a run is going is `409 agent_busy`, so wait for `finished`.
The run's end state, its last message, and its PRs live on the run, and
`status` reads both. The agent opens the PR itself under our branch
name (`autoCreatePR` is off) with `gh`, as the user, through the
`GH_TOKEN` secret set once in Cursor (cursor.com/dashboard, Cloud
Agents, Secrets: a GitHub token of the user's with `repo` scope). The
VM's own git token can push but cannot open a PR, label, or file an
issue, so without the secret the run stops at its first step. Nothing
is posted on GitHub by this skill, apart from size labels the repo
lacks (step 3). Agents are never archived: an archived agent stops
answering PR comments, and that kills the review loop.

## Three modes

- `/handoff-cursor <issue-url> [--model <id>]`: the first prompt for an
  issue.
- `/handoff-cursor <epic-url> [--model <id>]`: the first prompt for a
  run, the plan with a Stack block that `/plan-up` wrote in this chat.
- `/handoff-cursor <note>`: a follow-up for the agent already running on
  this chat's issue or run. No URL. A plan prepped `on` the open stack
  is a follow-up too: a new layer.

`--model` is a model id from `scripts/cursor.sh models` (`claude-opus-5`,
`gpt-5.5`, `composer-2.5`, …). No flag: the account default. Unknown
id: print the list and stop.

## First prompt

1. **Source.** A plan the user said `ok` to in this chat: read its
   `.md` file, the path `/plan-up` gave in its summary
   (`$HOME/.agents/artifacts/plan/plan-<slug>.md`, per
   `../../shared-skill-core/plan-page.md`). No plan: say
   `Run /plan-up first.` and stop. A `handoff-ready` issue is no
   exception; `/plan-up` takes its short path on that label and still
   writes the plan file. A run always needs the plan; an epic URL, or a
   set's first ticket URL with `#n` numbers, with no plan is
   `Run /plan-up first.`

2. **Facts.** `gh repo view --json nameWithOwner,defaultBranchRef`. Then
   `scripts/cursor.sh repos`: the repo must be in the list, or the agent
   cannot clone it. Missing: say `Connect owner/name to Cursor first:
   cursor.com/dashboard, Integrations, GitHub.` and stop. The `Author`
   line: `git config user.name` and `git config user.email`, as
   `Name <email>`. From
   the issue, and in a run from each layer's issue: number, title, and
   the `What to build`, `Done when`, and `Scope` sections verbatim. The
   issue's size letter, XS to L: its size label, read through the repo
   convention's `size` map,
   `python3 ../to-issue/scripts/conventions.py get owner/repo`.
   On `MISS`, match the label by eye the way
   `../../shared-skill-core/issue-rules.md` § Repo convention
   does. No size label: `none`. A run: the plan's Stack table already
   carries the letter per layer.

3. **Labels.** The PR gets a size label, XS to XL, in the repo's own
   spelling. First the bot check: `grep -ril 'size' .github/workflows`
   on the base branch, and read any hit. A workflow that labels PRs by
   size (`pr-size-labeler`, `size-label`, a `labeler` with size rules)
   owns the label. Take its label names from its config, mapped onto XS
   to XL, and write the prompt line as `Size labels: bot · XS <name> ·
   … · XL <name>`; a bot with fewer bands lists the bands it has.
   Create nothing, and skip the rest of this step.
   No bot: the four issue labels come from the `size` map (defaults
   `size/XS` … `size/L`). XL takes the same shape: swap the size letter
   or word in the L label, so `size/L` gives `size/XL` and `Size: Large`
   gives `Size: XL`. A repo that already has a label that clearly reads
   XL keeps it. Then `gh label list --limit 200 --json name -q
   '.[].name'`; create what is missing, and only that. The four issue
   labels use the commands in `issue-rules.md` § Repo convention; the
   one PR-only label:

   ```bash
   gh label create "size/XL" --color 0F5C62 --description "Over the ceiling; PR only. A ticket this size is an epic"
   ```

   The five names go on the prompt's `Size labels` line.

4. **Assemble** per the prompt rules; a run per their § Run. The rules
   block is the output of `render.sh cursor rules`, pasted whole,
   unchanged, once.

5. **Check.** Every Proof row of the plan, of every layer, is in the
   prompt. Every video of the plan is in the prompt, and every
   `video n @ step m` in a Proof row names a video that is. Every
   `file:line` and every `layer n, slice m` of the plan is
   in the prompt. The `Size labels` line has five names that exist in the
   repo; the issue line, or every Stack row, has a size letter or
   `none`. Every line of the prompt traces to the plan, the issue, the
   repo's labels, or the rules. Placeholders left: zero.

6. **Send.** Write the prompt to a file in the scratch directory, then
   `scripts/cursor.sh create <file> --repo owner/name --base <base>
   --title "#<n> <title>" --issue <issue-url> [--model <id>]` (a run:
   the epic URL; a set: the first ticket URL). It prints `<agent_id>`
   and the app URL and records both in
   `~/.config/dispatch/cursor-sessions.tsv`. The prompt never goes in
   chat: it is hundreds of lines the user already saw as the plan and
   the issue. Chat gets two lines: `Prompt: <file path> (<n> lines)`
   and `Agent started: <url>`. A `validation_error` on the prompt means
   the text was too long for Cursor after all: report the byte count and
   stop.

7. **Watch.** In Claude Code, start a Monitor, `persistent: true`,
   command `bash scripts/cursor.sh watch
   <agent_id> --repo owner/name --issue <n>`, description `Cursor #<n>`
   (a run: the first layer's issue number; each later layer's PR shows
   up in the finish message). It prints one line per event and nothing
   between: `pr <url>` (a PR whose head branch starts with `<type>/<n>-`,
   read from GitHub, since Cursor's own git snapshot tracks only its
   `cursor/…` workspace branch), `finished`, `error`, `cancelled`, or
   `expired`, each with the run's last message. On each
   line, tell the user the state and the agent's message in one or two
   lines. Cursor has no `blocked` state: an agent that needs an answer
   ends its run with the question as its message, so `finished` is
   either the finish message (a PR is there) or a question (step 8).
   `error` and `expired` end the run with nothing; `say` the same note
   again as a follow-up and start the watch again, once; a second
   `error` goes to the user with the message. In Codex there is no
   Monitor: print `scripts/cursor.sh status <agent_id>` as the way to
   check. Stop.

8. **Answer.** On `finished` whose message asks something, or asks what
   to do next, or has no PR: the agent asked. You are the brain that
   wrote the plan; you answer, not the user. First get the whole
   message: the watch line cuts it, so run `scripts/cursor.sh status
   <agent_id>` and read it whole. Then sort it by the two tests in
   `../plan-up/SKILL.md` step 5, the same sort § Follow-up
   step 1 uses:
   - **Small fork**: the plan, the issue, or the repo holds the answer.
     Fetch the code with Explore when you need a `file:line`. Decide,
     shape the answer per `prompt.md` § Answer, `say` it. Under 20
     lines: print it in one fenced block; longer: its file path and one
     line of summary. Then one line: `Answered <url>`. Tell the user in
     one line what the agent asked and what you answered. The watch
     exited on `finished`; start it again as in step 7. Stop.
   - **Big fork**: the pick needs a fact the repo does not hold, or a
     wrong pick is hard to undo (the list in plan-up step 5: a schema or
     stored data, a public API, auth, a secret, data that leaves the
     system, a new dependency, a force push, a delete, anything that
     touches other branches or PRs than the plan names). Quote the
     agent's question as it is, in a fenced block, then the agent URL,
     then one question to the user, two options at most, with the
     option you would pick first and the `file:line` behind each. The
     user answers with `/handoff-cursor <note>`. Stop.

   Not sure which: big.

   A question about a review comment (is it true, is it in scope, fix
   it or leave it) is sorted first by the three questions and the
   verdict table in the rules block § After the PR opens, the same
   table `/validate-pr-review` uses. `fix here` inside the plan's
   slices is a small fork; `fix here` that moves a seam, a `Decided`
   line, or `Out of scope` is a big fork. `fix later` is never "leave
   it": file the issue yourself with `/capture bug: …` (a `[bug]`,
   label `bug`, no priority) before you `say`, and put the issue URL in
   the answer so the agent's reply carries it. Tell the user the issue
   URL in the same line.

9. **Finish check.** On `finished` with a PR and a finish message: read
   every review thread, `gh api graphql` on `reviewThreads` (or `gh pr
   view --comments`). Each resolved thread carries a commit SHA, an
   issue URL, or a push-back fact, and the finish message has its
   `Filed:` line. Every reply and every PR comment the agent wrote has
   the user's login as `author.login` (`gh api user -q .login` here
   gives it); one under Cursor's bot login is a rule broken. A thread
   resolved with none of those, a true finding answered with "out of
   scope" and no URL, or a comment under the wrong login: `say` a
   follow-up that names the thread and asks for the fix, the issue, or
   the comment posted again with `gh`, and start the watch again.
   Report to the user: PR URL, size, the issues filed, and anything
   sent back. Review comments that land later start new
   runs on the agent by themselves (it is subscribed to its PR); to
   follow those rounds, start the watch with `--follow`, which does not
   exit on `finished`.

## Follow-up

1. **Sort the note.** Fetch the code it touches with Explore. A choice
   it leaves open is a fork; sort it by the two tests in
   `../plan-up/SKILL.md` step 5. A big fork goes to the user
   first. Anything else: shape it as is. A note that answers a big fork
   from First prompt step 8 is an answer: `prompt.md` § Answer, not
   § Follow-up.

2. **Shape** per `prompt.md` § Follow-up: what changed, what to do with
   `file:line`, which Proof rows it touches, which video a changed walk
   sits in, how to check. A new layer:
   `prompt.md` § New layer, the layer's plan whole under `# Stack`, its
   Stack row with the size letter. The rules block stays out; the
   agent already has it, and the size labels with it.

3. **Send.** The agent is the one this chat started; a chat without
   one uses `scripts/cursor.sh last <issue-url>`. Write the note to a
   file, `scripts/cursor.sh say <agent_id> <file>`. Under 20 lines:
   print the note in one fenced block; longer: its file path and one
   line of summary. Then one line: `Sent to <url>`. `409 agent_busy`:
   a run is still going; wait for the watch's `finished`, then send.
   The watch exits on `finished`, so start it again as in First prompt
   step 7. Stop.

## Known limits

- **Commit identity.** The workspace's default is
  `Cursor Agent <cursoragent@cursor.com>`, but the agent commits from
  a shell, so the rules set `git config user.name` and `user.email`
  from the prompt's `Author` line first; GitHub then shows the user as
  author and committer (proven 2026-09-16, perch PR 122). The commit
  is still signed with Cursor's key, which is not on the user's
  account, so it shows `Unverified` instead of `Verified`. A repo that
  requires verified signatures rejects it; that job goes to
  `/handoff-devin`. The PR opens as the user because `gh` runs with
  the user's `GH_TOKEN`.
- **The PR is the agent's, not Cursor's.** With `autoCreatePR` off,
  Cursor's own PR flow does nothing (its PR tool only "registers a
  request"), so the agent opens the PR with `gh` on our branch. Cursor
  then knows nothing of that PR: its git snapshot keeps the `cursor/…`
  workspace branch, and it does not auto-subscribe. Hence `watch
  --repo --issue` asks GitHub, and the rules make the agent subscribe
  to the PR itself.
- **Proof media.** The agent has no browser logged in to github.com,
  so nothing is pasted into the PR editor. Instead `gh pr edit
  --attach <file>` (gh 2.99+, in the VM since 2026-09) uploads each
  screenshot and video as a GitHub asset and rewrites the body's
  `./<file>` links. Images show inline, videos play, and only people
  with repo access see them, which a raw link in a private repo cannot
  do (GitHub's image proxy has no login, so such images render blank).
- **Proven 2026-09-16 on perch PRs 122 and 123:** PR opens as the user
  on our branch name, draft, label on; the agent's own subscription
  works (a comment started a new run, the agent replied on the PR, and
  its own reply did not loop); Playwright installs in about 17 s and
  records, ffmpeg is present, and `--attach` put 3 screenshots and 2
  videos in one command. Not yet proven: a two-layer stack from one
  agent; the review loop on the Pro plan (auto-fix CI is Teams only,
  so the rules make the agent watch checks itself).
- **Token-like text kills a run.** A message that holds a long masked
  token (`ghs_****…`) trips the model's repetition guard and the run
  ends as `error` with no message, after the work is done. The rules
  forbid `gh auth status` and any `Token:` line for that reason.
- **Default model.** No `--model` means the account default, which was
  Cursor Grok 4.6 on 2026-09-16. Pass `--model` for anything real.

## Examples

**User:** `/handoff-cursor https://github.com/acme/shop/issues/42` after a
`/plan-up` ended with `Ready for /handoff-cursor.`

Plan read from `$HOME/.agents/artifacts/plan/plan-acme-shop-42.md`. Repo
`acme/shop`, base `main`, in `cursor.sh repos`, issue labelled
`size/M`. Labels: `size/XS` to `size/L` exist, `size/XL`
created. Prompt assembled: Repo, base, Size labels, issue with `size M`,
Task with the issue's What to build, Done when verbatim, Plan blocks
from the file, Rules pasted. Check: six Proof rows present, every
`file:line` present, five labels named. `create` with `--repo acme/shop
--issue`, printed, `Agent started: <url>`, Monitor on `watch`. Stop.
Forty minutes later the watch prints `pr <url>`, then `finished … ::
<finish message>`; each becomes two lines to the user. The finish
message says `size/M: 6 files, 1 package, no new seam, 212 lines`; the
issue said M, so nothing more.

**User:** `/handoff-cursor https://github.com/acme/shop/issues/42 --model
claude-opus-5` after the same `/plan-up`

Same, with `--model claude-opus-5` on `create`.

**User:** `/handoff-cursor https://github.com/acme/shop/issues/57` after a
short-path `/plan-up` (issue carries `handoff-ready`) ended with
`Ready for /handoff-cursor.`

Plan read from `$HOME/.agents/artifacts/plan/plan-acme-shop-57.md`: one
slice, two Proof rows, no walks, no videos. Prompt assembled with the
`UI walks` and `Videos` blocks dropped, `create`, watch, stop.

**User:** `/handoff-cursor https://github.com/acme/shop/issues/57` with no
`/plan-up` in this chat, issue carries `handoff-ready`

`Run /plan-up first.` Stop. The label makes `/plan-up` short, not
optional.

**User:** `/handoff-cursor https://github.com/acme/shop/issues/61` after a
`/plan-up`, but `cursor.sh repos` does not list `acme/shop`

`Connect acme/shop to Cursor first: cursor.com/dashboard, Integrations,
GitHub.` Stop.

**User:** `/handoff-cursor the export button should be disabled while the
file builds` while agent 42 runs

Explore fetches the button at `ExportButton.tsx:18` and the loading
pattern at `SaveButton.tsx:22`. The repo shows the answer, so no
question. Follow-up shaped: Changed (new row #7, disabled state copies
`SaveButton.tsx:22`), Proof (row #7, `video 1 @ step 5`), Slices (one at
the component seam, `ExportButton.tsx:18`), UI walks (walk 1 extended),
Videos (video 1 whole, one step added, Shows updated), Check (test,
walk, video 1). `say` to agent 42 is `409 agent_busy`: the run is still
going. Wait for `finished`, `say`, printed, watch again, stop.

**Watch prints** `finished <url> :: The plan names lib/format.ts:12 for
the date helper but that file only has formatCurrency. Should I add
formatDate there or …` with no `pr` line before it

`status` gives the whole message: add it to `lib/format.ts` or make a
new `lib/date.ts`. Explore: `lib/format.ts` holds one helper, and
`utils/time.ts:4` already exports `toIsoDate`. The repo holds the
answer, so small fork. Answer per § Answer: use `utils/time.ts:4`, no
new helper, Decided line updated, run the slice 2 tests again. `say`,
printed, `Answered <url>`, watch again. One line to the user: the agent
asked where the date helper lives; answered `utils/time.ts:4`. Stop.

**Watch prints** `finished <url> :: The users table has no team_id
column. Should I add a migration or …`

`status` gives the whole message. A new column is stored data: big
fork. The agent's question quoted in a fenced block, the URL, then one
question to the user: `A` add the migration in this PR (would pick,
`migrations/0042.sql` shows the shape), `B` stop this layer and file the
migration as its own ticket. Stop. The user answers
`/handoff-cursor A, add the migration`; that note goes as § Answer.

**User:** `/handoff-cursor https://github.com/acme/shop/issues/70` after a
`/plan-up` of the run #71, #73, #74 ended with `Ready for /handoff-cursor.`

Run plan found. Repo `acme/shop`, base `main`; all five size labels
exist. Prompt per § Run: Repo, base, Size labels, the Stack table with
its Size column, Facts once, then three layer blocks, each with
its issue's Task and Done when verbatim and its plan blocks. Rules once
at the end. Check: every Proof row of all three layers present, the
`layer 1, slice 1` pointer present. `create` with `--issue` set to the
epic URL, printed, watch. The watch prints three `pr` lines as the
layers open. Stop.

**User:** `/handoff-cursor https://github.com/acme/shop/issues/75` after a
`/plan-up … on pull/80` in this chat, agent running on the stack

A one-layer plan on `PR #80`. Follow-up per § New layer: `# Changed`
says layer 4 goes on top of PR 80, `# Stack` carries the layer's plan
whole, `# Check` names its gates. `say` to the stack's agent once its
run is `finished`, `Sent to <url>`, watch again. Stop.

**User:** `/handoff-cursor the export button should be disabled while the
file builds` in a fresh chat, no agent started here

`scripts/cursor.sh last <issue-url>` gives the agent from the ledger.
Note shaped as above, `say`, then a Monitor on `watch` since this chat
has none. Stop.
