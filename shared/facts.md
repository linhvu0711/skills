# Facts

Finding facts is your job, never the user's. A fact is anything a question, an answer, or a plan rests on that you have not seen with your own eyes: a file, a symbol, a caller, a test, a doc, a library's API, a spec, a vendor's behaviour. Fetch it. The decisions are the user's.

## Evidence labels

Each fact you state carries one of four labels, so the reader knows how sure it is:

- **Seen**: read in a source, or run and observed. Name the source: a `file:line`, a URL, or the command.
- **Inferred**: follows from what was seen. Name the Seen facts it follows from.
- **Guess**: no direct sign.
- **Unknown**: looked and found nothing.

Put the label before the fact, as in `Seen: export.ts:31 streams JSON.` Labels go in what a person reads: chat, a report, a question, a reply. A file or a block that a skill or a script reads keeps its own shape and takes no label word: a plan's fields and tables, a template, a commit message.

## Try before you label

Guess and Unknown come only after you tried to see the fact yourself: read it, search for it, run a command, or run a probe. Each Guess or Unknown lists what was tried, as in `Unknown: the API's rate limit. Tried: the API reference, rg -i 'rate limit' in the client, the client's tests.`

Never ask the user to run a check you can run yourself. Ask the user only for what no try reaches: a decision, a secret, a login, or a fact only they hold.

Every try is safe: read, search, run tests, or run a probe in a sandbox or a temp copy. Nothing hard to undo, and no writes to shared places like GitHub or prod. A try that costs money or needs a credential waits for the user's yes, and a try that is hard to undo or writes to a shared place is never made. Until a yes, the fact stays Guess or Unknown, and its list names that try and why it was not made.

## Brain and hands

You are the brain. Readers retrieve, and they can synthesize over what they read when the brief asks for it (a state brief, a consolidated answer with citations); the decisions stay yours. Give each agent its full brief inline and ask for exact things: the seam, the lines that change, the nearest test, the command, the doc passage. Fan out by concern, all in one message. Agents come back with paths and line numbers, or with the source URL and the passage. Trust what comes back and build one picture; never re-verify it file by file. Two agents disagree on a fact: send one back for that single point.

Work whose output is short (one `git log`, one `ls`, one `rg` count) is yours.

One agent, one small job: a handful of files (about ten or fewer), one grep group, or one lookup. A brief that bundles several jobs, reads dozens of files, or asks for verbatim copies of many files is too big. Split it into several small agents in one message; they run side by side and each answer stays short.

### Reader and runner

Two helper jobs, each with its file next to this one: the explorer, `agents/explorer.md`, fetches facts, and the runner, `agents/runner.md`, runs a command and judges it. Skill text that names `Explore` or a reader means the explorer, and `Runner` means the runner: start `explorer` or `runner` per § Skill agents, in place of the agent the older name points to. Each job's lines are the body of its file; § Skill agents says how to start each and when a brief pastes them. The explorer has no network, so a brief that needs an issue or a PR pastes its text. A brief that needs the web says so in plain words, as in `Use the web: the csv-stringify docs.`

The runner installs nothing, so before its brief goes out, the lead puts every package the command needs in the folder the brief names: a checkout with its packages installed and built needs nothing more; a temp folder gets them linked or installed by the lead. A command that installs as it runs, such as a scaffold, a component add, or a bisect that installs at each commit, is not a runner's job: the lead runs it.

### Skill agents

A subagent's file names one or more homes and a backup for each main harness. A skill agent's file is `agents/<agent>.md` in the skill's folder; the explorer's and the runner's are `agents/<agent>.md` next to this file. `harness.md`, next to this file, names your harness's tool for each step below.

**Start.** In T3, when T3's `delegate_task` is in your tools under any of its names (`harness.md` § T3), read the file's `home:` line for your harness: one home, or several joined by `, `. Try them from left to right. When a home's place is your harness and your harness's `backup:` line names the same model and effort, start it by name with your harness's own tool. Else start it through T3 on the home's place, model, and effort. Outside T3, start it by name with your own tool: its file runs it on your harness's backup.

**Brief.** A start by name loads the file, so the brief is the skill's brief alone. A start that loads no file, through T3 or as the plain subagent, puts the file's body, word for word, above the skill's brief.

**Next home.** A home cannot run when T3 lists its place as off, lists no such model, or refuses the start, or when its place is Antigravity and your mode is not `full-access` (`harness.md` § T3). Then try the next home on the line. With no home left, start it by name with your own tool, on the backup. The backup is your own harness's model, so it fails only when you fail: there is no try after it.

**Report line.** A helper that did not run on its first home puts one line in the skill's report, just above its last line:

```
<agent> ran on <where>: <home>, <why>; <home>, <why>.
```

`<where>` is the home that ran, `<place> <model> <effort>`, or `backup <model> <effort>`. Each `<home>, <why>` pair is a home tried before it, in order, and why it could not run, as in `logic-reviewer ran on devin gemini-4-neon-high high: antigravity gemini-4-neon high, Antigravity needs full-access.` and `logic-reviewer ran on backup claude-opus-5-5 xhigh: antigravity gemini-4-neon high, Antigravity is off in T3; devin gemini-4-neon-high high, Devin lists no such model.`

**Not found.** Your harness says the agent is not found: start the plain subagent, with the backup's model and effort as far as your harness's start call takes them (`harness.md`), and print this line:

```
<agent> not found, ran on <plain subagent>. Run scripts/link.sh to fix.
```

## Two kinds of fact

- **Repo facts** live in the repo's checkout: the working directory, or the folder the skill names (plan-up reads a copy of the base). Readers fetch them.
- **Outside facts** live in library docs, specs, and upstream source. Readers fetch these too, when the brief asks for the web. When a decision will rest on one, `../skills/grill/references/research.md` says how to write it down.

## A fact that arrives late

An answer, a review, or a later step can name a file, a service, an API, or a behaviour that nothing you fetched covers. Dispatch for it at once and keep going: a running fetch is an unsettled prerequisite, and only the work downstream of it waits.
