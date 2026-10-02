# Probes

A probe runs something to settle a fact that reading cannot: does the
tool do what we need, what does the API really return, where is the
limit. It is part of the facts step, like an Explore round. A change
found in the build costs more than a fact found here, so a probe that
settles a real doubt is cheap.

A probe is not a `spike` ticket. A probe is minutes, inside the plan,
and ends in one fact. A `spike` ticket is its own work, and ends in a
decision.

## When

Probe a fact only when both hold:

- the plan changes with the answer: a seam, a `Change`, a `Then`
  literal, a `Decided` line, or which option a big fork recommends;
- reading leaves real doubt: the docs are silent, vague, or contradict
  what the repo or an issue says, or the behaviour hangs on data,
  versions, or setup the docs do not cover.

Everything else is not probed. A fact the docs state plainly, and
nothing contradicts, is taken from the docs. A fact the repo already
shows in a passing test, or a Known line in the issue, is taken as read.
A fact the plan does not lean on is not fetched at all. Never probe to
be thorough: each probe names the plan line it settles.

Good probes: the library parses the file shape the issue links; the
vendor sandbox returns `pending` on ACH refunds, not `succeeded`; the
query stays under 200 ms on a seeded table of the size the issue names;
the new option exists in the version the lockfile pins.

## Free or asked

A probe runs without asking when all of these hold:

- it costs no money: no paid API call, no paid tier, no cloud resource;
- it needs no credential and no account the repo's own tests do not
  already use;
- it touches nothing shared: no production or staging data, no real
  user, no push, no GitHub write, no message sent;
- it sends no repo code or data to a service that does not hold it
  already.

A probe that fails any of these waits for a yes. Put every such probe in
one message: the question it settles, what it runs, what leaves the
machine, and what it costs. A `no` leaves the fact to reading: it stays
a doubt, and step 5 sorts it like any other.

## Where

Never in the checkout you started in, and never in the base copy, which
stays read-only. Each probe gets its own `mktemp -d` folder. A probe
that needs the repo's code adds a detached worktree there:
`git worktree add --detach "$PROBE/wt" <BASE_SHA>`, and removes it with
`git worktree remove --force "$PROBE/wt"` when it ends, pass or fail.
A package it needs installs into its folder, never into the repo's
manifests. A service it starts (a container, a dev server) it stops.
When the probes end, `git status --porcelain` is as step 1 found it,
and `git worktree list` holds only the base copy beyond what step 1
found.

## How

Probes fan out like Explore agents: one sub-agent per probe, all in one
message, beside any Explore round that is still open. The agent needs
hands: general-purpose in Claude Code. In Codex, run them yourself, one
after another.

Each brief, inline:

- the question, and the plan line it settles;
- what to run, and the rule that reads the answer: the output, value,
  or error that means yes, and the one that means no;
- a time box of about 15 minutes;
- the folder, and the cleanup above;
- what to return: the answer, the command or script, the output lines
  that show it, and every doc it found wrong or missing on the way, in
  the repo or upstream.

A probe that cannot answer inside its box is not a probe. It is a big
fork: ask whether to plan on what reading shows, or to stop for a
`spike` ticket first (`../../shared-skill-core/issue-rules.md`).

A `no` is a fact like a `yes`: the tool cannot do it, so the fork
changes. A probe that shows the issue itself is wrong (a Done-when line
the tool cannot meet) stops the plan: say which line and what the probe
showed, and name `/grill`.

## What it leaves

One `Proved` line per probe, per `plan.md` § Shape, and nothing else:
the scripts stay in the temp folder and go with it. The executor reads
no file of ours, so a line carries what it needs to build: the value,
the shape, the limit. A doc the probe found wrong or missing becomes a
`Docs` line in the slice it follows, per `plan.md` § Slices.
