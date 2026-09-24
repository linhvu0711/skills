# Facts

Finding facts is your job, never the user's. A fact is anything a question, an answer, or a plan rests on that you have not seen with your own eyes: a file, a symbol, a caller, a test, a doc, a library's API, a spec, a vendor's behaviour. Fetch it. The decisions are the user's.

## Brain and hands

You are the brain. Explore agents retrieve, and they can synthesize over what they read when the brief asks for it (a state brief, a consolidated answer with citations); the decisions stay yours. Give each agent its full brief inline and ask for exact things: the seam, the lines that change, the nearest test, the command, the doc passage. Fan out by concern, all in one message. Agents come back with paths and line numbers, or with the source URL and the passage. Trust what comes back and build one picture; never re-verify it file by file. Two agents disagree on a fact: send one back for that single point.

Work whose output is short (one `git log`, one `ls`, one `rg` count) is yours.

One agent, one small job: a handful of files (about ten or fewer), one grep group, or one lookup. A brief that bundles several jobs, reads dozens of files, or asks for verbatim copies of many files is too big. Split it into several small agents in one message; they run side by side and each answer stays short.

In Codex there are no sub-agents: use the read tools yourself, in the same order, and keep the same notes.

## Two kinds of fact

- **Repo facts** live in the working directory. Explore agents fetch them.
- **Outside facts** live in library docs, specs, and upstream source. Explore agents fetch these too, with `SEARCH=on` in the brief. When a decision will rest on one, `../skills/grill/references/research.md` says how to write it down.

## A fact that arrives late

An answer, a review, or a later step can name a file, a service, an API, or a behaviour that nothing you fetched covers. Dispatch for it at once and keep going: a running fetch is an unsettled prerequisite, and only the work downstream of it waits.
