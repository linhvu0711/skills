# Design It Twice

When the user wants to explore alternative interfaces for a chosen deepening candidate, use this parallel sub-agent pattern. Based on "Design It Twice" (Ousterhout): your first idea is unlikely to be the best.

Uses the vocabulary in `../../shared-skill-core/codebase-design.md`: **module**, **interface**, **seam**, **adapter**, **leverage**.

## Process

### 1. Frame the problem space

Before spawning sub-agents, write a user-facing explanation of the problem space for the chosen candidate:

- The constraints any new interface would need to satisfy
- The dependencies it would rely on, and which category they fall into (see [deepening.md](deepening.md))
- A rough illustrative code sketch to ground the constraints, not a proposal, just a way to make the constraints concrete
- The scoring points: 3 to 6 named points the designs will be scored on, each one line that says what a good design does on it. Start from **depth**, **locality**, and **seam placement**, and add the points this candidate's constraints ask for, such as the error modes a caller must handle or the tests that survive. Name them now, before any design comes back, so no design picks its own measure.

Show this to the user, then immediately proceed to Step 2. The user reads and thinks while the sub-agents work in parallel.

### 2. Spawn sub-agents

Spawn 3+ sub-agents in parallel. Each must produce a **radically different** interface for the deepened module.

Agent type by harness. Claude Code: the `interface-designer` agent (Opus, read-only). Codex: its normal sub-agent.

Prompt each sub-agent with a separate technical brief (file paths, coupling details, dependency category from [deepening.md](deepening.md), what sits behind the seam, and the five output sections below). The brief is independent of the user-facing problem-space explanation in Step 1. Give each agent a different design constraint:

- Agent 1: "Minimize the interface: aim for 1–3 entry points max. Maximise leverage per entry point."
- Agent 2: "Maximise flexibility: support many use cases and extension."
- Agent 3: "Optimise for the most common caller: make the default case trivial."
- Agent 4 (if applicable): "Design around ports & adapters for cross-seam dependencies."

Include both `../../shared-skill-core/codebase-design.md` vocabulary and CONTEXT.md vocabulary in the brief so each sub-agent names things consistently with the architecture language and the project's domain language.

Keep the scoring points out of the briefs. Each sub-agent pushes its own constraint; a designer that knows the measure drifts toward the middle.

Each sub-agent outputs, in this order:

1. Usage example: how the callers use the module, written first, from the real callers it traced
2. Interface (types, methods, params, plus invariants, ordering, error modes), shaped to fit the usage above
3. What the implementation hides behind the seam
4. Dependency strategy and adapters (see [deepening.md](deepening.md))
5. Trade-offs: where leverage is high, where it's thin

The usage comes first on purpose: the interface fits how the code is used, not the other way round. A design whose usage example has to work around its own interface has failed its first test.

### 3. Present and score

Present designs sequentially so the user can absorb each one.

Then score them one point at a time, in the order Step 1 named the points: for each point, give every design `strong`, `fair`, or `weak`, with one clause why, before you move to the next point. No point joins after the designs come back. End with a table: one row per point, one column per design.

### 4. Read agreement and divergence

- **The designs agree** on a part (the same seam, the same entry point, the same thing hidden): a strong sign that part is right. Say so, and carry it into the pick.
- **The designs differ wildly** (each puts the seam in a different place, or hides a different thing): the question is unclear, not the designs. Do not average them. Name the split, ask the user the question that would settle it, reframe the problem space of Step 1 with the answer, and run Step 2 again. After one reframe, designs that still differ go to the user as the open choice, with their scores.

### 5. Recommend

Give your own recommendation: which design you think is strongest, by its scores, and why. Be opinionated: the user wants a strong read, not a menu. A hybrid takes one or two parts from each design at most; a merge that takes more is an average, and is not offered.
