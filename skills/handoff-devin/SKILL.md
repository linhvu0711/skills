---
name: handoff-devin
description: "Build the Devin prompt from the plan file /plan-up wrote in this chat (one ticket, or a run stacked as PRs), start the Devin session by API, and watch it. Also sends a follow-up note to the running session, including a new layer on its stack."
disable-model-invocation: true
---

The prompt skeleton and the rules block are shared with
`/handoff-cursor` and live in `~/.agents/shared-skill-core/handoff/`
as templates. Read the prompt rules first, rendered for Devin:
`bash ~/.agents/shared-skill-core/handoff/render.sh devin prompt`
(the prompt skeleton, where each block comes from, and the follow-up
shape). The rules block is
`bash ~/.agents/shared-skill-core/handoff/render.sh devin rules`, pasted
verbatim into every first prompt. Never paste the raw templates: their
marker lines and `{{words}}` are for the renderer. An edit to a rule
goes into the template, so both skills get it. This file is the order
of operations.

`scripts/devin.sh` is the only thing that talks to Devin: `create`,
`status`, `say`, `watch`, `last`, `upload`. Run it with no arguments for
the usage. It reads the key itself. The API caps prompt length and a
brief with its plan runs far past it, so `create` and `say` never send
the file as the prompt: they upload it as an attachment and send a short
prompt, the head lines plus an `ATTACHMENT:"<url>"` line, and Devin
reads the file whole. Always, not only past the cap. A session made by
API runs on the org default agent, whatever it is set to; the prompt
carries the repo, so nothing is picked by hand. Nothing is posted on GitHub, apart from size labels
the repo lacks (step 3). Sessions are never
archived: an archived session stops answering PR comments, and that
kills the review loop.

Devin's machine needs a `GH_TOKEN` secret (the user's GitHub token,
set in Devin's Secrets on 2026-09-16): its own `gh` login is Devin's
GitHub app, which cannot act as the user. Its `gh` is also old (2.78),
so the rules make Devin install a current one first; `gh pr edit
--attach` (2.99+) is how proof media gets into a PR, same as
handoff-cursor.

## Three modes

- `/handoff-devin <issue-url>`: the first prompt for an issue.
- `/handoff-devin <epic-url>`: the first prompt for a run, the plan with a
  Stack block that `/plan-up` wrote in this chat.
- `/handoff-devin <note>`: a follow-up for the session already running on this
  chat's issue or run. No URL. A plan prepped `on` the open stack is a
  follow-up too: a new layer.

## First prompt

1. **Source.** A plan the user said `ok` to in this chat: read its
   `.md` file, the path `/plan-up` gave in its summary
   (`~/.agents/artifacts/plan/plan-<slug>.md`, per
   `../../shared-skill-core/plan-page.md`). No plan: say
   `Run /plan-up first.` and stop. A `handoff-ready` issue is no
   exception; `/plan-up` takes its short path on that label and still
   writes the plan file. A run always needs the plan; an epic URL, or a
   set's first ticket URL with `#n` numbers, with no plan is
   `Run /plan-up first.`

2. **Facts.** `gh repo view --json nameWithOwner,defaultBranchRef`. From
   the issue, and in a run from each layer's issue: number, title, and
   the `What to build`, `Done when`, and `Scope` sections verbatim. The
   issue's size letter, XS to L: its size label, read through the repo
   convention's `size` map,
   `python3 ~/.agents/skills/to-issue/scripts/conventions.py get owner/repo`.
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
   block is the output of `render.sh devin rules`, pasted whole,
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
   `scripts/devin.sh create <file> --title "#<n> <title>" --issue
   <issue-url>` (a run: the epic URL; a set: the first ticket URL). The
   script uploads the file and sends the short pointer prompt itself;
   nothing to trim or split. It prints `<session_id>` and the app URL
   and records both in `~/.config/dispatch/sessions.tsv`. The prompt
   never goes in chat: it is hundreds of lines the user already saw as
   the plan and the issue. Chat gets two lines: `Prompt: <file path>
   (<n> lines)` and `Session started: <url> · <linux|macos|windows>`.
   **Platform.** You pick the VM from the repo and the task; the user
   only overrides by naming one. Linux is the default and needs no
   flag. `--platform macos` when the code or the plan's gates need an
   Apple toolchain: an `.xcodeproj` or `.xcworkspace`, a
   `Package.swift` with an iOS, macOS, watchOS, or tvOS target, a
   `Podfile`, a gate that runs `xcodebuild` or the iOS Simulator, or a
   walk in Safari on macOS. `--platform windows` when the code or the
   gates need Windows: a `.sln` or `.csproj` for WPF, WinForms, or
   WinUI, a PowerShell-only build, a walk in a Windows-native app, or a
   gate that only runs on Windows. A web app, a CLI, or a server stays
   on Linux even when the user runs a Mac. A `.devin/blueprint.yaml`
   in the repo with a single `runs-on` wins over this rule: that is the
   platform the snapshot is built for. Say the pick and the reason in
   one line before the create. A value the org does not have is a 400
   that lists the ones it has; show that list to the user and stop.
   **Mode.** Do not pass `--mode`; the org default runs. Pass it only
   when the user names one.

