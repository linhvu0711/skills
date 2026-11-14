# complete-task

Does a task issue for you: work in a platform outside the repo, such as making an account, a key, a bucket, or a DNS record. It works in your own browser and Mac apps through [use-mac](../use-mac/), and you do only the steps that must be yours.

## Use it when

An issue has the `manual` label, and you want the agent to do it. Type `/complete-task #16` (`$complete-task #16` in Codex). [orchestrate](../orchestrate/) starts it for you as `/complete-task --ready #16`: the thread posts `Ready: #16 … Send go`, with what to have near you and about how long it takes, and waits for your `go`. Orchestrate runs one task at a time on this Mac.

## What you get

The task done, and the issue closed with a result comment and its proved Done-when boxes ticked. A box it cannot prove keeps the issue open, and the comment says what is left.

The agent opens its own browser window and finds its tab by ID, so you keep working in your own tabs. It uses a CLI first when one is signed in already. It stops only for your steps: a password, a passkey or 2FA check, a payment, a Mac permission pop-up, or moving a secret. Each comes as numbered steps that name the tab, the field, and the word to send back, such as `done`.

It never reads a secret. It opens the page with the secret and the place it goes, with the name filled in; you copy and paste; it checks only that the name is there.

The steps in the issue count as your yes. A step that cannot be undone and touches something this run did not make, such as deleting an old project, waits for your `yes` first.

When a step fails, it tries once more if that is safe, then gives you numbered steps. For a long wait, such as an app review, it comments, adds the `waiting` label, and ends, so orchestrate moves on; say `resume #16` to orchestrate when the wait is over. A bug in the code seen on the way goes to [capture](../capture/).

## Needs

- `gh`, signed in.
- [use-mac](../use-mac/) and its `agent-desktop`.
- Brave, Chrome, or Safari with JavaScript from Apple Events turned on (Brave and Chrome: View > Developer).

## Fits with

- [to-issue](../to-issue/) and [to-epic](../to-epic/) write task issues with the steps this skill follows.
- [orchestrate](../orchestrate/) starts it, one task at a time.
- [use-mac](../use-mac/) drives the browser and the apps.
- [capture](../capture/) logs a code bug seen on the way.
