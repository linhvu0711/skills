---
name: explain-again
description: Rewrite the assistant's most recent completed answer in plain, simple language at about a 5th-grade reading level, without changing its meaning. Use when the user asks for the last answer to be made plain, simpler, easier to understand, less technical, or free of jargon.
---

# explain-again

Rewrite the last completed answer you gave before the user's current request.

## Rules

1. Reply with the rewritten answer alone: no preface such as "In simple terms", no word about the rewrite.
2. Keep the conclusion, the facts, the caveats, the uncertainty, and the status. An unverified claim stays unverified.
3. Write at about a 5th-grade reading level: everyday words, short sentences, concrete examples. Spell out jargon and acronyms; a technical term that must stay gets a plain explanation the first time it appears.
4. Make it shorter and easier to scan, unless shortening drops something the user needs.
5. Keep names, numbers, links, commands, paths, and error messages exact. Drop low-level detail the result does not need.
6. Rewrite only. No research, no tools, no actions, no new facts or advice.
7. Steps the user must follow stay as a short ordered list. Everything else reads best as a compact paragraph.
8. No earlier completed answer in the visible conversation: say "I don't have an earlier answer to simplify."
