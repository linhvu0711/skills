# Model tiers

Each subagent's file names a tier, 1 to 4, and a checker line, yes or no. The tables below give the model it runs on. `scripts/agents.sh` reads the fenced tables; change a model or an order here, in one cell.

## Tiers

**Tier 1: fast and cheap** (Haiku, Terra low).
Can do: follow clear steps, pull out facts, sort things into named kinds, run tools in a loop.
Slips on: vague goals, long reasoning, spotting what is missing, very long briefs.
Example job: "Read this log and say which test failed."

**Tier 2: the steady worker** (Sonnet, Terra medium, SWE-2.1 high).
Can do: read and judge real code, apply a long list of rules, run long multi-step work without losing the thread.
Slips on: open problems with no frame, subtle bugs that need deep tracing.
Example job: "Check this file against these 30 rules."

**Tier 3: the deep thinker** (Opus, Sol).
Can do: reason through unclear problems, trace causes across many files, find what is missing or wrong, check a claim hard.
Slips on: rarely on reasoning; it costs more and takes longer.
Example job: "Find every way this change can break a caller."

**Tier 4: the best judgment** (Fable, Astra).
Can do: open design calls with no right answer, taste, novel problems, one view out of a lot of context.
Slips on: nothing tier 3 does better; it costs the most.
Example job: "Is this the right shape for code that does not exist yet?"

## How to pick

- Find the hardest step of the job. Pick the lowest tier that does that step well.
- Go up one tier when a miss is silent (the report just looks clean) or costly (it ships a bug).
- Go down one tier when a later step catches the mistake, or when the job runs many times per skill run.
- Checker: yes when the subagent judges work the main agent's model family made: a plan, the grill's decisions, a PR. Checker: no when it judges outside things: the codebase, a log, CI output.
- A new subagent: ask the user for its tier and checker line, with your pick and its reason.

## Tier models

`none` means the company has no model at that tier.

```tsv
tier	claude	codex	antigravity	devin
1	claude-haiku-5-5 high	gpt-6.1-terra low	none	none
2	claude-sonnet-5-5 high	gpt-6.1-terra medium	gemini-4-neon low	swe-2-1-medium high
3	claude-opus-5-5 high	gpt-6.2-sol medium	gemini-4-neon medium	none
4	claude-fable-5-2 high	gpt-6.2-astra high	gemini-4-neon high	none
```

## Try order

Each cell lists the companies a subagent tries, in order, for its tier and checker line, by the main agent's harness. In T3 each try runs in turn until one starts. Outside T3, only the last one runs. From Claude and Codex, the last one is the main agent's own company, so a helper fails only when the main agent fails.

```tsv
row	claude	codex	antigravity
1 no	claude	codex	claude
1 yes	claude	codex	claude
2 no	devin, claude	devin, codex	devin, antigravity
2 yes	devin, claude	devin, codex	devin, antigravity
3 no	claude	codex	antigravity
3 yes	antigravity, claude	claude, codex	claude, antigravity
4 no	claude	codex	antigravity
4 yes	antigravity, claude	claude, codex	claude, antigravity
```

## In use

sync-harnesses checks the models only of a company in use, and fails a try order that reaches a company not in use.

```tsv
company	in use
claude	yes
codex	no
antigravity	yes
devin	yes
```

**Main agent: Claude Code.** Antigravity can run as the main agent in T3, but a tier-1 subagent then has no Antigravity model to fall back on: it runs only when Claude is on. When Gemini has a tier-1 model, fill that cell and end the Antigravity tier-1 rows on `antigravity`.
