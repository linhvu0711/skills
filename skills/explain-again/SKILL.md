---
name: explain-again
description: Rewrite the assistant's most recent completed answer in plain, simple language at about a 5th-grade reading level, without changing its meaning. Use when the user asks for the last answer to be made plain, simpler, easier to understand, less technical, or free of jargon.
---

# Plain

Rewrite the most recent completed assistant answer that came before the user's current request.

## Rules

1. Give only the rewritten answer. Do not add a preface such as "In simple terms" or discuss the rewriting process.
2. Preserve the original conclusion, factual meaning, important caveats, uncertainty, and status. Never turn an unverified claim into a confirmed one.
3. Write at about a 5th-grade reading level: everyday words, short sentences, and concrete explanations. Expand or replace jargon and acronyms; when a technical term must stay, explain it in simple words the first time it appears.
4. Make the answer shorter and easier to scan unless shortening it would remove something the user needs.
5. Keep essential names, numbers, links, commands, paths, and error messages exact. Remove low-level detail that is not needed to understand the result.
6. Do not research, use tools, take actions, or add new facts or advice. This task is a rewrite of the prior answer only.
7. If the prior answer contains steps the user must follow, retain them in a short ordered list. Otherwise, prefer a compact paragraph.
8. If there is no earlier completed assistant answer in the visible conversation, say: "I don't have an earlier answer to simplify."
