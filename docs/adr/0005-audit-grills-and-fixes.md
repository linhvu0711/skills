# The audit grills and fixes; set only starts the Standard

`audit-coding-standards` was read-only. On `needs work` it told the user to run `set-coding-standards`, which ran the whole audit again (research agents and code sampling) before the grill. The cost was double, and the user had to start a second skill to answer questions about the report they already had. We split the skills by when they run. `set-coding-standards` makes the Standard the first time, and also takes in scattered rules. When the Standard already exists, it stops. `audit-coding-standards` checks the Standard and then grills the user on the findings at once. It writes the settled changes, or nothing when the user stops the grill before it ends. Because the audit now writes files, only its slash command starts it, the same as set. The skills change to follow this decision in a later pull request.

## Considered options

- Keep the audit read-only, and let set take an existing report so the audit does not run twice. We rejected it because the user still has to start a second skill to act on a report that is already in front of them.
- Add a `--report` flag for a read-only audit. We rejected it because the report prints in full before the first question, and the user can stop there.