7. **Watch.** In Claude Code, start a Monitor, `persistent: true`,
   command `bash ~/.agents/skills/handoff-devin/scripts/devin.sh watch
   <session_id>`, description `Devin #<n>`. It prints one line per
   event and nothing between: `blocked` (Devin asked and waits),
   `finished`, `error`, `suspended:<why>` (asleep; `inactivity` is the
   usual why), or `pr <url>`. On each line, tell the user the state and
   Devin's message in one or two lines. A session that waits too long
   goes `suspended:inactivity` or `finished` with no PR; `say` wakes it,
   so treat both as blocked. Without a Monitor (a background shell only reports when the
   process ends), add `--once`: the watch then exits on the first
   event, and you start it again after you answer. In Codex there is no
   Monitor: print `scripts/devin.sh status <session_id>` as the way to
   check. Stop.

8. **Answer.** On `blocked`, Devin asked something, or asked what to do
   next. You are the brain that wrote the plan; you answer, not the
   user. First get the whole question: the watch line cuts it, so run
   `scripts/devin.sh status <session_id>` and read the message whole.
   Then sort it by the two tests in `~/.agents/skills/plan-up/SKILL.md`
   step 5, the same sort § Follow-up step 1 uses:
   - **Small fork**: the plan, the issue, or the repo holds the answer.
     Fetch the code with Explore when you need a `file:line`. Decide,
     shape the answer per `prompt.md` § Answer, `say` it. Under 20
     lines: print it in one fenced block; longer: its file path and one
     line of summary. Then one line: `Answered <url>`. Tell the user in
     one line what Devin asked and what you answered. The watch keeps
     running. Stop.
   - **Big fork**: the pick needs a fact the repo does not hold, or a
     wrong pick is hard to undo (the list in plan-up step 5: a schema or
     stored data, a public API, auth, a secret, data that leaves the
     system, a new dependency, a force push, a delete, anything that
     touches other branches or PRs than the plan names). Quote Devin's
     question as it is, in a fenced block, then the session URL, then
     one question to the user, two options at most, with the option you
     would pick first and the `file:line` behind each. The user answers
     with `/handoff-devin <note>`. Stop.

   Not sure which: big. A `finished` with no PR and a question in the
   message is the same step.

   A question about a review comment (is it true, is it in scope, fix
   it or leave it) is sorted first by the three questions and the
   verdict table in the rules block § After the PR opens, the same
   table `/validate-pr-review` uses. `fix here` inside the plan's
   slices is a small fork; `fix here` that moves a seam, a `Decided`
   line, or `Out of scope` is a big fork. `fix later` is never "leave
   it": file the issue yourself with `/capture bug: …` (a `[bug]`,
   label `bug`, no priority) before you `say`, and put the issue URL in the
   answer so Devin's reply carries it. Tell the user the issue URL in
   the same line.

9. **Finish check.** On `finished` with a PR: read every review thread,
   `gh api graphql` on `reviewThreads` (or `gh pr view --comments`).
   Each resolved thread carries a commit SHA, an issue URL, or a
   push-back fact, and the finish message has its `Filed:` line.
   Every reply and every PR comment Devin wrote has the user's login
   as `author.login` (`gh api user -q .login` here gives it); one
   under Devin's app login is a rule broken. Every issue on the
   `Filed:` line, read with `gh issue view <n> --json title,labels,body`,
   has the `[bug]` title (the repo's own spelling per the `size` map's
   style), the `bug` label, and the `## Bug`, `## Context`, `## Status`
   body from the rules block § After the PR opens; one that does not is
   fixed here with `gh issue edit`, title, label, and body, keeping
   Devin's facts, and the fix is named in the report. A thread
   resolved with none of those, a true finding answered with "out of
   scope" and no URL, or a comment under the wrong login: `say` a
   follow-up that names the thread and asks for the fix, the issue, or
   the comment posted again with `gh`, and keep the watch. Report to
   the user: PR URL, size, the issues filed, and anything sent back.

## Follow-up

1. **Sort the note.** Fetch the code it touches with Explore. A choice
   it leaves open is a fork; sort it by the two tests in
   `~/.agents/skills/plan-up/SKILL.md` step 5. A big fork goes to the user
   first. Anything else: shape it as is. A note that answers a big fork
   from First prompt step 8 is an answer: `prompt.md` § Answer, not
   § Follow-up.

2. **Shape** per `prompt.md` § Follow-up: what changed, what to do with
   `file:line`, which Proof rows it touches, which video a changed walk
   sits in, how to check. A new layer:
   `prompt.md` § New layer, the layer's plan whole under `# Stack`, its
   Stack row with the size letter. The rules block stays out; the
   session already has it, and the size labels with it.

