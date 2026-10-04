---
name: unslop
description: "Remove AI writing patterns from prose. Use for docs, READMEs, blog posts, any non-code text that should sound human. Triggers: 'unslop', 'humanize', 'make this sound human', 'clean up this writing', 'edit for voice', 'de-AI this text'."
---

# Unslop

Edit text to remove AI patterns and add human voice.

## Process

1. Scan for the patterns below
2. Rewrite — preserve meaning, match intended tone
3. Add soul (see next section)
4. Self-audit: "What makes this obviously AI generated?" Fix remaining tells.

## Adding soul

Removing patterns is half the job. Sterile, voiceless writing is just as obvious.

- **Have opinions.** React to facts instead of neutrally listing pros and cons.
- **Vary rhythm.** Short sentences. Then longer ones that take their time. Mix it up.
- **Acknowledge complexity.** "Impressive but also kind of unsettling" beats "impressive."
- **Use "I" when it fits.** First person isn't unprofessional.
- **Let some mess in.** Perfect structure feels algorithmic.
- **Be specific.** Not "this is concerning" but "there's something unsettling about agents churning away at 3am."

## Patterns to detect and fix

### Content

1. **Significance inflation** — "pivotal moment", "testament to", "evolving landscape", "setting the stage for", "indelible mark", "deeply rooted". Cut puffery, state what happened.
2. **Notability name-dropping** — listing media outlets without context. Pick one, say what was said.
3. **Superficial -ing phrases** — "highlighting...", "ensuring...", "reflecting...", "showcasing...", "fostering...". Delete or expand with real sources.
4. **Promotional language** — "nestled", "vibrant", "breathtaking", "groundbreaking", "renowned", "stunning", "must-visit". Use neutral descriptions.
5. **Vague attributions** — "Experts believe", "Industry reports suggest", "Some critics argue". Name the source or delete.
6. **Formulaic challenges** — "Despite challenges... continues to thrive." Replace with specific facts.

### Language

7. **AI vocabulary** — Additionally, crucial, delve, enduring, enhance, fostering, garner, interplay, intricate, landscape (abstract), pivotal, showcase, tapestry (abstract), testament, underscore, vibrant. Replace with plain words.
8. **Copula avoidance** — "serves as", "stands as", "boasts", "features". Just say "is" or "has".
9. **Negative parallelisms** — "It's not just X, it's Y." State the point directly.
10. **Rule of three** — forcing ideas into groups of three. Use the natural number.
11. **Synonym cycling** — protagonist/main character/central figure/hero in one paragraph. Pick one, repeat it.
12. **False ranges** — "from X to Y" where X and Y aren't on a meaningful scale. List topics directly.

### Style

13. **Em dash overuse** — avoid em dashes entirely. Use periods, commas, or parentheses. Em dashes are an AI tell.
14. **Colon overuse** — colons are fine before a list or example. Not as mid-sentence connectors. "If you're coming from traditional automation: instead of registering event handlers, you describe conditions" adds nothing with the colon. Rewrite to let the point stand on its own without comparison framing. "Describing when the scheduler should fire works best as plain English." Same meaning, no crutch punctuation.
15. **Boldface overuse** — don't bold every proper noun or acronym.
16. **Inline-header lists** — "**Performance:** Performance improved..." Convert to prose.
17. **Title case headings** — use sentence case.
18. **Decorative emojis** — remove from headings and bullets.
19. **Curly quotes** — replace with straight quotes.

### Communication artifacts

20. **Chatbot phrases** — "I hope this helps!", "Let me know if...", "Of course!", "Certainly!" Remove.
21. **Cutoff disclaimers** — "While specific details are limited..." Find sources or remove.
22. **Sycophantic tone** — "Great question! You're absolutely right!" Respond directly.

### Filler

23. **Filler phrases** — "In order to" → "To". "Due to the fact that" → "Because". "It is important to note that" → delete.
24. **Excessive hedging** — "could potentially possibly be argued that it might" → "may".
25. **Generic conclusions** — "The future looks bright." State specific plans or facts.

### Jargon

26. **Abstract metaphor nouns.** Substrate, wedge, vector, locus, vantage, nexus, primitive (as noun), harness (as metaphor), surface (as in "API surface"), bedrock, scaffolding (as metaphor), modality, paradigm, gold-plating, ratchet (as metaphor), evacuate (for moving code), endgame, north star, flywheel. These read as technical but usually have a plainer concrete word. "Substrate" becomes "base". "Wedge in" becomes "add". "Vector" becomes "way" or "method". "Gold-plating" becomes "more than the job needs". "Ratchet" becomes the mechanism's real name or "a limit that only tightens". "Evacuate" becomes "move out". "Endgame" becomes "the last phase". Pick the concrete word.

### Plain speech

27. **Say what it does, not how it feels.** "the database stays close at hand", "SQL you can read", "types that follow your schema" name a feeling. The fix names the mechanism or a number: "`.toSQL()` returns the exact string sent to the database", "a column rename fails the build". Ask what the sentence tells the reader to do or know, then write that. If you can't restate it as a concrete instruction, fact, or number, cut it. One more check: if the sentence could appear unchanged in another project's docs, it says nothing about this one. Cut it.
28. **Shorten or split dense sentences.** If the reader has to backtrack to parse a sentence, break it in two or drop clauses. One idea per sentence.
29. **Active voice.** Prefer it. Catch "is/are/was/were + past participle" and name the actor: "queries are validated" becomes "the compiler validates queries", "the file is parsed by the loader" becomes "the loader parses the file". Passive is fine only when the actor is unknown or genuinely doesn't matter.
30. **Cut adverbs, or use a stronger verb.** "runs quickly" becomes "is fast" or the number. "significantly improves" becomes the measured delta. An adverb propping up a weak verb means the verb is wrong.
31. **Prefer the plain word.** "utilize" becomes "use", "leverage" becomes "use", "facilitate" becomes "help", "numerous" becomes "many", "in the event that" becomes "if". The fancier synonym is rarely clearer.
32. **Mannered prose.** Metaphor or flourish where a literal phrase exists: aphorisms ("wire it or delete it"), rhetorical fragments for effect, personified code ("the plan holds it"), figurative verbs ("rides along", "stands on"), stock framing phrases. "A dial worth turning" becomes "a parameter worth varying". Say what you mean. Rule 26 covers the metaphor nouns.
33. **Over-compression.** Dropped articles, verbless fragments, symbol-speak, and abbreviations that make the reader decode instead of read. "Parser rejects bad date → exit 2, no write" becomes "The parser rejects a bad date, exits with code 2, and writes nothing." Write whole sentences with their articles and verbs, and spell out arrows and abbreviations.
