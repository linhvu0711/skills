---
name: handoff
description: "Build the prompt from the plan file /plan-up wrote in this chat (one ticket, or a run stacked as PRs), start a Devin session or a Cursor cloud agent by API, and watch it. Devin unless named, or the executor that started the issue. Also sends a follow-up note to the running session, including a new layer on its stack."
disable-model-invocation: true
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

The prompt skeleton and the rules block live in
`../../shared-skill-core/handoff/` as templates, shared with `/ship`.
Read the prompt rules first, rendered for the executor:
`bash ../../shared-skill-core/handoff/render.sh <executor> prompt`
(the prompt skeleton, where each block comes from, and the follow-up
shape). The rules block is
`bash ../../shared-skill-core/handoff/render.sh <executor> rules`,
pasted verbatim into every first prompt. Never paste the raw templates:
their marker lines and `{{words}}` are for the renderer. An edit to a
rule goes into the template, so every executor gets it. This file is
the order of operations: the flow once, then a section per executor
for its own steps.

`scripts/handoff.sh` is the only thing the flow runs to reach an
executor: `route`, `start`, `status`, `say`, `watch`. Run it with no
arguments for the usage. It keeps the handoff ledger,
`~/.config/dispatch/handoff.tsv`, a row per session with its executor
and issue, and its adapters read their own keys. The two Cursor verbs
the module does not carry, `repos` and `models`, run as
`scripts/adapters/cursor.sh` (§ Cursor). Nothing is posted on GitHub,
apart from size labels the repo lacks (step 3). Sessions are never
archived: an archived session stops answering PR comments, and that
kills the review loop.

## Arguments

- `/handoff [devin|cursor] [<issue-url> | <epic-url>] [--model <id>]`:
  the first prompt for an issue, or for a run (the plan with a Stack
  block that `/plan-up` wrote in this chat). No URL: the plan this chat
  holds.
- `/handoff [devin|cursor] <note>`: a follow-up for the session already
  running on this chat's issue or run. A plan prepped `on` the open
  stack is a follow-up too: a new layer.

The first word is the executor when it is `devin` or `cursor`, when it
is the only word, or when a URL follows it. Any other word there: say
`executor must be devin or cursor` and stop; `handoff.sh` stops with the
same words. Anything else is a note; a one-word note names its
executor first, as `/handoff devin yes`.

No executor named: `bash scripts/handoff.sh route <issue-url>` picks
it: `follow <executor> <session> <link>` names the executor that
started the issue, and `start devin` a new issue. A named executor:
`route <issue-url> <executor>`. A run's issue URL is the epic URL; a
set's, the first ticket URL. Say the pick in one line, as
`Executor: cursor (started #42)`. `--model` names a Cursor model
(§ Cursor); with Devin, say `--model is for cursor` and stop.

## First prompt

1. **Source.** A plan the user said `ok` to in this chat: read its
   `.md` file, the path `/plan-up` gave in its summary
   (`$HOME/.agents/artifacts/plan/plan-<slug>.md`, per
   `../../shared-skill-core/plan-page.md`). No plan: say
   `Run /plan-up first.` and stop. A `handoff-ready` issue or a run
   is no exception. No URL: the issue is the plan's, from its
   `# Plan: #<n>` title and its `Repo:` line. Then the executor, per
   § Arguments. `route` printed `follow …`: the issue already has a
   session, and a second one would build it twice. Show its link and ask
   one question, per `../../shared-skill-core/grilling.md`: `A` send
   this plan to it as a follow-up (§ Follow-up, from step 2), the pick;
   `B` start a new session. Wait. `A`: § Follow-up. `B`: go on.

2. **Facts.** `gh repo view --json nameWithOwner,defaultBranchRef`. From
   the issue, and in a run from each layer's issue: number, title, and
   the `What to build`, `Done when`, and `Scope` sections verbatim. The
   issue's size letter, XS to L: its size label, read through the repo
   convention's `size` map,
   `python3 ../to-issue/scripts/conventions.py get owner/repo`.
   On `MISS`, match the label by eye the way
   `../../shared-skill-core/issue-rules.md` § Repo convention
   does. No size label: `none`. A run: the plan's Stack table already
   carries the letter per layer. Then the executor's own facts:
   § Cursor.

