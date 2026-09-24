# Grilling

Interview the user relentlessly until you reach a shared understanding. Map the work as a **design tree**, where every decision branches into the decisions that hang off it.

Keep the tree and its **frontier** in your head. The frontier is every decision whose prerequisites are already settled: the questions you can ask now without guessing at answers you have not heard yet. Ask it **one question per message**. Each message is one decision, the context to pick fast, the real options, your pick first. Then wait.

Format a question like so:

```
❓ **<question title>**: <one or two sentences of context, with the `file:line` it rests on>

✅ A. <option> — my pick: <why in a few words>
B. <option>
C. <option>
```

Options sit on their own lines, labelled A, B, C, D, as many as there are real ways. Two is the usual case, four is the ceiling. Your pick is always A, and line A starts with the ✅ emoji and ends with `— my pick:` and the reason, so the pick stands out at a glance. Lines B, C, D carry no emoji. Never leave the marker off.

Each answer reshapes the tree. Settled decisions push the frontier outward and unblock the questions that depended on them. Recompute the frontier and ask the next question. A question waits only when its answer truly depends on one still open. When it could go either way, ask it now as a conditional ("if the last answer is A, then ..."). Every branch gets asked; one more question is cheaper than a branch left silent.

Keep a running list of settled decisions, so the summary at the end is one paste.

Finding facts is your job, never the user's. `facts.md` in this folder says how to fetch them and how a running fetch fits into the frontier. The decisions are the user's. Put each one to them and wait.

## Branches that are always in the tree

The tree comes from the work, and most of it is free. But a few branches are missed by reflex, and a later stage needs each of them. So these rows are always in the tree. Each one is settled, or you say "not applicable" out loud. Silence is not an answer.

| Grill must settle | Who needs it |
|---|---|
| Who does what, and what they see at the end | `to-issue` What to build |
| The done list: one observable outcome per line | `to-issue` Done when |
| The five unhappy states for each user action, per `issue-rules.md` § Unhappy paths. Each one settled, or named as out | `to-issue` Done when and Scope Out |
| What is near but out | `to-issue` Scope Out |
| Files, seams, schema or API change, migrations, packages touched | `to-issue` size; `to-epic` cutting |
| For work over one ticket: what gates what | `to-epic` phases and edges |
| Terms | `CONTEXT.md`, per `domain-modeling.md` |

Bugs and slow things are not grilled from scratch. `/diagnose` finds the cause first and says whether a grill is needed. When it is, the tree starts from the open decision it named.

## Done

The session is done when the frontier is empty, every branch of the design tree visited, nothing left silently assumed, and every row above holds for each ticket-sized piece of the work. That last test is the `to-issue` readiness gate and the `to-epic` facts step; when it holds, those skills do not fail. Ask the user to confirm you have reached a shared understanding, then stop. Act on the plan only after that confirmation.

When the frontier keeps growing and the work will not settle in this session, say `This needs a map. Run /discover-path.` and stop. The user decides; grill only points.
