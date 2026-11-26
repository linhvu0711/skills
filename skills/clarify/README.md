# clarify

Explains what the agent said when you did not follow it: its last answer, or only the part you name.

## Use it when

You read the agent's answer and did not follow it. Type `/clarify` in Claude Code or `$clarify` in Codex for the last answer, or name the part: `/clarify home`, `/clarify "the gate refused the first start"`, `/clarify your answer about the session skills`. Asking "what does that mean?" works too.

## What you get

A short answer: what the thing is, why it matters here, and a plain meaning for each term. Most of what you missed is already in the session, in tool output you never saw, so it explains from there first. It reads code or docs only when the session lacks the answer. It gives no new advice and changes nothing.

> You: `/clarify the gate refused the first start`
>
> Agent: "The gate is a script that runs each time the agent starts a helper. It turned down the first try because that helper is set to run on another model first. The agent then started it that way, so nothing is broken."

## Needs

Nothing beyond the agent you chat with. No tools to install, no other skills.

## Fits with

Works alone. No other skill in this repo calls it.
