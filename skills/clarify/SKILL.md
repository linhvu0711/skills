---
name: clarify
description: Explain what the agent said when the user did not follow it, by default the last answer, or only the part the user names, such as a term, a line, or an earlier answer. Explains from the session first, in short plain words. Use when the user says they do not understand an answer, asks what a term or line means, or types /clarify or $clarify.
---

# clarify

Explain the part of what you said that the user did not follow.

## What to explain

- The request names nothing, as a bare `/clarify` or "I don't get it": your last completed answer before this request.
- The request names something: only that thing, and nothing else. The user names it any way: a term (`/clarify home`, "what do you mean by home?"), a quoted line (`/clarify "the gate refused the first start"`), or a pointer to an earlier answer (`/clarify your answer about the session skills`). Work out which part of the session it means.

## Where the context comes from

1. The session first. What the user missed is often in tool output, files read, or commands run that they never saw.
2. Code or docs only when the session lacks the context. Read them; change nothing.

## The reply

- Short: what the thing is, why it matters here, and a plain meaning for each term it uses.
- Keep names, numbers, commands, paths, and error text exact.
- Explain only. Give no new advice, take no actions, and make no edits.

## Nothing to explain

- No earlier answer in the session: say "I have no earlier answer to explain."
- The named thing is not in the session, and not in the code or docs: say so, and ask which part the user means.
