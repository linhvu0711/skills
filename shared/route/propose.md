# Propose a step

How to read an issue no label routes, the Router's `"stage":"unlabeled"`, and guess the step its thread should run. A proposal starts nothing; the user's yes does, and the skill then writes the answer to the issue as a label, `answer_label` in `labels.sh`.

## Step

Read the issue, its body and comments. The first case that holds:

1. A person must do it outside the repo, per `../issue-rules.md` § Task body: `task`.
2. Something is broken or slow today, by the bug words in `../../skills/capture/SKILL.md` § Hard rules: `triage`.
3. It passes `## Readiness gate` in `../issue-rules.md`: `ship`, then § Size. A size of XXL makes it `xxl`.
4. An open PR closes it: `ready-pr`.
5. It is done, a duplicate, or out of date: `close`, with the proof: the PR, the issue, or the line that shows it.
6. An idea that is not decided yet: `grill`.
7. No case holds for sure: `unsure`, with the two best guesses and a reason for each.

## Size

For `ship`, or `unsure` with `ship` as a guess: size the work from the code, never from the title. Find the code the issue touches, with an explorer per `../facts.md` when it is more than a few files, and guess the lines the change will add and remove, on the scale of `../size.md`. Hold the size and its estimate line, as `size.md` writes it: `S: about 20 lines, 2 files`. XXL is never one ticket: the proposal is `xxl`, `Cut it with /file-epic`.
