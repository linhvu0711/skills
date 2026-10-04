# unslop

Edits prose so it stops sounding like an AI wrote it: cuts the stock phrases and puts some voice back.

## Use it when

You have docs, a README, a blog post, or any other non-code text that should read like a person wrote it. `/unslop` in Claude Code, `$unslop` in Codex, or "make this sound human", "de-AI this text", "clean up this writing".

## What you get

The same text, same meaning, without the tells: no "pivotal", "delve", or "testament to", no em dashes, no "It's not just X, it's Y", no forced lists of three, no "I hope this helps!".

> Before: "This powerful tool serves as a testament to modern engineering, seamlessly cutting your build time in half."
>
> After: "The tool cuts your build time in half."

It also adds voice back: opinions, varied rhythm, specific detail.

It also flags jargon and stiff prose: metaphor nouns like "substrate" or "north star", lines about how a thing feels instead of what it does, dense sentences, passive voice, adverbs, fancy words, mannered prose, and notes compressed past reading. Parentheses stay allowed.

## Needs

Nothing beyond Claude Code or Codex. No tools, no other skills.

## Fits with

- [grill](../grill/) runs this skill on its ADR and glossary prose before it commits them.

## Credits

A copy of the `unslop` skill from [poteto/noodle](https://github.com/poteto/noodle) (`.agents/skills/unslop`), MIT license, with rules 26 to 33 copied from the `unslop` skill in [pstack](https://github.com/cursor/plugins/tree/main/pstack) (`pstack/skills/unslop`), also by Lauren Tan, MIT license. pstack's ban on parentheses is left out. The skill text is upstream's; this repo does not reword it.
