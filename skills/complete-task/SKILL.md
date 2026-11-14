---
name: complete-task
description: "Do one task issue, an issue with the `manual` label whose work lives in a platform outside the repo, in the user's own browser and Mac apps with use-mac. The user does only their own steps: a password, a passkey or 2FA check, a payment, a Mac permission pop-up, moving a secret. Use for '/complete-task #16' or '$complete-task #16'; orchestrate starts it with --ready."
disable-model-invocation: true
---

# Complete task

Do a task issue for the user, so they do the least: only their own steps, each one written out. All the rest is yours.

Input: `[--ready] <issue number or URL>`. The repo is the URL's, or this checkout's (`gh repo view --json nameWithOwner`).

## Your step

A **your step** is a step only the user can do: a password, a passkey or 2FA check, a payment, a Mac permission pop-up, or moving a secret (§ Secret). Hand it over as numbered steps, one action each, that name the window or tab by its title, the field or button, and the word to send back. Then wait for that word.

```
Your step, in the Brave window "Cloudflare | Sign in":
1. Click "Log in with passkey".
2. Touch the fingerprint sensor.
3. Send done here.
```

## Ask first

A step that cannot be undone and touches a thing this run did not make, such as deleting a project that was there before, rotating a live key, or changing DNS on a live domain. Send one message: what you will do, why, and that it cannot be undone. Then wait for `yes`.

Every other step written in the issue counts as the user's yes. It is the yes that use-mac § Guardrails asks for. A thing this run made, you may change or delete.

## Secret

You read names, never values. While a page shows a secret, take no snapshot, no screenshot, and no page text from it.

1. Open the page that shows the secret in your window, and the place it goes with its name filled in. The issue's Hand back says the names. When it names no place, ask one question with your pick, such as `Save X_CLIENT_SECRET as a repo secret? (my pick)`.
2. Give a your step: copy from the one tab, paste in the other, save, send `done`.
3. Prove it by its name alone, with a command that prints names only, such as `gh secret list`.

## Steps

1. **Ready.** Only with `--ready`. Read the issue as in step 2, then post `Ready: #N <title>. Have near you: <Bring>. About <time>. Send go when you are free.` Bring is the body's **Bring:** line; the time is your guess of the whole run. End the turn. On `go`, go on at step 2. With no `--ready`, start at step 2.
2. **Read.** `gh issue view <n> --repo <owner/repo> --json number,title,body,labels,comments,state`. A closed issue, or one with no `manual` label: say which, and stop with nothing changed.
3. **Sort.** List each step from `## Steps`. Mark each one yours, a your step, or ask first. With no steps, work them out from `## What to build` and `## Done when`; when that still leaves a doubt, ask one question with your pick. Tell the user in one line which steps will be theirs.
4. **Terminal first.** A step a CLI can do or show with a login it has already (`gh`, `wrangler`, `railway`, `vercel`), do there.
5. **Browser and apps.** The rest through use-mac: § Browser for a web page, in your own window with your tab found by ID; its loop for a Mac app. Prove each step by reading the page or app again. When a page differs from the issue's steps, do what the page needs for the same result, and keep the difference for the result comment.
6. **Your step and ask first.** As § Your step and § Ask first say, at the point the step comes.
7. **Secret.** As § Secret says.
8. **Wrong path.** As § Wrong path says.
9. **Prove.** Each `## Done when` box, from the platform's page or a CLI, by a check you ran in this run.
10. **Close out.**
    - One result comment on the issue: what exists now and where, each Done when box with its proof, each difference from the steps, and what is left. Names only, never a value.
    - Tick each proved box: write the body with `- [ ]` made `- [x]` on those lines to a temp file, then `gh issue edit <n> --repo <owner/repo> --body-file <file>`.
    - Every box proved: `gh issue close <n> --repo <owner/repo>`. Else leave it open; the comment says what is left.
    - Close your browser window as use-mac § Browser says, quit the apps you opened, and delete your screenshots and temp files.
    - A bug in the code seen on the way: log it with the capture skill, one line, and go on.
    - Tell the user in a few lines: done, or what is left.

## Wrong path

- **A step fails.** Try it once more when that is safe: a read, a page load, a form that saved nothing. Else stop, and give the user numbered steps for what is left, with what you saw.
- **Not a task.** Step 2 stops.
- **No steps.** Step 3 works them out.
- **A long wait**, such as an app review or a DNS change that takes hours. Comment `Waiting for <what>, about <time>. Say resume #<n> to the orchestrator when it is over.`, then `gh issue edit <n> --repo <owner/repo> --add-label waiting`. When `gh` fails because the label is missing, create it with its line in `../../shared/issue-rules.md` § Labels, and add it again. Then end: the task turn moves on to the next task.
- **No reach to the browser.** A script error about JavaScript from Apple Events, or an Automation pop-up. Give a your step that turns it on: in Brave, View > Developer > Allow JavaScript from Apple Events; for the pop-up, OK, or System Settings > Privacy & Security > Automation, then your terminal app, then the browser.
- **No rights.** Name the account you are in and the right it lacks, such as `signed in as <account>, which is not an owner of the Cloudflare account`, and give a your step to switch accounts or get the right.