3. **Send.** The session is the one this chat started; a chat without
   one uses `scripts/devin.sh last <issue-url>`. Write the note to a
   file, `scripts/devin.sh say <session_id> <file>` (it goes as an
   attachment too). Under 20 lines: print the note in one fenced block;
   longer: its file path and one line of summary. Then one line:
   `Sent to <url>`. The watch from the
   first prompt is still running; a chat without one, or one whose
   watch has stopped (it exits on `finished`), starts it as in First
   prompt step 7. Stop.

## Examples

**User:** `/handoff-devin https://github.com/acme/shop/issues/42` after a
`/plan-up` ended with `Ready for /handoff-devin.`

Plan read from `~/.agents/artifacts/plan/plan-acme-shop-42.md`. Repo `acme/shop`, base `main`, issue labelled
`size/M`. Labels: `size/XS` to `size/L` exist, `size/XL`
created. Prompt assembled: Repo, base, Size labels, issue with `size M`,
Task with the issue's What to build, Done when verbatim, Plan blocks
from the file, Rules pasted. Check: six Proof rows present, every
`file:line` present, five labels named. `create` with `--issue`, printed, `Session
started: <url>`, Monitor on `watch`. Stop. Forty minutes later the
watch prints `pr <url>`, then `finished … :: <Devin's finish message>`;
each becomes two lines to the user. The finish message says `size/M: 6
files, 1 package, no new seam, 212 lines`; the issue said M, so nothing
more.

**User:** `/handoff-devin https://github.com/acme/shop/issues/57` after a
short-path `/plan-up` (issue carries `handoff-ready`) ended with
`Ready for /handoff-devin.`

Plan read from `~/.agents/artifacts/plan/plan-acme-shop-57.md`: one
slice, two Proof rows, no walks, no videos. Prompt assembled with the
`UI walks` and `Videos` blocks dropped, `create`, watch, stop.

**User:** `/handoff-devin https://github.com/acme/shop/issues/57` with no
`/plan-up` in this chat, issue carries `handoff-ready`

`Run /plan-up first.` Stop. The label makes `/plan-up` short, not
optional.

**User:** `/handoff-devin the export button should be disabled while the
file builds` while session 42 runs

Explore fetches the button at `ExportButton.tsx:18` and the loading
pattern at `SaveButton.tsx:22`. The repo shows the answer, so no
question. Follow-up shaped: Changed (new row #7, disabled state copies
`SaveButton.tsx:22`), Proof (row #7, `video 1 @ step 5`), Slices (one at
the component seam, `ExportButton.tsx:18`), UI walks (walk 1 extended),
Videos (video 1 whole, one step added, Shows updated), Check (test,
walk, video 1).
`say` to session 42, printed, stop.

**Watch prints** `blocked <url> :: The plan names lib/format.ts:12 for
the date helper but that file only has formatCurrency. Should I add
formatDate there or …` while session 42 runs

`status` gives the whole message: add it to `lib/format.ts` or make a
new `lib/date.ts`. Explore: `lib/format.ts` holds one helper, and
`utils/time.ts:4` already exports `toIsoDate`. The repo holds the
answer, so small fork. Answer per § Answer: use `utils/time.ts:4`, no
new helper, Decided line updated, run the slice 2 tests again. `say`,
printed, `Answered <url>`. One line to the user: Devin asked where the
date helper lives; answered `utils/time.ts:4`. Stop.

**Watch prints** `blocked <url> :: The users table has no team_id
column. Should I add a migration or …` while session 42 runs

`status` gives the whole message. A new column is stored data: big
fork. Devin's question quoted in a fenced block, the URL, then one
question to the user: `A` add the migration in this PR (would pick,
`migrations/0042.sql` shows the shape), `B` stop this layer and file the
migration as its own ticket. Stop. The user answers
`/handoff-devin A, add the migration`; that note goes as § Answer.

**User:** `/handoff-devin https://github.com/acme/shop/issues/61` with no
plan in this chat

`Run /plan-up first.` Stop.

**User:** `/handoff-devin https://github.com/acme/shop/issues/70` after a
`/plan-up` of the run #71, #73, #74 ended with `Ready for /handoff-devin.`

Run plan found. Repo `acme/shop`, base `main`; all five size labels
exist. Prompt per § Run: Repo, base, Size labels, the Stack table with
its Size column, Facts once, then three layer blocks, each with
its issue's Task and Done when verbatim and its plan blocks. Rules once
at the end. Check: every Proof row of all three layers present, the
`layer 1, slice 1` pointer present. `create` with `--issue` set to the
epic URL, printed, watch. Stop.

**User:** `/handoff-devin https://github.com/acme/shop/issues/75` after a
`/plan-up … on pull/80` in this chat, session running on the stack

A one-layer plan on `PR #80`. Follow-up per § New layer: `# Changed`
says layer 4 goes on top of PR 80, `# Stack` carries the layer's plan
whole, `# Check` names its gates. `say` to the stack's session, `Sent
to <url>`. Stop.

**User:** `/handoff-devin the export button should be disabled while the
file builds` in a fresh chat, no session started here

`scripts/devin.sh last <issue-url>` gives the session from the ledger.
Note shaped as above, `say`, then a Monitor on `watch` since this chat
has none. Stop.