3. **Labels.** The PR gets a size label, XS to XL, in the repo's own
   spelling. First the bot check, on the base branch whatever the
   checkout is on: `git fetch --quiet origin <base>`, then
   `git grep -il size origin/<base> -- .github/workflows`, and read each
   hit with `git show <hit>`; a hit already reads `origin/<base>:<path>`. A workflow that labels PRs by
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
   block is the output of `render.sh <executor> rules`, pasted whole,
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
   `bash scripts/handoff.sh start <executor> <file> --title "#<n> <title>"
   --issue <issue-url>` (a run: the epic URL; a set: the first ticket
   URL), plus the executor's options from § Devin or § Cursor. It prints
   `<session>` and `<link>`, tab separated, and writes the ledger row. A
   stderr line `#<n> already has a <executor> session` goes to the user
   as it is. The prompt never goes in chat: it is hundreds of lines the
   user already saw as the plan and the issue. Chat gets two lines:
   `Prompt: <file path> (<n> lines)` and
   `Session started: <link> · <executor> · <platform or model>`.

7. **Watch.** In Claude Code, start a Monitor, `persistent: true`,
   command `bash scripts/handoff.sh watch <executor> <session>`, plus the
   executor's poll options from § Cursor, description `<Executor> #<n>`.
   It prints one line per event and nothing between: `pr <url>`, or
   `<state> <link> :: <message>` for `blocked`, `finished`, `error`,
   `cancelled`, `expired`, or `suspended:<why>`. After three failed polls
   in a row it prints `poll failed <link> :: <error>` and exits: show it
   and stop. On each line, tell the user the state and the message in
   one or two lines. What each state means for the executor is in its
   section. Without a Monitor, add `--once`: the watch exits on the first
   event, and you start it again after you answer. In Codex there is no
   Monitor: print `bash scripts/handoff.sh status <executor> <session>`
   as the way to check. Stop.

8. **Answer.** The executor asked something, or asked what to do next;
   its section says which events mean that. You are the brain that
   wrote the plan; you answer, not the user. First get the whole
   question: the watch line cuts it, so run
   `bash scripts/handoff.sh status <executor> <session>` and read the
   message whole. Then sort it by the two tests in
   `../plan-up/SKILL.md` step 5, the same sort § Follow-up step 1 uses:
   - **Small fork**: the plan, the issue, or the repo holds the answer.
     Fetch the code with Explore when you need a `file:line`. Decide,
     shape the answer per `prompt.md` § Answer, `say` it. Under 20
     lines: print it in one fenced block; longer: its file path and one
     line of summary. Then one line: `Answered <link>`. Tell the user in
     one line what the executor asked and what you answered. The watch
     goes on as the executor's section says. Stop.
   - **Big fork**: the pick needs a fact the repo does not hold, or a
     wrong pick is hard to undo (the list in plan-up step 5: a schema or
     stored data, a public API, auth, a secret, data that leaves the
     system, a new dependency, a force push, a delete, anything that
     touches other branches or PRs than the plan names). Quote the
     executor's question as it is, in a fenced block, then the session
     link, then one question to the user, two options at most, with the
     option you would pick first and the `file:line` behind each. The
     user answers with `/handoff <note>`. Stop.

   Not sure which: big.

   A question about a review comment (is it true, is it in scope, fix
   it or leave it) is sorted first by the three questions and the
   verdict table in the rules block § After the PR opens, the same
   table `/validate-pr-review` uses. `fix here` inside the plan's
   slices is a small fork; `fix here` that moves a seam, a `Decided`
   line, or `Out of scope` is a big fork. `fix later` is never "leave
   it": file the issue yourself with `/capture bug: …` (a `[bug]`,
   label `bug`, no priority) before you `say`, and put the issue URL in
   the answer so the executor's reply carries it. Tell the user the
   issue URL in the same line.

9. **Finish check.** On `finished` with a PR and a finish message: read
   every review thread, `gh api graphql` on `reviewThreads` (or `gh pr
   view --comments`). Each resolved thread carries a commit SHA, an
   issue URL, or a push-back fact, and the finish message has its
   `Filed:` line. Every reply and every PR comment the executor wrote
   has the user's login as `author.login` (`gh api user -q .login` here
   gives it); one under the executor's app or bot login is a rule
   broken. Every issue on the `Filed:` line, read with
   `gh issue view <n> --json title,labels,body`, has the `[bug]` title
   (the repo's own spelling per the `size` map's style), the `bug`
   label, and the `## Bug`, `## Context`, `## Status` body from the
   rules block § After the PR opens; one that does not is fixed here
   with `gh issue edit`, title, label, and body, keeping the executor's
   facts, and the fix is named in the report. A thread resolved with
   none of those, a true finding answered with "out of scope" and no
   URL, or a comment under the wrong login: `say` a follow-up that
   names the thread and asks for the fix, the issue, or the comment
   posted again with `gh`, and keep the watch as the executor's section
   says. Report to the user: PR URL, size, the issues filed, and
   anything sent back.

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
   Stack row with the size letter, and its `Proved` block, if any. The
   rules block stays out; the session already has it, and the size labels
   with it.

3. **Send.** The session is the one this chat started. A chat without
   one runs `bash scripts/handoff.sh route <issue-url> [<executor>]`, the
   issue from this chat's plan; a chat with no plan either asks for the
   issue URL in one line and waits. A new layer routes by the stack's
   URL, not its own issue's: the epic URL, or a set's first ticket URL,
   the one the stack was handed off with; not known here, ask for it in
   one line and wait. `follow <executor> <session> <link>`
   is the session, so a note with no executor named goes to the
   executor that started the issue. `start …` means the issue has no
   session: say `#<n> has no handoff session. Start one with /handoff
   <issue-url>.` and stop. Write the note to a file,
   `bash scripts/handoff.sh say <executor> <session> <file>`. Under 20
   lines: print the note in one fenced block; longer: its file path and
   one line of summary. Then one line: `Sent to <link>`. The watch goes
   on as the executor's section says; a chat without one starts it as
   in First prompt step 7. Stop.

## Devin

**Start options.** `--platform` picks the VM; you pick it from the repo
and the task, and the user only overrides by naming one. Linux is the
default and needs no flag. `--platform macos` when the code or the
plan's gates need an Apple toolchain: an `.xcodeproj` or
`.xcworkspace`, a `Package.swift` with an iOS, macOS, watchOS, or tvOS
target, a `Podfile`, a gate that runs `xcodebuild` or the iOS
Simulator, or a walk in Safari on macOS. `--platform windows` when the
code or the gates need Windows: a `.sln` or `.csproj` for WPF,
WinForms, or WinUI, a PowerShell-only build, a walk in a Windows-native
app, or a gate that only runs on Windows. A web app, a CLI, or a server
stays on Linux even when the user runs a Mac. A `.devin/blueprint.yaml`
in the repo with a single `runs-on` wins over this rule: that is the
platform the snapshot is built for. Say the pick and the reason in one
line before `start`. A value the org does not have is a 400 that lists
the ones it has; show that list to the user and stop. Do not pass
`--mode`; the org default runs. Pass it only when the user names one.

**Attachments.** The API caps prompt length, so the adapter uploads the
file as an attachment and sends the head lines plus an
`ATTACHMENT:"<url>"` line; a `say` goes the same way. Devin reads the
file whole, so nothing is trimmed or split. The session runs on the org
default agent; the prompt carries the repo.

**GitHub.** Devin's machine needs a `GH_TOKEN` secret (the user's
GitHub token, set in Devin's Secrets on 2026-09-16): its own `gh` login
is Devin's GitHub app, which cannot act as the user. Its `gh` is also
old (2.78), so the rules make Devin install a current one first;
`gh pr edit --attach` (2.99+) is how proof media gets into a PR.

**Watch.** `blocked` is Devin asking: First prompt step 8. A session
that waits too long goes `suspended:inactivity`, or `finished` with no
PR; `say` wakes it, so treat both as `blocked`, and a `finished` with
no PR and a question in the message is step 8 too. The watch keeps
running after a `say`; it exits on `finished`, and a chat whose watch
has stopped starts it again.

## Cursor

**Facts.** Step 2 adds two facts. `bash scripts/adapters/cursor.sh
repos`: the repo must be in the list, or the agent cannot clone it.
Missing: say `Connect owner/name to Cursor first: cursor.com/dashboard,
Integrations, GitHub.` and stop; `start` stops with the same words. The
`Author` line: `git config user.name` and `git config user.email`, as
`Name <email>`.

**Model.** `--model` is a model id from
`bash scripts/adapters/cursor.sh models` (`claude-opus-5`, `gpt-5.5`,
`composer-2.5`, …). Unknown id: print the list and stop. No flag: the
account default, which was Cursor Grok 4.6 on 2026-09-16. Pass
`--model` for anything real.

**Start options.** `--repo owner/name --base <base>`, and
`--model <id>` when one is named. The prompt file goes whole into the
API as the prompt text: Cursor has no attachments and no documented
length cap. A `validation_error` on the prompt means the text was too
long after all: report the byte count and stop.

**Agent and runs.** An **agent** (`bc-…`) is the durable session; each
prompt to it is a **run** (`run-…`): `start` makes run 1, `say` the
next. One run at a time; a `say` while a run is going is
`409 agent_busy`, so wait for the watch's `finished`, then send. The
agent opens the PR itself on our branch name (`autoCreatePR` is off)
with `gh`, as the user, through the `GH_TOKEN` secret set once in
Cursor (cursor.com/dashboard, Cloud Agents, Secrets: the user's GitHub
token with `repo` scope). Without it the run stops at its first step:
the VM's own token can push but cannot open a PR, label, or file an
issue.

**Watch.** Poll options `--repo owner/name --issue <n>` (a run: the
first layer's issue number; each later layer's PR shows up in the
finish message): a `pr <url>` line is a PR whose head branch starts
with `<type>/<n>-`, read from GitHub, since Cursor's own git snapshot
tracks only its `cursor/…` workspace branch. Cursor has no `blocked`
state: an agent that needs an answer ends its run with the question as
its message, so `finished` is either the finish message (a PR is
there) or a question (First prompt step 8). `error` and `expired` end
the run with nothing; `say` the same note again as a follow-up and
start the watch again, once; a second `error` goes to the user with
the message. The watch exits on `finished`, so after every `say` start
it again. Review comments that land later start new runs on the agent
by themselves (it is subscribed to its PR); to follow those rounds,
start the watch with `--follow`, which does not exit on `finished`.

**Known limits.**
- Commits show the user as author, from the `Author` line (proven
  2026-09-16, perch PR 122), but are signed with Cursor's key, so they
  show `Unverified`. A repo that requires verified signatures rejects
  them; that job goes to Devin.
- Cursor knows nothing of the PR the agent opens with `gh`, so the
  watch asks GitHub, and the rules make the agent subscribe to the PR.
- Proof media goes in by `gh pr edit --attach <file>` (gh 2.99+): the
  agent has no browser logged in to github.com.
- Not yet proven: a two-layer stack from one agent; the review loop on
  the Pro plan (auto-fix CI is Teams only, so the rules make the agent
  watch checks itself).
- A message that holds a long masked token (`ghs_****…`) ends the run
  as `error` with no message. The rules forbid `gh auth status` and any
  `Token:` line for that reason.

## Examples

**User:** `/handoff https://github.com/acme/shop/issues/42` after a
`/plan-up` ended with `Ready for /handoff.`

Plan read from `$HOME/.agents/artifacts/plan/plan-acme-shop-42.md`.
`route` prints `start devin`: `Executor: devin (new issue)`. Prompt
assembled and checked. A web app, so Linux. `start devin` with `--issue`, `Session started: <link> · devin ·
linux`, Monitor on `watch`. Stop. Later the watch prints `pr <url>`,
then `finished … :: <finish message>`; each becomes two lines to the
user.

**User:** `/handoff cursor https://github.com/acme/shop/issues/42 --model
claude-opus-5` after the same `/plan-up`

`Executor: cursor (named)`. `cursor.sh repos` lists `acme/shop`,
`cursor.sh models` lists `claude-opus-5`, the `Author` line comes from
`git config`. `start cursor` with `--repo acme/shop --base main --model
claude-opus-5`, Monitor on `watch cursor <agent> --repo acme/shop
--issue 42`. Stop.

**User:** `/handoff` after a short-path `/plan-up` of #57 ended with
`Ready for /handoff.`

No URL: the issue is the plan's, #57. No walks, no videos: the prompt
drops those blocks. With no plan in this chat: `Run /plan-up first.`

**User:** `/handoff foo`

`foo` is the only word, so it is the executor slot:
`executor must be devin or cursor`. Stop.

**User:** `/handoff the export button should be disabled while the file
builds`; a Cursor agent started #42, the issue of this chat's plan

No executor named. `route https://github.com/acme/shop/issues/42`
prints `follow cursor bc-1 https://cursor.com/agents/bc-1`. Explore
fetches the button at `ExportButton.tsx:18` and the loading pattern at
`SaveButton.tsx:22`; the repo shows the answer, so no question. Note
shaped per § Follow-up, `say cursor bc-1`, `Sent to <link>`, watch
again. Stop.

**Watch prints** `blocked <link> :: Where does formatDate go?` from Devin

`status devin` gives it whole. `utils/time.ts:4` already exports
`toIsoDate`: small fork. § Answer, `say`, `Answered <link>`. Stop.

**Watch prints** `finished <link> :: The users table has no team_id
column. Should I add a migration or …` from Cursor, no `pr` line

A question, and stored data: big fork. Quoted, the link, then one
question: `A` add the migration in this PR (would pick,
`migrations/0042.sql` shows the shape), `B` file it as its own ticket.
Stop. The user's `/handoff A, add the migration` goes as § Answer.

**User:** `/handoff https://github.com/acme/shop/issues/75` after a
`/plan-up … on pull/80`, a session running on the stack

A one-layer plan on `PR #80`: § New layer, `say` to the stack's session.
